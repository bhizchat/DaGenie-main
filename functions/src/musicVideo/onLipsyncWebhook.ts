/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import axios from "axios";
import * as crypto from "crypto";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const db = getFirestore();

/**
 * Replicate webhook receiver for lipsync predictions.
 * Body reflects Replicate prediction schema.
 * Prefer addressing the exact storyboard via prediction.metadata
 * to avoid expensive scans. Fallback to scan if metadata missing.
 */
export const onLipsyncWebhook = functions
  .runWith({timeoutSeconds: 60})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      // Verify Replicate signed webhook if secret is configured
      const secret = process.env.REPLICATE_WEBHOOK_SECRET;
      if (secret) {
        try {
          const sig = String(req.header("X-Replicate-Signature") || "");
          const bodyRaw = JSON.stringify(req.body || {});
          const h = crypto.createHmac("sha256", secret).update(bodyRaw).digest("hex");
          if (!sig || sig !== h) {
            res.status(200).json({ignored: true, reason: "bad_signature"});
            return;
          }
        } catch {
          res.status(200).json({ignored: true, reason: "verify_failed"});
          return;
        }
      }
      const body = req.body || {};
      const status = String(body?.status || "");
      const predId = String(body?.id || "");
      const output = body?.output;

      if (!predId) { res.status(400).json({error: "bad_request"}); return; }

      const meta = body?.metadata || {};
      const envRef = meta?.runId ? db.collection("runs").doc(String(meta.runId)) : null;
      let uid: string | undefined = meta.uid;
      let projectId: string | undefined = meta.projectId;
      let storyboardId: string | undefined = meta.storyboardId;
      if (envRef) {
        try {
          const envSnap = await envRef.get();
          const env = (envSnap.data() || {}) as any;
          uid = env?.uid || uid;
          projectId = env?.projectId || projectId;
          storyboardId = env?.storyboardId || storyboardId;
        } catch {/* envelope optional */}
      }
      const outUrl = Array.isArray(output) ? output[0] : output;
      const ok = status === "succeeded";

      let updated = false;
      if (uid && projectId && storyboardId) {
        const sbRef = db.collection("users").doc(uid).collection("musicVideos").doc(projectId).collection("storyboards").doc(storyboardId);
        const snap = await sbRef.get();
        const cur = (snap.data() || {}) as any;
        const recordedSid = cur?.finishing?.storyboardId;
        if (recordedSid && recordedSid !== storyboardId) {
          functions.logger.warn("sid_mismatch", { recordedSid, storyboardId, runId: meta.runId, projectId, uid });
        }
        const curPred = cur?.finishing?.lipsync?.predictionId || null;
        const curStatus = cur?.finishing?.lipsync?.status || "";
        // Idempotency: ignore mismatched or already-done predictions
        if (curPred && curPred !== predId) {
          res.status(200).json({ignored: true});
          return;
        }
        if (curStatus === "done" && status === "succeeded") {
          res.status(200).json({dup: true});
          return;
        }
        await sbRef.set({
          finishing: { lipsync: { status: ok ? "done" : status, predictionId: predId, outputUrl: ok ? String(outUrl || "") : null, lastError: ok ? null : String(body?.error || body?.logs || status) } },
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        updated = true;

        // If lipsync succeeded, kick off mux immediately (best-effort)
        if (ok) {
          try {
            await db.runTransaction(async (tx) => {
              const s = await tx.get(sbRef);
              const d = (s.data() || {}) as any;
              const mux = d?.finishing?.mux || {};
              if (mux?.status === "queued" || mux?.status === "done") return; // idempotent
              tx.set(sbRef, { finishing: { mux: { status: "queued", finalUrl: null, lastError: null } } }, {merge: true});
            });
            const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || (process.env.FIREBASE_CONFIG ? JSON.parse(String(process.env.FIREBASE_CONFIG)).projectId : "");
            const muxUrl = `https://us-central1-${project}.cloudfunctions.net/muxAudioVideo`;
            await axios.post(muxUrl, {uid, projectId, storyboardId, runId: meta.runId}, {timeout: 300000});
          } catch (e:any) {
            await sbRef.set({ finishing: { mux: { status: "idle", lastError: String(e?.message || e) } } }, {merge: true}).catch(()=>{});
          }
        }

        // Optional mirror for legacy project listeners
        try {
          if (uid && projectId) {
            const projRef = db.doc(`users/${uid}/projects/${projectId}`);
            if (ok && outUrl) {
              await projRef.set({
                finalVideoUrl: String(Array.isArray(output) ? output[0] : output || ""),
                finishing: { status: "done" },
                updatedAt: FieldValue.serverTimestamp(),
              }, {merge: true});
            } else if (!ok) {
              await projRef.set({
                finishing: { status: "failed" },
                updatedAt: FieldValue.serverTimestamp(),
              }, {merge: true});
            }
          }
        } catch {/* best-effort mirror */}
      } else {
        // Fallback: find by predictionId scan
        const usersSnap = await db.collection("users").get();
        for (const u of usersSnap.docs) {
          const mvSnap = await u.ref.collection("musicVideos").get();
          for (const mv of mvSnap.docs) {
            const sbs = await mv.ref.collection("storyboards").where("finishing.lipsync.predictionId", "==", predId).get();
            for (const sb of sbs.docs) {
              await sb.ref.set({
                finishing: { lipsync: { status: ok ? "done" : status, predictionId: predId, outputUrl: ok ? String(outUrl || "") : null, lastError: ok ? null : String(body?.error || body?.logs || status) } },
                updatedAt: FieldValue.serverTimestamp(),
              }, {merge: true});
              updated = true;
            }
          }
        }
      }

      res.status(200).json({ok: true, updated});
    } catch (e: any) {
      functions.logger.error("onLipsyncWebhook.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error"});
    }
  });


