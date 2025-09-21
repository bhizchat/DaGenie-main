import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {FieldValue} from "firebase-admin/firestore";
import axios from "axios";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }

// When a storyboard scene document is created under users/{uid}/musicVideos/{projectId}/storyboards/{storyboardId}/scenes/{sceneId}
// kick off image generation for that scene if imageUrl is empty. This ensures progress even if the HTTP request from the app timed out.
export const startMusicStoryboardOnCreate = functions
  .runWith({timeoutSeconds: 300, memory: "512MB"})
  .region("us-central1")
  .firestore.document("users/{uid}/musicVideos/{projectId}/storyboards/{storyboardId}/scenes/{sceneId}")
  .onCreate(async (snap, ctx) => {
    try {
      const {uid, projectId, storyboardId, sceneId} = ctx.params as any;
      const data = snap.data() || {};
      const imageUrl = String(data.imageUrl || "");
      const action = String(data.action || "");
      const animation = String(data.animation || "");
      functions.logger.info("mv_scene_onCreate_fired", {
        uid, projectId, storyboardId, sceneId,
        idx: Number(data.index || 0), hasImage: Boolean(imageUrl)
      });
      if (imageUrl) { return; } // already has an image
      // Read storyboard-level context (references, style/environment, idea)
      const sbRef = snap.ref.parent.parent;
      let env = ""; let style = "3D stylized"; let idea = ""; let references: string[] = [];
      if (sbRef) {
        try {
          const sb = await sbRef.get();
          const sbd = sb.exists ? (sb.data() as any) : {};
          env = String(sbd?.environment || "");
          style = String(sbd?.style || style);
          idea = String(sbd?.ideaText || "");
          if (Array.isArray(sbd?.referenceImageUrls)) {
            references = (sbd.referenceImageUrls as any[]).map((v) => String(v)).filter(Boolean);
          }
        } catch {}
      }
      const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || (process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)).projectId : "");
      const base = `https://us-central1-${project}.cloudfunctions.net`;
      const imgUrl = `${base}/generateStoryboardImages`;
      const payload = {
        scenes: [{index: Number(data.index || 0), action, animation}],
        style,
        referenceImageUrls: references,
        provider: "nano",
        ideaText: idea,
        environment: env,
      } as any;
      functions.logger.info("mv_scene_image_request", {
        uid, projectId, storyboardId, sceneId,
        idx: Number(data.index || 0), refs: references.length, style
      });
      let out: any = null;
      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          const resp = await axios.post(imgUrl, payload, {timeout: 300000});
          out = Array.isArray(resp.data?.scenes) ? resp.data.scenes[0] : null;
          if (out?.imageUrl) { break; }
        } catch (e: any) {
          functions.logger.warn("mv_scene_image_request_error", {
            uid, projectId, storyboardId, sceneId, attempt, message: String(e?.message || e)
          });
          if (attempt < 3) { await new Promise(r => setTimeout(r, 1500)); }
        }
      }
      if (out && out.imageUrl) {
        await snap.ref.set({ imageUrl: out.imageUrl, updatedAt: FieldValue.serverTimestamp() }, {merge: true});
        functions.logger.info("mv_scene_image_written", { uid, projectId, storyboardId, sceneId });
      } else {
        functions.logger.warn("mv_scene_image_no_output", { uid, projectId, storyboardId, sceneId });
      }
    } catch (e) {
      functions.logger.warn("startMusicStoryboardOnCreate.failed", { message: String((e as any)?.message || e) });
    }
  });
