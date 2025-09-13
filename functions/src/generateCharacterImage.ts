import * as functions from "firebase-functions";
import axios from "axios";
import { getApps, initializeApp, applicationDefault } from "firebase-admin/app";
import { getStorage } from "firebase-admin/storage";
import Replicate from "replicate";

if (!getApps().length) {
  initializeApp({ credential: applicationDefault() });
}
const storage = getStorage();

const PIXAR_PROMPT = "Create a 3D Pixar-style animated portrait of the person in this photo, with expressive, large, friendly eyes, soft skin shading, cartoony lighting, and slightly exaggerated features typical of Pixar animation — while preserving the exact facial features, expression, hairstyle, skin tone, eye shape, nose shape, and distinguishing marks. Render in high detail, with clean lighting, subtle depth of field, warm color grading. The background should be simple or softly blurred, so the character stands out. Do not alter pose or expression substantially; retain the same camera angle and framing as the original photo.";

export const generateCharacterImage = functions
  .runWith({ timeoutSeconds: 300, secrets: ["REPLICATE_API_TOKEN"] })
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") {
        res.status(405).json({ error: "method_not_allowed" });
        return;
      }
      const requestId = `CHAR_${Date.now()}`;
      const { referenceImageUrls = [], name = "", bio = "" } = (req.body || {}) as any;

      console.log("[CHAR] env", {
        id: requestId,
        project: process.env.GOOGLE_CLOUD_PROJECT,
        service: process.env.K_SERVICE,
        revision: process.env.K_REVISION,
        defaultBucket: storage.bucket().name,
      });

      const candidates: string[] = (referenceImageUrls || []).map(String).filter(Boolean);
      console.log("[CHAR] refs", { id: requestId, count: candidates.length, first: candidates[0]?.slice(0, 96) });
      if (candidates.length === 0) {
        res.status(400).json({ error: "bad_request", message: "referenceImageUrls required" });
        return;
      }

      type AnchorKind = "admin-bytes" | "signed-url" | "https-bytes";
      let anchorKind: AnchorKind | null = null;
      let selectedInput: Buffer | string | null = null;

      function parseGs(gsUrl: string) {
        const without = gsUrl.replace("gs://", "");
        const i = without.indexOf("/");
        return { bucket: without.slice(0, i), object: without.slice(i + 1) };
      }

      for (const u of candidates) {
        try {
          if (u.startsWith("gs://")) {
            const { bucket, object } = parseGs(u);
            console.log("[CHAR] admin_try", { id: requestId, bucket, object });
            const file = storage.bucket(bucket).file(object);
            const [exists] = await file.exists();
            if (!exists) throw new Error("gs_object_not_found");
            const [buf] = await file.download();
            selectedInput = Buffer.from(buf);
            anchorKind = "admin-bytes";
            console.log("[CHAR] admin_ok", { id: requestId, bytes: buf.byteLength });
            break;
          } else {
            const r = await axios.get<ArrayBuffer>(u, { responseType: "arraybuffer", timeout: 20000 });
            const buf = Buffer.from(r.data as any);
            selectedInput = buf;
            anchorKind = "https-bytes";
            console.log("[CHAR] https_ok", { id: requestId, bytes: buf.byteLength });
            break;
          }
        } catch (e) {
          if (u.startsWith("gs://")) {
            try {
              const { bucket, object } = parseGs(u);
              const file = storage.bucket(bucket).file(object);
              const [signed] = await file.getSignedUrl({ version: "v4", action: "read", expires: Date.now() + 15 * 60 * 1000 });
              selectedInput = signed;
              anchorKind = "signed-url";
              console.log("[CHAR] signed_url_ok", { id: requestId, bucket, object });
              break;
            } catch (se: any) {
              console.error("[CHAR] signed_url_failed", { id: requestId, msg: String(se?.message || se) });
              // try next candidate
            }
          } else {
            console.error("[CHAR] anchor_try_failed", { id: requestId, url: u.slice(0, 96), msg: String((e as any)?.message || e) });
          }
        }
      }

      if (!selectedInput) {
        console.error("[CHAR] no_anchor_available", { id: requestId, candidates });
        res.status(422).json({ error: "no_anchor", message: "No reference image could be read (admin, signed URL, or https)." });
        return;
      }
      console.log("[CHAR] flux_input_kind", { id: requestId, kind: anchorKind });

      const token = process.env.REPLICATE_API_TOKEN as string | undefined;
      if (!token) {
        res.status(500).json({ error: "missing_token" });
        return;
      }
      const replicate = new Replicate({ auth: token });
      const input: any = { prompt: PIXAR_PROMPT, input_image: selectedInput, output_format: "png" };
      const output: any = await replicate.run("black-forest-labs/flux-kontext-pro", { input });

      let buf: Buffer | null = null;
      if (output && typeof output.url === "function") {
        const u = output.url();
        const dl = await axios.get<ArrayBuffer>(u, { responseType: "arraybuffer", timeout: 120000 });
        buf = Buffer.from(dl.data as any);
      } else if (output && typeof output.arrayBuffer === "function") {
        const ab = await output.arrayBuffer();
        buf = Buffer.from(ab);
      } else if (typeof output === "string") {
        const dl = await axios.get<ArrayBuffer>(output, { responseType: "arraybuffer", timeout: 120000 });
        buf = Buffer.from(dl.data as any);
      } else if ((output as any) instanceof Uint8Array) {
        buf = Buffer.from(output as any);
      }
      if (!buf) {
        res.status(502).json({ error: "replicate_no_output" });
        return;
      }

      const bucket = storage.bucket();
      const objectPath = `characters/${Date.now()}_${Math.floor(Math.random()*1e6)}.png`;
      const file = bucket.file(objectPath);
      await file.save(buf, {
        contentType: "image/png",
        metadata: { metadata: { name, bio, requestId } },
        resumable: false,
      });
      const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media`;
      console.log("[CHAR] uploaded", { id: requestId, path: objectPath });
      res.status(200).json({ imageUrl: publicUrl, requestId });
    } catch (err) {
      const msg = (err as any)?.message || String(err);
      console.error("[CHAR] failed", msg);
      res.status(500).json({ error: "internal_error", message: msg });
    }
  });
