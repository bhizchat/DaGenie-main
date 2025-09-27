/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getStorage} from "firebase-admin/storage";
import {gsToFetchableUrl} from "../utils/storageHelpers.js";
import Replicate from "replicate";
import axios from "axios";
import crypto from "crypto";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const storage = getStorage();
function defaultBucketName(): string {
  const cfg = process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)) : undefined as any;
  const fromCfg: string | undefined = cfg?.storageBucket;
  const fromProj: string | undefined = (process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT) ? `${process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT}.appspot.com` : undefined;
  const fromEnv: string | undefined = process.env.FIREBASE_STORAGE_BUCKET as string | undefined;
  return String(fromEnv || fromCfg || fromProj || "").trim();
}

/**
 * Generate an avatar from a reference image using a Flux Kontext model via Replicate.
 * Expects env REPLICATE_API_TOKEN. Model slug can be passed as `modelSlug` or via REPLICATE_FLUX_MODEL.
 * Input JSON: { referenceImage: string (gs://|https|data:), prompt?: string, style?: string, modelSlug?: string }
 * Output: { avatarUrl: string, replicateUrl?: string }
 */
export const generateFluxAvatar = functions
  .runWith({timeoutSeconds: 540, memory: "1GB", secrets: ["REPLICATE_API_TOKEN"]})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      const token = (process.env.REPLICATE_API_TOKEN as string) || "";
      if (!token) { res.status(500).json({error: "replicate_token_missing"}); return; }

      const body: any = req.body || {};
      let referenceImage: string = String(body.referenceImage || body.referenceImageUrl || "");
      const prompt: string = String(body.prompt || "make this a highly stylized 3D render, cartoonish character portrait, exaggerated features, adaptive color palette that reflects the subject's vibe, smooth CGI animation look");
      const modelSlug: string = String(body.modelSlug || process.env.REPLICATE_FLUX_MODEL || "black-forest-labs/flux-kontext-pro");
      if (!referenceImage) { res.status(400).json({error: "bad_request", message: "referenceImage is required"}); return; }

      if (referenceImage.startsWith("gs://")) {
        referenceImage = await gsToFetchableUrl(referenceImage, (m, x) => functions.logger.info(m, x));
      }

      // If still a data URI, rehost to HTTPS
      async function rehostDataUriToHttps(dataUri: string): Promise<string> {
        const m = dataUri.match(/^data:([^;]+);base64,(.*)$/i);
        const mime = (m && m[1]) || "image/png";
        const b64 = (m && m[2]) || "";
        const buf = Buffer.from(b64, "base64");
        const bucket = storage.bucket(defaultBucketName());
        const objectPath = `flux_inputs/${Date.now()}_${Math.random().toString(36).slice(2)}.${mime.includes("jpeg") ? "jpg" : "png"}`;
        const file = bucket.file(objectPath);
        const tokenMeta: string = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        await file.save(buf, {contentType: mime, metadata: {metadata: {firebaseStorageDownloadTokens: tokenMeta}}, resumable: false});
        return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${tokenMeta}`;
      }
      if (/^data:/i.test(referenceImage)) referenceImage = await rehostDataUriToHttps(referenceImage);

      const replicate = new Replicate({auth: token});
      functions.logger.info("generateFluxAvatar.start", {hasRef: /^https?:/i.test(referenceImage)});

      // Minimal, model-agnostic input. You may adjust keys once exact model schema is known.
      // Flux Kontext expects `input_image`; keep `image` alias in case of future schema changes
      const input: Record<string, any> = {
        prompt,
        input_image: referenceImage,
        output_format: "png",
      };

      let output: any;
      try {
        // Replicate type expects a template-literal slug; cast to any to allow env-provided values
        output = await replicate.run(modelSlug as any, {input});
      } catch (e:any) {
        functions.logger.error("generateFluxAvatar.replicate_error", {message: String(e?.message || e)});
        res.status(500).json({error: "replicate_error", message: String(e?.message || e)});
        return;
      }

      // Extract URL
      let replicateUrl: string | undefined;
      try {
        if (output && typeof output.url === "function") replicateUrl = await output.url();
        else if (typeof output === "string") replicateUrl = output;
        else if (Array.isArray(output) && typeof output[0] === "string") replicateUrl = output[0];
      } catch {}

      if (!replicateUrl) { res.status(502).json({error: "no_output"}); return; }

      // Download to Storage
      const r = await axios.get<ArrayBuffer>(replicateUrl, {responseType: "arraybuffer", timeout: 300000});
      const bucket = storage.bucket(defaultBucketName());
      const objectPath = `flux_avatars/${Date.now()}_${Math.random().toString(36).slice(2)}.png`;
      const file = bucket.file(objectPath);
      const tokenMeta: string = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      await file.save(Buffer.from(r.data as any), {contentType: "image/png", metadata: {metadata: {firebaseStorageDownloadTokens: tokenMeta}}, resumable: false});
      const avatarUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${tokenMeta}`;

      res.status(200).json({avatarUrl, replicateUrl});
    } catch (e:any) {
      functions.logger.error("generateFluxAvatar.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  });


