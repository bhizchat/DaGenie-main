/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {onCall, CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import axios from "axios";
// Removed ad prompt builder usage; storyboard prompt is the only source
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
// Removed legacy ad-category utilities

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

  // Choose prompt/model by archetype; keep commercial path unchanged
  const archetype: string = String((job.archetype || "commercial")).toLowerCase();
  const requestedModel: string = String(job.model || "").toLowerCase();
  // Prefer storyboard prompt strictly by mode; avoid legacy ad fields
  try { await jobRef.set({templateId: "storyboard"}, {merge: true}); } catch {}
  const mode = String((job as any)?.mode || "").toLowerCase();
  // Refuse to process storyboard jobs through legacy ad path
  if (mode === "storyboard" || typeof (job as any)?.storyboardPrompt === "string") {
    try { await jobRef.set({debug: {refusedByAdPath: true}}, {merge: true}); } catch {}
    throw new HttpsError("failed-precondition", "refuse_storyboard_job");
  }
  let primaryPrompt: string | undefined = undefined;
  if (typeof (job as any)?.veoPrompt === "string" && (job as any).veoPrompt.trim().length > 0) {
    primaryPrompt = String((job as any).veoPrompt).trim();
  } else {
    primaryPrompt = JSON.stringify({scene: "animation", description: p.product.description || "storyboard"});
  }

  // Detect ad-like/multi-scene prompts; rebuild from promptV1 + honoredSelection when needed
  const looksLikeAd = (s: string) => /product[-\s]?focus|photorealistic cinematic|made to be remembered|Narrator:\s*"/i.test(s);
  let needsRepair = false;
  try {
    const parsed = JSON.parse(primaryPrompt);
    const seqLen = Array.isArray(parsed?.sequence) ? parsed.sequence.length : 0;
    if (seqLen !== 1 || looksLikeAd(primaryPrompt)) needsRepair = true;
  } catch { needsRepair = true; }
  if (needsRepair) {
    const selIdx: number = (typeof (job as any)?.honoredSelection?.selectedIndex === "number" ? (job as any).honoredSelection.selectedIndex : 0);
    const firstScene = Array.isArray(p?.scenes) ? (p.scenes.find((s: any) => Number(String(s.id||"").replace(/\D+/g, "")) === selIdx) || p.scenes[selIdx] || p.scenes[0]) : undefined;
    const beats = (firstScene?.beats || []).filter(Boolean);
    const desc = beats.join(" ").trim() || "beat";
    const repaired = { scene: "animation", style: "animated mascot short, playful, campus vibe", sequence: [{ shot: "storyboard_beat", camera: "controlled", description: desc }], format: (p.output?.resolution === "16:9" || p.output?.resolution === "9:16") ? p.output.resolution : "9:16" };
    primaryPrompt = JSON.stringify(repaired);
    try { await jobRef.set({debug: {correctedPromptApplied: true, primaryPromptHead: String(primaryPrompt).slice(0, 180)}}, {merge: true}); } catch {}
  }

  // If storyboard has dialogue lines, prepend a single quoted dialogue cue to the prompt text for Veo audio
  let finalPromptToSend: string = primaryPrompt;
  try {
    const parsed: any = JSON.parse(primaryPrompt);
    const lines: string[] = Array.isArray(parsed?.dialogue) ? (parsed.dialogue as any[]).filter((s) => typeof s === "string" && s.trim().length > 0) : [];
    const accent: string | undefined = (typeof parsed?.accent === "string" && parsed.accent.trim().length > 0) ? parsed.accent.trim() : undefined;
    if (lines.length) {
      const firstLine = String(lines[0]).replace(/^\s*"|"\s*$/g, "").trim();
      const voice = `"${firstLine}"${accent ? ` (${accent})` : ""}`;
      finalPromptToSend = `${voice}\n\n${primaryPrompt}`;
      if (lines.length > 1) {
        try { await jobRef.set({debug: {trimmedMultiScene: true, dialogueLinesProvided: lines.length}}, {merge: true}); } catch {}
      }
    }
  } catch (_) { /* primaryPrompt is not JSON; leave as-is */ }

  // Debug: persist and log a preview of both the incoming storyboard JSON and final string we will send
  try {
    const preview = primaryPrompt.slice(0, 800);
    let dialoguePreview: string | null = null;
    let dialogueLinesCount = 0;
    let hasJsonDialogue = false;
    try {
      const parsedForPreview: any = JSON.parse(primaryPrompt);
      if (Array.isArray(parsedForPreview?.dialogue)) {
        hasJsonDialogue = true;
        const lines = (parsedForPreview.dialogue as any[]).filter((s: any) => typeof s === "string");
        dialogueLinesCount = lines.length;
        dialoguePreview = lines.join(" | ") || null;
      }
    } catch {}
    const finalHead = String(finalPromptToSend).slice(0, 220);
    const hasVoiceoverPrefix = /^\s*Voiceover:/i.test(finalPromptToSend);
    await jobRef.set({debug: {promptPreview: preview, dialoguePreview, dialogueLinesCount, hasJsonDialogue, finalPromptHead: finalHead, hasVoiceoverPrefix, finalPromptFull: finalPromptToSend}}, {merge: true});
    console.log("[startVeoForJob] prompt_preview", {len: primaryPrompt.length, head: preview});
    console.log("[startVeoForJob] final_prompt_head", {len: finalPromptToSend.length, head: finalHead, hasVoiceoverPrefix, dialogueLinesCount});
    // Log the entire final prompt string being sent
    console.log("[startVeoForJob] FINAL_PROMPT", finalPromptToSend);
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

  // If WAN was requested, route to WAN and bypass Veo entirely
  if (requestedModel.includes("wan")) {
    try {
      await jobRef.update({status: "processing", provider: "wan2.2", updatedAt: Timestamp.now()});
    } catch (_) { /* noop */ }
    try {
      // Use storyboard prompt when present; otherwise fallback to generated product prompt
      const wanPrompt = primaryPrompt;
      const wanEndpoint = "https://us-central1-dategenie-dev.cloudfunctions.net/wanI2vFast";
      const wanBody: any = {image: (imageUrl || effectiveImagePath || ""), prompt: wanPrompt, frames_per_second: 16, num_frames: 97, resolution: "480p"};
      console.log("[startVeoForJob] WAN request", {hasImage: !!effectiveImagePath, promptLen: wanPrompt.length});
      const wanResp = await axios.post(wanEndpoint, wanBody, {timeout: 540000});
      const videoUrl: string | undefined = wanResp.data?.videoUrl || wanResp.data?.replicateUrl;
      console.log("[startVeoForJob] WAN response", {hasVideo: !!videoUrl});
      if (!videoUrl) {
        throw new Error("wan_no_video_url");
      }
      await jobRef.update({status: "ready", finalVideoUrl: videoUrl, updatedAt: Timestamp.now()});
      try { await db.collection("analyticsEvents").add({uid, event: "ad_job_generation_ready", jobId, url: videoUrl, provider: "wan2.2", createdAt: Date.now()}); } catch (_) {}
      return {status: "ready", finalVideoUrl: videoUrl};
    } catch (wanErr: any) {
      const msg = typeof wanErr?.message === "string" ? wanErr.message : String(wanErr);
      console.error("[startVeoForJob] wan route failed", msg);
      await jobRef.update({status: "error", error: msg?.slice(0, 500) || "wan_error", updatedAt: Timestamp.now()});
      try { await db.collection("analyticsEvents").add({uid, event: "ad_job_generation_error", jobId, reason: msg?.slice(0, 200) || "wan_error", provider: "wan2.2", createdAt: Date.now()}); } catch (_) {}
      throw new HttpsError("internal", msg || "WAN generate failed");
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
    if (!m) return "veo-3.0-generate-001";
    const s = String(m).toLowerCase();
    if (s.includes("fast")) return "veo-3.0-fast-generate-001";
    return s.includes("preview") ? s.replace("-preview", "-001") : m;
  };
  // Route model by archetype (default preserves existing)
  let modelName = normalizeModel(job.model as string);
  if (archetype === "cory") {
    modelName = "veo-3.0-generate-001";
  } else if (archetype === "rufus" || archetype === "commercial") {
    modelName = normalizeModel(job.model as string || "veo-3.0-fast-generate-001");
  }

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
  const instances: any[] = [{prompt: finalPromptToSend}];
  if (inlineImageB64) {
    instances[0].image = {imageBytes: inlineImageB64, mimeType: "image/jpeg"};
    console.log("[startVeoForJob] attached image as base64 bytes");
  } else if (imageUrl) {
    // As a last resort, fetch via HTTPS and inline as base64
    try {
      const resp = await axios.get<ArrayBuffer>(imageUrl, {responseType: "arraybuffer", timeout: 30000});
      const b64 = Buffer.from(resp.data as any).toString("base64");
      instances[0].image = {imageBytes: b64, mimeType: "image/jpeg"};
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
    // Map aspect ratio and resolution from prompt JSON when possible
    let aspect: string | undefined;
    try {
      const parsed: any = JSON.parse(primaryPrompt);
      const fmt = String(parsed?.format || "").trim();
      if (fmt === "16:9" || fmt === "9:16") aspect = fmt;
    } catch {}
    const parameters: any = {negativePrompt: "text, captions, subtitles, watermarks"};
    if (!aspect) aspect = "16:9";
    if (modelName === "veo-3.0-generate-001" && aspect === "9:16") aspect = "16:9";
    parameters.aspectRatio = aspect;
    if (aspect === "16:9") parameters.resolution = "1080p";
    const body = {instances, parameters};
    try { await jobRef.set({debug: {aspectRatioSent: aspect || null, resolutionSent: parameters.resolution || null}}, {merge: true}); } catch {}
    console.log("[startVeoForJob] POST predictLongRunning", {hasImage: true, promptLen: finalPromptToSend.length});
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

    // If operation has explicit error, surface it with context
    if (op?.error) {
      try {
        await jobRef.set({debug: {opError: op.error}}, {merge: true});
      } catch {}
      throw new HttpsError("internal", (op.error?.message as string) || "veo_operation_error");
    }

    const gv = (op.result?.generatedVideos?.[0]) || (op.response?.generatedVideos?.[0]) || (op.response?.generated_videos?.[0]);
    const sample = op.response?.generateVideoResponse?.generatedSamples?.[0] ||
      op.result?.generateVideoResponse?.generatedSamples?.[0] ||
      op.response?.generatedSamples?.[0] ||
      op.result?.generatedSamples?.[0] ||
      op.response?.generate_video_response?.generated_samples?.[0] ||
      op.result?.generate_video_response?.generated_samples?.[0];

    // Try a robust set of URL fields
    let downloadUrl: string | null = null;
    const tryVals: Array<string | undefined> = [
      sample?.video?.uri,
      sample?.video?.url,
      (sample as any)?.video?.signedUri,
      (sample as any)?.video?.gcsUri,
      (sample as any)?.videoUri,
      (sample as any)?.uri,
      gv?.video?.uri,
      gv?.video?.url,
      (gv as any)?.uri,
      (op.response as any)?.videoUri,
      (op.result as any)?.videoUri,
    ];
    for (const v of tryVals) {
      if (typeof v === "string" && v.trim().length > 0) { downloadUrl = v; break; }
    }

    // Files API fallback: when response carries a File handle instead of a URL
    if (!downloadUrl) {
      const fileObj = (gv && (gv as any).video) || (sample && (sample as any).video) || (op?.response?.generated_videos?.[0]?.video) || (op?.response?.generatedVideos?.[0]?.video);
      const fileName: string | undefined = (fileObj && typeof (fileObj as any).name === "string" ? (fileObj as any).name : undefined) || (typeof fileObj === "string" && /^files\//i.test(fileObj) ? fileObj : undefined);
      if (fileName) {
        try {
          const metaUrl = `${apiBase}/${encodeURIComponent(fileName)}?key=${encodeURIComponent(apiKey)}`;
          const meta = (await axios.get(metaUrl, {timeout: 30000})).data;
          const dlUri: string | undefined = meta?.downloadUri || (fileObj as any)?.downloadUri || (fileObj as any)?.uri;
          if (typeof dlUri === "string" && /^https?:\/\//i.test(dlUri)) {
            downloadUrl = dlUri;
          } else {
            // Fallback to :download endpoint returning bytes; rehost immediately
            const bytesResp = await axios.get<ArrayBuffer>(`${apiBase}/${encodeURIComponent(fileName)}:download?key=${encodeURIComponent(apiKey)}`, {responseType: "arraybuffer", timeout: 300000});
            const outPath = `generated_ads/${jobId}/output.mp4`;
            const bucket = storage.bucket();
            const file = bucket.file(outPath);
            const token: string = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
            await file.save(Buffer.from(bytesResp.data as any), {contentType: "video/mp4", metadata: {metadata: {firebaseStorageDownloadTokens: token}}, resumable: false});
            const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(outPath)}?alt=media&token=${token}`;
            await jobRef.update({status: "ready", finalVideoUrl: publicUrl, updatedAt: Timestamp.now()});
            try { await db.collection("analyticsEvents").add({uid, event: "ad_job_generation_ready", jobId, url: publicUrl, createdAt: Date.now()}); } catch {}
            return {status: "ready", finalVideoUrl: publicUrl};
          }
        } catch (e: any) {
          console.error("[startVeoForJob] files api download failed", e?.message);
        }
      }
    }

    // As a last resort, scan for any URL-like string under expected containers
    if (!downloadUrl) {
      const scan = (obj: any, depth = 0): string | undefined => {
        if (!obj || depth > 6) return undefined;
        if (typeof obj === "string") {
          if (/^https?:\/\//i.test(obj)) return obj;
          return undefined;
        }
        if (Array.isArray(obj)) {
          for (const it of obj) { const r = scan(it, depth + 1); if (r) return r; }
          return undefined;
        }
        if (typeof obj === "object") {
          // Prefer keys that look like video/media
          const entries = Object.entries(obj) as Array<[string, any]>;
          for (const [k, v] of entries) {
            if (/video|media|uri|url/i.test(k)) {
              const r = scan(v, depth + 1); if (r) return r;
            }
          }
          for (const [, v] of entries) {
            const r = scan(v, depth + 1); if (r) return r;
          }
        }
        return undefined;
      };
      const scanned = scan(op?.response) || scan(op?.result);
      if (scanned) downloadUrl = scanned;
    }

    // Persist a brief shape for troubleshooting
    try {
      const shape = {
        hasGv: !!gv, hasSample: !!sample,
        sampleHasVideo: !!(sample as any)?.video,
        gvHasVideo: !!gv?.video,
      };
      await jobRef.set({debug: {opShape: shape}}, {merge: true});
    } catch {}

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


