/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import axios from "axios";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const db = getFirestore();

type Shot = {
  index: number;
  action: string;
  animation?: string;
  speech?: string;
  imageUrl: string; // avatar image used as i2v anchor
};

/**
 * Cloned storyboard generator specifically for the music-video flow.
 * For now, this scaffolds an 8-shot plan and enqueues WAN generation for each shot.
 * Later, replace the shot planning with Nano Banana + beats-aware logic.
 */
export const generateMusicStoryboard = functions
  .runWith({timeoutSeconds: 300, memory: "512MB"})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      const {uid, projectId, settingId, referenceImageUrl, audioGsPath, promptKit, ideaText} = (req.body || {}) as any;
      if (!uid || !projectId || !referenceImageUrl) { res.status(400).json({error: "bad_request"}); return; }

      // Create storyboard doc
      const sbRef = db.collection("users").doc(uid).collection("musicVideos").doc(projectId).collection("storyboards").doc();
      const now = Timestamp.now();
      const idea = String(ideaText || "").toLowerCase();
      await sbRef.set({
        uid,
        projectId,
        status: "created",
        createdAt: now,
        updatedAt: now,
        isLatest: true,
        mode: "music-video",
        settingId: settingId || null,
        ideaText: idea || null,
      }, {merge: true});
      functions.logger.info("generateMusicStoryboard.storyboard_created", {uid, projectId, storyboardId: sbRef.id, path: sbRef.path});

      // Use promptKit cues to name actions and animations (fallback to generic)
      const beats: string[] = Array.isArray(promptKit?.formatBeats) && promptKit.formatBeats.length > 0 ? promptKit.formatBeats : [
        "Arrival orbit",
        "Verse micro-loops",
        "Hook procession",
        "Carousel mini-sets",
        "River ride",
        "Macro inserts",
        "Finale spiral"
      ];
      const camera: string[] = Array.isArray(promptKit?.cameraGrammar) && promptKit.cameraGrammar.length > 0 ? promptKit.cameraGrammar : [
        "orbit 12°", "micro dolly-in", "parallax pass", "crane-up reveal"
      ];
      const environment: string = String(promptKit?.environment || "");
      const fpsHint: string = String(promptKit?.fpsHint || "");
      const bio: string = String(promptKit?.bio || "");
      // Use a human‑readable style string instead of settingId
      const styleDesc: string = ["3D stylized", bio].filter(Boolean).join(" — ");

      // Rap performance grammar (no explicit club/street/crowd/stage archetypes)
      const performanceBeats: string[] = [
        "mic-to-mouth close-up, confident delivery",
        "walk-and-rap tracking angle",
        "lens lean-in with direct eye contact",
        "low-angle power pose, shoulders squared",
        "side-profile bars, head-nod cadence",
        "hand emphasis on rhyme hits",
        "hood-of-car verse silhouette",
        "turn-and-deliver three-quarter pose",
        "chain flash on the downbeat",
        "neon sign backlight silhouette",
        "stairs landing power look",
        "handheld selfie bar (arm’s length)"
      ];
      const micProps: string[] = ["handheld microphone (wireless)", "handheld microphone (wired)", "no mic (pose)"];
      const lighting: string[] = ["neon rim + soft key", "tungsten practicals + colored fill", "hard key with haze volumetrics"];

      // Lightweight idea blending: prioritize keywords to bias beat/prop selection
      const kw = new Set(idea.split(/[^a-z0-9]+/).filter(Boolean));
      function bias<T>(arr: T[], predicate: (t: T) => boolean, boost = 2): T[] {
        // duplicate matching items to increase selection probability
        const out: T[] = [];
        for (const a of arr) { out.push(a); if (predicate(a)) { for (let i = 0; i < boost; i++) out.push(a); } }
        return out.length ? out : arr;
      }
      const perfBiased = bias(performanceBeats, (p) => {
        if (kw.has("mic") || kw.has("microphone")) return /mic/i.test(p);
        if (kw.has("chain") || kw.has("bling")) return /chain/i.test(p);
        if (kw.has("walk") || kw.has("track")) return /walk/i.test(p);
        return false;
      });
      const propBiased = bias(micProps, (p) => kw.has("mic") || kw.has("microphone"));
      const camBiased = bias(camera, (c) => kw.has("orbit") ? /orbit/i.test(String(c)) : kw.has("dolly") ? /dolly/i.test(String(c)) : false);
      const lightBiased = bias(lighting, (l) => kw.has("neon") ? /neon/i.test(String(l)) : kw.has("tungsten") ? /tungsten/i.test(String(l)) : false);
      const total = 12; // fixed 12 shots ≈ 60s at ~5s each
      const shots: Shot[] = Array.from({length: total}).map((_, i) => {
        const beat = beats[i % beats.length];
        const cam = camBiased[i % camBiased.length];
        const perf = perfBiased[i % perfBiased.length];
        const prop = propBiased[i % propBiased.length];
        const light = lightBiased[i % lightBiased.length];
        const micro = Array.isArray(promptKit?.setPacks) && promptKit.setPacks.length > 0 ? promptKit.setPacks[i % promptKit.setPacks.length] : (Array.isArray(promptKit?.worldPillars) && promptKit.worldPillars.length > 0 ? promptKit.worldPillars[i % promptKit.worldPillars.length] : "signature backdrop");
        const animBits = [
          `camera ${cam}`,
          `motion aligned to bpm`,
          environment ? `environment ${environment}` : "",
          `lighting ${light}`,
          fpsHint ? `fps ${fpsHint}` : ""
        ].filter(Boolean).join("; ");
        return {
          index: i + 1,
          action: `${beat} at ${micro} — ${perf} (${prop})`,
          animation: animBits,
          imageUrl: String(referenceImageUrl),
        } as Shot;
      });

      const batch = db.batch();
      functions.logger.info("generateMusicStoryboard.plan", {
        uid,
        projectId,
        settingId,
        ideaHead: (idea || "").slice(0, 120),
        beatsCount: beats.length,
        shotsPlanned: shots.length,
      });
      for (const s of shots) {
        const id4 = String(s.index).padStart(4, "0");
        const sceneRef = sbRef.collection("scenes").doc(id4);
        batch.set(sceneRef, {
          index: s.index,
          action: s.action,
          animation: s.animation || null,
          imageUrl: s.imageUrl,
          script: s.action,
          durationSec: 5.0,
          video: {status: "idle"},
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      functions.logger.info("generateMusicStoryboard.scenes_batch_prepared", {storyboardId: sbRef.id, count: shots.length, first: shots[0]?.action});
      await batch.commit();
      functions.logger.info("generateMusicStoryboard.scenes_written", {storyboardId: sbRef.id, written: shots.length, path: `${sbRef.path}/scenes`});

      // Generate storyboard images using the avatar as the i2i anchor
      try {
        const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || (process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)).projectId : "");
        const base = `https://us-central1-${project}.cloudfunctions.net`;
        const imgUrl = `${base}/generateStoryboardImages`;
        const payload = {
          scenes: shots.map((s) => ({index: s.index, action: s.action, animation: s.animation})),
          style: styleDesc,
          referenceImageUrls: [referenceImageUrl],
          provider: "nano", // nano-banana with Flux fallback already supported in function
          ideaText: idea,
          environment,
        } as any;
        functions.logger.info("generateMusicStoryboard.images_request", {storyboardId: sbRef.id, scenes: shots.length, provider: "nano", style: styleDesc, env: environment});
        const resp = await axios.post(imgUrl, payload, {timeout: 300000});
        functions.logger.info("generateMusicStoryboard.images_requested", {project, storyboardId: sbRef.id, scenes: shots.length});
        const images = Array.isArray(resp.data?.scenes) ? resp.data.scenes as Array<{index: number; imageUrl: string}> : [];
        const upd = db.batch();
        for (const sc of images) {
          const id4 = String(sc.index).padStart(4, "0");
          const sceneRef = sbRef.collection("scenes").doc(id4);
          upd.set(sceneRef, { imageUrl: sc.imageUrl, updatedAt: FieldValue.serverTimestamp() }, {merge: true});
        }
        await upd.commit();
        functions.logger.info("generateMusicStoryboard.images_written", {storyboardId: sbRef.id, written: images.length});
      } catch (e: any) {
        functions.logger.warn("generateMusicStoryboard.images_failed", {message: String(e?.message || e)});
      }

      functions.logger.info("generateMusicStoryboard.ok", {uid, projectId, storyboardId: sbRef.id, shots: shots.length, audio: !!audioGsPath});
      res.status(200).json({ok: true, storyboardId: sbRef.id, shots: shots.length});
    } catch (e: any) {
      functions.logger.error("generateMusicStoryboard.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  });


