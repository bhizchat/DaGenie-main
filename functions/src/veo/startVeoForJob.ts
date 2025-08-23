/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {onCall, CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import axios from "axios";
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
  const snap = await jobRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Job not found");
  const job = snap.data() as any;
  if (job.uid !== uid) throw new HttpsError("permission-denied", "Not your job");

  const p = job.promptV1 as VideoPromptV1 | undefined;
  if (!p) throw new HttpsError("failed-precondition", "missing promptV1");
  // Enforce: image is required for Veo generation
  if (!p.product?.imageGsPath || typeof p.product.imageGsPath !== "string") {
    await jobRef.update({status: "error", error: "image_required", updatedAt: Timestamp.now()});
    throw new HttpsError("failed-precondition", "image_required");
  }

  // Compose a single Veo-friendly prompt including audio cues
  const header = p.style === "cinematic" ? "Cinematic, photorealistic hero product reveal." : "Creative, playful animation with cohesive motion grammar.";
  const audio = p.audio.preference === "with_sound" ?
    ` Sound design: ${p.audio.sfxHints?.join(", ") || "tasteful SFX"}. ${p.audio.voiceoverScript ? `Dialogue: "${p.audio.voiceoverScript}"` : ""}` :
    " Silent visual — avoid text overlays.";
  const scenes = p.scenes.map((s) => {
    const beats = s.beats.join("; ");
    const shots = s.shots.map((sh) => `${sh.camera} shot of ${sh.subject} — ${sh.action}`).join("; ");
    return `Scene ${s.id} (${s.duration_s}s): ${beats}. Shots: ${shots}.`;
  }).join(" \n");
  const cta = p.cta?.copy ? ` End on a clean hero frame. CTA vibe: ${p.cta.copy}.` : " End on a clean hero frame.";
  const prompt = `${header} Subject: ${p.product.description}. ${scenes}.${cta}${audio ? " " + audio : ""}`.trim();

  // Resolve image (required) from gs:// to a signed URL; fallback to Firebase token URL.
  // If the bucket in gs:// is not accessible (e.g., firebasestorage.app host), try the project's default bucket.
  // Additionally, attempt to read bytes directly so we can send inline base64 which is accepted by Veo.
  let imageUrl: string | undefined;
  let inlineImageB64: string | undefined;
  let rawBucketForInline: string | undefined;
  let rawObjectPathForInline: string | undefined;
  if (p.product.imageGsPath && typeof p.product.imageGsPath === "string") {
    const gs = p.product.imageGsPath as string; // gs://bucket/object
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
      const defaultBucketName = defaultBucket.name;

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

      // Attempt with bucket from gs://, then fallback to project's default bucket
      imageUrl = await tryBuildFrom(primaryBucketName);
      if (!imageUrl && primaryBucketName !== defaultBucketName) {
        console.log("[startVeoForJob] retrying image URL resolution via default bucket", {defaultBucketName});
        imageUrl = await tryBuildFrom(defaultBucketName);
        if (imageUrl) {
          console.log("[startVeoForJob] resolved via default bucket");
        }
      }
    }
  }

  // Prefer inline base64 by downloading from GCS when possible
  if (rawBucketForInline && rawObjectPathForInline) {
    try {
      const [bytes] = await storage.bucket(rawBucketForInline).file(rawObjectPathForInline).download();
      inlineImageB64 = Buffer.from(bytes).toString("base64");
      console.log("[startVeoForJob] prepared inline base64 image from GCS");
    } catch (e: any) {
      console.error("[startVeoForJob] inline base64 download failed", e?.message);
    }
  }

  // Prepare REST endpoints for Veo (Generative Language API)
  const apiKey = process.env.VEO_API_KEY as string;
  const apiBase = "https://generativelanguage.googleapis.com/v1beta";
  const normalizeModel = (m?: string): string => {
    if (!m) return "veo-3.0-generate-preview";
    const s = String(m).toLowerCase();
    if (s.includes("fast")) return "veo-3.0-generate-preview";
    return m;
  };
  const modelName = normalizeModel(job.model as string);

  console.log("[startVeoForJob] begin jobId=", jobId, " model=", modelName);
  console.log("[startVeoForJob] codepath=REST_v1beta axios");
  await jobRef.update({status: "queued", provider: "veo3", updatedAt: Timestamp.now()});
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
    console.error("[startVeoForJob] image sign/inline failed; aborting generation");
    await jobRef.update({status: "error", error: "image_sign_failed", updatedAt: Timestamp.now()});
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
      if (tries % 3 === 0) console.log("[startVeoForJob] poll", {tries, done: !!op?.done});
      tries++;
    }

    if (!op?.done) {
      await jobRef.update({status: "error", error: "timeout", updatedAt: Timestamp.now()});
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
      return {status: "ready", finalVideoUrl: publicUrl};
    } catch (rehErr: any) {
      console.error("[startVeoForJob] rehost failed; returning original url", rehErr?.message);
      await jobRef.update({status: "ready", finalVideoUrl: downloadUrl, updatedAt: Timestamp.now()});
      return {status: "ready", finalVideoUrl: downloadUrl};
    }
  } catch (e: any) {
    const msg = typeof e?.message === "string" ? e.message : String(e);
    console.error("[startVeoForJob] generate/poll error", msg, e?.response?.data || e?.stack);
    await jobRef.update({status: "error", error: msg?.slice(0, 500) || "internal", updatedAt: Timestamp.now()});
    throw new HttpsError("internal", msg || "Veo generate failed");
  }
});


