/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {CloudTasksClient} from "@google-cloud/tasks";
import Replicate from "replicate";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const db = getFirestore();
const tasks = new CloudTasksClient();

export const startStoryboardRun = functions
  .runWith({timeoutSeconds: 180, secrets: ["REPLICATE_API_TOKEN"]})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      const {uid, projectId, storyboardId, runId} = (req.body || {}) as any;
      if (!uid || !projectId || !storyboardId || !runId) { res.status(400).json({error: "bad_request"}); return; }

      const sbRef = db.collection("users").doc(uid)
        .collection("projects").doc(projectId)
        .collection("storyboards").doc(storyboardId);

      await db.runTransaction(async (tx) => {
        const sb = await tx.get(sbRef);
        if (!sb.exists) throw new Error("storyboard_not_found");
        tx.set(sbRef, {
          state: { activeRunId: runId },
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      });

      // Best-effort cleanup of stale in-flight work (queued/running with different runId)
      const scenesSnap = await sbRef.collection("scenes").get();
      const replicateToken = process.env.REPLICATE_API_TOKEN || "";
      const replicate = replicateToken ? new Replicate({auth: replicateToken}) : null;
      const batch = db.bulkWriter();

      await Promise.allSettled(scenesSnap.docs.map(async (d) => {
        const data = d.data() || {} as any;
        const v = (data.video || {}) as any;
        const status = String(v.status || "").toLowerCase();
        const isInflight = ["queued", "running", "processing"].includes(status);
        const stale = isInflight && v.runId && v.runId !== runId;
        if (!stale) return;

        // Delete queued Cloud Task if known
        const taskName = v.taskName as (string|undefined);
        if (taskName) {
          try { await tasks.deleteTask({name: taskName}); } catch {}
        }
        // Cancel Replicate prediction if known
        const predictionId = v.predictionId as (string|undefined);
        if (predictionId && replicate) {
          try { await (replicate as any).predictions.cancel(predictionId); } catch {}
        }
        // Mark as canceled
        await batch.set(d.ref, {
          video: { ...(v || {}), status: "canceled", lastError: null },
          videoStatus: "canceled",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }));

      await batch.close();
      res.status(200).json({ok: true, activeRunId: runId});
    } catch (e: any) {
      functions.logger.error("startStoryboardRun.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  });


