/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {CloudTasksClient} from "@google-cloud/tasks";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const db = getFirestore();
const tasks = new CloudTasksClient();

const LOCATION = process.env.TASKS_LOCATION || "us-central1";
const QUEUE = process.env.TASKS_QUEUE || "storyboard-clips";

function deterministicTaskName(projectId: string, storyboardId: string, sceneId: string, provider?: string, suffix?: string): string {
  const p = (provider || "wan").toLowerCase();
  const sfx = suffix ? `-${suffix}` : "";
  return `${projectId}-${storyboardId}-${sceneId}-${p}${sfx}`.toLowerCase();
}

export const enqueueSceneVideo = functions
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      const {uid, projectId, storyboardId, sceneId, provider, requestId, nameSuffix, delaySeconds} = (req.body || {}) as any;
      if (!uid || !projectId || !storyboardId || !sceneId) { res.status(400).json({error: "bad_request"}); return; }

      const sbRef = db.collection("users").doc(uid).collection("projects").doc(projectId).collection("storyboards").doc(storyboardId);
      const sceneRef = sbRef.collection("scenes").doc(String(sceneId));

      // Mark queued
      await sceneRef.set({ video: { status: "queued", provider: provider || null }, videoStatus: "queued", updatedAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp() }, {merge: true});

      const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || process.env.FIREBASE_CONFIG && JSON.parse(String(process.env.FIREBASE_CONFIG)).projectId || "";
      const parent = tasks.queuePath(project, LOCATION, QUEUE);
      const taskName = deterministicTaskName(projectId, storyboardId, String(sceneId), provider, nameSuffix);

      const runUrl = process.env.RUN_SCENE_URL || `https://us-central1-${project}.cloudfunctions.net/runSceneVideo`;
      const payload = {uid, projectId, storyboardId, sceneId, provider: provider || null, requestId: requestId || null};

      const httpRequest: any = {
        httpMethod: "POST",
        url: runUrl,
        headers: {"Content-Type": "application/json"},
        body: Buffer.from(JSON.stringify(payload)).toString("base64"),
      };
      // If OIDC is configured, attach a token for the target
      if (process.env.TASKS_OIDC_SERVICE_ACCOUNT) {
        httpRequest.oidcToken = {
          serviceAccountEmail: process.env.TASKS_OIDC_SERVICE_ACCOUNT,
          audience: process.env.TASKS_OIDC_AUDIENCE || runUrl,
        };
      }

      const task: any = { httpRequest, name: tasks.taskPath(project, LOCATION, QUEUE, taskName) };
      const nowSec = Math.floor(Date.now() / 1000);
      const delay = Number(delaySeconds || 0);
      if (Number.isFinite(delay) && delay > 0) {
        task.scheduleTime = { seconds: nowSec + Math.floor(delay) };
      }
      try {
        const [resp] = await tasks.createTask({parent, task});
        functions.logger.info("enqueue_scene_video.task_created", {name: resp?.name || null});
      } catch (e: any) {
        const code = (e && typeof e.code !== "undefined") ? e.code : undefined;
        const msg = String(e?.message || e);
        const already = code === 6 || /ALREADY_EXISTS/i.test(msg);
        if (!already) {
          functions.logger.error("enqueue_scene_video.createTask_error", {code, msg, parent, LOCATION, QUEUE, runUrl});
          throw e;
        }
        functions.logger.info("enqueue_scene_video.dedup", {taskName});
      }

      functions.logger.info("enqueue_scene_video.ok", {requestId, uid, projectId, storyboardId, sceneId, taskName, provider: provider || null, delaySeconds: delay || 0});
      res.status(200).json({ok: true, taskName});
    } catch (e: any) {
      functions.logger.error("enqueue_scene_video.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  });


