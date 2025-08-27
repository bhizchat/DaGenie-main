/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {onCall, CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import axios from "axios";
import {buildProductPrompt} from "./buildProductPrompt";
import crypto from "crypto";

const VEO_API_KEY = defineSecret("VEO_API_KEY");

if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}
const db = getFirestore();
const storage = getStorage();

export interface StartVeoInput { jobId: string }

type VideoPromptV1 = {
  meta: { version: string; createdAt: string };
  product: { description: string; imageGsPath?: string };
  style: "cinematic" | "creative_animation";
  audio: { preference: "with_sound" | "no_sound"; voiceoverScript?: string; sfxHints?: string[] };
  cta: { key: string; copy: string };
  scenes: Array<{ id: string; duration_s: number; beats: string[]; shots: Array<{ camera: string; subject: string; action: string; textOverlay?: string }> }>;
  output: { resolution: string; duration_s: number };
};

// ===== Product-commercial schema (lightweight) =====
enum ProductCategory {
  ClothingApparel = "clothing_apparel",
  FoodBeverages = "food_beverages",
  Electronics = "electronics",
  HealthBeautyPersonal = "health_beauty_personal",
  Books = "books",
  Supplies = "supplies",
  Toys = "toys",
  JewelryAccessories = "jewelry_accessories",
}

const CATEGORY_KEYWORDS: Record<ProductCategory, string[]> = {
  [ProductCategory.ClothingApparel]: ["shirt", "t-shirt", "hoodie", "dress", "jeans", "sneaker", "jacket", "apparel", "clothing", "fashion", "wear"],
  [ProductCategory.FoodBeverages]: ["coffee", "tea", "soda", "cola", "drink", "juice", "latte", "burger", "snack", "cookie", "food", "beverage", "chocolate"],
  [ProductCategory.Electronics]: ["phone", "laptop", "tablet", "camera", "headset", "headphones", "speaker", "console", "tv", "monitor", "gadget", "device"],
  [ProductCategory.HealthBeautyPersonal]: ["perfume", "fragrance", "skincare", "serum", "makeup", "lipstick", "shampoo", "soap", "lotion", "cream", "personal care"],
  [ProductCategory.Books]: ["book", "novel", "paperback", "hardcover", "author", "poetry", "ebook"],
  [ProductCategory.Supplies]: ["pen", "notebook", "stapler", "tape", "binder", "paper", "marker", "pet", "home", "office", "school", "cleaner"],
  [ProductCategory.Toys]: ["toy", "lego", "plush", "doll", "figure", "puzzle", "game", "playset"],
  [ProductCategory.JewelryAccessories]: ["ring", "necklace", "bracelet", "earring", "watch", "jewelry", "sunglasses", "bag", "accessory"],
};

function classifyCategory(text: string): ProductCategory {
  const t = String(text || "").toLowerCase();
  let best: ProductCategory = ProductCategory.Electronics;
  let bestHits = -1;
  for (const cat of Object.values(ProductCategory)) {
    const hits = CATEGORY_KEYWORDS[cat].reduce((acc, k) => acc + (t.includes(k) ? 1 : 0), 0);
    if (hits > bestHits) {
      bestHits = hits; best = cat as ProductCategory;
    }
  }
  return best;
}

function buildCommercialPrompt(desc: string, userHint?: string): {text: string; category: ProductCategory; templateId: string} {
  const category = classifyCategory(`${desc} ${userHint ?? ""}`);
  const base = (s: string) => s.replace(/\s+/g, " ").trim();
  const d = desc.trim();
  const hint = userHint?.trim();
  let text = "";
  let templateId = "";
  switch (category) {
  case ProductCategory.Electronics:
    templateId = "electronics_crate_wireframe_v1";
    text = base(`Cinematic photoreal product reveal for: ${d}. Scene: black void that constructs into a premium showroom. A matte-black crate with glowing logo opens in clean symmetry; blue energy arcs sketch a wireframe silhouette of the product, then lower and dissolve into the real device. Camera: fixed wide, graceful motion only on reveals. Lighting: deep ambient with crisp blue highlights, final soft studio glow. Environment assembles along with the silhouette. No on-screen text.`);
    break;
  case ProductCategory.FoodBeverages:
    templateId = "food_crave_macro_v1";
    text = base(`Crave-inducing cinematic for: ${d}. Start with macro textures (fizz/steam/ice). A glowing wave reveals the product silhouette, which fills with the drink. Condensation and chill fog develop; final hero on reflective surface. Camera: slow dolly pullback to centered bottle/cup. Lighting: dark stage with warm rim and internal glow. No text.`);
    break;
  case ProductCategory.HealthBeautyPersonal:
    templateId = "beauty_silk_pastel_v1";
    text = base(`Luxury pastel cinematic for: ${d}. A floating bloom/silk cradle opens to reveal the product. Silk ribbons lift it gently; soft petals drift. Camera: smooth dolly-in, subtle arc. Lighting: soft golden top-light, warm ambient fill. Environment: infinite pastel void. No text.`);
    break;
  case ProductCategory.JewelryAccessories:
    templateId = "jewelry_macro_sparkle_v1";
    text = base(`Macro elegance for: ${d}. Velvet pedestal in a dark studio; bokeh sparkles and controlled rim lights. Slow glide macro across facets/metal; final centered hero with tasteful shimmer. No text.`);
    break;
  case ProductCategory.ClothingApparel:
    templateId = "apparel_fabric_runway_v1";
    text = base(`Fashion minimalism for: ${d}. Fabric close-ups ripple; color swatches morph; garment rotates on a clean runway void. Camera: slow parallax orbit with gentle dolly-in. Lighting: studio white with soft shadows. No text.`);
    break;
  case ProductCategory.Books:
    templateId = "books_ink_page_morph_v1";
    text = base(`Cinematic literary reveal for: ${d}. Ink spreads across a page forming motifs, pages flip and morph into a calm reading scene, then isolate the book in center frame. Camera: top-down to hero. Lighting: warm desk lamp ambience. No text.`);
    break;
  case ProductCategory.Supplies:
    templateId = "supplies_workbench_array_v1";
    text = base(`Clean workbench build for: ${d}. Items slide into a tidy array; one hero item rises and rotates for detail, then settles centered. Camera: fixed overhead then gentle tilt. Lighting: bright studio with soft reflections. No text.`);
    break;
  case ProductCategory.Toys:
    templateId = "toys_playful_orbit_v1";
    text = base(`Playful kinetic ad for: ${d}. Colorful blocks snap together; variants orbit; final hero toy locks center with cheerful motion. Camera: lively but smooth. Lighting: bright gradient backdrop. No text.`);
    break;
  }
  if (hint && hint.length > 0) {
    text += ` Creative hint: ${hint}.`;
  }
  return {text, category, templateId};
}

// no brand-specific selection; templates are applied by category

export async function startVeoForJobCore(uid: string, jobId: string): Promise<{status: string; finalVideoUrl?: string}> {
  const jobRef = db.collection("adJobs").doc(jobId);
  const snap = await jobRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Job not found");
  const job = snap.data() as any;
  if (job.uid !== uid) throw new HttpsError("permission-denied", "Not your job");
  if (job.status === "ready" && job.finalVideoUrl) {
    console.log("[startVeoForJob] already_ready", {jobId});
    return {status: "ready", finalVideoUrl: job.finalVideoUrl};
  }
  if (job.status === "error") {
    console.log("[startVeoForJob] already_error", {jobId});
    throw new HttpsError("failed-precondition", String(job.error || "error"));
  }

  const p = job.promptV1 as VideoPromptV1 | undefined;
  if (!p) throw new HttpsError("failed-precondition", "missing promptV1");
  console.log("[startVeoForJob] incoming imageGsPath prefix=", String(p.product?.imageGsPath || "").slice(0, 32));
  // REQUIRE image: generation must use the attached product image
  let effectiveImagePath: string | undefined = (p.product?.imageGsPath as string | undefined);
  const normalizeHttpsToGs = (url?: string): string | undefined => {
    if (!url || typeof url !== "string") return undefined;
    const s = url.trim();
    // firebase token URL: https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<object>?alt=media&token=...
    const m1 = s.match(/^https?:\/\/firebasestorage\.googleapis\.com\/v0\/b\/([^/]+)\/o\/([^?]+)(?:\?.*)?$/i);
    if (m1) return `gs://${m1[1]}/${decodeURIComponent(m1[2])}`;
    // storage.googleapis.com direct: https://storage.googleapis.com/<bucket>/<object>
    const m2 = s.match(/^https?:\/\/storage\.googleapis\.com\/([^/]+)\/(.+)$/i);
    if (m2) return `gs://${m2[1]}/${m2[2]}`;
    // new host: https://<bucket>.firebasestorage.app/o/<object>?...
    const m3 = s.match(/^https?:\/\/([^/.]+)\.firebasestorage\.app\/(?:v0\/)?o\/([^?]+)(?:\?.*)?$/i);
    if (m3) return `gs://${m3[1]}.appspot.com/${decodeURIComponent(m3[2])}`;
    return undefined;
  };
  const sanitizeGs = (gs?: string): string | undefined => {
    if (!gs || typeof gs !== "string") return undefined;
    let s = gs.trim();
    if (!s.startsWith("gs://")) return undefined;
    // normalize bucket host to appspot.com if needed
    s = s.replace(/\.firebasestorage\.app\//, ".appspot.com/");
    return s;
  };
  // Back-compat and normalization path
  if (!effectiveImagePath || !String(effectiveImagePath).startsWith("gs://")) {
    // Try legacy field
    if (typeof job.inputImagePath === "string") {
      effectiveImagePath = sanitizeGs(job.inputImagePath) || effectiveImagePath;
    }
    // Try HTTPS url to normalize
    if ((!effectiveImagePath || !effectiveImagePath.startsWith("gs://")) && typeof job.inputImageUrl === "string") {
      const asGs = normalizeHttpsToGs(job.inputImageUrl);
      if (asGs) effectiveImagePath = asGs;
    }
    // Persist normalized gs path back to promptV1 when found
    if (effectiveImagePath && effectiveImagePath.startsWith("gs://")) {
      try {
        await jobRef.set({promptV1: {...p, product: {...p.product, imageGsPath: effectiveImagePath}}}, {merge: true});
      } catch (e) {
        console.debug("[startVeoForJob] normalization write failed", (e as Error)?.message);
      }
    }
  }
  if (!effectiveImagePath || !String(effectiveImagePath).startsWith("gs://")) {
    console.error("[startVeoForJob] image_required: missing or invalid gs:// path", {jobId, got: p.product?.imageGsPath});
    await jobRef.update({status: "error", error: "image_required", updatedAt: Timestamp.now(), debug: {imageRequired: true, imageGsPath: p.product?.imageGsPath || null}});
    try {
      await db.collection("analyticsEvents").add({uid, event: "ad_job_generation_error", jobId, reason: "image_required", createdAt: Date.now(), imageGsPath: p.product?.imageGsPath || null});
    } catch (anErr) {
      console.error("[startVeoForJob] analytics image_required log error", (anErr as Error)?.message);
    }
    throw new HttpsError("failed-precondition", "image_required");
  }

  // Build JSON prompt from category-driven structured templates
  const built = buildCommercialPrompt(p.product.description || "");
  const categoryStr = String(built.category);
  const productName = (p.product.description || "product").trim().slice(0, 80);
  const brief: any = {
    productName,
    category: categoryStr,
    productTraits: [],
    audience: undefined,
    desiredPerception: [],
    proofMoment: undefined,
    styleWords: [],
    cta: null,
    durationSeconds: null,
    aspectRatio: job.aspectRatio || (p.output as any)?.resolution?.includes("1920x1080") ? "16:9" : "9:16",
    brand: {},
  };
  const jsonPrompt = buildProductPrompt(brief as any);
  // Inject preferred dialogue from job brief (slogan -> name) to ensure final prompt uses it
  const brand = (job?.brief?.brand || {}) as any;
  const preferredDialogue = (brand?.slogan && String(brand.slogan).trim()) || (brand?.name && `Introducing ${brand.name}`) || null;
  if (preferredDialogue) {
    (jsonPrompt as any).dialogue = [String(preferredDialogue)];
  }
  const prompt = JSON.stringify(jsonPrompt);
  const templateId = categoryStr.includes("electronics") ? "electronics_json_v1" :
    (categoryStr.includes("food") || categoryStr.includes("beverages")) ? "food_beverage_json_v1" :
      (categoryStr.includes("health") || categoryStr.includes("beauty") || categoryStr.includes("personal")) ? "beauty_json_v1" :
        "apparel_fallback_json_v1";
  try {
    await jobRef.set({templateId, veoPrompt: prompt}, {merge: true});
  } catch (e) {
    console.debug("[startVeoForJob] optional category/template set failed", (e as Error)?.message);
  }
  // Debug: persist and log a preview of the prompt and dialogue so we can see it from client/devtools
  try {
    const preview = prompt.slice(0, 800);
    const dialoguePreview = Array.isArray((jsonPrompt as any).dialogue) ? (jsonPrompt as any).dialogue.join(" | ") : null;
    await jobRef.set({debug: {promptPreview: preview, dialoguePreview}}, {merge: true});
    console.log("[startVeoForJob] prompt_preview", {len: prompt.length, head: preview});
  } catch (e: any) {
    console.error("[startVeoForJob] prompt preview write failed", e?.message);
  }

  // Resolve image (required) from gs:// to inline bytes preferred; fallback to signed or token URL.
  // If the bucket host differs, normalize and also try the project's default bucket as a fallback.
  let imageUrl: string | undefined = (job.inputImageUrl as string | undefined);
  let inlineImageB64: string | undefined;
  let rawBucketForInline: string | undefined;
  let rawObjectPathForInline: string | undefined;
  if (effectiveImagePath && typeof effectiveImagePath === "string") {
    const gs = effectiveImagePath as string; // gs://bucket/object
    const m = gs.match(/^gs:\/\/([^/]+)\/(.+)$/);
    if (m) {
      // Normalize Firebase host-style bucket to classic GCS bucket if needed
      let primaryBucketName = m[1];
      if (primaryBucketName.endsWith(".firebasestorage.app")) {
        primaryBucketName = primaryBucketName.replace(/\.firebasestorage\.app$/, ".appspot.com");
      }
      const objectPath = m[2];
      rawBucketForInline = primaryBucketName;
      rawObjectPathForInline = objectPath;
      const defaultBucket = storage.bucket(); // project's default bucket
      let defaultBucketName = defaultBucket.name;
      if (defaultBucketName.endsWith(".firebasestorage.app")) {
        defaultBucketName = defaultBucketName.replace(/\.firebasestorage\.app$/, ".appspot.com");
      }

      const tryExists = async (bucketName: string): Promise<boolean> => {
        try {
          const [exists] = await storage.bucket(bucketName).file(objectPath).exists();
          console.log("[startVeoForJob] exists check", {bucketName, exists});
          return !!exists;
        } catch (e: any) {
          console.error("[startVeoForJob] exists check error", bucketName, e?.message);
          return false;
        }
      };

      const tryDirectDownload = async (bucketName: string): Promise<string | undefined> => {
        try {
          const [bytes] = await storage.bucket(bucketName).file(objectPath).download();
          console.log("[startVeoForJob] direct download succeeded", {bucketName, bytes: bytes.length});
          return Buffer.from(bytes).toString("base64");
        } catch (e: any) {
          console.error("[startVeoForJob] direct download failed", bucketName, e?.message);
          return undefined;
        }
      };

      const tryBuildFrom = async (bucketName: string): Promise<string | undefined> => {
        try {
          const file = storage.bucket(bucketName).file(objectPath);
          const [signed] = await file.getSignedUrl({action: "read", expires: Date.now() + 60 * 60 * 1000});
          return signed;
        } catch (e: any) {
          console.error("[startVeoForJob] signed URL error", e?.message);
          try {
            const file = storage.bucket(bucketName).file(objectPath);
            const [meta] = await file.getMetadata();
            const token = meta?.metadata?.firebaseStorageDownloadTokens as string | undefined;
            if (token && token.length > 0) {
              return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`;
            }
          } catch (e2: any) {
            console.error("[startVeoForJob] metadata fetch error", e2?.message);
          }
          return undefined;
        }
      };

      // Existence checks to pick correct bucket and prefer direct download
      const primaryExists = await tryExists(primaryBucketName);
      const defaultExists = (!primaryExists && primaryBucketName !== defaultBucketName) ? await tryExists(defaultBucketName) : false;

      let chosenBucket: string | undefined = undefined;
      if (primaryExists) {
        chosenBucket = primaryBucketName;
      } else if (defaultExists) {
        chosenBucket = defaultBucketName;
      }

      if (chosenBucket) {
        // Prefer direct download to inline base64
        const b64 = await tryDirectDownload(chosenBucket);
        if (b64) {
          inlineImageB64 = b64;
          rawBucketForInline = chosenBucket;
          rawObjectPathForInline = objectPath;
        } else {
          // Fall back to building an accessible URL
          imageUrl = await tryBuildFrom(chosenBucket);
          if (imageUrl) {
            rawBucketForInline = chosenBucket;
            rawObjectPathForInline = objectPath;
          }
        }
      } else {
        console.error("[startVeoForJob] object not found in either bucket candidate", {primaryBucketName, defaultBucketName, objectPath});
      }
    }
  }

  // If we obtained inline bytes above, persist debug length
  if (inlineImageB64 && rawBucketForInline && rawObjectPathForInline) {
    try {
      const byteLen = Buffer.from(inlineImageB64, "base64").length;
      await jobRef.set({debug: {imageInlineBytesLen: byteLen}}, {merge: true});
      console.log("[startVeoForJob] prepared inline base64 image from GCS");
    } catch (e) {
      console.debug("[startVeoForJob] optional debug image bytes len set failed", (e as Error)?.message);
    }
  }

  // Prepare REST endpoints for Veo (Generative Language API)
  const apiKey = (process.env.VEO_API_KEY as string | undefined)?.trim();
  const masked = apiKey ? `${String(apiKey).slice(0, 6)}••••${String(apiKey).slice(-4)}` : "missing";
  console.log("[startVeoForJob] apiKey_present=", !!apiKey, "apiKey_masked=", masked);
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "missing_veo_api_key");
  }
  const apiBase = "https://generativelanguage.googleapis.com/v1beta";
  const normalizeModel = (m?: string): string => {
    if (!m) return "veo-3.0-generate-preview";
    const s = String(m).toLowerCase();
    if (s.includes("fast")) return "veo-3.0-fast-generate-preview";
    return m;
  };
  const modelName = normalizeModel(job.model as string);

  console.log("[startVeoForJob] begin jobId=", jobId, " model=", modelName);
  console.log("[startVeoForJob] codepath=REST_v1beta axios");
  // Mark job as actively generating before network calls
  await jobRef.update({status: "generating", provider: "veo3", updatedAt: Timestamp.now()});
  // analytics: generation started
  try {
    await db.collection("analyticsEvents").add({uid, event: "ad_job_generation_started", jobId, model: modelName, createdAt: Date.now()});
  } catch (anErr) {
    console.error("[startVeoForJob] analytics started log error", (anErr as Error)?.message);
  }
  // Build predictLongRunning body (prefer inline image bytes; gcsUri is not supported for Veo 3)
  const instances: any[] = [{prompt}];
  if (inlineImageB64) {
    instances[0].image = {bytesBase64Encoded: inlineImageB64, mimeType: "image/jpeg"};
    console.log("[startVeoForJob] attached image as base64 bytes");
  } else if (imageUrl) {
    // As a last resort, fetch via HTTPS and inline as base64
    try {
      const resp = await axios.get<ArrayBuffer>(imageUrl, {responseType: "arraybuffer", timeout: 30000});
      const b64 = Buffer.from(resp.data as any).toString("base64");
      instances[0].image = {bytesBase64Encoded: b64, mimeType: "image/jpeg"};
      console.log("[startVeoForJob] attached image by fetching URL and inlining base64");
    } catch (e: any) {
      console.error("[startVeoForJob] https fetch for image failed", e?.message);
    }
  }
  if (!instances[0].image) {
    console.error("[startVeoForJob] image_sign_failed: could not inline image bytes", {jobId, rawBucketForInline, rawObjectPathForInline, imageUrlPresent: !!imageUrl});
    await jobRef.update({status: "error", error: "image_sign_failed", updatedAt: Timestamp.now(), debug: {rawBucketForInline, rawObjectPathForInline, imageUrlAttempted: !!imageUrl}});
    try {
      await db.collection("analyticsEvents").add({uid, event: "ad_job_generation_error", jobId, reason: "image_sign_failed", createdAt: Date.now()});
    } catch (anErr) {
      console.error("[startVeoForJob] analytics image_sign_failed log error", (anErr as Error)?.message);
    }
    throw new HttpsError("failed-precondition", "image_sign_failed");
  }

  try {
    // Kick off predictLongRunning
    const predictUrl = `${apiBase}/models/${encodeURIComponent(modelName)}:predictLongRunning?key=${encodeURIComponent(apiKey)}`;
    const body = {instances, parameters: {negativePrompt: "text, captions, subtitles, watermarks"}};
    console.log("[startVeoForJob] POST predictLongRunning", {hasImage: true, promptLen: prompt.length});
    const genResp: any = await axios.post(predictUrl, body, {timeout: 120000});
    const operationName = genResp.data?.name || genResp.data?.operation || genResp.data?.id;
    console.log("[startVeoForJob] operation=", operationName);
    await jobRef.update({status: "processing", providerJobId: operationName || null, updatedAt: Timestamp.now()});

    // Poll the operation until done
    let tries = 0;
    const maxTries = 48; // up to ~8 min
    let op: any = {done: false};
    while (!op?.done && tries < maxTries) {
      await new Promise((r) => setTimeout(r, 10000));
      const opUrl = `${apiBase}/${operationName}?key=${encodeURIComponent(apiKey)}`;
      const opResp = await axios.get(opUrl, {timeout: 60000});
      op = opResp.data;
      if (tries % 3 === 0) {
        console.log("[startVeoForJob] poll", {tries, done: !!op?.done});
        try {
          await jobRef.set({processing: {heartbeat: Timestamp.now(), pollAttempts: tries}}, {merge: true});
        } catch (e) {
          console.debug("[startVeoForJob] heartbeat write skipped", (e as Error)?.message);
        }
      }
      tries++;
    }

    if (!op?.done) {
      await jobRef.update({status: "error", error: "timeout", updatedAt: Timestamp.now()});
      try {
        await db.collection("analyticsEvents").add({uid, event: "ad_job_generation_error", jobId, reason: "timeout", createdAt: Date.now()});
      } catch (anErr) {
        console.error("[startVeoForJob] analytics timeout log error", (anErr as Error)?.message);
      }
      throw new HttpsError("deadline-exceeded", "Veo operation timed out");
    }

    const gv = (op.result?.generatedVideos?.[0]) || (op.response?.generatedVideos?.[0]) || (op.response?.generated_videos?.[0]);
    const sample = op.response?.generateVideoResponse?.generatedSamples?.[0] ||
      op.result?.generateVideoResponse?.generatedSamples?.[0] ||
      op.response?.generatedSamples?.[0] ||
      op.result?.generatedSamples?.[0];
    const downloadUrl = sample?.video?.uri || sample?.video?.url || gv?.video?.uri || gv?.video?.url || gv?.video || gv?.uri || null;
    if (!downloadUrl) {
      await jobRef.update({status: "error", error: "no_video", updatedAt: Timestamp.now()});
      try {
        await db.collection("analyticsEvents").add({uid, event: "ad_job_generation_error", jobId, reason: "no_video", createdAt: Date.now()});
      } catch (anErr) {
        console.error("[startVeoForJob] analytics no_video log error", (anErr as Error)?.message);
      }
      throw new HttpsError("internal", "No video URL in operation result");
    }

    console.log("[startVeoForJob] ready url prefix=", String(downloadUrl).slice(0, 80));
    // Rehost the video to Firebase Storage so clients can play without API headers
    try {
      const dl = await axios.get<ArrayBuffer>(String(downloadUrl), {
        responseType: "arraybuffer",
        headers: {"x-goog-api-key": apiKey},
        timeout: 300000,
      });
      const outPath = `generated_ads/${jobId}/output.mp4`;
      const bucket = storage.bucket();
      const file = bucket.file(outPath);
      const token: string = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      await file.save(Buffer.from(dl.data as any), {
        contentType: "video/mp4",
        metadata: {metadata: {firebaseStorageDownloadTokens: token}},
        resumable: false,
      });
      const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(outPath)}?alt=media&token=${token}`;
      await jobRef.update({status: "ready", finalVideoUrl: publicUrl, updatedAt: Timestamp.now()});
      try {
        await db.collection("analyticsEvents").add({uid, event: "ad_job_generation_ready", jobId, url: publicUrl, createdAt: Date.now()});
      } catch (anErr) {
        console.error("[startVeoForJob] analytics ready log error", (anErr as Error)?.message);
      }
      return {status: "ready", finalVideoUrl: publicUrl};
    } catch (rehErr: any) {
      console.error("[startVeoForJob] rehost failed; returning original url", rehErr?.message);
      await jobRef.update({status: "ready", finalVideoUrl: downloadUrl, updatedAt: Timestamp.now()});
      try {
        await db.collection("analyticsEvents").add({uid, event: "ad_job_generation_ready", jobId, url: downloadUrl, createdAt: Date.now()});
      } catch (anErr) {
        console.error("[startVeoForJob] analytics ready log error (fallback)", (anErr as Error)?.message);
      }
      return {status: "ready", finalVideoUrl: downloadUrl};
    }
  } catch (e: any) {
    const msg = typeof e?.message === "string" ? e.message : String(e);
    console.error("[startVeoForJob] generate/poll error", msg, e?.response?.data || e?.stack);
    await jobRef.update({status: "error", error: msg?.slice(0, 500) || "internal", updatedAt: Timestamp.now()});
    try {
      await db.collection("analyticsEvents").add({uid, event: "ad_job_generation_error", jobId, reason: msg?.slice(0, 200) || "internal", createdAt: Date.now()});
    } catch (anErr) {
      console.error("[startVeoForJob] analytics error log error", (anErr as Error)?.message);
    }
    throw new HttpsError("internal", msg || "Veo generate failed");
  }
}

export const startVeoForJob = onCall({
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
  secrets: [VEO_API_KEY],
}, async (req: CallableRequest<StartVeoInput>) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "User must be signed in.");
  const jobId = (req.data?.jobId || "").trim();
  if (!jobId) throw new HttpsError("invalid-argument", "Missing jobId");
  const jobRef = db.collection("adJobs").doc(jobId);
  // Idempotent gating: set processing.startedAt if absent; if present, do not start another worker
  let shouldStart = false;
  await db.runTransaction(async (tx) => {
    const doc = await tx.get(jobRef);
    if (!doc.exists) throw new HttpsError("not-found", "Job not found");
    const data = doc.data() as any;
    if (data.uid !== uid) throw new HttpsError("permission-denied", "Not your job");
    if (data.status === "ready" && data.finalVideoUrl) {
      // Early return by throwing a sentinel and catching after txn
      throw new HttpsError("ok", "already_ready");
    }
    if (data.processing?.startedAt) {
      return; // someone else already started
    }
    tx.set(jobRef, {processing: {startedAt: Timestamp.now()}}, {merge: true});
    shouldStart = true;
  }).catch((e) => {
    if ((e as any)?.code === "ok") {
      // handled in outer scope
    } else if (e instanceof HttpsError) {
      throw e;
    } else {
      throw new HttpsError("internal", (e as Error)?.message || "transaction failed");
    }
  });

  // If already ready, return immediately
  const after = await jobRef.get();
  const data = after.data() as any;
  if (data?.status === "ready" && data?.finalVideoUrl) {
    return {status: "ready", finalVideoUrl: data.finalVideoUrl};
  }
  if (!shouldStart) {
    return {status: "pending"};
  }
  return await startVeoForJobCore(uid, jobId);
});


