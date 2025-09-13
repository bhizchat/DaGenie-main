import {onRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import OpenAI from "openai";
import {inferFormatWithScores} from "./veo/inferFormat";
import {AdBrief} from "./veo/brief";

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const ELEVENLABS_API_KEY = defineSecret("ELEVENLABS_API_KEY");

// Initialize Admin SDK once
try {
  admin.app();
} catch {
  admin.initializeApp();
}

type ChatMessage = {role: "user" | "assistant" | "system"; content: string};

// --- Phase 1: VideoPromptV1 schema/types (runtime-validated) ---
type VideoPromptV1 = {
  meta: { version: "VideoPromptV1"; createdAt: string; uid?: string; jobId?: string };
  product: { name?: string; description: string; imageGsPath?: string };
  style: "cinematic" | "creative_animation";
  audio: { preference: "with_sound" | "no_sound"; voiceoverScript?: string; musicMood?: string; sfxHints?: string[] };
  cta: { key: string; copy: string };
  scenes: Array<{ id: string; duration_s: number; beats: string[]; shots: Array<{ camera: string; subject: string; action: string; textOverlay?: string }> }>;
  output: { resolution: "1080x1920" | "1920x1080" | "1:1" | string; duration_s: number; fps?: number };
};

function stripControlChars(str: string): string {
  // Replace ASCII control chars (0..31) with spaces without using control-char regex
  let out = "";
  for (let i = 0; i < str.length; i++) {
    const code = str.charCodeAt(i);
    out += (code >= 32 ? str[i] : " ");
  }
  return out;
}

function clampStr(s: any, max: number): string {
  const raw = typeof s === "string" ? s : String(s ?? "");
  const cleaned = stripControlChars(raw);
  return cleaned.trim().slice(0, max);
}

function clampArr<T>(arr: any, max: number): T[] {
  return Array.isArray(arr) ? arr.slice(0, max) : [];
}

function sanitizePrompt(input: Partial<VideoPromptV1>): { prompt: VideoPromptV1; flags: string[] } {
  const flags: string[] = [];
  const version = "VideoPromptV1" as const;
  const meta = {
    version,
    createdAt: new Date().toISOString(),
    uid: input.meta?.uid ? clampStr(input.meta.uid, 128) : undefined,
    jobId: input.meta?.jobId ? clampStr(input.meta.jobId, 128) : undefined,
  } as VideoPromptV1["meta"];

  const style: VideoPromptV1["style"] = input.style === "creative_animation" ? "creative_animation" : "cinematic";
  if (input.style !== style) flags.push("style_defaulted");

  const audioPref: "with_sound" | "no_sound" = input.audio?.preference === "no_sound" ? "no_sound" : "with_sound";
  const audio: VideoPromptV1["audio"] = {
    preference: audioPref,
    voiceoverScript: input.audio?.voiceoverScript ? clampStr(input.audio.voiceoverScript, 800) : undefined,
    musicMood: input.audio?.musicMood ? clampStr(input.audio.musicMood, 120) : undefined,
    sfxHints: clampArr<string>(input.audio?.sfxHints, 10).map((s) => clampStr(s, 80)),
  };

  const product: VideoPromptV1["product"] = {
    name: input.product?.name ? clampStr(input.product.name, 120) : undefined,
    description: clampStr(input.product?.description ?? "", 400),
    imageGsPath: input.product?.imageGsPath ? clampStr(input.product.imageGsPath, 300) : undefined,
  };

  const cta: VideoPromptV1["cta"] = {
    key: clampStr(input.cta?.key ?? "", 80),
    copy: clampStr(input.cta?.copy ?? "", 160),
  };

  const scenesIn = clampArr<any>(input.scenes, 8).map((s, idx) => ({
    id: clampStr(s?.id ?? `s${idx + 1}`, 16),
    duration_s: Math.max(1, Math.min(12, Number(s?.duration_s ?? 4))),
    beats: clampArr<string>(s?.beats, 8).map((b) => clampStr(b, 120)),
    shots: clampArr<any>(s?.shots, 6).map((sh: any) => ({
      camera: clampStr(sh?.camera ?? "", 120),
      subject: clampStr(sh?.subject ?? "", 160),
      action: clampStr(sh?.action ?? "", 160),
      textOverlay: sh?.textOverlay ? clampStr(sh?.textOverlay, 80) : undefined,
    })),
  }));

  const output: VideoPromptV1["output"] = {
    resolution: (input.output?.resolution as any) || "1080x1920",
    duration_s: Math.max(6, Math.min(20, Number(input.output?.duration_s ?? 12))),
    fps: input.output?.fps ? Math.max(24, Math.min(60, Number(input.output.fps))) : undefined,
  };

  const prompt: VideoPromptV1 = {meta, product, style, audio, cta, scenes: scenesIn, output};
  if (product.description.length >= 400) flags.push("product_desc_truncated");
  return {prompt, flags};
}

export const voiceAssistant = onRequest({
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
  cors: true,
  secrets: [OPENAI_API_KEY, ELEVENLABS_API_KEY],
}, async (req, res) => {
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");

  function send(data: unknown) {
    res.write(`data: ${JSON.stringify(data)}\n\n`);
  }

  try {
    if (req.method !== "POST") {
      res.status(405);
      send({type: "error", message: "Method not allowed"});
      res.end();
      return;
    }

    // Build-final-prompt mode (plain JSON response, not SSE)
    if (req.body && req.body.action === "build_final_prompt") {
      const {history, styleKey, audioPreference, jobId} = req.body || {};
      const messages: ChatMessage[] = (history && Array.isArray(history)) ? history : [];
      const textContext = messages.map((m) => `${m.role}: ${m.content}`).join("\n");
      const category = inferCategory(textContext);
      const aspect = "16:9";
      const withSound = audioPreference === "with_sound";
      const creative = buildCreativeJson({category, styleKey: String(styleKey || "cinematic"), aspect, withSound, contextText: textContext});

      // Map creative skeleton to VideoPromptV1
      const rough: Partial<VideoPromptV1> = {
        meta: {version: "VideoPromptV1", createdAt: new Date().toISOString(), jobId},
        product: {description: deriveProductDescription(textContext)},
        style: (String(styleKey || "cinematic") === "creative_animation" ? "creative_animation" : "cinematic"),
        audio: {preference: withSound ? "with_sound" : "no_sound", voiceoverScript: deriveVoiceover(textContext)},
        cta: deriveCTA(textContext),
        scenes: deriveScenesFromCategory(creative, category),
        output: {resolution: aspect === "16:9" ? "1920x1080" : "1080x1920", duration_s: 12},
      };
      const {prompt, flags} = sanitizePrompt(rough);

      // Persist to Firestore if jobId provided
      if (jobId && typeof jobId === "string" && jobId.length > 0) {
        try {
          // Best-effort enrich with inputImagePath from job
          const jobRef = admin.firestore().collection("adJobs").doc(jobId);
          const snap = await jobRef.get();
          const jobData = snap.exists ? (snap.data() as any) : undefined;
          if (!prompt.product.imageGsPath && jobData?.inputImagePath) {
            prompt.product.imageGsPath = String(jobData.inputImagePath);
          }
          // Do not write undefined uid; only set if available
          const maybeUid = (req as any).auth?.uid;
          if (typeof maybeUid === "string" && maybeUid.length > 0) {
            prompt.meta.uid = maybeUid;
          } else {
            // Ensure undefined fields are dropped before write
            // JSON round-trip removes undefined recursively
            const tmp = JSON.parse(JSON.stringify(prompt));
            await jobRef.set({promptV1: tmp}, {merge: true});
            console.log("[build_final_prompt] wrote without uid");
            // Also respond
            console.log("[prompt_build]", {len: textContext.length, scenes: prompt.scenes.length, flags});
            res.setHeader("Content-Type", "application/json");
            res.status(200).send({prompt: tmp, flags}).end();
            return;
          }
          // Normal write path (uid set)
          await jobRef.set({promptV1: prompt}, {merge: true});
        } catch (e) {
          console.error("[build_final_prompt] firestore write error", (e as any)?.message);
        }
      }

      // Analytics-style log (stdout)
      console.log("[prompt_build]", {len: textContext.length, scenes: prompt.scenes.length, flags});

      res.setHeader("Content-Type", "application/json");
      res.status(200).send({prompt, flags}).end();
      return;
    }

    const {history, voice, tts, speakText, imageDataUrl, imageUrl, imageGsPath} = req.body ?? {} as {
      history: ChatMessage[];
      voice?: string;
      tts?: "eleven" | "apple";
      speakText?: string;
      imageDataUrl?: string; // data URL like data:image/jpeg;base64,xxx
      imageUrl?: string; // remote URL (https)
      imageGsPath?: string; // gs://bucket/object (for meta/logging only)
    };

    const messages: ChatMessage[] = (history && Array.isArray(history)) ? history : [];
    const imageUrlToUse = (typeof imageUrl === "string" && imageUrl.length > 0) ?
      imageUrl :
      ((typeof imageDataUrl === "string" && imageDataUrl.startsWith("data:")) ? imageDataUrl : undefined);
    // Emit a meta event so the client can log that we saw the image and text
    const imagePresent = !!(imageUrlToUse || (typeof imageGsPath === "string" && imageGsPath.startsWith("gs://")));
    send({type: "meta", image: imagePresent, lastUserLen: (messages[messages.length - 1]?.content?.length) || 0});
    console.log("[voiceAssistant] image_present=", imagePresent, imageUrlToUse ? String(imageUrlToUse).slice(0, 32) : (imageGsPath ? String(imageGsPath).slice(0, 32) : ""));

    // Determine last user message content to guide language
    const lastUser = [...messages].reverse().find((m) => m.role === "user");
    const languageGuard: ChatMessage = {
      role: "system",
      content: "Respond strictly in the same language as the user's last message. Keep tone natural; do not translate to another language. If the user writes in Spanish, reply in Spanish; if Japanese, reply in Japanese; mirror the user's language and script.",
    };

    const openai = new OpenAI({apiKey: process.env.OPENAI_API_KEY});
    // Guardrails & open-ended follow-up strategy
    const systemGuard: ChatMessage = {
      role: "system",
      content: [
        "You are 'Genie', a friendly creative companion that helps small businesses create short video ads.",
        "Tone: encouraging, brand-first, concise, no jargon. Acknowledge what the user says and, if an image is attached, briefly describe it in one sentence so they know you understood.",
        "Follow-up strategy (ask at most one question per turn, only if missing):",
        "Q1: ‘This will help me tailor the video perfectly for you. Tell me about your product in your own words—what makes it special, and who is it for?’",
        "Q2: ‘How do you want people to feel and think after watching? Give me 2–3 words (e.g., cozy, trustworthy; bold, exciting).’",
        "Q3: ‘If we could show one moment that proves its value, what would we see or hear? Describe a scene, vibe, or a line customers say.’",
        "Optional: Only if not provided and relevant — ‘Would you like a closing message or tagline at the end?’",
        "Do not ask the user to choose a format or style. Ask one question at a time, keep each question under 2 sentences, value-frame why you ask, and wait for the answer before proceeding.",
        "CRITICAL: Never draft or propose an ad script, scenes, storyboard, shot list, or voiceover. Never write lines like 'Here’s a draft', 'Scene:', 'Voiceover:', 'Cut to', or bracketed beats. Keep outputs to short acknowledgements and one question only.",
      ].join(" \n"),
    };
    console.log("[voiceAssistant] messages count=", messages.length);

    // When speakText is provided, bypass the LLM and just speak that text (still stream tokens)
    let fullText = "";
    if (typeof speakText === "string" && speakText.trim().length > 0) {
      fullText = speakText.trim();
      // Stream word-by-word to mimic real-time narration
      const pieces = fullText.match(/\S+\s*/g) ?? [fullText];
      for (const p of pieces) {
        send({type: "token", text: p});
        // small pacing delay so UI can animate streaming text
        await new Promise((r) => setTimeout(r, 25));
      }
    } else {
      // Build multimodal-capable message list for OpenAI (open-ended flow)
      const mmMessages: any[] = [];
      mmMessages.push(systemGuard);
      if (lastUser) mmMessages.push(languageGuard);
      for (const m of messages) {
        mmMessages.push({role: m.role, content: m.content});
      }
      // If an image is provided, append a user message with multimodal parts
      if (imageUrlToUse) {
        mmMessages.push({
          role: "user",
          content: [
            {type: "text", text: "Consider the attached product image while understanding my request."},
            {type: "image_url", image_url: {url: imageUrlToUse}},
          ],
        });
      }
      // Stream the assistant reply token-by-token
      const stream = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: mmMessages as any,
        stream: true,
        temperature: 0.7,
      });

      for await (const part of stream) {
        const delta = part.choices?.[0]?.delta?.content ?? "";
        if (delta) {
          fullText += delta;
          send({type: "token", text: delta});
        }
      }
    }

    // TTS step (optional)
    const useEleven = (tts ?? "eleven") === "eleven" && !!process.env.ELEVENLABS_API_KEY;
    if (useEleven && fullText.trim().length > 0) {
      try {
        const voiceId = voice || "21m00Tcm4TlvDq8ikWAM"; // default voice
        const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
          method: "POST",
          headers: {
            "xi-api-key": process.env.ELEVENLABS_API_KEY as string,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
          },
          body: JSON.stringify({
            text: fullText,
            model_id: "eleven_multilingual_v2",
            optimize_streaming_latency: 0,
          }),
        });

        // Validate ElevenLabs response before emitting audio
        if (!r.ok) {
          const errBody = await r.text();
          console.error("[voiceAssistant] elevenlabs error", r.status, errBody?.slice(0, 300));
          send({type: "tts_fallback", message: `elevenlabs ${r.status}`, detail: errBody?.slice(0, 300)});
          // Do not block flow if TTS fails
        } else {
          const contentType = r.headers.get("content-type") || "";
          const ab = await r.arrayBuffer();
          if (!ab || ab.byteLength === 0) {
            console.error("[voiceAssistant] elevenlabs empty audio");
            send({type: "tts_fallback", message: "empty audio payload"});
          } else {
            const buf = Buffer.from(ab);
            const b64 = buf.toString("base64");
            send({type: "audio", format: contentType.includes("mpeg") ? "mp3" : contentType, base64: b64, bytes: buf.length});
          }
        }
      } catch (e: any) {
        console.error("[voiceAssistant] elevenlabs exception", e?.message);
        send({type: "tts_fallback", message: e?.message || "elevenlabs failed"});
      }
    } else {
      send({type: "tts_fallback"});
    }

    // After the chat turn, infer format from the latest conversation so the client can confirm and generate
    try {
      const textContext = messages.map((m) => `${m.role}: ${m.content}`).join("\n");
      const lastUserText = (messages[messages.length - 1]?.content || "").toLowerCase();
      const brief: AdBrief = {
        productName: undefined,
        category: /phone|laptop|mouse|headset|watch|camera|device|gadget/.test(textContext) ? "electronics" : undefined,
        productTraits: [],
        audience: undefined,
        brandPersona: [],
        desiredPerception: (textContext.match(/(cozy|calm|premium|luxurious|playful|bold|excited|trustworthy|modern|minimal)/gi) || []).map((v) => v.toLowerCase()),
        proofMoment: undefined,
        styleWords: [],
        cta: null,
        durationSeconds: null,
        aspectRatio: /16\s*:\s*9/.test(textContext) ? "16:9" : "9:16",
        brand: {},
        assets: {},
      } as AdBrief;
      const {format, roomScore, prodScore} = inferFormatWithScores(brief);
      console.log("[voiceAssistant] format_preview", {format, roomScore, prodScore, lastUser: lastUserText.slice(0, 120)});
      send({type: "format_preview", format, roomScore, prodScore});
      // Ask client to show the confirmation/generate affordance
      send({type: "request_confirmation"});
    } catch (e: any) {
      console.error("[voiceAssistant] format_preview_error", e?.message);
    }

    send({type: "done"});
    res.end();
    return;
  } catch (err: any) {
    send({type: "error", message: err?.message || "unknown"});
    res.end();
    return;
  }
});

// Helpers
function inferCategory(text: string): string {
  const t = (text || "").toLowerCase();
  if (/(coke|coca[- ]cola|soda|beverage|coffee|latte|espresso|beer|corona)/.test(t)) return "beverage_crave";
  if (/(perfume|dior|miss dior|fragrance|luxury|louis vuitton|lv|handbag)/.test(t)) return "luxury_minimal";
  if (/(iphone|samsung|galaxy|phone|laptop|headset|vision pro|head-mounted|vr|ar)/.test(t)) return "tech_reveal";
  if (/(jeep|ferrari|maserati|car|wrangler|auto|vehicle)/.test(t)) return "auto_crate";
  if (/(room|bedroom|ikea|capsule|box opens|transforms|plush|toy|pok[eé]? ball|labubu|tom & jerry|pikachu)/.test(t)) return "room_transformation";
  if (/(thread|embroidery|logo to|logo-to|stitch)/.test(t)) return "fashion_logo_to_product";
  return "product_commercial";
}

function buildCreativeJson(params: { category: string; styleKey: string; aspect: string; withSound: boolean; contextText: string }) {
  const {category, styleKey, aspect, withSound} = params;
  const base: any = {
    type: category,
    aspect_ratio: aspect,
    audio: {sfx: withSound ? "yes" : "no", notes: withSound ? "Include tasteful SFX; subtle music." : "No dialogue or SFX; purely visual."},
    style: styleKey === "cinematic" ? "cinematic photorealistic" : "creative surreal animation",
    negative_prompts: ["no text"],
  };
  const description = category === "beverage_crave" ?
    "Macro crave aesthetic in a black void. Energy wave reveals product silhouette; liquid fills the form; condensation builds." :
    category === "room_transformation" ?
      "Fixed wide shot. A themed container pops; items assemble mid-air into a styled space in clean hyper-lapse." :
      category === "luxury_minimal" ?
        "Pastel or velvet void. Iconic element transforms into product with elegant, minimal motion." :
        category === "tech_reveal" ?
          "Futuristic showroom. Logo/energy ripple morphs into device; lighting glides across glass and metal." :
          category === "auto_crate" ?
            "Dark stage. Branded crate opens; energy/wireframe constructs environment and vehicle; wireframe dissolves to real." :
            category === "fashion_logo_to_product" ?
              "Golden threads flow from logo, weaving the product before a soft, luxurious spotlight." :
              "Cinematic product commercial with a magical reveal and precise hero ending.";
  const finalTextPromptForAi = `${description} Aspect ${aspect}. ${withSound ? "Include tasteful SFX and subtle score." : "No sound."}`;
  return {
    ...base,
    description,
    environment: {setting: "stage/void or appropriate space", mood: "elevated, brand-forward"},
    camera: {framing: "centered hero", movement: styleKey === "cinematic" ? "slow dolly/push" : "playful arcs"},
    elements: [],
    motion: "build/reveal then hold",
    ending: "clean hero frame",
    final_text_prompt_for_ai: finalTextPromptForAi,
  };
}

// --- Derivation helpers for Phase 1 ---
function deriveProductDescription(text: string): string {
  const t = (text || "").trim();
  // Cheap heuristic: last user line, stripped, clamped
  const last = t.split(/\n/).reverse().find((l) => /user: /i.test(l)) || t;
  return (last.replace(/^user:\s*/i, "").slice(0, 200)) || "Product for a short commercial";
}

function deriveVoiceover(text: string): string | undefined {
  if (!/with sound|dialogue|voice|voiceover|effects|sfx|music/i.test(text)) return undefined;
  // Seed a one-line VO; LLM or editor can expand later
  return "A short, punchy line that matches the reveal and ends with the CTA.";
}

// --- Option-aware CTA classifier helpers ---
type CtaCandidate = { key: string; synonyms: string[] };

function buildCtaCandidates(category: string): CtaCandidate[] {
  const base: CtaCandidate[] = [
    {key: "online_orders", synonyms: ["online", "order", "orders", "website", "buy online", "checkout", "purchase online"]},
    {key: "in_store_purchase", synonyms: ["store", "in store", "in person", "shop", "retail", "go to the store", "purchase in store"]},
    {key: "store_locator", synonyms: ["nearby", "find a store", "locator", "locations", "near me", "map"]},
    {key: "reservations", synonyms: ["reserve", "reservation", "book", "booking", "table"]},
    {key: "app_install", synonyms: ["install", "download", "app", "get the app"]},
    {key: "coupon", synonyms: ["coupon", "promo", "promo code", "discount", "code"]},
    {key: "add_to_cart", synonyms: ["add to cart", "add it to cart", "add to basket", "cart"]},
  ];
  if (category === "beverage_crave") {
    return [base[0], base[1], base[2], base[5], base[6]]; // online, in-store, locator, coupon, add_to_cart
  }
  return base;
}

function tokenize(s: string): string[] {
  return (s.toLowerCase().replace(/[^a-z0-9\s]/g, " ").match(/\b[\w-]{2,}\b/g) || []);
}

function jaroWinkler(a: string, b: string): number {
  const s1 = a; const s2 = b;
  const m = Math.floor(Math.max(s1.length, s2.length) / 2) - 1;
  let matches = 0; let transpositions = 0;
  const s1Matches = new Array(s1.length).fill(false);
  const s2Matches = new Array(s2.length).fill(false);
  for (let i = 0; i < s1.length; i++) {
    const start = Math.max(0, i - m);
    const end = Math.min(i + m + 1, s2.length);
    for (let j = start; j < end; j++) {
      if (s2Matches[j]) continue;
      if (s1[i] !== s2[j]) continue;
      s1Matches[i] = true; s2Matches[j] = true; matches++; break;
    }
  }
  if (matches === 0) return 0;
  let k = 0;
  for (let i = 0; i < s1.length; i++) {
    if (!s1Matches[i]) continue;
    while (!s2Matches[k]) k++;
    if (s1[i] !== s2[k]) transpositions++;
    k++;
  }
  const jaro = (matches / s1.length + matches / s2.length + (matches - transpositions / 2) / matches) / 3;
  let prefix = 0;
  for (let i = 0; i < Math.min(4, Math.min(s1.length, s2.length)); i++) {
    if (s1[i] === s2[i]) prefix++; else break;
  }
  return jaro + prefix * 0.1 * (1 - jaro);
}

function classifyCta(userText: string, candidates: CtaCandidate[]): { key: string; score: number } | null {
  const toks = tokenize(userText);
  if (toks.length === 0) return null;
  const joined = toks.join(" ");
  const negWords = new Set(["no", "not", "without", "don't", "dont", "never"]);

  function containsNegationNear(term: string): boolean {
    const arr = toks;
    for (let i = 0; i < arr.length; i++) {
      if (arr[i] === term) {
        for (let j = Math.max(0, i - 2); j <= Math.min(arr.length - 1, i + 2); j++) {
          if (negWords.has(arr[j])) return true;
        }
      }
    }
    return false;
  }

  let best: { key: string; score: number } | null = null;
  for (const c of candidates) {
    let score = 0;
    for (const syn of c.synonyms) {
      const s = syn.toLowerCase();
      if (joined.includes(s)) score += 2; else {
        for (const t of toks) {
          const sim = jaroWinkler(t, s);
          if (sim >= 0.92) {
            score += 1.2; break;
          }
          if (sim >= 0.85) {
            score += 0.6;
          }
        }
      }
      const synHead = s.split(" ")[0];
      if (containsNegationNear(synHead)) score -= 2.5;
    }
    if (!best || score > best.score) best = {key: c.key, score};
  }
  if (best && best.score >= 1.2) return best;
  return null;
}

function deriveCTA(text: string): { key: string; copy: string } {
  const category = inferCategory(text);
  const opts = buildCtaCandidates(category);
  const guess = classifyCta(text, opts);
  if (guess) {
    const copy = guess.key === "online_orders" ? "Order now" :
      guess.key === "in_store_purchase" ? "Find it in-store" :
        guess.key === "store_locator" ? "Find a nearby store" :
          guess.key === "reservations" ? "Book now" :
            guess.key === "app_install" ? "Download the app" :
              guess.key === "coupon" ? "Get your coupon" :
                guess.key === "add_to_cart" ? "Add to cart" : "Learn more";
    return {key: guess.key, copy};
  }
  return {key: "learn_more", copy: "Learn more"};
}

function deriveScenesFromCategory(creative: any, category: string) {
  // Minimal scene scaffolds that conform to VideoPromptV1.sentence structure
  const scenes: any[] = [];
  if (category === "beverage_crave") {
    scenes.push({id: "s1", duration_s: 4, beats: ["Energy wave reveals outline"], shots: [{camera: "macro pullback", subject: "bottle silhouette", action: "glowing fizz trails"}]});
    scenes.push({id: "s2", duration_s: 4, beats: ["Liquid fills silhouette"], shots: [{camera: "tight hero", subject: "liquid pour", action: "condensation grows"}]});
    scenes.push({id: "s3", duration_s: 4, beats: ["Hero hold"], shots: [{camera: "centered hero", subject: "bottle", action: "soft fog, subtle spin"}]});
  } else if (category === "room_transformation") {
    scenes.push({id: "s1", duration_s: 2, beats: ["Container trembles"], shots: [{camera: "fixed wide", subject: "themed box", action: "dust puff"}]});
    scenes.push({id: "s2", duration_s: 6, beats: ["Items assemble in hyper-lapse"], shots: [{camera: "fixed wide", subject: "room items", action: "precise snap into place"}]});
    scenes.push({id: "s3", duration_s: 4, beats: ["Final hold"], shots: [{camera: "fixed wide", subject: "finished room", action: "calm hold"}]});
  } else if (category === "tech_reveal") {
    scenes.push({id: "s1", duration_s: 4, beats: ["Logo ripple morph"], shots: [{camera: "slow drift", subject: "logo", action: "fluid glass ripple"}]});
    scenes.push({id: "s2", duration_s: 4, beats: ["Device forms"], shots: [{camera: "orbit micro", subject: "device", action: "light dances on glass and metal"}]});
    scenes.push({id: "s3", duration_s: 4, beats: ["Hero hold"], shots: [{camera: "low wide", subject: "device", action: "clean studio glow"}]});
  } else {
    scenes.push({id: "s1", duration_s: 4, beats: ["Magical reveal"], shots: [{camera: "centered", subject: "product", action: "tasteful transformation"}]});
    scenes.push({id: "s2", duration_s: 4, beats: ["Brand moment"], shots: [{camera: "macro detail", subject: "signature element", action: "light accent"}]});
    scenes.push({id: "s3", duration_s: 4, beats: ["Hero hold"], shots: [{camera: "hero", subject: "product", action: "steady hold"}]});
  }
  return scenes;
}


