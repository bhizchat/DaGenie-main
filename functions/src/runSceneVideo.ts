/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import axios from "axios";
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
  .runWith({timeoutSeconds: 540, memory: "1GB"})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      verifyOidcFromTasks(req);
      const {uid, projectId, storyboardId, sceneId, provider, requestId} = (req.body || {}) as any;
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

      await sceneRef.update({
        "video.status": "running",
        "video.provider": provider || data?.video?.provider || null,
        videoStatus: "running",
        updatedAt: FieldValue.serverTimestamp(),
      }).catch(async () => {
        // fallback if document missing fields
        await sceneRef.set({ video: { ...(data.video || {}), status: "running", provider: provider || null }, videoStatus: "running", updatedAt: FieldValue.serverTimestamp() }, {merge: true});
      });

      // Build a provider-agnostic input from the scene fields
      // Build provider-agnostic input (placeholder for future integration)

      let outputUrl: string | null = null;
      let providerJobId: string | null = null;

      // Provider dispatch (WAN)
      const normalizedProvider = (provider || data?.video?.provider || "wan").toString().toLowerCase();
      if (normalizedProvider === "wan") {
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
          video: { ...(data.video || {}), status: "error", provider: provider || null, lastError: "wan_no_output" },
          videoStatus: "error",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        functions.logger.error("run_scene_video.no_output_url", {docPath: sceneRef.path});
        res.status(502).json({error: "wan_no_output"});
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
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  });


