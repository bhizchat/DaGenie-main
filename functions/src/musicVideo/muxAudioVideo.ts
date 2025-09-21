/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import ffmpegPath from "ffmpeg-static";
import {spawn} from "child_process";
import axios from "axios";
import * as fs from "fs";
import * as path from "path";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const db = getFirestore();
const storage = getStorage();

function run(cmd: string, args: string[], cwd?: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, {cwd, stdio: "inherit"});
    p.on("exit", (code) => code === 0 ? resolve() : reject(new Error(`${cmd} exited ${code}`)));
    p.on("error", reject);
  });
}

async function download(url: string, p: string) {
  const r = await axios.get<ArrayBuffer>(url, {responseType: "arraybuffer", timeout: 300000});
  fs.writeFileSync(p, Buffer.from(r.data as any));
}

export const muxAudioVideo = functions
  .runWith({timeoutSeconds: 540, memory: "1GB"})
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

      const videoUrl = sb?.finishing?.lipsync?.outputUrl || sb?.finishing?.concat?.masterVideoUrl;
      const audioUrl = sb?.finishing?.audioGsPath;
      if (!videoUrl || !audioUrl) { res.status(400).json({error: "missing_inputs"}); return; }

      const tmp = fs.mkdtempSync(path.join(process.cwd(), "mux-"));
      const videoPath = path.join(tmp, "v.mp4");
      const audioPath = path.join(tmp, "a.m4a");
      await Promise.all([download(videoUrl, videoPath), download(audioUrl, audioPath)]);

      const outPath = path.join(tmp, "final.mp4");
      const ff = (ffmpegPath as unknown as string);
      await run(ff, ["-i", videoPath, "-i", audioPath, "-c:v", "copy", "-c:a", "aac", "-shortest", outPath]);

      const bucket = storage.bucket();
      const objectPath = `masters/${uid}/${projectId}/${storyboardId}/final_${Date.now()}.mp4`;
      await bucket.upload(outPath, {destination: objectPath, metadata: {contentType: "video/mp4"}});
      const file = bucket.file(objectPath);
      const [signedUrl] = await file.getSignedUrl({action: "read", expires: Date.now() + 30 * 24 * 60 * 60 * 1000});

      await sbRef.set({
        finishing: { ...(sb.finishing || {}), mux: { status: "done", finalUrl: signedUrl, lastError: null } },
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      res.status(200).json({ok: true, finalUrl: signedUrl});
    } catch (e: any) {
      functions.logger.error("muxAudioVideo.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  });


