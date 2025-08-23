/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {onCall, CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import axios from "axios";

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

  // Resolve image (optional) from gs:// to a signed URL
  let imageUrl: string | undefined;
  if (p.product.imageGsPath && typeof p.product.imageGsPath === "string") {
    try {
      const gs = p.product.imageGsPath as string; // gs://bucket/object
      const m = gs.match(/^gs:\/\/([^/]+)\/(.+)$/);
      if (m) {
        const bucket = storage.bucket(m[1]);
        const file = bucket.file(m[2]);
        const [signed] = await file.getSignedUrl({action: "read", expires: Date.now() + 60 * 60 * 1000});
        imageUrl = signed;
      }
    } catch (e: any) {
      console.error("[startVeoForJob] signed URL error", e?.message);
    }
  }

  // Prepare REST endpoints for Veo (Generative Language API)
  const apiKey = process.env.VEO_API_KEY as string;
  const apiBase = "https://generativelanguage.googleapis.com/v1beta";
  const modelName = (job.model as string) || "veo-3.0-generate-preview";

  await jobRef.update({status: "queued", provider: "veo3", updatedAt: Timestamp.now()});
  const request: any = {prompt};
  // Negative prompt: discourage text/watermarks
  request.config = {negative_prompt: "text, captions, subtitles, watermarks"};
  if (imageUrl) request.image = {uri: imageUrl};

  try {
    // Kick off generateMedia
    const genUrl = `${apiBase}/models/${encodeURIComponent(modelName)}:generateMedia?key=${encodeURIComponent(apiKey)}`;
    const genResp = await axios.post(genUrl, request, {timeout: 120000});
    const operationName = genResp.data?.name || genResp.data?.operation || genResp.data?.id;
    await jobRef.update({status: "processing", providerJobId: operationName || null, updatedAt: Timestamp.now()});

    // Poll the operation until done
    let tries = 0;
    const maxTries = 48; // up to ~8 min
    let op: any = {done: false};
    while (!op?.done && tries < maxTries) {
      await new Promise((r) => setTimeout(r, 10000));
      const opUrl = `${apiBase}/operations/${encodeURIComponent(operationName)}?key=${encodeURIComponent(apiKey)}`;
      const opResp = await axios.get(opUrl, {timeout: 60000});
      op = opResp.data;
      tries++;
    }

    if (!op?.done) {
      await jobRef.update({status: "error", error: "timeout", updatedAt: Timestamp.now()});
      throw new HttpsError("deadline-exceeded", "Veo operation timed out");
    }

    const gv = (op.result?.generatedVideos?.[0]) || (op.response?.generatedVideos?.[0]) || (op.response?.generated_videos?.[0]);
    const downloadUrl = gv?.video?.uri || gv?.video?.url || gv?.video || gv?.uri || null;
    if (!downloadUrl) {
      await jobRef.update({status: "error", error: "no_video", updatedAt: Timestamp.now()});
      throw new HttpsError("internal", "No video URL in operation result");
    }

    await jobRef.update({status: "ready", finalVideoUrl: downloadUrl, updatedAt: Timestamp.now()});
    return {status: "ready", finalVideoUrl: downloadUrl};
  } catch (e: any) {
    const msg = typeof e?.message === "string" ? e.message : String(e);
    console.error("[startVeoForJob] generate/poll error", msg, e?.response?.data || e?.stack);
    await jobRef.update({status: "error", error: msg?.slice(0, 500) || "internal", updatedAt: Timestamp.now()});
    throw new HttpsError("internal", msg || "Veo generate failed");
  }
});


