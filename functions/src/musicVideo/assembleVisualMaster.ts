/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import ffmpegPath from "ffmpeg-static";
import {spawn, spawnSync} from "child_process";
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

async function probeDurationSeconds(p: string): Promise<number | null> {
  try {
    // Try ffprobe per-stream duration (video stream)
    const out = spawnSync("ffprobe", ["-v","error","-select_streams","v:0","-show_entries","stream=duration","-of","default=nw=1:nk=1", p], {encoding: "utf8"});
    const txt = (out.stdout || "").trim();
    const n = Number(txt);
    if (Number.isFinite(n) && n > 0) return n;
  } catch {}
  try {
    const out2 = spawnSync("ffprobe", ["-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1", p], {encoding: "utf8"});
    const txt2 = (out2.stdout || "").trim();
    const n2 = Number(txt2);
    if (Number.isFinite(n2) && n2 > 0) return n2;
  } catch {}
  return null;
}

async function downloadTo(tmpDir: string, url: string, name: string): Promise<string> {
  const p = path.join(tmpDir, name);
  const r = await axios.get<ArrayBuffer>(url, {responseType: "arraybuffer", timeout: 300000});
  fs.writeFileSync(p, Buffer.from(r.data as any));
  return p;
}

export const assembleVisualMaster = functions
  .runWith({timeoutSeconds: 540, memory: "1GB"})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      const {uid, projectId, storyboardId, runId} = (req.body || {}) as any;
      if (!uid || !projectId || !storyboardId || !runId) { res.status(400).json({error: "bad_request"}); return; }

      const sbRef = db.collection("users").doc(uid).collection("musicVideos").doc(projectId).collection("storyboards").doc(storyboardId);
      const sbSnap = await sbRef.get();
      const sb = sbSnap.data() || {} as any;
      const activeRunId = sb?.state?.activeRunId;
      if (activeRunId && activeRunId !== runId) { res.status(409).json({error: "stale_run"}); return; }

      const finishing = (sb?.finishing || {}) as any;
      const audioDurationSec: number = Number(finishing?.concat?.durationSec || 0) || 0;
      const programVideoUrl: string | null = finishing?.programVideoUrl || null;

      // If caller provided a single program video, loop it to match audio length
      if (programVideoUrl) {
        const tmpProg = fs.mkdtempSync(path.join(process.cwd(), "asm-"));
        const ff = (ffmpegPath as unknown as string);
        const inPath = await downloadTo(tmpProg, programVideoUrl, "program.mp4");
        // Repeat enough times; final trim will set exact length
        const approxProgramSec = Math.max(1, Math.floor(audioDurationSec || 60));
        const repeats = Math.max(1, Math.ceil(approxProgramSec / 54));
        const listPath = path.join(tmpProg, "files.txt");
        fs.writeFileSync(listPath, Array.from({length: repeats}).map(() => `file '${inPath.replace(/'/g, "'\\''")}'`).join("\n"));
        const concatOut = path.join(tmpProg, "concat.mp4");
        await run(ff, ["-f","concat","-safe","0","-i",listPath,"-c","copy", concatOut]);
        const targetOut = path.join(tmpProg, "visual.mp4");
        const tProg = Math.max(1, Math.floor(audioDurationSec || 1));
        await run(ff, ["-i", concatOut, "-t", String(tProg), "-c", "copy", targetOut]);
        const measured = await probeDurationSeconds(targetOut);

        const bucket = storage.bucket();
        const objectPath = `masters/${uid}/${projectId}/${storyboardId}/visual_${Date.now()}.mp4`;
        await bucket.upload(targetOut, {destination: objectPath, metadata: {contentType: "video/mp4"}});
        const file = bucket.file(objectPath);
        const [signedUrl] = await file.getSignedUrl({action: "read", expires: Date.now() + 12 * 60 * 60 * 1000});
        await sbRef.set({
          finishing: { ...(sb.finishing || {}), concat: { status: "done", masterVideoUrl: signedUrl, durationSec: measured ?? tProg } },
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        res.status(200).json({ok: true, masterVideoUrl: signedUrl});
        return;
      }

      // Gather scene clips ordered by index (legacy path if a program video is not provided)
      const scenesSnap = await sbRef.collection("scenes").orderBy("index").get();
      const urls: string[] = [];
      scenesSnap.forEach((d) => {
        const v = (d.data()?.video || {}) as any;
        if (v?.status === "done" && v?.outputUrl) urls.push(String(v.outputUrl));
      });
      if (!urls.length) { res.status(409).json({error: "no_clips"}); return; }

      const tmp = fs.mkdtempSync(path.join(process.cwd(), "asm-"));

      // Download clips
      const localClips: string[] = [];
      let idx = 0;
      for (const u of urls) {
        localClips.push(await downloadTo(tmp, u, `clip_${String(++idx).padStart(2, "0")}.mp4`));
      }

      // Build concat list repeated to cover audio length (assume ~5s per clip if unknown)
      const approxClipDur = 5; // our WAN default per scene
      const approxProgram = approxClipDur * localClips.length;
      const repeats = Math.max(1, Math.ceil((audioDurationSec || approxProgram) / Math.max(1, approxProgram)));
      const listPath = path.join(tmp, "files.txt");
      const lines: string[] = [];
      for (let r = 0; r < repeats; r++) {
        for (const pth of localClips) { lines.push(`file '${pth.replace(/'/g, "'\\''")}'`); }
      }
      fs.writeFileSync(listPath, lines.join("\n"));

      const concatOut = path.join(tmp, "concat.mp4");
      const ff = (ffmpegPath as unknown as string);
      await run(ff, ["-f", "concat", "-safe", "0", "-i", listPath, "-c", "copy", concatOut]);

      const targetOut = path.join(tmp, "visual.mp4");
      const t = Math.max(1, Math.floor(audioDurationSec || approxProgram));
      await run(ff, ["-i", concatOut, "-t", String(t), "-c", "copy", targetOut]);
      const measured = await probeDurationSeconds(targetOut);

      // Upload to Storage
      const bucket = storage.bucket();
      const objectPath = `masters/${uid}/${projectId}/${storyboardId}/visual_${Date.now()}.mp4`;
      await bucket.upload(targetOut, {destination: objectPath, metadata: {contentType: "video/mp4"}});
      const file = bucket.file(objectPath);
      const [signedUrl] = await file.getSignedUrl({action: "read", expires: Date.now() + 12 * 60 * 60 * 1000});

      await sbRef.set({
        finishing: { ...(sb.finishing || {}), concat: { status: "done", masterVideoUrl: signedUrl, durationSec: measured ?? t } },
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      res.status(200).json({ok: true, masterVideoUrl: signedUrl});
    } catch (e: any) {
      functions.logger.error("assembleVisualMaster.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  });


