/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getStorage} from "firebase-admin/storage";
import axios from "axios";
import crypto from "crypto";
import Replicate from "replicate";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const storage = getStorage();

export const createOriginalCharacter = functions
  .runWith({timeoutSeconds: 300, memory: "1GB", secrets: ["REPLICATE_API_TOKEN", "OPENAI_KEY"]})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      const body: any = req.body || {};
      const referenceImageUrls: string[] = Array.isArray(body.referenceImageUrls) ? body.referenceImageUrls.filter(Boolean) : [];
      const description: string = String(body.description || body.bio || "").trim();
      const uid: string | undefined = String(body.uid || "").trim() || undefined;

      const replicateToken = process.env.REPLICATE_API_TOKEN as string | undefined;
      if (!replicateToken) { res.status(500).json({error: "missing_replicate_token"}); return; }
      const replicate = new Replicate({auth: replicateToken});

      // Lookism prompts
      const lookismImageToImage = `Lookism webtoon style portrait. Clean lineart, sharp ink contour, subtle halftone, smooth cel-shading with 2–3 tone shadows, soft gradient highlights, glossy eyes, small defined nose bridge, tidy lips, slightly elongated face proportions (webtoon ideal). Keep the subject’s identity, pose, hair length/part, and outfit, but stylize them to Korean webtoon aesthetics. Neutral studio background with soft vignette; no props, no text.\n\nFace: even skin, luminous but not plastic; crisp eyelashes; catchlights in both eyes. Hair: simplified clumps with clear strand groups and edge highlights. Clothing: simplified folds and neat seams, webtoon rendering.\n\nMake it look like Lookism / Korean webtoon (NOT anime, NOT realistic).\n9:16 vertical, portrait framing, head-and-shoulders, centered composition. High resolution, print-clean.`;
      const lookismTextOnly = (desc: string) => `Lookism webtoon style character portrait of ${desc}. Clean lineart, crisp ink contour, 2–3 tone cel-shading, luminous skin, glossy eyes with sharp catchlights, simplified clothing folds. Neutral studio background, soft vignette, no props, no text. 9:16 vertical, head-and-shoulders, centered. High resolution, print-ready.`;

      // Run Flux Kontext
      let imgBuf: Buffer | null = null;
      try {
        if (referenceImageUrls.length > 0) {
          const input: any = { prompt: lookismImageToImage, input_image: referenceImageUrls[0], output_format: "png" };
          const output: any = await replicate.run("black-forest-labs/flux-kontext-pro", { input });
          if (typeof output === "string") {
            const dl = await axios.get<ArrayBuffer>(output, {responseType: "arraybuffer", timeout: 180000});
            imgBuf = Buffer.from(dl.data as any);
          } else if (output && typeof output.arrayBuffer === "function") {
            const ab = await output.arrayBuffer(); imgBuf = Buffer.from(ab);
          } else if (output && typeof output.url === "function") {
            const u = output.url(); const dl = await axios.get<ArrayBuffer>(u, {responseType: "arraybuffer", timeout: 180000}); imgBuf = Buffer.from(dl.data as any);
          }
        } else {
          const input: any = { prompt: lookismTextOnly(description), output_format: "png" };
          const output: any = await replicate.run("black-forest-labs/flux-kontext-pro", { input });
          if (typeof output === "string") {
            const dl = await axios.get<ArrayBuffer>(output, {responseType: "arraybuffer", timeout: 180000});
            imgBuf = Buffer.from(dl.data as any);
          } else if (output && typeof output.arrayBuffer === "function") {
            const ab = await output.arrayBuffer(); imgBuf = Buffer.from(ab);
          } else if (output && typeof output.url === "function") {
            const u = output.url(); const dl = await axios.get<ArrayBuffer>(u, {responseType: "arraybuffer", timeout: 180000}); imgBuf = Buffer.from(dl.data as any);
          }
        }
      } catch (e: any) {
        res.status(502).json({error: "flux_kontext_failed", message: String(e?.message || e)}); return;
      }
      if (!imgBuf) { res.status(502).json({error: "no_image_output"}); return; }

      // Save to storage
      const bucket = storage.bucket();
      const charId = `user_${(crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`}`;
      const objectPath = `characters/${uid || "anon"}/${charId}/portrait.png`;
      const file = bucket.file(objectPath);
      const token = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      await file.save(imgBuf, {contentType: "image/png", metadata: {metadata: {firebaseStorageDownloadTokens: token}}, resumable: false});
      const imageUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`;

      // Name & bio via OpenAI (GPT-4o-mini)
      let nameOut = String(body.name || "").trim();
      let bioOut = String(body.bio || "").trim();
      try {
        if (!process.env.OPENAI_KEY) throw new Error("missing_openai_key");
        if (!nameOut || !bioOut) {
          const prompt = `You are writing a short profile for a Korean webtoon character (Lookism vibe).\nUser text: ${description || "(image only)"}.\nReturn JSON {"name": "<2-3 word name>", "bio": "<2-3 sentence bio>"}.`;
          const r = await axios.post("https://api.openai.com/v1/chat/completions", {
            model: "gpt-4o-mini",
            messages: [{role: "system", content: "Return strict JSON only."}, {role: "user", content: prompt}],
            temperature: 0.6,
            response_format: {type: "json_object"}
          }, {headers: {Authorization: `Bearer ${process.env.OPENAI_KEY}`}});
          const content = r.data?.choices?.[0]?.message?.content || "{}";
          const parsed = JSON.parse(content);
          nameOut = nameOut || String(parsed.name || "").trim() || "Unnamed";
          bioOut = bioOut || String(parsed.bio || "").trim() || "";
        }
      } catch (e) { /* fall back to provided fields */ }

      res.status(200).json({characterId: charId, imageUrl, name: nameOut, bio: bioOut});
    } catch (e: any) {
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  });
