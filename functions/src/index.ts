import * as logger from "firebase-functions/logger";
import { onRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { initializeApp, getApps } from "firebase-admin/app";
import { Storage } from "@google-cloud/storage";
import crypto from "crypto";
import Replicate from "replicate";
// Re-export storyboard HTTP endpoints so they are included in the build (ESM needs explicit .js)
export { saveStoryboardSet } from "./saveStoryboardSet.js";
export { startStoryboardRun } from "./startStoryboardRun.js";
export { enqueueSceneVideo } from "./enqueueSceneVideo.js";
export { runSceneVideo } from "./runSceneVideo.js";
export { wanI2vFast } from "./wanI2VFast.js";
export { generateFluxAvatar } from "./musicVideo/generateFluxAvatar.js";
export { generateMusicStoryboard, generateMusicStoryboardV2 } from "./musicVideo/generateMusicStoryboard.js";
// Ensure storyboard image generator and scene onCreate trigger are deployed
export { generateStoryboardImages } from "./generateStoryboardImages.js";

if (!getApps().length) {
  // Set the default Storage bucket so workers can resolve bucket() without explicit name
  const cfg = process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)) : undefined as any;
  const cfgBucket: string | undefined = cfg?.storageBucket;
  const envBucket: string | undefined = process.env.FIREBASE_STORAGE_BUCKET as string | undefined;
  const proj = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  const fallbackBucket: string | undefined = proj ? `${proj}.appspot.com` : undefined;
  const storageBucket = String(envBucket || cfgBucket || fallbackBucket || "").trim();
  initializeApp(storageBucket ? { storageBucket } : {});
}
const db = getFirestore();
const storage = new Storage();
const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN || "" });

async function gsToHttps(gsPath: string): Promise<string> {
  const m = gsPath.match(/^gs:\/\/([^\/]+)\/(.+)$/);
  if (!m) throw new Error("invalid_gs_path");
  const [, bucket, path] = m;
  const file = storage.bucket(bucket).file(path);
  const [exists] = await file.exists();
  if (!exists) throw new Error("file_not_found");
  const ttlEnv = Number(process.env.SIGNED_URL_TTL_MS || process.env.MEDIA_SIGN_URL_TTL_MS || 1000 * 60 * 60);
  const ttlMs = Number.isFinite(ttlEnv) && ttlEnv > 0 ? ttlEnv : (1000 * 60 * 60);
  const [url] = await file.getSignedUrl({ action: "read", expires: Date.now() + ttlMs });
  return url;
}

async function preflight(url: string, expectedKind: "audio" | "video") {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);
  try {
    // Try HEAD first
    let resp = await fetch(url as any, { method: "HEAD", signal: controller.signal as any } as any);
    if (!resp.ok || resp.status < 200 || resp.status >= 300) {
      // Fallback to GET Range
      const headers: any = { Range: "bytes=0-0" } as any;
      resp = await fetch(url as any, { method: "GET", headers, signal: controller.signal as any } as any);
    }
    const ok = resp.ok && (resp.status === 200 || resp.status === 206);
    const ct = resp.headers.get("content-type") || "";
    const clStr = resp.headers.get("content-length") || "";
    const cl = Number(clStr) || undefined;
    const kindOk = expectedKind === "audio" ? ct.startsWith("audio/") || ct.includes("mpeg") || ct.includes("aac") : ct.startsWith("video/") || ct.includes("mp4");
    return { ok, status: resp.status, contentType: ct, contentLength: cl, kindOk };
  } catch (e: any) {
    return { ok: false, status: 0, contentType: "", contentLength: undefined, kindOk: false, error: String(e?.message || e) };
  } finally {
    clearTimeout(timeout);
  }
}

export const startMusicFinishingV2 = onRequest(async (req, res) => {
  try {
    const { uid, projectId, storyboardId, runId, audioGsPath, audioDurationSec } = req.body || {};
    if (!uid || !projectId || !runId || !audioGsPath) { res.status(400).send("missing_fields"); return; }
    const audioUrl = await gsToHttps(audioGsPath);
    await db.doc(`users/${uid}/projects/${projectId}`).set({
      "finishing.runId": runId,
      "finishing.storyboardId": storyboardId || "default",
      "finishing.audioGsPath": audioGsPath,
      "finishing.audioUrl": audioUrl,
      "finishing.audioDurationSec": Number(audioDurationSec ?? 0),
      "finishing.startedAt": Date.now(),
      "finishing.status": "starting",
    }, { merge: true });
    logger.info("startMusicFinishing", { uid, projectId, runId });
    res.status(200).send({ ok: true, audioUrl });
  } catch (e: any) {
    logger.error("startMusicFinishing.error", { error: String(e) });
    res.status(500).send({ ok: false, error: String(e) });
  }
});

export const submitLipsyncV2 = onRequest({ region: "us-central1", secrets: ["REPLICATE_API_TOKEN"] }, async (req, res) => {
  try {
    const { uid, projectId, storyboardId, runId, videoUrl: bodyVideoUrl, audioUrl: bodyAudioUrl } = req.body || {};
    if (!uid || !projectId || !runId) { res.status(400).send("missing_fields"); return; }
    // Environment sanity logging (non-sensitive)
    try {
      const projectEnv = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || (process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)).projectId : "");
      const regionEnv = process.env.FUNCTION_REGION || process.env.GOOGLE_CLOUD_REGION || "us-central1";
      const hasReplicate = !!(process.env.REPLICATE_API_TOKEN && process.env.REPLICATE_API_TOKEN!.length > 0);
      logger.info("submitLipsync.env_sanity", { project: projectEnv, region: regionEnv, replicateTokenPresent: hasReplicate });
    } catch {}
    const ref = db.doc(`users/${uid}/projects/${projectId}`);
    const doc = await ref.get();
    const data = doc.data() || {};
    const finishingData: any = (data as any)?.finishing || {};
    // Prefer body overrides → persisted https URL → fallback gs:// if present
    let audioStored: string | undefined = (typeof bodyAudioUrl === "string" && bodyAudioUrl.trim().length > 0) ? String(bodyAudioUrl).trim() : (finishingData?.audioUrl as (string|undefined));
    const videoStored: string | undefined = (typeof bodyVideoUrl === "string" && bodyVideoUrl.trim().length > 0) ? String(bodyVideoUrl).trim() : (data as any)?.videoURL || (data as any)?.videoUrl;
    const hasFinishingAudioGs = typeof finishingData?.audioGsPath === "string" && String(finishingData.audioGsPath).startsWith("gs://");
    // If no audio URL but we have a gs:// path, use it (convert to https later)
    if (!audioStored && hasFinishingAudioGs) {
      audioStored = String(finishingData.audioGsPath);
    }
    try {
      logger.info("submitLipsync.inputs_loaded", {
        uid, projectId, runId,
        hasBodyAudio: !!bodyAudioUrl && String(bodyAudioUrl).length > 0,
        hasFinishingAudioUrl: typeof finishingData?.audioUrl === "string" && finishingData.audioUrl.length > 0,
        hasFinishingAudioGsPath: hasFinishingAudioGs,
        hasAudioStored: !!audioStored,
        hasBodyVideo: typeof bodyVideoUrl === "string" && bodyVideoUrl.length > 0,
        hasDocVideoURL: typeof (data as any)?.videoURL === "string" && (data as any).videoURL.length > 0,
        hasDocVideoUrlLower: typeof (data as any)?.videoUrl === "string" && (data as any).videoUrl.length > 0,
      });
    } catch {}
    if (!audioStored || !videoStored) {
      logger.warn("submitLipsync.missing_media_urls", {
        uid, projectId, runId,
        hasBodyAudio: !!bodyAudioUrl && String(bodyAudioUrl).length > 0,
        hasFinishingAudioUrl: typeof finishingData?.audioUrl === "string" && finishingData.audioUrl.length > 0,
        hasFinishingAudioGsPath: hasFinishingAudioGs,
        hasAudioStored: !!audioStored,
        hasBodyVideo: typeof bodyVideoUrl === "string" && bodyVideoUrl.length > 0,
        hasDocVideoURL: typeof (data as any)?.videoURL === "string" && (data as any).videoURL.length > 0,
        hasDocVideoUrlLower: typeof (data as any)?.videoUrl === "string" && (data as any).videoUrl.length > 0,
      });
      res.status(400).send({ ok: false, code: "missing_media_urls" });
      return;
    }

    // Idempotency: only short-circuit if this runId is already in submit/processing stage
    const finishing = (data as any)?.finishing || {};
    const alreadySubmitted = finishing?.runId === runId && (
      finishing?.status === "submitted" || finishing?.status === "processing" || typeof finishing?.predictionId === "string"
    );
    if (alreadySubmitted) {
      logger.info("submitLipsync.idempotent_return", { uid, projectId, runId });
      res.status(200).send({ ok: true, predictionId: finishing?.predictionId, replayed: true });
      return;
    }
    // Media preflight (audio & video)
    // Guarantee HTTPS: convert gs:// -> signed HTTPS if needed
    const audioFromGs = audioStored.startsWith("gs://");
    const audioUrl = audioFromGs ? await gsToHttps(audioStored) : audioStored;
    const chosenAudioSource = (typeof bodyAudioUrl === "string" && bodyAudioUrl.length > 0)
      ? "body"
      : (finishingData?.audioUrl ? "finishing.audioUrl" : (hasFinishingAudioGs ? "finishing.audioGsPath" : "unknown"));
    const chosenVideoSource = (typeof bodyVideoUrl === "string" && bodyVideoUrl.length > 0)
      ? "body"
      : ((data as any)?.videoURL ? "videoURL" : ((data as any)?.videoUrl ? "videoUrl" : "unknown"));
    const videoUrl = videoStored.startsWith("gs://") ? await gsToHttps(videoStored) : videoStored;
    try {
      logger.info("submitLipsync.sources", {
        uid, projectId, runId,
        audio_source: chosenAudioSource, audio_short: String(audioUrl).slice(0,64),
        video_source: chosenVideoSource, video_short: String(videoUrl).slice(0,64),
      });
    } catch {}
    // If we derived audio from gs://, persist https URL to finishing.audioUrl to stabilize subsequent calls
    if (audioFromGs) {
      try { await ref.set({ "finishing.audioUrl": audioUrl }, { merge: true }); } catch {}
    }

    const audioCheck = await preflight(audioUrl, "audio");
    const videoCheck = await preflight(videoUrl, "video");
    if (!audioCheck.ok || !audioCheck.kindOk) {
      logger.warn("submitLipsync.media_unreachable_audio", { uid, projectId, runId, status: audioCheck.status, ct: audioCheck.contentType, cl: audioCheck.contentLength });
      res.status(422).send({ ok: false, code: "media_unreachable", which: "audio", status: audioCheck.status });
      return;
    }
    if (!videoCheck.ok || !videoCheck.kindOk) {
      logger.warn("submitLipsync.media_unreachable_video", { uid, projectId, runId, status: videoCheck.status, ct: videoCheck.contentType, cl: videoCheck.contentLength });
      res.status(422).send({ ok: false, code: "media_unreachable", which: "video", status: videoCheck.status });
      return;
    }
    // Preflight passed – log short URL prefixes and content types for traceability
    try {
      logger.info("submitLipsync.media_preflight_ok", {
        uid, projectId, runId,
        audio_short: audioUrl.slice(0, 64), audio_ct: audioCheck.contentType,
        video_short: videoUrl.slice(0, 64), video_ct: videoCheck.contentType,
      });
    } catch {}

    // Write stub/lock first so duplicates before prediction creation are idempotent
    const webhookToken = crypto.randomUUID();
    await ref.set({
      "finishing.runId": runId,
      "finishing.storyboardId": storyboardId || "default",
      "finishing.webhookToken": webhookToken,
      "finishing.status": "submitted",
      "finishing.ttl": Date.now() + 1000*60*60*24,
      "finishing.inputs": {
        audioUrl, audioContentType: audioCheck.contentType, audioContentLength: audioCheck.contentLength,
        videoUrl, videoContentType: videoCheck.contentType, videoContentLength: videoCheck.contentLength
      }
    }, { merge: true });
    // Create Replicate prediction (LipSync-2-Pro)
    const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || (process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)).projectId : "");
    const base = `https://us-central1-${project}.cloudfunctions.net`;
    const webhookUrl = `${base}/lipsyncWebhookV2?uid=${uid}&projectId=${projectId}&runId=${runId}&token=${webhookToken}`;
    logger.info("submitLipsync.webhook_url", { uid, projectId, runId, webhookUrl });
    const prediction: any = await (replicate as any).predictions.create({
      model: "sync/lipsync-2-pro",
      input: { video: videoUrl, audio: audioUrl },
      webhook: webhookUrl,
      webhook_events_filter: ["completed"]
    });
    await ref.set({ "finishing.predictionId": prediction?.id || null }, { merge: true });
    logger.info("replicate.prediction.created", { uid, projectId, runId, predictionId: prediction?.id || null, model: "sync/lipsync-2-pro" });
    // Optional non-blocking verify
    try {
      const chk: any = await (replicate as any).predictions.get(prediction?.id);
      logger.info("replicate.prediction.status", { predictionId: prediction?.id, status: chk?.status });
    } catch (e: any) {
      logger.warn("replicate.prediction.get_failed", { error: String(e) });
    }
    res.status(200).send({ ok: true, predictionId: prediction?.id || null, replayed: false });
  } catch (e: any) {
    logger.error("submitLipsync.error", { error: String(e) });
    res.status(500).send({ ok: false, error: String(e) });
  }
});

export const lipsyncWebhookV2 = onRequest({ region: "us-central1" }, async (req, res) => {
  try {
    const { uid, projectId, runId, token } = req.query as Record<string, string>;
    const body = req.body as any;
    if (!uid || !projectId) { res.status(400).send("missing_query"); return; }
    const ref = db.doc(`users/${uid}/projects/${projectId}`);
    const snap = await ref.get();
    const docData = snap.data() || {} as any;
    const finishing = docData.finishing || {} as any;

    // Verify token when present
    if (finishing?.webhookToken && token !== finishing.webhookToken) { res.status(403).send("forbidden"); return; }

    // Idempotent: if already done with a final URL, no-op
    if (docData.finalVideoUrl && finishing?.status === "done") {
      logger.info("lipsyncWebhook.replayed", { uid, projectId, runId: runId || finishing?.runId });
      res.status(200).send({ ok: true, replayed: true });
      return;
    }
    if (body?.status === "succeeded") {
      const out = Array.isArray(body.output) ? body.output[0] : body.output;
      await ref.set({ finalVideoUrl: out, "finishing.status": "done", "finishing.completedAt": Date.now(), "finishing.runId": runId || finishing?.runId }, { merge: true });
      logger.info("lipsyncWebhook.completed", { uid, projectId, runId: runId || finishing?.runId, out_short: String(out).slice(0, 64) });
    } else if (body?.status === "failed") {
      await ref.set({ "finishing.status": "failed", "finishing.error": body?.error || "unknown" }, { merge: true });
      logger.warn("lipsyncWebhook.failed", { uid, projectId, runId: runId || finishing?.runId });
    }
    res.status(200).send({ ok: true });
  } catch (e: any) {
    logger.error("lipsyncWebhook.error", { error: String(e) });
    res.status(500).send({ ok: false, error: String(e) });
  }
});
