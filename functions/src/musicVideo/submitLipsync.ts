/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import Replicate from "replicate";
import {getStorage} from "firebase-admin/storage";
import ffmpegPath from "ffmpeg-static";
import {spawn} from "child_process";
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

function parseGsPath(gs: string): {bucket: string; object: string} | null {
  const m = /^gs:\/\/([^/]+)\/(.+)$/.exec(gs || "");
  if (!m) return null;
  return {bucket: m[1], object: m[2]};
}

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

      // Guard: only proceed once program length is at least 55s
      const dur = Number(sb?.finishing?.concat?.durationSec || 0);
      if (dur < 54) { res.status(409).json({error: "program_too_short", duration: dur}); return; }

      // Ensure a 60s audio derivative exists and is HTTPS-accessible
      let audio60Url: string | null = sb?.finishing?.audio60Url || null;
      if (!audio60Url) {
        const gs = parseGsPath(audioGsPath);
        if (!gs) { res.status(400).json({error: "bad_audio_path"}); return; }
        const bucket = storage.bucket(gs.bucket);
        const tmp = fs.mkdtempSync(path.join(process.cwd(), "ls-"));
        const srcPath = path.join(tmp, "src_audio");
        const outPath = path.join(tmp, "audio_60s.wav");
        await bucket.file(gs.object).download({destination: srcPath});
        const ff = (ffmpegPath as unknown as string);
        // Sample-accurate first 60s; mono 16k PCM
        await run(ff, ["-y","-i", srcPath, "-af", "atrim=start=0:end=60,asetpts=N/SR/TB", "-ac","1","-ar","16000","-c:a","pcm_s16le","-t","60", outPath]);
        const dstObject = `masters/${uid}/${projectId}/${storyboardId}/audio_60s_${Date.now()}.wav`;
        await bucket.upload(outPath, {destination: dstObject, metadata: {contentType: "audio/wav"}});
        const file = bucket.file(dstObject);
        const [signed] = await file.getSignedUrl({action: "read", expires: Date.now() + 12 * 60 * 60 * 1000});
        audio60Url = signed;
        await sbRef.set({ finishing: { ...(sb.finishing || {}), audio60Url } }, {merge: true});
      }

      // If video duration is < 60, also prepare an N-second audio to match it
      const N = Math.min(60, Math.max(1, Math.floor(dur || 60)));
      let audioNUrl = sb?.finishing?.audioNUrl || null;
      if (N < 60 && !audioNUrl) {
        const gs = parseGsPath(sb?.finishing?.audioGsPath || audioGsPath);
        if (!gs) { res.status(400).json({error: "bad_audio_path"}); return; }
        const bucket = storage.bucket(gs.bucket);
        const tmp = fs.mkdtempSync(path.join(process.cwd(), "lsn-"));
        const srcPath = path.join(tmp, "src_audio");
        const outPath = path.join(tmp, `audio_${N}s.wav`);
        await bucket.file(gs.object).download({destination: srcPath});
        const ff = (ffmpegPath as unknown as string);
        await run(ff, ["-y","-i", srcPath, "-af", `atrim=start=0:end=${String(N)},asetpts=N/SR/TB`, "-ac","1","-ar","16000","-c:a","pcm_s16le","-t", String(N), outPath]);
        const dstObject = `masters/${uid}/${projectId}/${storyboardId}/audio_${N}s_${Date.now()}.wav`;
        await bucket.upload(outPath, {destination: dstObject, metadata: {contentType: "audio/wav"}});
        const file = bucket.file(dstObject);
        const [signed] = await file.getSignedUrl({action: "read", expires: Date.now() + 12 * 60 * 60 * 1000});
        audioNUrl = signed;
        await sbRef.set({ finishing: { ...(sb.finishing || {}), audioNUrl, audioNSeconds: N } }, {merge: true});
      }

      const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || (process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)).projectId : "");
      const base = `https://us-central1-${project}.cloudfunctions.net`;
      const webhook = `${base}/onLipsyncWebhook`;

      const replicate = new Replicate({auth: process.env.REPLICATE_API_TOKEN as string});
      const created: any = await (replicate as any).predictions.create({
        model: "sync/lipsync-2-pro",
        input: { video: masterVideoUrl, audio: (N < 60 && audioNUrl) ? audioNUrl : audio60Url },
        // Include metadata so the webhook can address the exact doc with no scans
        metadata: { uid, projectId, storyboardId, runId },
        webhook,
        webhook_secret: process.env.REPLICATE_WEBHOOK_SECRET || undefined,
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


