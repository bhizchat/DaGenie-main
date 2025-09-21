/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {CloudTasksClient} from "@google-cloud/tasks";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const db = getFirestore();
const tasks = new CloudTasksClient();

const LOCATION = process.env.TASKS_LOCATION || "us-central1";
const QUEUE = process.env.TASKS_QUEUE || "storyboard-clips"; // reuse existing queue

function taskName(base: string, uid: string, projectId: string, storyboardId: string, runId: string) {
  return `${base}-${uid}-${projectId}-${storyboardId}-run-${runId}`.toLowerCase();
}

/**
 * Initialize finishing pipeline statuses and enqueue visual assembly.
 * Body: { uid, projectId, storyboardId, runId, audioGsPath, audioDurationSec }
 */
export const startMusicFinishing = functions
  .runWith({timeoutSeconds: 120, memory: "256MB"})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      const {uid, projectId, storyboardId, runId, audioGsPath, audioDurationSec} = (req.body || {}) as any;
      if (!uid || !projectId || !storyboardId || !runId || !audioGsPath) { res.status(400).json({error: "bad_request"}); return; }

      const sbRef = db.collection("users").doc(uid).collection("musicVideos").doc(projectId).collection("storyboards").doc(storyboardId);

      // Run fence check
      const sbSnap = await sbRef.get();
      const activeRunId = (sbSnap.data() as any)?.state?.activeRunId;
      if (activeRunId && activeRunId !== runId) {
        res.status(409).json({error: "stale_run", activeRunId});
        return;
      }

      // Bootstrap finishing status (idempotent merge)
      await sbRef.set({
        finishing: {
          audioGsPath,
          concat: { status: "queued", masterVideoUrl: null, lastError: null, durationSec: Number(audioDurationSec || 0) || null },
          lipsync: { status: "idle", predictionId: null, outputUrl: null, lastError: null },
          mux: { status: "idle", finalUrl: null, lastError: null },
        },
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      // Enqueue assembleVisualMaster task (deterministic)
      const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || (process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)).projectId : "");
      const parent = tasks.queuePath(project, LOCATION, QUEUE);
      const runUrl = process.env.ASSEMBLE_VISUAL_URL || `https://us-central1-${project}.cloudfunctions.net/assembleVisualMaster`;
      const tName = taskName("assemble", uid, projectId, storyboardId, runId);
      const httpRequest: any = {
        httpMethod: "POST",
        url: runUrl,
        headers: {"Content-Type": "application/json"},
        body: Buffer.from(JSON.stringify({uid, projectId, storyboardId, runId})).toString("base64"),
      };
      if (process.env.TASKS_OIDC_SERVICE_ACCOUNT) {
        httpRequest.oidcToken = {
          serviceAccountEmail: process.env.TASKS_OIDC_SERVICE_ACCOUNT,
          audience: process.env.TASKS_OIDC_AUDIENCE || runUrl,
        };
      }
      const task = {httpRequest, name: tasks.taskPath(project, LOCATION, QUEUE, tName)} as any;
      try { await tasks.createTask({parent, task}); } catch (e: any) {
        const msg = String(e?.message || e);
        if (!/ALREADY_EXISTS/i.test(msg)) { throw e; }
      }

      res.status(200).json({ok: true, enqueued: true, taskName: tName});
    } catch (e: any) {
      functions.logger.error("startMusicFinishing.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  });


