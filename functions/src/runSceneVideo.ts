/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import axios from "axios";
import Replicate from "replicate";
// axios not needed in scaffold; keep imports minimal

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const db = getFirestore();

function verifyOidcFromTasks(req: functions.https.Request): void {
  // Optional: If OIDC configured on Cloud Tasks, you can verify audience/issuer.
  // For now, we leave a placeholder; production can add @google-cloud/iam or jwks verification.
  // If your deployment mandates, implement verification here and throw on mismatch.
  return; // no-op
}

export const runSceneVideo = functions
  .runWith({timeoutSeconds: 540, memory: "1GB", secrets: ["REPLICATE_API_TOKEN"]})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      verifyOidcFromTasks(req);
      const {uid, projectId, storyboardId, sceneId, provider, requestId, idempotencyKey} = (req.body || {}) as any;
      if (!uid || !projectId || !storyboardId || !sceneId) { res.status(400).json({error: "bad_request"}); return; }

      const sbRef = db.collection("users").doc(uid).collection("projects").doc(projectId).collection("storyboards").doc(storyboardId);
      // Normalize scene id to 4-digit left-padded string (accepts 1/"1"/"0001")
      const rawId = String(sceneId);
      const parsed = Number(rawId);
      const id4 = Number.isFinite(parsed) ? String(parsed).padStart(4, "0") : rawId.padStart(4, "0");
      const sceneRef = sbRef.collection("scenes").doc(id4);
      functions.logger.info("run_scene_video.start", {requestId, uid, projectId, storyboardId, sceneId: id4, provider: provider || null, docPath: sceneRef.path});
      const snap = await sceneRef.get();
      if (!snap.exists) { res.status(404).json({error: "scene_not_found"}); return; }
      const data = snap.data() || {} as any;

      // Idempotency: if already done, short-circuit
      if (data?.video?.status === "done") {
        res.status(200).json({ok: true, noop: true});
        return;
      }

      // Idempotent claim: if already processing/done for veo, no-op
      let duplicate = false;
      await db.runTransaction(async (tx) => {
        const snap2 = await tx.get(sceneRef);
        const d2 = snap2.data() || {} as any;
        const v2 = (d2.video || {}) as any;
        const status = String(v2.status || "").toLowerCase();
        const prov = String(v2.provider || provider || "").toLowerCase();
        if (["running", "processing", "queued", "done"].includes(status) && (prov === "veo")) {
          duplicate = true;
          return;
        }
        const base: any = { status: "running", provider: provider || null };
        if (idempotencyKey) base.lock = { ...(v2.lock || {}), idempotencyKey };
        tx.set(sceneRef, { video: base, videoStatus: "running", updatedAt: FieldValue.serverTimestamp() }, {merge: true});
      });
      if (duplicate) { res.status(200).json({ok: true, deduped: true}); return; }

      // Build a provider-agnostic input from the scene fields
      // Build provider-agnostic input (placeholder for future integration)

      let outputUrl: string | null = null;
      let providerJobId: string | null = null;

      // Provider dispatch (default VEO-3 via Replicate)
      const normalizedProvider = (provider || data?.video?.provider || "veo").toString().toLowerCase();
      // Emergency guard: disable Veo runs entirely (return 200 to avoid Cloud Tasks retries)
      if (normalizedProvider === "veo" || normalizedProvider.includes("veo")) {
        await sceneRef.set({
          video: { ...(data.video || {}), status: "error", provider: provider || null, lastError: "veo_storyboards_disabled" },
          videoStatus: "error",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        res.status(200).json({ok: true, blocked: true, reason: "veo_storyboards_disabled"});
        return;
      }
      if (normalizedProvider === "veo") {
        // Build a minimal prompt from available scene fields
        const action = (data?.action || "").toString().trim();
        const anim = (data?.animation || "").toString().trim();
        const speech = (data?.speech || "").toString().trim();
        const script = (data?.script || "").toString().trim();
        const prompt = script || [action, anim, speech].filter(Boolean).join(". ");
        const image = (data?.imageUrl || "").toString();

        if (!image || !prompt) {
          functions.logger.error("run_scene_video.bad_input", {hasImage: !!image, hasPrompt: !!prompt});
          await sceneRef.set({ video: { ...(data.video || {}), status: "failed", lastError: "bad_scene_data" }, videoStatus: "failed", updatedAt: FieldValue.serverTimestamp() }, {merge: true});
          res.status(200).json({ok: false, reason: "bad_scene_data"});
          return;
        }

        try {
          const replicate = new Replicate();
          const input: any = { image, prompt };
          const output: any = await replicate.run("google/veo-3-fast", { input });
          if (output && typeof output.url === "function") {
            outputUrl = output.url();
          } else if (typeof output === "string") {
            outputUrl = output;
          } else if (output && typeof output.arrayBuffer === "function") {
            // Not uploading binary here; rely on replicate delivery URL only
            // If arrayBuffer returned, we can't derive a public URL directly
            outputUrl = null;
          }
          providerJobId = `veo_${Date.now()}`;
          functions.logger.info("run_scene_video.provider_veo_ok", {hasOutput: !!outputUrl});
        } catch (err: any) {
          const msg = String(err?.response?.data?.error || err?.message || err);
          functions.logger.error("run_scene_video.provider_veo_failed", {message: msg});
          await sceneRef.set({ video: { ...(data.video || {}), status: "failed", lastError: msg }, videoStatus: "failed", updatedAt: FieldValue.serverTimestamp() }, {merge: true});
          res.status(200).json({ok: false, reason: "provider_failed"});
          return;
        }
      } else if (normalizedProvider === "wan") {
        const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || (process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)).projectId : "dategenie-dev");
        const wanUrl = process.env.WAN_I2V_URL || `https://us-central1-${project}.cloudfunctions.net/wanI2vFast`;

        // Build a minimal prompt from available scene fields
        const action = (data?.action || "").toString().trim();
        const anim = (data?.animation || "").toString().trim();
        const speech = (data?.speech || "").toString().trim();
        const script = (data?.script || "").toString().trim();
        const prompt = script || [action, anim, speech].filter(Boolean).join(". ");
        const image = (data?.imageUrl || "").toString();

        if (!image || !prompt) {
          functions.logger.error("run_scene_video.bad_input", {hasImage: !!image, hasPrompt: !!prompt});
          res.status(400).json({error: "bad_scene_data"});
          return;
        }

        try {
          const resp = await axios.post(wanUrl, {
            image,
            prompt,
            num_frames: 81,
            frames_per_second: 16,
            resolution: "480p",
            go_fast: true,
          }, {timeout: 540_000});
          providerJobId = `wan_${Date.now()}`;
          outputUrl = (resp.data && (resp.data.videoUrl as string)) || null;
          functions.logger.info("run_scene_video.provider_wan_ok", {wanUrl, hasOutput: !!outputUrl});
        } catch (err: any) {
          const msg = String(err?.response?.data?.error || err?.message || err);
          functions.logger.error("run_scene_video.provider_wan_failed", {message: msg});
          throw err;
        }
      }

      // Treat missing video URL as failure, not done
      if (!outputUrl) {
        await sceneRef.set({
          video: { ...(data.video || {}), status: "failed", provider: provider || null, lastError: `${normalizedProvider}_no_output` },
          videoStatus: "failed",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        functions.logger.error("run_scene_video.no_output_url", {docPath: sceneRef.path, provider: normalizedProvider});
        res.status(200).json({ok: false, reason: `${normalizedProvider}_no_output`});
        return;
      }

      await sceneRef.update({
        "video.status": "done",
        "video.provider": provider || data?.video?.provider || null,
        "video.providerJobId": providerJobId,
        "video.outputUrl": outputUrl,
        "video.thumbUrl": data?.imageUrl || null,
        "video.lastError": null,
        videoStatus: "done",
        updatedAt: FieldValue.serverTimestamp(),
      }).catch(async () => {
        await sceneRef.set({
          video: {
            ...(data.video || {}),
            status: "done",
            provider: provider || null,
            providerJobId,
            outputUrl,
            thumbUrl: data?.imageUrl || null,
            lastError: null,
          },
          videoStatus: "done",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      });

      // Idempotently upsert a timeline clip doc so projects rehydrate on reopen
      try {
        const clipId = `scene-${id4}`;
        const tlRef = db.doc(`users/${uid}/projects/${projectId}/timeline/clips/${clipId}`);
        await tlRef.set({
          type: "video",
          source: {kind: "scene", storyboardId, sceneIndex: Number(id4)},
          url: outputUrl,
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        functions.logger.info("timeline.clip.upserted", {uid, projectId, storyboardId, sceneId: id4, clipId});
      } catch (e:any) {
        functions.logger.warn("timeline.clip.upsert_failed", {message: String(e?.message || e)});
      }

      functions.logger.info("run_scene_video.done", {requestId, uid, projectId, storyboardId, sceneId: id4, provider: provider || null, docPath: sceneRef.path, outputUrl});
      res.status(200).json({ok: true, outputUrl});
    } catch (e: any) {
      functions.logger.error("run_scene_video.failed", {message: String(e?.message || e)});
      // sceneRef may be undefined if we failed before computing it
      try {
        const {uid, projectId, storyboardId, sceneId} = (req.body || {}) as any;
        if (uid && projectId && storyboardId && sceneId) {
          const id4 = String(sceneId).padStart(4, "0");
          const sr = db.collection("users").doc(uid).collection("projects").doc(projectId).collection("storyboards").doc(storyboardId).collection("scenes").doc(id4);
          await sr.set({ video: { status: "failed", lastError: String(e?.message || e) }, videoStatus: "failed", updatedAt: FieldValue.serverTimestamp() }, {merge: true});
        }
      } catch {}
      res.status(200).json({ok: false, error: "internal_error"});
    }
  });


