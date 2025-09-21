/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import Replicate from "replicate";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const db = getFirestore();

export const submitLipsync = functions
  .runWith({timeoutSeconds: 120, secrets: ["REPLICATE_API_TOKEN"]})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      const {uid, projectId, storyboardId, runId} = (req.body || {}) as any;
      if (!uid || !projectId || !storyboardId || !runId) { res.status(400).json({error: "bad_request"}); return; }

      const sbRef = db.collection("users").doc(uid).collection("musicVideos").doc(projectId).collection("storyboards").doc(storyboardId);
      const snap = await sbRef.get();
      const sb = snap.data() || {} as any;
      const activeRunId = sb?.state?.activeRunId;
      if (activeRunId && activeRunId !== runId) { res.status(409).json({error: "stale_run"}); return; }

      const masterVideoUrl = sb?.finishing?.concat?.masterVideoUrl;
      const audioGsPath = sb?.finishing?.audioGsPath;
      if (!masterVideoUrl || !audioGsPath) { res.status(400).json({error: "missing_inputs"}); return; }

      const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || (process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)).projectId : "");
      const base = `https://us-central1-${project}.cloudfunctions.net`;
      const webhook = `${base}/onLipsyncWebhook`;

      const replicate = new Replicate({auth: process.env.REPLICATE_API_TOKEN as string});
      const created: any = await (replicate as any).predictions.create({
        model: "sync/lipsync-2-pro",
        input: { video: masterVideoUrl, audio: audioGsPath },
        webhook,
        webhook_events_filter: ["completed", "failed", "canceled"],
      });

      await sbRef.set({
        finishing: { ...(sb.finishing || {}), lipsync: { status: "running", predictionId: created?.id || null, outputUrl: null, lastError: null } },
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      res.status(200).json({ok: true, predictionId: created?.id || null});
    } catch (e: any) {
      functions.logger.error("submitLipsync.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  });


