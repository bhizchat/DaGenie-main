import * as functions from "firebase-functions";
import axios from "axios";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getStorage} from "firebase-admin/storage";
import crypto from "crypto";
import {buildEditPromptFromScript} from "./storyboardPromptBuilder";
import sharp from "sharp";
import Replicate from "replicate";

if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}
const storage = getStorage();

/**
 * Input: { scenes: Array<{ index: number, prompt?: string, action?: string, speechType?: string, speech?: string, animation?: string }>, style?: string }
 * Output: { scenes: Array<{ index: number, imageUrl: string }> }
 */
export const generateStoryboardImages = functions
  .runWith({timeoutSeconds: 300, secrets: ["GEMINI_API_KEY", "REPLICATE_API_TOKEN"]})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") {
        res.status(405).json({error: "method_not_allowed"});
        return;
      }
      const {scenes = [], style = "3D stylized", referenceImageUrls = [], character = "", provider = ""} = (req.body || {}) as any;
      const requestId = `SBIMG_${Date.now()}`;
      console.log("[SBIMG] req", {id: requestId, scenes: Array.isArray(scenes) ? scenes.length : null, refs: Array.isArray(referenceImageUrls) ? referenceImageUrls.length : null, style, character});
      const apiKey = (process.env.GEMINI_API_KEY as string) || (req.get("x-api-key") as string) || "";
      console.log("[SBIMG] key", {present: apiKey.length > 0, tail: apiKey ? apiKey.slice(-4) : null});
      if (!Array.isArray(scenes) || scenes.length === 0) {
        res.status(400).json({error: "bad_request", message: "scenes array required"});
        return;
      }
      if (!apiKey) {
        res.status(500).json({error: "missing_api_key"});
        return;
      }

      const out: Array<{index: number; imageUrl: string}> = [];
      const okMimes = new Set(["image/png", "image/jpeg", "image/webp", "image/heic", "image/heif"]);

      for (const s of scenes) {
        const index = Number(s?.index ?? out.length + 1);
        // Require at least one reference; treat the first as identity/style anchor for the chosen character
        const urls = (referenceImageUrls || []).map((u: any) => String(u)).filter(Boolean).slice(0, 3);
        if (urls.length === 0) {
          res.status(400).json({error: "bad_request", message: "At least one referenceImageUrl (character anchor) is required"});
          return;
        }

        // Build pure edit prompt from script (no dialogue text added onto image)
        const prompt = buildEditPromptFromScript({
          style,
          actionHint: s?.action || undefined,
          animationHint: s?.animation || undefined,
          settingHint: undefined, // keep edits minimal; background stays coherent with original
        });

        // Parts (edit flow): anchor image FIRST → then text (stronger identity anchoring)
        const parts: any[] = [];
        let replicateInputImage: Buffer | string | null = null;
        async function pushRef(u: string) {
          // Support gs:// bucket URIs as well as https URLs
          if (u.startsWith("gs://")) {
            const without = u.replace("gs://", "");
            const firstSlash = without.indexOf("/");
            const bucketName = firstSlash > 0 ? without.slice(0, firstSlash) : without;
            const objectPath = firstSlash > 0 ? without.slice(firstSlash + 1) : "";
            const file = getStorage().bucket(bucketName).file(objectPath);
            const [exists] = await file.exists();
            if (!exists) { throw new Error(`gs_object_not_found ${bucketName}/${objectPath}`); }
            const [meta] = await file.getMetadata();
            let ct = String(meta.contentType || "image/png").toLowerCase();
            if (!okMimes.has(ct)) ct = "image/png";
            const [buf] = await file.download();
            const bytes = buf.byteLength;
            console.log("[SBIMG] ref_info", {id: requestId, url: u.slice(0, 96), status: 200, ct, bytes});
            if (bytes < 1024) { throw new Error(`invalid_reference_response ct=${ct} bytes=${bytes}`); }
            parts.push({inline_data: {mime_type: ct, data: Buffer.from(buf).toString("base64")}});
            replicateInputImage = Buffer.from(buf);
            return;
          }
          const r = await axios.get<ArrayBuffer>(u, {responseType: "arraybuffer", timeout: 20000, validateStatus: () => true});
          const status = r && (r as any).status;
          let ct = String(r.headers["content-type"] || "").toLowerCase().split(";")[0];
          const isImage = okMimes.has(ct);
          const bytes = (r?.data as any) ? Buffer.byteLength(Buffer.from(r.data as any)) : 0;
          console.log("[SBIMG] ref_info", {id: requestId, url: u.slice(0, 96), status, ct, bytes});
          if (!isImage || bytes < 1024) { throw new Error(`invalid_reference_response ct=${ct} bytes=${bytes}`); }
          const b64 = Buffer.from(r.data as any).toString("base64");
          parts.push({inline_data: {mime_type: ct, data: b64}});
          replicateInputImage = Buffer.from(r.data as any);
        }
        try {
          await pushRef(urls[0]);
          console.log("[SBIMG] anchor_added", {id: requestId, idx: index, url: urls[0]?.slice(0, 96)});
        } catch (fe: any) {
          console.error("[SBIMG] ref_fetch_failed_primary", {id: requestId, idx: index, url: urls[0]?.slice(0, 64), msg: String(fe?.message || fe)});
          res.status(400).json({error: "anchor_unavailable", message: String(fe?.message || fe), url: String(urls[0] || "")});
          return;
        }
        // Text instruction after the image per editing guidance
        parts.push({text: prompt});
        console.log("[SBIMG] prompt_added", {id: requestId, idx: index, promptHead: prompt.slice(0, 160), promptLen: prompt.length});
        // Log full prompt for debugging/traceability
        console.log("[SBIMG] prompt_full", {id: requestId, idx: index, prompt});

        console.log("[SBIMG] compose", {id: requestId, idx: index, partsCount: parts.length, promptLen: prompt.length, promptHead: prompt.slice(0, 180)});

        // If caller explicitly requests Flux context, bypass Gemini and go straight to Replicate Flux Kontext Pro
        const forceFlux = String(provider || "").toLowerCase() === "flux";
        if (forceFlux) {
          try {
            const token = process.env.REPLICATE_API_TOKEN as string | undefined;
            if (!token) throw new Error("replicate_token_missing");
            const replicate = new Replicate({auth: token});
            const input: any = {
              prompt,
              input_image: replicateInputImage || urls[0],
              output_format: "png",
            };
            const output: any = await replicate.run("black-forest-labs/flux-kontext-pro", { input });
            let buf: Buffer | null = null;
            if (output && typeof output.url === "function") {
              const u = output.url();
              const dl = await axios.get<ArrayBuffer>(u, {responseType: "arraybuffer", timeout: 120000});
              buf = Buffer.from(dl.data as any);
            } else if (output && typeof output.arrayBuffer === "function") {
              const ab = await output.arrayBuffer();
              buf = Buffer.from(ab);
            } else if (typeof output === "string") {
              const dl = await axios.get<ArrayBuffer>(output, {responseType: "arraybuffer", timeout: 120000});
              buf = Buffer.from(dl.data as any);
            } else if ((output as any) instanceof Uint8Array) {
              buf = Buffer.from(output as any);
            }
            if (!buf) throw new Error("replicate_no_output");
            const bucket = storage.bucket();
            const objectPath = `storyboards/${Date.now()}_${index}.png`;
            const file = bucket.file(objectPath);
            const tokenUp: string = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
            await file.save(buf, {contentType: "image/png", metadata: {metadata: {firebaseStorageDownloadTokens: tokenUp, prompt: prompt.slice(0, 2000)}}, resumable: false});
            const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${tokenUp}`;
            console.log("[SBIMG] replicate_uploaded", {id: requestId, idx: index, path: objectPath});
            out.push({index, imageUrl: publicUrl});
            continue; // next scene
          } catch (rf: any) {
            console.error("[SBIMG] replicate_force_failed", {id: requestId, idx: index, msg: String(rf?.message || rf)});
            res.status(502).json({error: "replicate_failed", message: String(rf?.message || rf)});
            return;
          }
        }

        const apiBase = "https://generativelanguage.googleapis.com/v1beta";
        const model = "gemini-2.5-flash-image-preview";
        const url = `${apiBase}/models/${model}:generateContent`;
        const body = {contents: [{role: "user", parts}]};

        function extractGeminiError(e: any) {
          const top = e?.response?.data?.error || {};
          const details = Array.isArray(top?.details) ? top.details : [];
          const fieldViolations = details
            .flatMap((d: any) => (d?.fieldViolations || d?.violations || []))
            .map((v: any) => v?.description || v?.message)
            .filter(Boolean)
            .slice(0, 5);
          return {
            httpStatus: e?.response?.status,
            code: top?.code,
            status: top?.status,
            message: top?.message || String(e?.message || "request_failed"),
            fieldViolations,
          };
        }

        let resp;
        try {
          resp = await axios.post(url, body, {
            timeout: 180000,
            headers: {"Content-Type": "application/json", "x-goog-api-key": apiKey},
          });
        } catch (e: any) {
          const info = extractGeminiError(e);
          console.error("[SBIMG] gemini_request_failed", {id: requestId, idx: index, ...info, promptHead: prompt.slice(0, 220)});
          // Fallback to Replicate Flux Kontext
          try {
            const token = process.env.REPLICATE_API_TOKEN as string | undefined;
            if (!token) throw new Error("replicate_token_missing");
            const replicate = new Replicate({auth: token});
            const input: any = {
              prompt,
              input_image: replicateInputImage || urls[0],
              output_format: "png",
            };
            const output: any = await replicate.run("black-forest-labs/flux-kontext-pro", { input });
            let buf: Buffer | null = null;
            if (output && typeof output.url === "function") {
              const u = output.url();
              const dl = await axios.get<ArrayBuffer>(u, {responseType: "arraybuffer", timeout: 120000});
              buf = Buffer.from(dl.data as any);
            } else if (output && typeof output.arrayBuffer === "function") {
              const ab = await output.arrayBuffer();
              buf = Buffer.from(ab);
            } else if (typeof output === "string") {
              const dl = await axios.get<ArrayBuffer>(output, {responseType: "arraybuffer", timeout: 120000});
              buf = Buffer.from(dl.data as any);
            } else if ((output as any) instanceof Uint8Array) {
              buf = Buffer.from(output as any);
            }
            if (!buf) throw new Error("replicate_no_output");
            const bucket = storage.bucket();
            const objectPath = `storyboards/${Date.now()}_${index}.png`;
            const file = bucket.file(objectPath);
            const tokenUp: string = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
            await file.save(buf, {contentType: "image/png", metadata: {metadata: {firebaseStorageDownloadTokens: tokenUp, prompt: prompt.slice(0, 2000)}}, resumable: false});
            const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${tokenUp}`;
            console.log("[SBIMG] replicate_uploaded", {id: requestId, idx: index, path: objectPath});
            out.push({index, imageUrl: publicUrl});
            continue; // move to next scene
          } catch (rf: any) {
            console.error("[SBIMG] replicate_fallback_failed", {id: requestId, idx: index, msg: String(rf?.message || rf)});
            res.status(info.httpStatus || 502).json({error: "gemini_request_failed", ...info});
            return;
          }
        }

        const partsAny = resp?.data?.candidates?.[0]?.content?.parts || [];
        let dataField: string | undefined;
        let mimeType: string | undefined;
        for (const p of partsAny) {
          const d = p?.inline_data?.data ?? p?.inlineData?.data;
          const mt = p?.inline_data?.mime_type ?? p?.inlineData?.mimeType ?? "image/png";
          if (typeof d === "string" && d.length > 0) { dataField = d; mimeType = mt; break; }
        }
        if (!dataField) {
          console.error("[SBIMG] gemini_no_image", {id: requestId, idx: index, head: JSON.stringify(resp?.data || {}).slice(0, 400)});
          res.status(502).json({error: "gemini_no_image"});
          return;
        }

        const bucket = storage.bucket();
        const ext = (mimeType && String(mimeType).includes("jpeg")) ? "jpg" : "png";
        const objectPath = `storyboards/${Date.now()}_${index}.${ext}`;
        const file = bucket.file(objectPath);
        const original = Buffer.from(String(dataField), "base64");

        // Enforce 16:9 output at 1920x1080 via center-crop then resize with cover fit
        // 1) If source isn't 16:9, use cover fit to fill 1920x1080, cropping as needed
        // 2) Always output in same mime where practical (jpeg preferred)
        const width = 1920;
        const height = 1080;
        const outFormat = (ext === "jpg") ? "jpeg" : "png";
        let processed: Buffer;
        try {
          const pipeline = sharp(original)
            .resize({width, height, fit: "cover", position: "centre"});
          processed = outFormat === "jpeg" ? await pipeline.jpeg({quality: 92}).toBuffer() : await pipeline.png({compressionLevel: 9}).toBuffer();
        } catch (e) {
          console.warn("[SBIMG] sharp_failed_falling_back", {id: requestId, idx: index, msg: String((e as any)?.message || e)});
          processed = original; // fallback without enforcement
        }
        const token: string = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        await file.save(processed, {contentType: outFormat === "jpeg" ? "image/jpeg" : "image/png", metadata: {metadata: {firebaseStorageDownloadTokens: token, prompt: prompt.slice(0, 2000)}}, resumable: false});
        const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`;
        console.log("[SBIMG] uploaded", {id: requestId, idx: index, path: objectPath});
        out.push({index, imageUrl: publicUrl});
      }

      console.log("[SBIMG] ok", {id: requestId, count: out.length});
      res.status(200).json({scenes: out});
    } catch (err) {
      const msg = (err as any)?.message || String(err);
      console.error("[SBIMG] failed", msg, {stack: (err as any)?.stack});
      res.status(500).json({error: "internal_error", message: msg, hint: "Check Cloud Functions logs for [SBIMG] failed"});
    }
  });


