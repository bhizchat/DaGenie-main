/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";

if (!getApps().length) { initializeApp({credential: applicationDefault()}); }
const db = getFirestore();

/**
 * Replicate webhook receiver for lipsync predictions.
 * Body reflects Replicate prediction schema.
 * We expect metadata fields to find the storyboard; since we didn't send metadata, we
 * look up by scanning storyboards for matching predictionId under finishing.lipsync.
 */
export const onLipsyncWebhook = functions
  .runWith({timeoutSeconds: 60})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      const body = req.body || {};
      const status = String(body?.status || "");
      const predId = String(body?.id || "");
      const output = body?.output;

      if (!predId) { res.status(400).json({error: "bad_request"}); return; }

      // Find the storyboard document that holds this predictionId (small scans in practice)
      // Scope to musicVideos collections only.
      const usersSnap = await db.collection("users").get();
      let updated = false;
      for (const u of usersSnap.docs) {
        const mvSnap = await u.ref.collection("musicVideos").get();
        for (const mv of mvSnap.docs) {
          const sbs = await mv.ref.collection("storyboards").where("finishing.lipsync.predictionId", "==", predId).get();
          for (const sb of sbs.docs) {
            const outUrl = Array.isArray(output) ? output[0] : output;
            const ok = status === "succeeded";
            await sb.ref.set({
              finishing: { lipsync: { status: ok ? "done" : status, predictionId: predId, outputUrl: ok ? String(outUrl || "") : null, lastError: ok ? null : String(body?.error || body?.logs || status) }, },
              updatedAt: FieldValue.serverTimestamp(),
            }, {merge: true});
            updated = true;
          }
        }
      }

      res.status(200).json({ok: true, updated});
    } catch (e: any) {
      functions.logger.error("onLipsyncWebhook.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error"});
    }
  });


