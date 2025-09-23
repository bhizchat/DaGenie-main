/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import axios from "axios";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const db = getFirestore();

type Shot = {
  index: number;
  action: string;
  animation?: string;
  speech?: string;
  imageUrl: string; // avatar image used as i2v anchor
};

/**
 * Cloned storyboard generator specifically for the music-video flow.
 * For now, this scaffolds an 8-shot plan and enqueues WAN generation for each shot.
 * Later, replace the shot planning with Nano Banana + beats-aware logic.
 */
// Core handler used by both V1 and V2 exports
const generateMusicStoryboardHandler = async (req: functions.https.Request, res: functions.Response<any>) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      const {uid, projectId, settingId, referenceImageUrl, audioGsPath, promptKit, ideaText, storyboardId} = (req.body || {}) as any;
      if (!uid || !projectId || !referenceImageUrl) { res.status(400).json({error: "bad_request"}); return; }

      // Create storyboard doc (use provided storyboardId if present to allow immediate client navigation)
      const sbColl = db.collection("users").doc(uid).collection("musicVideos").doc(projectId).collection("storyboards");
      const sbRef = storyboardId ? sbColl.doc(String(storyboardId)) : sbColl.doc();
      const now = Timestamp.now();
      const idea = String(ideaText || "").toLowerCase();
      await sbRef.set({
        uid,
        projectId,
        status: "created",
        createdAt: now,
        updatedAt: now,
        isLatest: true,
        mode: "music-video",
        settingId: settingId || null,
        ideaText: idea || null,
      }, {merge: true});
      functions.logger.info("generateMusicStoryboard.storyboard_created", {uid, projectId, storyboardId: sbRef.id, path: sbRef.path});

      // Use promptKit cues to name actions and animations (camera only; no 'Hook/Verse' fallback)
      const camera: string[] = Array.isArray(promptKit?.cameraGrammar) && promptKit.cameraGrammar.length > 0 ? promptKit.cameraGrammar : [
        "orbit 12°", "micro dolly-in", "parallax pass", "crane-up reveal"
      ];
      const environment: string = String(promptKit?.environment || "");
      const fpsHint: string = String(promptKit?.fpsHint || "");
      const bio: string = String(promptKit?.bio || "");
      // Use a human‑readable style string instead of settingId
      const styleDesc: string = ["3D stylized", bio].filter(Boolean).join(" — ");

      // Lighting presets for animation hints
      const lighting: string[] = ["neon rim + soft key", "tungsten practicals + colored fill", "hard key with haze volumetrics"];

      // Lightweight idea blending: prioritize keywords to bias beat/prop selection
      const kw = new Set(idea.split(/[^a-z0-9]+/).filter(Boolean));
      function bias<T>(arr: T[], predicate: (t: T) => boolean, boost = 2): T[] {
        // duplicate matching items to increase selection probability
        const out: T[] = [];
        for (const a of arr) { out.push(a); if (predicate(a)) { for (let i = 0; i < boost; i++) out.push(a); } }
        return out.length ? out : arr;
      }
      const camBiased = bias(camera, (c) => kw.has("orbit") ? /orbit/i.test(String(c)) : kw.has("dolly") ? /dolly/i.test(String(c)) : false);
      const lightBiased = bias(lighting, (l) => kw.has("neon") ? /neon/i.test(String(l)) : kw.has("tungsten") ? /tungsten/i.test(String(l)) : false);

      // Gesture/move/framing vocab
      // (Lightweight; actPrefs below references the literals so we don't need these arrays elsewhere)

      function pick<T>(arr: T[]): T { return arr[Math.floor(Math.random() * arr.length)]; }

      // Act preferences were used for randomized movement; retained here for reference but no longer used

      // Positioning
      const positions = [
        "center hero",
        "left thirds foreground",
        "right thirds foreground",
        "depth block with foreground prop",
        "back‑to‑camera then look‑back",
      ];

      // Setting key helper
      const normalizeSetting = (s: string): string => String(s || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
      const settingKey = normalizeSetting(settingId || "");

      // Deprecated universal beats (kept in history for reference) – not used
      /* const UNIVERSAL_BEATS_ALL: string[] = [
        "Rap straight to camera (no mic, hand gestures)",
        "Walk-and-rap toward a tracking camera",
        "Post up with the crew (wide posse shot)",
        "Flex jewelry (close-ups of chains, rings, watches)",
        "Flash designer fits (runway walk, look-backs)",
        "Count, fan, or toss cash (money rain)",
        "Step out of a luxury car (doors up)",
        "Cruise a city strip (convertible/low-angle car rig)",
        "Rooftop performance with skyline behind",
        "Warehouse or parking-garage set",
        "Neon wall / LED tunnel walk-through",
        "Fish-eye lens close-ups (90s homage)",
        "Ultra-wide, low angle 'larger-than-life' shot",
        "Slow-motion strut through smoke",
        "Performance in a circle of cars (headlights rim light)",
        "Split screens / multi-panel edits (retro look)",
        "Dutch-angle push-ins for emphasis",
        "Snappy whip-pans on ad-libs",
        "Freeze-frame on punchlines (text or pose)",
        "Lip-sync on a moving dolly or steadicam",
        "Choreographed two-step with the crew",
        "Call-and-response hand cues (point to camera -> crowd)",
        "Show off grills / smile glints",
        "Close-up on tat details while holding a pose",
        "Champagne pop / soda spray (party vibe)",
        "Smoke plumes, foggers for backlight rays",
        "Drone or crane orbits around the artist",
        "Time-lapse city transitions (day->night)",
        "'Throne' pose (armchair, car hood, stoop)",
        "Basketball court cypher",
        "Barbershop cameo shot",
        "Corner-store 'bodega' scene",
        "Stoop storytelling with neighbors",
        "Alleyway performance with neon signage",
        "Graffiti wall backdrops; tag reveal on the beat",
        "Projection mapping on walls/clothes",
        "Color-gel red/blue split lighting on face",
        "Strobe hits on drops",
        "Quick rack-focus to jewelry or a lyric-specific prop",
        "POV shots from the driver's seat",
        "Wheel-spins / burnout B-roll",
        "Product placement on a table/console",
        "Smartphone selfie moments inside the video",
        "Mirror shots (bathroom, dressing room)",
        "Performance in rain (backlit droplets)",
        "Silhouette against a giant LED screen",
        "Green-screen surreal cutaways (floating items)",
        "Speed-ramped performance (under/over-crank)",
        "Match-cut outfit swaps on the snare",
        "'Before & after' glow-up montage",
        "Homage to classic videos (big fisheye / glossy colors)",
        "Story inserts (brief narrative beats)",
        "Performance-only 'pure visual' sections",
        "Conceptual set pieces (looping hallway, angled rooms)",
        "Car-to-car performance (artist in one, camera in another)",
        "Hood cameo parade (friends/family drive-by waves)",
        "'Counting blessings' prayer pose cutaway",
        "Snap zooms on name-drops",
        "Walk through a tunnel of phones filming",
        "Confetti cannons on the hook",
        "Fireworks / spark fountains (safe SFX)",
        "Light-painting with LED sticks",
        "High-speed lens on jewelry for sparkle trails",
        "Close-ups of hands while rapping (rings, gestures)",
        "Dance break with TikTokable moves",
        "Crowd wave from balcony/box seats",
        "On-set 'behind-the-scenes' inserts (slate, director hand)",
        "Vintage camcorder overlay / VHS filter",
        "Fish-eye handheld cypher spin (classic 90s feel)",
        "Hyper-saturated color grade (magenta/cyan)",
        "Luxury interiors (penthouse, hotel corridor)",
        "Private jet runway walk-by (establishing flex)",
        "Yacht deck performance (wide drone pullback)",
        "Jewelry 'table layout' insert (case opening)",
        "Designer store window reflections (night exterior)",
        "Car meet-up donuts around the artist",
        "Laser grid on the floor (club look)",
        "Crowd chant with hands up (stadium or gym)",
        "Industrial fans kicking dust/smoke for backlight rays",
        "Hologram or AR doubles of the artist",
        "Lyric-synced on-screen typography pops",
        "'Freeze world' effect while artist moves",
        "Reverse/rebound shots (liquid, confetti, jump)",
        "Quick 'photo shoot' montage inside the video",
        "Split-tone B&W sections for verses",
        "Speed ramp into a jump cut (impact edit)",
        "Whip-pan transitions between locations",
        "Car interior LED strips pulsing to the beat",
        "Low-key 'documentary' inserts (walking through the block)",
        "Drone top-down over intersections (grid symmetry)",
        "Performance on a flatbed truck moving through the city",
        "Shadow-only performance (silhouette wall dance)",
        "Crowd tunnel walk (friends flanking, camera backward)",
        "Artist signs a kid's hat or dap with elders (community nod)",
        "'Phone call' or FaceTime insert as a narrative beat",
        "Fashion runway strut down a street/bridge",
        "Final money-shot pull-out: city/arena reveal (fireworks)",
      ]; */
      // No universal beats or extra sampling; only use the setting's own list

      // Story templates (ordered beats) — 4 variants per setting.
      // Keep copy short and cinematic; each line is a shot idea.
      const STORY_TEMPLATES: Record<string, string[][]> = {
        [normalizeSetting("afro_japan")]: [
          [
            "Torii gate arrival; respectful nod",
            "Shoes off at genkan; enter townhouse",
            "Tea ceremony with a local — quiet smiles",
            "Lantern alley walk; neon kanji wake",
            "Training kata in courtyard; brush-stroke light",
            "Market lane cypher; call-and-response",
            "Cherry blossoms drift; close-up hands catching petals",
            "Rooftop look‑out; city glows below",
            "Paper fan flourish; playful bow",
            "Night parade passes; you lead the step",
            "Temple drums hit; head‑nod to camera",
            "Final rooftop pose; blossoms rain"
          ],
          [
            "Alley projection‑graffiti animates to beat",
            "Kimono‑streetwear fit reveal",
            "Meet‑cute at tea counter; share a pour",
            "Shrine courtyard cypher spin",
            "Calligraphy swipe reveals name",
            "Bridge crossing in light mist",
            "Taiko rim shots; hand chops in sync",
            "Festival masks crowd tunnel; high‑five",
            "Neon kanji skyline crane‑up",
            "Haiku punchline freeze pose",
            "Paper lanterns rise to sky",
            "Rooftop ‘throne’ pose, city beyond"
          ],
          [
            "Temple gate slow walk‑in",
            "Tatami tea set out; steam curls",
            "Low‑angle hero frame under lanterns",
            "Street vendor exchange; nod and smile",
            "Kendo footwork on vinyl mats (no blade)",
            "Fish‑eye courtyard spin",
            "Profile glide past shoji silhouettes",
            "Coin toss lands in bowl, grin",
            "Brush‑stroke projections across jacket",
            "Top‑down crosswalk symmetry",
            "Friends gather; synchronized two‑step",
            "Rooftop fireworks flicker on faces"
          ],
          [
            "Rains clears; door slides open to night",
            "Gift a paper fan; shared laugh",
            "Tea steam close‑up; eyes meet",
            "Neon alley walk‑and‑rap tracking",
            "Shrine steps pose; petals fly",
            "Taiko sticks hit; edit on snare",
            "Bridge rails parallax; hand trace",
            "Street mural reveal; point to lens",
            "Roofline run; stop at edge",
            "Bells ring; camera crane‑out",
            "Crew joins; wide hero frame",
            "Final bow; city sparkle pull‑back"
          ]
        ],
        [normalizeSetting("mango_island")]: [
          [
            "Boat lands at biolume bay; step onto dock",
            "Shades on; grin to camera",
            "Mango grove path; hands brush leaves",
            "Taste test; goofy face then smirk",
            "Friends appear from trees; bounce",
            "Jet pack ignition; mini lift‑off gag",
            "Rocket POV to Mango Planet",
            "Low‑angle hover; hand chops on snare",
            "Photo‑shoot montage with props",
            "Peel‑swirl transition; outfit swap",
            "Confetti cannon of petals on hook",
            "Crane pull‑back; island fireworks"
          ],
          [
            "Dock arrival at golden hour",
            "Counting bars; ring sparkle close‑up",
            "Fruit market tease; money fan",
            "Light‑painting with LED sticks",
            "Drone orbit over throne of mangos",
            "Crew tunnel with lanterns",
            "Reverse splash gag on drop",
            "Rocket cockpit wink to skyline",
            "Mist walk‑through in slow‑mo",
            "Leaf logo reveal in sand",
            "Friends wave from jetty",
            "Final goodbye from Mango Rocket"
          ],
          [
            "Glowing river boardwalk walk‑in",
            "Palm‑up ‘watch this’",
            "Seed‑car drift passes behind",
            "Macro mango texture to horizon rack‑focus",
            "Orange fit swap jump‑cut",
            "Drone circles as you pose",
            "Call‑me hand cue; fruit drones orbit",
            "Chain flash; head nod",
            "Juice lens drip gag",
            "Slow strut through mist",
            "Peel swirl transition",
            "Rocket streaks into night"
          ],
          [
            "Island map stamp intro",
            "Outfit check in mirror water",
            "Follow fireflies into grove",
            "Friends pop from behind trees",
            "Climb mango throne; laugh",
            "Whip‑pan to jet pack spark",
            "Sky ride over island",
            "POV cockpit countdown 3‑2‑1",
            "Orbit at cloud level",
            "Drop back to parade beach",
            "Waves glitter on beat",
            "Slow crane‑out to star field"
          ]
        ],
        [normalizeSetting("candy_island")]: [
          [
            "Entrance under peppermint arch; palm‑out ‘follow’",
            "Candy‑striped shades on; wink",
            "Licorice runway walk; look‑back",
            "Lollipop taste; playful reaction",
            "Gummy parade bounce",
            "Chocolate fountain push‑in",
            "Shopping cart POV; point to lens",
            "Soda spray pop; laugh",
            "Split screens sweet vs sour",
            "Drone over gumdrop hill",
            "Hook outfit swaps on snares",
            "Fireworks over candy city"
          ],
          [
            "Neon gummy tunnel walk‑through",
            "Jawbreaker sparkle close‑up",
            "Candy drone initials in sky",
            "Cape sprinkles trail twirl",
            "Peppermint club strobe hits",
            "Reverse sprinkle fall catch",
            "Taffy pull sync to beat",
            "Boardwalk friends wave",
            "Soda‑pop jacket foams",
            "Marshmallow step sequence",
            "Dutch‑angle at chocolate river",
            "Final pull‑out city fireworks"
          ],
          [
            "Ticket booth intro; grin",
            "Sugar market montage",
            "Candy‑letter name spell",
            "Bridge pass parallax",
            "Candy drone swarm",
            "Pop‑art fashion board",
            "Gummy crowd bounce",
            "Raceway POV rush",
            "Peppermint skyline wide",
            "Windmill lollipop sweep",
            "Hook jump‑cut outfit swaps",
            "Sky glitter finale"
          ],
          [
            "Cotton‑candy clouds reveal",
            "Street dance with friends",
            "Macro sugar crystals rack‑focus",
            "Candy cart ride‑along",
            "Sticker bomb frame edge",
            "Lego workers cameo",
            "Light‑paint initials",
            "Candy confetti rain",
            "Giant jelly wobble gag",
            "Posed hero frame",
            "Slow pull‑back",
            "Final wink to camera"
          ]
        ],
        [normalizeSetting("astro_world")]: [
          [
            "Gates open to golden head; palm sweep",
            "Midway parade performance",
            "Ride‑POV coaster climb",
            "LED tunnel walk; constellations trace",
            "Prize booth money fan",
            "Astronaut streetwear swap",
            "Zero‑g hop freeze",
            "Whip‑pan between rides",
            "Ferris wheel drone orbit",
            "Blimps drift over chorus",
            "Spark fountains on drop",
            "Final skyline + golden head"
          ],
          [
            "Ticket scan close‑up",
            "Neon funhouse mirrors",
            "Game stall montage",
            "Slate clap BTS wink",
            "Laser grid floor glide",
            "Hologram doubles moonwalk",
            "Dark‑ride glow silhouettes",
            "Strobe alley walk",
            "Balloon silhouettes in sky",
            "Friends chant wave",
            "Day–night flip timelapse",
            "Fireworks finale"
          ],
          [
            "Map reveal with route line",
            "Entrance photo pose",
            "Parade float orbit",
            "Coaster drop hands‑up",
            "Ferris slow spin POV",
            "Prize win celebration",
            "Midway dance circle",
            "Mirror room infinity",
            "Tunnel of light sway",
            "Rooftop view of park",
            "Sky carnival blimps",
            "Crane pull‑out farewell"
          ],
          [
            "Golden head portal intro",
            "LED tunnel walk‑and‑rap",
            "Pop‑up photo ops montage",
            "Friends join parade",
            "Ride montage quick cuts",
            "Cotton candy laugh",
            "Hologram stage tease",
            "Drone pull‑back crowd",
            "Sparkler line on beat",
            "Balloon release",
            "Glow city wide",
            "Signature pose end"
          ]
        ],
        [normalizeSetting("grand_theft_arena")]: [
          [
            "Tunnel walk‑in; lights flicker",
            "Center court step; chain flash",
            "LED ribbons pulse to beat",
            "Two‑step with crew at logo",
            "Top‑down symmetry drone",
            "Strobe hits on drops",
            "Locker room confetti test",
            "Smoke fan slow‑mo strut",
            "Split screen locker/court/jumbotron",
            "Parking deck whip‑pan",
            "Circle of headlights rim‑light",
            "Jumbotron hero pull‑out"
          ],
          [
            "Arena gates open exterior",
            "Put on tinted shades; look up",
            "Court line chalk reveal",
            "Crew huddle clap",
            "Drift car lap outside",
            "Scoreboard flip on drop",
            "Pyro line burst",
            "Drone light‑show grid",
            "Sand‑floor projection map",
            "Champagne locker room",
            "Trophy lift freeze",
            "Stadium wide finale"
          ],
          [
            "Echoing footsteps through tunnel",
            "First step into light",
            "Slow push‑in to center logo",
            "Camera orbit as you perform",
            "Wide empty seats mood",
            "Crew enters from tunnel",
            "Quick rack‑focus to rings",
            "Fans fill seats (loop VFX)",
            "Overhead crane‑down",
            "Parking deck performance",
            "Circle cars headlights",
            "Helicopter city reveal"
          ],
          [
            "Press room mic check",
            "Walk to court corridor",
            "Open arena to reveal",
            "Warm‑up stretch sequence",
            "First verse at center",
            "Crowd wave B‑roll",
            "Mascot dance cameo",
            "Score bug overlay gag",
            "Cut to parking lap",
            "Return to court finale",
            "Glitter drop on hook",
            "Jumbotron flash end"
          ]
        ],
      };

      // Use template beats if available; otherwise fall back to worldPillars list
      const settingPool: string[] = [];
      const templatesForSetting = STORY_TEMPLATES[settingKey];
      const selectedBeats = (templatesForSetting && templatesForSetting.length)
        ? templatesForSetting[Math.floor(Math.random() * templatesForSetting.length)].slice()
        : (settingPool.length ? settingPool.slice() : []);

      function sanitizeBeat(b: string): string { return String(b); }

      // Convert a terse beat into an avatar-focused sentence, e.g.
      // "Climb mango throne; laugh" → "Avatar climbs the mango throne and laughs."
      function avatarizeAction(raw: string): string {
        const text = String(raw || "").replace(/[\u2013\u2014]/g, "-").trim();
        const joiner = (i: number) => (i === 0 ? "" : (i === 1 ? " and " : ", then "));
        const parts = text
          .replace(/\s*->\s*|\s*→\s*/g, ";")
          .split(/[;|-]/)
          .map((s) => s.trim())
          .filter((s) => s.length > 0);

        function presentTense(phrase: string): string {
          const lowers = phrase.toLowerCase();
          // If starts with a preposition, verb with a generic lead-in
          if (/^(into|to|through|across|under|over|from|with|past|toward|towards|around)\b/.test(lowers)) {
            return "moves " + phrase;
          }
          // Common verb mappings
          const verbMap: Record<string, string> = {
            "climb": "climbs",
            "climbs": "climbs",
            "laugh": "laughs",
            "laughs": "laughs",
            "rap": "raps",
            "raps": "raps",
            "perform": "performs",
            "performs": "performs",
            "deliver": "delivers",
            "delivers": "delivers",
            "follow": "follows",
            "follows": "follows",
            "walk": "walks",
            "walk-in": "walks in",
            "walks": "walks",
            "run": "runs",
            "runs": "runs",
            "pose": "poses",
            "poses": "poses",
            "smile": "smiles",
            "smiles": "smiles",
            "wink": "winks",
            "winks": "winks",
            "nod": "nods",
            "nods": "nods",
            "point": "points",
            "points": "points",
            "stamp": "stamps",
            "stamps": "stamps",
            "reveal": "reveals",
            "reveals": "reveals",
            "spin": "spins",
            "spins": "spins",
          };
          const tokens = phrase.split(/\s+/);
          const head = tokens[0].toLowerCase();
          if (verbMap[head]) {
            tokens[0] = verbMap[head];
            return tokens.join(" ");
          }
          // If looks like a noun-y fragment (e.g., "island map stamp intro"), try to detect an embedded verb
          if (/\bstamp\b/i.test(lowers)) {
            return phrase.replace(/\b(stamp|stamps)\b/i, "stamps").replace(/\bintro\b/i, "as an introduction");
          }
          if (/lip\s*-?sync/i.test(lowers)) {
            return phrase.replace(/lip\s*-?sync(?:ing)?/i, "lip‑syncs");
          }
          return phrase; // leave as-is
        }

        // Apply small noun tweaks
        function polishObjects(s: string): string {
          let out = s
            .replace(/\bmango throne\b/i, "the mango throne")
            .replace(/\bgrove\b/i, /firefl(ies|y)/i.test(s) ? "the glowing grove" : "the grove")
            .replace(/\bisland map\b/i, "the island map");
          return out;
        }

        const body = parts.map((p, i) => polishObjects(presentTense(p))).reduce((acc, seg, i) => acc + joiner(i) + seg, "");
        const sentence = ("Avatar " + body).replace(/\s+\./g, ".").trim();
        return sentence.endsWith(".") ? sentence : sentence + ".";
      }
      const total = 12; // 12-beat mix: 5 performance + 7 concept
      // Define performance and concept beat pools from selectedBeats
      const perfVerbs = [
        "raps to camera",
        "delivers bars to lens",
        "lip‑syncs the hook",
        "walks and raps toward the camera",
        "poses and raps on beat",
      ];
      function performanceLine(seed: string, idx: number): string {
        const v = perfVerbs[idx % perfVerbs.length];
        // Prefer keeping any location nouns from seed; otherwise generic stage
        const context = /mango|island|grove|ferris|carousel|bridge|plaza|stage/i.test(seed) ? seed : "at center stage";
        return `rap performance — ${v} — ${context}`;
      }

      const perfIndices = new Set([0, 2, 4, 6, 8]); // 5 performance slots
      const shots: Shot[] = Array.from({length: total}).map((_, i) => {
        const seed = sanitizeBeat(selectedBeats[i % Math.max(1, selectedBeats.length)] || "");
        const isPerformance = perfIndices.has(i);
        const actionText = isPerformance ? performanceLine(seed, i) : seed;
        const cam = camBiased[i % camBiased.length] || pick(camera);
        const pos = pick(positions);
        const light = lightBiased[i % lightBiased.length];
        const animBits = [
          `camera ${cam}`,
          `position ${pos}`,
          environment ? `environment ${environment}` : "",
          `lighting ${light}`,
          fpsHint ? `fps ${fpsHint}` : "",
        ].filter(Boolean).join("; ");
        return {
          index: i + 1,
          action: avatarizeAction(actionText),
          animation: animBits,
          imageUrl: String(referenceImageUrl),
        } as Shot;
      });

      const batch = db.batch();
      functions.logger.info("generateMusicStoryboard.plan", {
        uid,
        projectId,
        settingId,
        ideaHead: (idea || "").slice(0, 120),
        beatsCount: selectedBeats.length,
        shotsPlanned: shots.length,
      });
      for (const s of shots) {
        const id4 = String(s.index).padStart(4, "0");
        const sceneRef = sbRef.collection("scenes").doc(id4);
        batch.set(sceneRef, {
          index: s.index,
          action: s.action,
          animation: s.animation || null,
          // Seed with empty image so Firestore onCreate trigger and background job will fill it
          imageUrl: "",
          script: s.action,
          durationSec: 5.0,
          video: {status: "idle"},
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      functions.logger.info("generateMusicStoryboard.scenes_batch_prepared", {storyboardId: sbRef.id, count: shots.length, first: shots[0]?.action});
      await batch.commit();
      functions.logger.info("generateMusicStoryboard.scenes_written", {storyboardId: sbRef.id, written: shots.length, path: `${sbRef.path}/scenes`});

      // Respond immediately so the client isn't blocked by long-running image generation
      functions.logger.info("generateMusicStoryboard.ok", {uid, projectId, storyboardId: sbRef.id, shots: shots.length, audio: !!audioGsPath});
      res.status(200).json({ok: true, storyboardId: sbRef.id, shots: shots.length});

      // Best-effort background image generation (may be pre-empted by platform). Primary path is Firestore triggers.
      try {
        const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || (process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)).projectId : "");
        const base = `https://us-central1-${project}.cloudfunctions.net`;
        const imgUrl = `${base}/generateStoryboardImages`;
        const debugPrompts = !!(promptKit?.debugPrompts || req.body?.debugPrompts);
        const payload = {
          scenes: shots.map((s) => ({index: s.index, action: s.action, animation: s.animation})),
          style: styleDesc,
          referenceImageUrls: [referenceImageUrl],
          provider: "nano", // nano-banana with Flux fallback already supported in function
          ideaText: idea,
          environment,
          // Debug and linkage for prompt logging
          uid,
          projectId,
          storyboardId: sbRef.id,
          debugPrompts,
        } as any;
        functions.logger.info("generateMusicStoryboard.images_request", {storyboardId: sbRef.id, scenes: shots.length, provider: "nano", style: styleDesc, env: environment});
        const resp = await axios.post(imgUrl, payload, {timeout: 300000});
        functions.logger.info("generateMusicStoryboard.images_requested", {project, storyboardId: sbRef.id, scenes: shots.length});
        const images = Array.isArray(resp.data?.scenes) ? resp.data.scenes as Array<{index: number; imageUrl: string}> : [];
        const upd = db.batch();
        for (const sc of images) {
          const id4 = String(sc.index).padStart(4, "0");
          const sceneRef = sbRef.collection("scenes").doc(id4);
          upd.set(sceneRef, { imageUrl: sc.imageUrl, updatedAt: FieldValue.serverTimestamp() }, {merge: true});
        }
        await upd.commit();
        functions.logger.info("generateMusicStoryboard.images_written", {storyboardId: sbRef.id, written: images.length});
      } catch (e: any) {
        functions.logger.warn("generateMusicStoryboard.images_failed", {message: String(e?.message || e)});
      }
    } catch (e: any) {
      functions.logger.error("generateMusicStoryboard.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  };

export const generateMusicStoryboard = functions
  .runWith({timeoutSeconds: 300, memory: "512MB"})
  .region("us-central1")
  .https.onRequest(generateMusicStoryboardHandler);


// Alias a V2 endpoint name to avoid deployment blockage on the original function
export const generateMusicStoryboardV2 = functions
  .runWith({timeoutSeconds: 300, memory: "512MB"})
  .region("us-central1")
  .https.onRequest(generateMusicStoryboardHandler);

