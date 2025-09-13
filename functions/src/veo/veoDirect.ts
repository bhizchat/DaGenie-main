/* eslint-disable max-len, require-jsdoc, valid-jsdoc, quotes, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getStorage} from "firebase-admin/storage";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import axios from "axios";
import crypto from "crypto";

if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}
const storage = getStorage();
const db = getFirestore();

// --- Helpers: sleep, jittered backoff, and safe logging of Axios errors ---
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function backoffDelayMs(attempt: number, base: number = 500, cap: number = 15000): number {
  const exp = Math.min(cap, Math.round(base * Math.pow(2, attempt - 1)));
  const jitter = Math.floor(Math.random() * Math.min(750, Math.round(exp * 0.25)));
  return Math.min(cap, exp + jitter);
}

function logAxiosError(where: string, err: any, extra?: Record<string, unknown>) {
  // Avoid logging secrets; include status and first ~300 chars of body
  const status = err?.response?.status;
  let bodyHead: string | undefined;
  try {
    if (typeof err?.response?.data === "string") {
      bodyHead = err.response.data.slice(0, 300);
    } else if (err?.response?.data) {
      bodyHead = JSON.stringify(err.response.data).slice(0, 300);
    }
  } catch {}
  functions.logger.error("[veoDirect] upstream_error", {where, status, bodyHead, ...(extra || {})});
}

function parseRetryAfterMs(err: any): number {
  try {
    const h = err?.response?.headers || {};
    const ra = (h["retry-after"] || h["Retry-After"]) as string | undefined;
    if (ra) {
      const sec = Number(ra);
      if (!Number.isNaN(sec)) return sec * 1000;
      const dateMs = Date.parse(ra);
      if (!Number.isNaN(dateMs)) return Math.max(0, dateMs - Date.now());
    }
  } catch {}
  // Fallback: if API returns google.rpc.RetryInfo in JSON details
  try {
    const details = err?.response?.data?.error?.details;
    if (Array.isArray(details)) {
      const ri = details.find((d: any) => String(d?.["@type"] || d?.type || "").includes("RetryInfo"));
      if (ri?.retryDelay) {
        const s = Number(ri.retryDelay.seconds || 0);
        const n = Number(ri.retryDelay.nanos || 0);
        return s * 1000 + Math.ceil(n / 1e6);
      }
    }
  } catch {}
  return 0;
}

// --- Global throttle using Firestore to serialize starts across instances ---
const THROTTLE_DOC = db.doc("system/veo_throttle");
const MAX_CONCURRENT = 1; // serialize to avoid bursts
const MIN_SPACING_MS = 7000; // ~8.5 RPM between start times

async function acquireVeoLease(maxWaitMs: number = 180_000): Promise<boolean> {
  const start = Date.now();
  while (Date.now() - start < maxWaitMs) {
    try {
      let acquired = false; let waitMs = 1000;
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(THROTTLE_DOC);
        const now = Date.now();
        const data: any = snap.exists ? snap.data() : { inflight: 0, lastStartAtMs: 0 };
        const inflight = Number(data.inflight || 0);
        const lastStartAtMs = Number(data.lastStartAtMs || 0);
        const since = now - lastStartAtMs;
        if (inflight < MAX_CONCURRENT && since >= MIN_SPACING_MS) {
          tx.set(THROTTLE_DOC, { inflight: inflight + 1, lastStartAtMs: now }, { merge: true });
          acquired = true;
        } else {
          const need = Math.max(MIN_SPACING_MS - since, 500);
          waitMs = Math.min(15_000, need + Math.floor(Math.random() * 500));
        }
      });
      if (acquired) return true;
      await sleep(waitMs);
    } catch {
      await sleep(1000 + Math.floor(Math.random() * 500));
    }
  }
  return false;
}

async function releaseVeoLease(): Promise<void> {
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(THROTTLE_DOC);
      const data: any = snap.exists ? snap.data() : { inflight: 0 };
      const inflight = Math.max(0, Number(data.inflight || 0) - 1);
      tx.set(THROTTLE_DOC, { inflight }, { merge: true });
    });
  } catch {}
}

/**
 * Direct Veo 3 generate endpoint (HTTPS), mirroring WAN shape.
 * Input (JSON):
 *  - image (string, required): gs:// path or https/data URI
 *  - prompt (string, required)
 *  - model (string, optional): default "veo-3.0-generate-001"
 *  - aspectRatio ("16:9"|"9:16", optional)
 *  - resolution ("1080p"|"720p", optional)
 *  - jobId (string, optional) — when present, function writes status/debug to Firestore
 * Output: { videoUrl: string, jobId?: string }
 */
export const veoDirect = functions
  .runWith({timeoutSeconds: 540, memory: "1GB", secrets: ["VEO_API_KEY"]})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      const apiKey = (process.env.VEO_API_KEY as string | undefined)?.trim();
      if (!apiKey) { res.status(500).json({error: "missing_veo_api_key"}); return; }

      const body: any = req.body || {};
      const image: string = String(body.image || "");
      const prompt: string = String(body.prompt || "");
      const jobId: string | undefined = typeof body.jobId === "string" && body.jobId.trim().length > 0 ? String(body.jobId).trim() : undefined;
      if (!image || !prompt) { res.status(400).json({error: "bad_request", message: "image and prompt are required"}); return; }
      const model: string = String(body.model || "veo-3.0-generate-001");

      // Veo 3 AR/resolution per docs: allow 16:9 or 9:16; 1080p only for 16:9; 9:16 → 720p
      const aspect: "16:9"|"9:16" = (body.aspectRatio === "16:9" ? "16:9" : "9:16");
      const resolution: "720p"|"1080p"|undefined = (aspect === "16:9") ? (body.resolution === "1080p" ? "1080p" : "720p") : "720p";
      const parameters: any = {
        negativePrompt: "text, captions, subtitles, watermarks",
        aspectRatio: aspect,
        // Shorten to reduce capacity pressure; 5s is usually sufficient
        durationSeconds: 5,
        sampleCount: 1,
        personGeneration: "allow_adult",
      };
      if (resolution) parameters.resolution = resolution;

      // Resolve image to bytes
      let imageBytesB64: string | undefined;
      if (image.startsWith("gs://")) {
        const m = image.match(/^gs:\/\/([^/]+)\/(.+)$/);
        const bucketName = m?.[1];
        const objectPath = m?.[2];
        if (!bucketName || !objectPath) { res.status(400).json({error: "bad_request", message: "invalid gs path"}); return; }
        const [bytes] = await storage.bucket(bucketName).file(objectPath).download();
        imageBytesB64 = Buffer.from(bytes).toString("base64");
      } else if (/^https?:\/\//i.test(image)) {
        const r = await axios.get<ArrayBuffer>(image, {responseType: "arraybuffer", timeout: 30000});
        imageBytesB64 = Buffer.from(r.data as any).toString("base64");
      } else if (/^data:/i.test(image)) {
        const b64 = String(image).split(",").pop() || "";
        imageBytesB64 = b64;
      }
      if (!imageBytesB64) { res.status(400).json({error: "bad_request", message: "unable to read image"}); return; }

      // Optional: mark generating on existing job
      let jobRef: FirebaseFirestore.DocumentReference | undefined;
      if (jobId) {
        try {
          jobRef = db.collection("adJobs").doc(jobId);
          await jobRef.set({
            status: "generating",
            provider: "veo3_direct",
            processing: {startedAt: Timestamp.now(), startedBy: "veo_direct"},
            debug: {
              finalPromptHead: String(prompt).slice(0, 220),
              finalPromptFull: prompt,
              model,
              aspectRatioSent: aspect,
              resolutionSent: parameters.resolution ?? null,
              durationSecondsSent: parameters.durationSeconds,
            }
          }, {merge: true});
        } catch {}
      }

      // Call Veo predictLongRunning (protected by a global lease to avoid bursts)
      const apiBase = "https://generativelanguage.googleapis.com/v1beta";
      const predictUrl = `${apiBase}/models/${encodeURIComponent(model)}:predictLongRunning`;
      // Attach image bytes in the shape most commonly accepted by Veo 3.0. Some
      // endpoints accept either `imageBytes` or `bytesBase64Encoded`; include both
      // for maximum compatibility.
      const instances: any[] = [{
        prompt,
        image: {
          imageBytes: imageBytesB64,
          bytesBase64Encoded: imageBytesB64,
          mimeType: "image/jpeg",
        },
      }];
      const leased = await acquireVeoLease(120_000);
      if (!leased) {
        if (jobRef) { try { await jobRef.set({status: "queued", updatedAt: Timestamp.now(), debug: {throttle: "lease_timeout"}}, {merge: true}); } catch {} }
        res.status(429).json({error: "throttled", message: "lease_timeout"});
        return;
      }
      // Call Veo predictLongRunning with retries on 429/5xx
      let predict: any;
      {
        const maxAttempts = 5;
        for (let attempt = 1; attempt <= maxAttempts; attempt++) {
          try {
            predict = await axios.post(
              predictUrl,
              {instances, parameters},
              {timeout: 120000, headers: {"x-goog-api-key": apiKey, "Content-Type": "application/json"}}
            );
            break; // success
          } catch (e: any) {
            const code = e?.response?.status;
            // Retry on 429 and 5xx; otherwise bubble
            if (code === 429 || (typeof code === "number" && code >= 500 && code < 600)) {
              logAxiosError("predictLongRunning", e, {attempt});
              const hinted = parseRetryAfterMs(e);
              const wait = Math.max(hinted, backoffDelayMs(attempt));
              await sleep(wait);
              if (attempt === maxAttempts) throw e;
              continue;
            }
            logAxiosError("predictLongRunning_nonretry", e, {attempt});
            throw e;
          }
        }
      }
      const operationName = predict.data?.name || predict.data?.operation || predict.data?.id;
      if (jobRef) { try { await jobRef.set({debug: {operationName}}, {merge: true}); } catch {} }

      // Poll LRO with resilient retries
      let tries = 0; const maxTries = 60; let op: any = {done: false};
      while (!op?.done && tries < maxTries) {
        await sleep(10000);
        const opUrl = `${apiBase}/${operationName}`;
        try {
          const opResp = await axios.get(opUrl, {timeout: 60000, headers: {"x-goog-api-key": apiKey}});
          op = opResp.data; tries++;
          if (jobRef && (tries % 3 === 0)) { try { await jobRef.set({debug: {pollCount: tries, lastPollAt: Timestamp.now()}}, {merge: true}); } catch {} }
          if (op?.error) {
            const msg = op?.error?.message || "operation_error";
            if (jobRef) { try { await jobRef.set({status: "error", error: msg, updatedAt: Timestamp.now()}, {merge: true}); } catch {} }
            res.status(502).json({error: "operation_error", message: msg});
            return;
          }
        } catch (e: any) {
          // Network/timeout during polling; retry with backoff
          const wait = backoffDelayMs(Math.min(tries + 1, 5));
          logAxiosError("poll_long_running", e, {tries, wait});
          await sleep(wait);
        }
      }

      // Log summary of LRO outcome for diagnostics
      try {
        functions.logger.log("[veoDirect] lro_complete", {
          tries,
          done: !!op?.done,
          hasResponse: !!op?.response,
          hasResult: !!op?.result,
          respSamples: Array.isArray(op?.response?.generateVideoResponse?.generatedSamples) ? op.response.generateVideoResponse.generatedSamples.length : null,
          resultSamples: Array.isArray(op?.result?.generateVideoResponse?.generatedSamples) ? op.result.generateVideoResponse.generatedSamples.length : null,
        });
      } catch {}

      // Extract URL from a robust set of documented and observed shapes
      const gv = op?.response?.generateVideoResponse?.generatedSamples?.[0]?.video ||
                 op?.result?.generateVideoResponse?.generatedSamples?.[0]?.video ||
                 op?.response?.generatedVideos?.[0]?.video ||
                 op?.result?.generatedVideos?.[0]?.video;
      const sample = op?.response?.generateVideoResponse?.generatedSamples?.[0] ||
        op?.result?.generateVideoResponse?.generatedSamples?.[0] ||
        op?.response?.generatedSamples?.[0] ||
        op?.result?.generatedSamples?.[0] ||
        op?.response?.generate_video_response?.generated_samples?.[0] ||
        op?.result?.generate_video_response?.generated_samples?.[0];

      let url: string | null = null;
      const tryVals: Array<string | undefined> = [
        (sample as any)?.video?.uri,
        (sample as any)?.video?.url,
        (sample as any)?.video?.signedUri,
        (sample as any)?.video?.gcsUri,
        (sample as any)?.videoUri,
        (sample as any)?.uri,
        (gv as any)?.uri,
        (gv as any)?.url,
        (op?.response as any)?.videoUri,
        (op?.result as any)?.videoUri,
      ];
      for (const v of tryVals) {
        if (typeof v === "string" && v.trim().length > 0) { url = v; break; }
      }

      try {
        functions.logger.log("[veoDirect] extract_url", {
          hasGV: !!gv,
          gotUrl: !!url,
          urlHead: url ? String(url).slice(0, 96) : null,
        });
      } catch {}

      // Files API fallback
      if (!url) {
        const fileObj = (gv && (gv as any)) || (sample && (sample as any));
        const fileName: string | undefined = (fileObj && typeof (fileObj as any).name === "string" ? (fileObj as any).name : undefined) ||
          (typeof fileObj === "string" && /^files\//i.test(fileObj) ? (fileObj as any) : undefined);
        if (fileName) {
          try {
            const metaUrl = `${apiBase}/${encodeURIComponent(fileName)}`;
            const meta = (await axios.get(metaUrl, {timeout: 30000, headers: {"x-goog-api-key": apiKey}})).data;
            const dlUri: string | undefined = meta?.downloadUri || (fileObj as any)?.downloadUri || (fileObj as any)?.uri;
            if (typeof dlUri === "string" && /^https?:\/\//i.test(dlUri)) {
              url = dlUri;
            } else {
              const bytesResp = await axios.get<ArrayBuffer>(`${apiBase}/${encodeURIComponent(fileName)}:download`, {responseType: "arraybuffer", timeout: 300000, headers: {"x-goog-api-key": apiKey}});
              // Rehost and return
              const outPath = `veo_videos/${Date.now()}_${Math.random().toString(36).slice(2)}.mp4`;
              const bucket = storage.bucket();
              const file = bucket.file(outPath);
              const token: string = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
              await file.save(Buffer.from(bytesResp.data as any), {contentType: "video/mp4", metadata: {metadata: {firebaseStorageDownloadTokens: token}}, resumable: false});
              const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(outPath)}?alt=media&token=${token}`;
              if (jobRef) { try { await jobRef.set({status: "ready", finalVideoUrl: publicUrl, updatedAt: Timestamp.now()}, {merge: true}); } catch {} }
              res.status(200).json({videoUrl: publicUrl, jobId: jobId || null});
              return;
            }
          } catch {/* keep falling through */}
        } else {
          try { functions.logger.error("[veoDirect] no_video_url_no_fileName", { opHead: JSON.stringify(op).slice(0, 600) }); } catch {}
        }
      }

      if (!url) {
        // As a last resort, deep-scan the response for any URL-looking string
        const scan = (obj: any, depth = 0): string | undefined => {
          if (!obj || depth > 6) return undefined;
          if (typeof obj === "string") { return /^https?:\/\//i.test(obj) ? obj : undefined; }
          if (Array.isArray(obj)) { for (const it of obj) { const r = scan(it, depth + 1); if (r) return r; } return undefined; }
          if (typeof obj === "object") {
            const entries = Object.entries(obj);
            for (const [k, v] of entries) { if (/video|media|uri|url/i.test(k)) { const r = scan(v, depth + 1); if (r) return r; } }
            for (const [, v] of entries) { const r = scan(v, depth + 1); if (r) return r; }
          }
          return undefined;
        };
        url = scan(op?.response) || scan(op?.result) || null;
      }

      if (!url) {
        try { functions.logger.error("[veoDirect] no_video_url", { opHead: JSON.stringify(op).slice(0, 900) }); } catch {}
        if (jobRef) { try { await jobRef.set({status: "error", error: "no_video", updatedAt: Timestamp.now()}, {merge: true}); } catch {} }
        res.status(500).json({error: "no_video"}); return;
      }

      // Best effort rehost for direct URLs; include small retry on 429/5xx
      try {
        try { functions.logger.log("[veoDirect] rehost_start", { urlHead: String(url).slice(0, 96) }); } catch {}
        let dl: any;
        const maxAttempts = 4;
        for (let attempt = 1; attempt <= maxAttempts; attempt++) {
          try {
            dl = await axios.get<ArrayBuffer>(url, {responseType: "arraybuffer", headers: {"x-goog-api-key": apiKey}, timeout: 300000});
            break;
          } catch (e: any) {
            const code = e?.response?.status;
            if (code === 429 || (typeof code === "number" && code >= 500 && code < 600)) {
              logAxiosError("rehost_download", e, {attempt});
              const wait = backoffDelayMs(attempt);
              await sleep(wait);
              if (attempt === maxAttempts) throw e;
              continue;
            }
            throw e;
          }
        }
        const outPath = `veo_videos/${Date.now()}_${Math.random().toString(36).slice(2)}.mp4`;
        const bucket = storage.bucket();
        const file = bucket.file(outPath);
        const token: string = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        await file.save(Buffer.from(dl.data as any), {contentType: "video/mp4", metadata: {metadata: {firebaseStorageDownloadTokens: token}}, resumable: false});
        const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(outPath)}?alt=media&token=${token}`;
        if (jobRef) { try { await jobRef.set({status: "ready", finalVideoUrl: publicUrl, updatedAt: Timestamp.now()}, {merge: true}); } catch {} }
        res.status(200).json({videoUrl: publicUrl, jobId: jobId || null});
      } catch {
        if (jobRef) { try { await jobRef.set({status: "ready", finalVideoUrl: url, updatedAt: Timestamp.now()}, {merge: true}); } catch {} }
        res.status(200).json({videoUrl: url, jobId: jobId || null});
      } finally { await releaseVeoLease(); }
    } catch (err) {
      const msg = (err as any)?.message || String(err);
      functions.logger.error("veoDirect failed", msg);
      const jobId: string | undefined = (req.body && typeof req.body.jobId === "string" && req.body.jobId.trim().length > 0) ? String(req.body.jobId).trim() : undefined;
      if (jobId) { try { await db.collection("adJobs").doc(jobId).set({status: "error", error: msg?.slice(0, 500) || "internal", updatedAt: Timestamp.now()}, {merge: true}); } catch {} }
      res.status(500).json({error: "internal_error", message: msg});
    }
  });


