/* eslint-disable max-len, require-jsdoc, valid-jsdoc, operator-linebreak, quotes, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import axios from "axios";
import Replicate from "replicate";
import crypto from "crypto";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getStorage} from "firebase-admin/storage";
import {gsToFetchableUrl} from "./utils/storageHelpers";

if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}

const storage = getStorage();

/**
 * WAN 2.2 image-to-video (fast) endpoint.
 * Input (JSON):
 *  - image (string, required): URL | data URI | gs:// bucket path
 *  - prompt (string, required)
 *  - Optional fields per model schema: seed, go_fast, last_image, num_frames, resolution,
 *    sample_shift, frames_per_second, disable_safety_checker, lora_* (see schema)
 *
 * Output: { videoUrl: string, replicateUrl?: string, prediction?: any }
 */
export const wanI2vFast = functions
  .runWith({timeoutSeconds: 540, secrets: ["REPLICATE_API_TOKEN"]})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") {
        functions.logger.warn("wanI2vFast: bad_method", {method: req.method});
        res.status(405).json({error: "method_not_allowed"});
        return;
      }

      const token = (process.env.REPLICATE_API_TOKEN as string) || "";
      if (!token) {
        functions.logger.error("wanI2vFast: missing_token");
        res.status(500).json({error: "replicate_token_missing"});
        return;
      }

      const body: any = req.body || {};
      let image: string = String(body.image || "");
      const prompt: string = String(body.prompt || "");
      if (!image || !prompt) {
        functions.logger.warn("wanI2vFast: missing_params", {hasImage: !!image, hasPrompt: !!prompt});
        res.status(400).json({error: "bad_request", message: "image and prompt are required"});
        return;
      }

      // If gs:// provided, convert to a temporary HTTPS URL that Replicate can fetch
      if (image.startsWith("gs://")) {
        try {
          image = await gsToFetchableUrl(image, (m, x) => functions.logger.info(m, x));
        } catch (e:any) {
          functions.logger.error('wanI2vFast: gs_to_https_failed', e?.message || e);
        }
      }

      const isHttp = /^https?:\/\//i.test(image);
      const isData = /^data:[a-z]+\/[a-z0-9.+-]+;base64,/i.test(image);
      if (!(isHttp || isData)) {
        functions.logger.warn("wanI2vFast: invalid_image_uri", {imagePrefix: String(image).slice(0, 80)});
        res.status(400).json({error: "bad_request", message: "image must be an http(s) or data URI"});
        return;
      }

      // Replicate requires a URL; if we still have a data URI, rehost it to Storage to get an https URL
      async function rehostDataUriToHttps(dataUri: string): Promise<string> {
        const m = dataUri.match(/^data:([^;]+);base64,(.*)$/i);
        const mime = (m && m[1]) || "image/png";
        const b64 = (m && m[2]) || "";
        const buf = Buffer.from(b64, "base64");
        const bucket = storage.bucket();
        const objectPath = `wan_inputs/${Date.now()}_${Math.random().toString(36).slice(2)}.${mime.includes("jpeg") ? "jpg" : "png"}`;
        const file = bucket.file(objectPath);
        const token = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        await file.save(buf, {contentType: mime, metadata: {metadata: {firebaseStorageDownloadTokens: token}}, resumable: false});
        return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`;
      }

      let imageUrl = image;
      if (isData) {
        try {
          imageUrl = await rehostDataUriToHttps(image);
          functions.logger.info("wanI2vFast: data_uri_rehosted", {prefix: imageUrl.slice(0, 80)});
        } catch (e:any) {
          functions.logger.error("wanI2vFast: data_rehost_failed", e?.message || e);
          res.status(400).json({error: "bad_request", message: "failed to process input image"});
          return;
        }
      }

      // Coerce and bound optional parameters according to provided schema
      function asInt(v: any, d: number): number {
        const n = Number(v);
        return Number.isFinite(n) ? n : d;
      }
      function asNum(v: any, d: number): number {
        const n = Number(v);
        return Number.isFinite(n) ? n : d;
      }
      function asBool(v: any, d: boolean): boolean {
        if (typeof v === "boolean") return v;
        if (typeof v === "string") return v === "true" || v === "1";
        return d;
      }

      const num_frames = Math.max(81, Math.min(121, asInt(body.num_frames, 81)));
      const frames_per_second = Math.max(5, Math.min(30, asInt(body.frames_per_second, 16)));
      const resolution: "480p" | "720p" = (body.resolution === "720p" ? "720p" : "480p");
      const sample_shift = Math.max(1, Math.min(20, asNum(body.sample_shift, 12)));
      const go_fast = asBool(body.go_fast, true);
      const disable_safety_checker = asBool(body.disable_safety_checker, false);

      const seed = body.seed == null || body.seed === "" ? undefined : asInt(body.seed, undefined as any);
      const last_image = body.last_image ? String(body.last_image) : undefined;
      const lora_scale_transformer = body.lora_scale_transformer == null ? 1 : asNum(body.lora_scale_transformer, 1);
      const lora_scale_transformer_2 = body.lora_scale_transformer_2 == null ? 1 : asNum(body.lora_scale_transformer_2, 1);
      const lora_weights_transformer = body.lora_weights_transformer ? String(body.lora_weights_transformer) : undefined;
      const lora_weights_transformer_2 = body.lora_weights_transformer_2 ? String(body.lora_weights_transformer_2) : undefined;

      // Build input payload (omit undefined fields)
      const modelInput: Record<string, any> = {
        image: imageUrl,
        prompt,
        go_fast,
        num_frames,
        resolution,
        sample_shift,
        frames_per_second,
        disable_safety_checker,
      };
      if (seed !== undefined) modelInput.seed = seed;
      if (last_image) modelInput.last_image = last_image;
      if (lora_weights_transformer) modelInput.lora_weights_transformer = lora_weights_transformer;
      if (lora_weights_transformer_2) modelInput.lora_weights_transformer_2 = lora_weights_transformer_2;
      if (lora_scale_transformer !== undefined) modelInput.lora_scale_transformer = lora_scale_transformer;
      if (lora_scale_transformer_2 !== undefined) modelInput.lora_scale_transformer_2 = lora_scale_transformer_2;

      const replicate = new Replicate({auth: token});
      functions.logger.info("wanI2vFast: start", {hasImage: image.startsWith("gs://") || image.startsWith("http"), promptLen: prompt.length, num_frames, frames_per_second, resolution, sample_shift, go_fast});

      // Run synchronously to obtain file output (mp4 URL or blob)
      let output: any;
      try {
        output = await replicate.run("wan-video/wan-2.2-i2v-fast", {input: modelInput});
      } catch (e:any) {
        const msg = String(e?.message || e);
        // Surface clear diagnostics for common errors
        if (msg.includes("402") || /Payment Required/i.test(msg)) {
          functions.logger.error("wanI2vFast: replicate_insufficient_credit", {message: msg});
          res.status(402).json({error: "replicate_insufficient_credit", message: msg});
          return;
        }
        if (/422|validation/i.test(msg)) {
          functions.logger.error("wanI2vFast: replicate_validation_error", {message: msg, imagePrefix: imageUrl.slice(0,80)});
          res.status(422).json({error: "replicate_validation_error", message: msg});
          return;
        }
        throw e;
      }
      functions.logger.info("wanI2vFast: replicate_done", {hasOutput: !!output, type: typeof output});

      // Extract a downloadable URL if present
      let replicateUrl: string | undefined;
      try {
        if (output && typeof output.url === "function") {
          replicateUrl = await output.url();
        } else if (typeof output === "string") {
          replicateUrl = output;
        }
      } catch (_) { /* noop */ }
      functions.logger.info("wanI2vFast: replicate_url", {present: !!replicateUrl, prefix: replicateUrl ? String(replicateUrl).slice(0, 80) : null});

      // Attempt to download and persist in Cloud Storage. If it fails, return replicateUrl.
      let finalUrl = replicateUrl;
      if (replicateUrl) {
        try {
          const r = await axios.get<ArrayBuffer>(replicateUrl, {responseType: "arraybuffer", timeout: 300000});
          const bucket = storage.bucket();
          const objectPath = `wan_videos/${Date.now()}_${Math.random().toString(36).slice(2)}.mp4`;
          const file = bucket.file(objectPath);
          const tokenMeta: string = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
          await file.save(Buffer.from(r.data as any), {
            contentType: "video/mp4",
            metadata: {metadata: {firebaseStorageDownloadTokens: tokenMeta}},
            resumable: false,
          });
          finalUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${tokenMeta}`;
          functions.logger.info("wanI2vFast: storage_saved", {objectPath, urlPrefix: String(finalUrl).slice(0, 80)});
        } catch (e) {
          // best-effort; keep replicateUrl as fallback
          functions.logger.warn("wanI2vFast: copy_to_storage_failed", (e as any)?.message || e);
        }
      }

      functions.logger.info("wanI2vFast: success", {hasVideo: !!finalUrl, hasReplicateUrl: !!replicateUrl});
      res.status(200).json({videoUrl: finalUrl || null, replicateUrl: replicateUrl || null});
    } catch (err) {
      const msg = (err as any)?.message || String(err);
      functions.logger.error("wanI2vFast failed", msg);
      res.status(500).json({error: "internal_error", message: msg});
    }
  });



