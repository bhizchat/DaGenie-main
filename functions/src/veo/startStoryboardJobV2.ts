/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {onCall, CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import axios from "axios";

const VEO_API_KEY = defineSecret("VEO_API_KEY");

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const db = getFirestore();
const storage = getStorage();

export interface StartStoryboardV2Input { jobId: string }

function looksLikeAd(obj: any, raw: string): boolean {
  const t = String(raw || "").toLowerCase();
  if (/made to be remembered|product[-\s]?focus|photorealistic cinematic|text_overlay|keywords|narrator:\s*"/i.test(t)) return true;
  if (obj && ("elements" in obj || "keywords" in obj || (Array.isArray(obj?.sequence) && obj.sequence.length > 1))) return true;
  return false;
}

export const startStoryboardJobV2 = onCall({
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
  secrets: [VEO_API_KEY],
}, async (req: CallableRequest<StartStoryboardV2Input>) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "User must be signed in.");
  const jobId = (req.data?.jobId || "").trim();
  if (!jobId) throw new HttpsError("invalid-argument", "Missing jobId");

  const jobRef = db.collection("adJobs").doc(jobId);
  const snap = await jobRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Job not found");
  const job = snap.data() as any;
  if (job.uid !== uid) throw new HttpsError("permission-denied", "Not your job");

  const v1 = job.promptV1 as any;
  if (!v1) throw new HttpsError("failed-precondition", "missing promptV1");

  // Mark generating
  await jobRef.set({status: "generating", provider: "veo3", processing: { startedAt: Timestamp.now(), startedBy: "storyboard_v2" }, updatedAt: Timestamp.now()}, {merge: true});

  // Prepare prompt strictly from storyboardPrompt; rebuild if contaminated
  let primary = typeof job.storyboardPrompt === "string" ? job.storyboardPrompt : "";
  let parsed: any = undefined;
  let repaired = false;
  try { parsed = JSON.parse(primary || "{}"); } catch { /* will repair */ }
  if (!parsed || looksLikeAd(parsed, primary)) {
    const selIdx = (typeof job?.honoredSelection?.selectedIndex === "number" ? job.honoredSelection.selectedIndex : 0);
    const scene = Array.isArray(v1?.scenes) ? (v1.scenes.find((s: any) => Number(String(s.id||"").replace(/\D+/g, "")) === selIdx) || v1.scenes[selIdx] || v1.scenes[0]) : undefined;
    const beats = (scene?.beats || []).filter(Boolean);
    const desc = (beats.join(" ").trim() || "beat");
    parsed = { scene: "animation", style: "animated mascot short, playful, campus vibe", sequence: [{shot: "storyboard_beat", camera: "controlled", description: desc}], format: (v1?.output?.resolution === "16:9" ? "16:9" : "9:16") };
    primary = JSON.stringify(parsed);
    repaired = true;
  }

  // Build final prompt with single quoted line if present
  const lines: string[] = Array.isArray(parsed?.dialogue) ? (parsed.dialogue as any[]).filter((s: any) => typeof s === "string" && s.trim().length > 0) : [];
  const accent: string | undefined = (typeof parsed?.accent === "string" && parsed.accent.trim().length > 0) ? parsed.accent.trim() : undefined;
  let finalPromptToSend = primary;
  if (lines.length) {
    const first = String(lines[0]).replace(/^\s*"|"\s*$/g, "").trim();
    const voice = `"${first}"${accent ? ` (${accent})` : ""}`;
    finalPromptToSend = `${voice}\n\n${primary}`;
  }

  // Prepare image bytes
  const imageGs = String(v1?.product?.imageGsPath || "");
  if (!imageGs.startsWith("gs://")) throw new HttpsError("failed-precondition", "image_required");
  const m = imageGs.match(/^gs:\/\/([^/]+)\/(.+)$/);
  const bucketName = m?.[1];
  const objectPath = m?.[2];
  if (!bucketName || !objectPath) throw new HttpsError("failed-precondition", "image_required");
  const [bytes] = await storage.bucket(bucketName).file(objectPath).download();
  const imageBytes = Buffer.from(bytes).toString("base64");

  // API call
  const apiKey = (process.env.VEO_API_KEY as string | undefined)?.trim();
  if (!apiKey) throw new HttpsError("failed-precondition", "missing_veo_api_key");
  const apiBase = "https://generativelanguage.googleapis.com/v1beta";
  const modelName = String(job.model || "veo-3.0-generate-001");
  // Emergency guard: disable Veo models entirely for storyboard flow
  if (/veo/i.test(modelName)) {
    await jobRef.set({status: "error", updatedAt: Timestamp.now(), debug: {blocked: "veo_storyboards_disabled"}}, {merge: true});
    throw new HttpsError("unavailable", "veo_storyboards_disabled");
  }
  let aspect = (parsed?.format === "16:9" || parsed?.format === "9:16") ? parsed.format : "9:16";
  if (modelName === "veo-3.0-generate-001" && aspect === "9:16") aspect = "16:9";
  const parameters: any = {negativePrompt: "text, captions, subtitles, watermarks", aspectRatio: aspect};
  if (aspect === "16:9") parameters.resolution = "1080p";

  // Branch: WAN fast path uses our existing HTTPS function with same sanitized prompt
  if (/^wan/i.test(modelName)) {
    const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "dategenie-dev";
    const wanUrl = `https://us-central1-${projectId}.cloudfunctions.net/wanI2vFast`;
    await jobRef.set({processing: {startedAt: Timestamp.now()}, debug: {finalPromptHead: finalPromptToSend.slice(0, 220), finalPromptFull: finalPromptToSend, provider: "wan", correctedPromptApplied: repaired, dialogueLinesCount: lines.length}}, {merge: true});
    const wanBody = {image: imageGs, prompt: finalPromptToSend};
    const r = await axios.post(wanUrl, wanBody, {timeout: 300000});
    const vurl = r.data?.videoUrl || r.data?.replicateUrl;
    if (!vurl) throw new HttpsError("internal", "wan_no_video_url");
    await jobRef.set({status: "ready", finalVideoUrl: vurl, updatedAt: Timestamp.now()}, {merge: true});
    return {status: "ready", finalVideoUrl: vurl};
  }

  const instances: any[] = [{prompt: finalPromptToSend, image: {imageBytes, mimeType: "image/jpeg"}}];
  const predictUrl = `${apiBase}/models/${encodeURIComponent(modelName)}:predictLongRunning?key=${encodeURIComponent(apiKey)}`;
  const body = {instances, parameters};
  const genResp: any = await axios.post(predictUrl, body, {timeout: 120000});
  const operationName = genResp.data?.name || genResp.data?.operation || genResp.data?.id;
  await jobRef.set({processing: {startedAt: Timestamp.now()}, debug: {finalPromptHead: finalPromptToSend.slice(0, 220), finalPromptFull: finalPromptToSend, aspectRatioSent: parameters.aspectRatio, resolutionSent: parameters.resolution ?? null, correctedPromptApplied: repaired, dialogueLinesCount: lines.length}}, {merge: true});

  // Poll
  let tries = 0; const maxTries = 48; let op: any = {done: false};
  while (!op?.done && tries < maxTries) {
    await new Promise((r) => setTimeout(r, 10000));
    const opUrl = `${apiBase}/${operationName}?key=${encodeURIComponent(apiKey)}`;
    const opResp = await axios.get(opUrl, {timeout: 60000});
    op = opResp.data; tries++;
  }
  const gv = (op.result?.generatedVideos?.[0]) || (op.response?.generatedVideos?.[0]) || (op.response?.generated_videos?.[0]);
  const sample = op.response?.generateVideoResponse?.generatedSamples?.[0] || op.result?.generateVideoResponse?.generatedSamples?.[0] || op.response?.generatedSamples?.[0] || op.result?.generatedSamples?.[0];
  const url = sample?.video?.uri || sample?.video?.url || gv?.video?.uri || gv?.video?.url || gv?.video || gv?.uri || null;
  if (!url) throw new HttpsError("internal", "No video URL in operation result");

  // Rehost
  try {
    const dl = await axios.get<ArrayBuffer>(String(url), {responseType: "arraybuffer", headers: {"x-goog-api-key": apiKey}, timeout: 300000});
    const outPath = `generated_ads/${jobId}/output.mp4`;
    const bucket = storage.bucket();
    const file = bucket.file(outPath);
    const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    await file.save(Buffer.from(dl.data as any), {contentType: "video/mp4", metadata: {metadata: {firebaseStorageDownloadTokens: token}}, resumable: false});
    const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(outPath)}?alt=media&token=${token}`;
    await jobRef.set({status: "ready", finalVideoUrl: publicUrl, updatedAt: Timestamp.now()}, {merge: true});
    return {status: "ready", finalVideoUrl: publicUrl};
  } catch (e: any) {
    await jobRef.set({status: "ready", finalVideoUrl: url, updatedAt: Timestamp.now()}, {merge: true});
    return {status: "ready", finalVideoUrl: url};
  }
});


