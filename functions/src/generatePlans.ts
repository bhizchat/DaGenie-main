/* eslint-disable max-len, require-jsdoc, valid-jsdoc, operator-linebreak, quotes, @typescript-eslint/no-explicit-any, indent */
import * as functions from "firebase-functions/v1";

import * as logger from "firebase-functions/logger";
import {Request, Response} from "express";
import {initializeApp, applicationDefault, getApps} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import OpenAI from "openai"; // Using global fetch available in Node 20+

interface Venue {
  placeId: string;
  name: string;
  rating: number;
  address: string;
  types?: string[];
  priceLevel?: number;
  photoUrl?: string;
  mapsUrl?: string;
}

interface Scores {
  romance: number; // 0–10 (1 decimal)
  vibes: number; // 0–10
  food: number; // 0–10
  hype: number; // 0–10
}

interface Plan {
  title: string;
  itinerary: string;
  venue: Venue;
  heroImgUrl: string;
  id: string;
  scores: Scores;
}

// Initialise Firebase Admin once.
if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}
const db = getFirestore();
// Allow saving documents with undefined optional fields (e.g. venue.priceLevel)
// to avoid "Cannot use undefined as a Firestore value" errors.
db.settings({ignoreUndefinedProperties: true});

// Access environment variables. In Cloud Functions v2 the keys set via
//   firebase functions:config:set openai.key="YOUR_KEY" google.places.key="YOUR_KEY"
// are surfaced at runtime as process.env.OPENAI_KEY and process.env.GOOGLE_PLACES_KEY
// Feature flags
// Set DISABLE_PAYWALL="true" to disable quota.
// TEMPORARY: hard-disable paywall for App Store submission
const DISABLE_PAYWALL = true;
// Free monthly quota for non-subscribed users (default 3). Override with FREE_QUOTA env var.
const FREE_QUOTA = Number(process.env.FREE_QUOTA) || 3;

const OPENAI_KEY: string | undefined = process.env.OPENAI_KEY;
const PLACES_KEY: string | undefined = process.env.GOOGLE_PLACES_KEY;

let openaiClient: OpenAI | null = null;
/**
 * Lazily instantiate the OpenAI client so that local builds (which may not
 * have OPENAI_KEY set) do not crash when the module is required. Cloud
 * Functions runtime will still create the client on first use.
 */
function getOpenAI(): OpenAI {
  if (!openaiClient) {
    openaiClient = new OpenAI({apiKey: OPENAI_KEY});
  }
  return openaiClient;
}

/**
 * Generate a stylised illustration URL using OpenAI gpt-image-1.
 * Alternating style is passed in – "Studio Ghibli" or "Korean manhwa".
 */
async function makeIllustration(title: string, location: string, style: string): Promise<string> {
  const openai = getOpenAI();
  const prompt = `${style} illustration, whimsical, pastel palette. Romantic date titled '${title}' set in ${location}. No text, no logos.`;
  const img = await openai.images.generate({model: "gpt-image-1", prompt, n: 1, size: "1024x1024"});
  return img.data?.[0]?.url ?? "";
}

async function enrichVenue(name: string, location: string): Promise<Venue> {
  if (!PLACES_KEY) {
    return {
      placeId: "unknown",
      name,
      rating: 0,
      address: location,
      mapsUrl: undefined,
    };
  }
  try {
    const query = encodeURIComponent(`${name} in ${location}`);
    const searchUrl = `https://maps.googleapis.com/maps/api/place/textsearch/json?query=${query}&key=${PLACES_KEY}`;
    const searchResp = await fetch(searchUrl as string);
    const searchJson: any = await searchResp.json();
    const candidate = searchJson.results?.[0];
    if (!candidate) {
      return {placeId: "", name, rating: 0, address: location, mapsUrl: undefined};
    }
    const addr = candidate.formatted_address ?? location;
    const mapsUrl = candidate.place_id
      ? `https://www.google.com/maps/search/?api=1&query=place_id:${candidate.place_id}`
      : `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(addr)}`;

    return {
      placeId: candidate.place_id,
      name: candidate.name ?? name,
      rating: candidate.rating ?? 0,
      address: addr,
      types: candidate.types,
      priceLevel: candidate.price_level,
      photoUrl: candidate.photos?.[0]?.photo_reference
        ? `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photo_reference=${candidate.photos[0].photo_reference}&key=${PLACES_KEY}`
        : undefined,
      mapsUrl,
    };
  } catch (e) {
    logger.warn("Failed to enrich venue via Places", e as Error);
    return {placeId: "", name, rating: 0, address: location, mapsUrl: undefined};
  }
}

// ---------- Scoring heuristics ----------
const ROMANTIC_TYPES = new Set([
  "park", "botanical_garden", "garden", "natural_feature", "art_gallery", "museum", "spa", "aquarium",
  "zoo", "tourist_attraction", "scenic_lookout", "beach", "church",
]);

const ROMANTIC_KEYWORDS = [
  "cozy", "sunset", "stroll", "candle", "intimate", "picturesque", "picnic", "romantic", "wine",
];
const VIBES_TYPES = new Set([
  "park", "beach", "cafe", "bar", "wine_bar", "lounge", "garden",
]);
const VIBES_KEYWORDS = [
  "chill", "relaxed", "laid-back", "sunset", "picnic", "cozy", "vibes",
];


function scoreFromKeywords(text: string, list: string[]): boolean {
  const lower = text.toLowerCase();
  return list.some((kw) => lower.includes(kw));
}

function computeScores(venue: Venue, itinerary: string): Scores {
  // -------- Romance (heuristic 0–10) --------
  let romance = 2.0; // baseline out of 10
  if (venue.rating && venue.rating >= 4.5) romance += 1.0;
  if (venue.types?.some((t) => ROMANTIC_TYPES.has(t))) romance += 3.0;
  if (scoreFromKeywords(itinerary, ROMANTIC_KEYWORDS)) romance += 2.0;
  romance = clamp10(romance);

  // -------- Vibes (chillness) --------
  let vibes = 2.0;
  if (venue.priceLevel && venue.priceLevel <= 1) vibes += 1.0; // cheaper often chill
  if (venue.types?.some((t) => VIBES_TYPES.has(t))) vibes += 3.0;
  if (scoreFromKeywords(itinerary, VIBES_KEYWORDS)) vibes += 2.0;
  vibes += Math.min(2, Math.max(0, (venue.rating ?? 0) - 4.0)); // up to +2
  vibes = clamp10(vibes);

  // -------- Food rating --------
  let food = 0.0;
  if (venue.rating) {
    food = clamp10((venue.rating / 5) * 8 + 1.0); // scale ~1–9
  }
  if (venue.types?.some((t) => ["restaurant", "cafe", "bakery"].includes(t))) {
    food += 1.0;
  }
  food = clamp10(food);

  // -------- Hype heuristic --------
  let hype = 0.0;
  if (venue.rating) hype += (venue.rating / 5) * 6; // up to 6
  if ((venue as any).userRatingsTotal && (venue as any).userRatingsTotal > 500) hype += 1.5;
  if (venue.types?.some((t) => ["night_club", "bar", "stadium", "concert_hall"].includes(t))) hype += 2.0;
  hype = clamp10(hype);

  return {
    romance: Number(romance.toFixed(1)),
    vibes: Number(vibes.toFixed(1)),
    food: Number(food.toFixed(1)),
    hype: Number(hype.toFixed(1)),
  };
}

function clamp10(n: number): number {
  return Math.max(0, Math.min(10, n));
}

export const generatePlans = functions
  .runWith({timeoutSeconds: 540, secrets: ["OPENAI_KEY", "GOOGLE_PLACES_KEY"]})
  .region("us-central1")
  .https.onRequest(async (req: Request, res: Response): Promise<void> => {
  const t0 = Date.now();
  logger.info("🔄 generatePlans invoked");
  try {
    // Basic Auth check (optional)
    const idToken = (req.headers.authorization || "").replace("Bearer ", "");
    let uid = "anonymous";
    if (idToken) {
      try {
        uid = (await getAuth().verifyIdToken(idToken)).uid;
      } catch (e) {
        logger.warn("Invalid ID token", e as Error);
      }
    }

    // ---- Quota & subscription check ----
    if (!DISABLE_PAYWALL && uid !== "anonymous") {
      const userRef = db.collection("users").doc(uid);
      const userSnap = await userRef.get();
      const userData = userSnap.exists ? (userSnap.data() as any) : {};
      const now = Date.now();
      const sub = userData?.subscription;
      const subscribed = sub?.active && typeof sub.expiry === "number" && sub.expiry > now;

      if (!subscribed) {
        const firstOfMonth = new Date();
        firstOfMonth.setDate(1);
        firstOfMonth.setHours(0, 0, 0, 0);
        const plansSnap = await userRef.collection("plans")
          .where("createdAt", ">=", firstOfMonth.getTime())
          .get();
        if (plansSnap.size >= FREE_QUOTA) {
          res.status(402).json({error: "quota_exceeded", message: "Free quota exceeded. Subscribe for unlimited plans."});
          return;
        }
      }
    }

    const {location = "", preferences = "", budget = "$", timeOfDay = "any"} = req.body || {};
    if (!OPENAI_KEY) {
      logger.error("OPENAI_KEY undefined", {envKeys: Object.keys(process.env).filter((k) => k.toLowerCase().includes("openai"))});
      res.status(500).json({error: "OpenAI key not configured"});
      return;
    }

    // Build system & user prompts
    const budgetDesc = budget === "$$" ? "moderate budget" : (budget === "$$$" ? "high budget" : "low budget");
    const timeLabel = timeOfDay !== "any" ? timeOfDay : "";
    const openai = getOpenAI();
    const systemPrompt = "YOU ARE DateGenie, an expert New-York-Times-style travel writer and event planner.";
    const userPrompt = `
Context:
• User profile: 28-year-old couple, enjoys spontaneous experiences, ${budgetDesc}.
• Location: ${location}
• Preferences: ${preferences}${timeLabel ? ", " + timeLabel : ""}

Task:
1. Propose THREE distinct date plans, each with:
   – title (4–6 words, catchy)
   – itinerary (≤120 words, first-person plural)
   – venueName
   – romance (0–1)
   – novelty (0–1)
2. Avoid duplicate venues across plans.
3. Consider commute time (≤30 min) and provide weather-safe options.

Output JSON ONLY:
{
  "plans": [
    { "title": "", "itinerary": "", "venueName": "", "romance": 0.0, "novelty": 0.0 },
    { "title": "", "itinerary": "", "venueName": "", "romance": 0.0, "novelty": 0.0 },
    { "title": "", "itinerary": "", "venueName": "", "romance": 0.0, "novelty": 0.0 }
  ]
}`;

    logger.info("🧠 calling GPT-4o-mini");
    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini", // lightweight yet capable; adjust if needed
      temperature: 0.8,
      max_tokens: 500,
      response_format: {type: "json_object"},
      messages: [
        {role: "system", content: systemPrompt},
        {role: "user", content: userPrompt},
      ],
    });

    let parsed: any;
    try {
      {
        const content = completion.choices[0].message.content ?? "{}";
        parsed = JSON.parse(content);
        logger.info(`🧠 GPT response parsed in ${Date.now() - t0}ms`);
      }
    } catch (e) {
      logger.error("Failed to parse OpenAI JSON", e as Error, completion.choices[0].message.content);
      res.status(500).json({error: "OpenAI returned invalid JSON"});
      return;
    }

    const rawPlans = (parsed.plans ?? []) as any[];

    // allocate arrays for downstream processing
    const heroUrls: string[] = Array(rawPlans.length).fill("");
    const imagePromises: Promise<void>[] = [];
    const venues: Venue[] = [];
    const plans: Plan[] = [];


    for (const [i, p] of rawPlans.entries()) {
      const step = i + 1;
      logger.info(`📍 Plan ${step}: enriching venue`);
      const venue = await enrichVenue(p.venueName || p.title, location);
      logger.info(`📍 Plan ${step}: venue enriched (${venue.name})`);
      venues.push(venue);

      if (venue.photoUrl) {
        heroUrls[i] = venue.photoUrl;
        logger.info(`🖼️ Plan ${step}: using Google Places photo`);
      } else {
        const style = i % 2 === 0 ? "Studio Ghibli" : "Korean manhwa";
        logger.info(`🎨 Plan ${step}: generating illustration (${style})`);
        const imgP = makeIllustration(p.title, location, style)
          .then((url) => {
            logger.info(`🎨 Plan ${step}: illustration done`);
            heroUrls[i] = url;
          })
          .catch(() => {
            heroUrls[i] = "";
          });
        imagePromises.push(imgP);
      }
    }

    // Wait for any illustrations we kicked off
    if (imagePromises.length) {
      await Promise.all(imagePromises);
    }

    for (const [i, p] of rawPlans.entries()) {
      plans.push({
        id: crypto.randomUUID(),
        title: p.title,
        itinerary: p.itinerary,
        heroImgUrl: heroUrls[i],
        venue: venues[i],
        scores: computeScores(venues[i], p.itinerary),
      });
    }

    // Persist to Firestore under user if authenticated
    if (uid !== "anonymous") {
      const batch = db.batch();
      const userPlansRef = db.collection("users").doc(uid).collection("plans");
      plans.forEach((plan) => {
        const docRef = userPlansRef.doc();
        batch.set(docRef, {
          ...plan,
          createdAt: Date.now(),
        });
      });
      await batch.commit();
    }

    // --- Analytics event: plan_generation ---
    try {
      await db.collection("analyticsEvents").add({
        uid,
        event: "generate_plan",
        location,
        preferences,
        budget,
        timeOfDay,
        planCount: plans.length,
        createdAt: Date.now(),
      });
    } catch (e) {
      logger.warn("Analytics logging failed", e as Error);
    }

    logger.info(`✅ Completed in ${Date.now() - t0}ms`);
    res.status(200).json({plans});
  } catch (err) {
    logger.error("generatePlans failed", err as Error);
    res.status(500).json({error: "Internal error"});
  }
});
