/* eslint-disable max-len, indent */
import * as functions from "firebase-functions/v1";
const {HttpsError} = functions.https;
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";

// Ensure Admin SDK initialised (for local emulator cold starts)
if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}

const db = getFirestore();

/**
 * Callable function to award romance points to the current user.
 * Request data: { points?: number, planId: string }
 * (points defaults to 3, max 10)
 * Ensures each planId can only be redeemed once per user.
 * Increments users/{uid}/stats.romancePoints (creates doc if missing).
 */
export const awardRomancePoints = functions
  .region("us-central1")
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const {planId} = data as {planId?: string};
  if (!planId || typeof planId !== "string") {
    throw new HttpsError("invalid-argument", "planId required");
  }
  const ptsRaw = data?.points;
  const points = typeof ptsRaw === "number" && ptsRaw > 0 ? Math.min(ptsRaw, 10) : 3;

  const uid = context.auth!.uid;
  const userRef = db.collection("users").doc(uid);
  const awardRef = userRef.collection("awardedPlans").doc(planId);
  const statsRef = userRef.collection("stats").doc("aggregates");

  await db.runTransaction(async (txn) => {
    const awardSnap = await txn.get(awardRef);
    if (awardSnap.exists) {
      throw new HttpsError("already-exists", "Points already collected for this plan");
    }
    txn.set(awardRef, {points, awardedAt: Date.now()});
    txn.set(statsRef, {
      romancePoints: FieldValue.increment(points),
      updatedAt: Date.now(),
    }, {merge: true});
  });

  // --- Analytics event: romance_points_earned ---
  try {
    await db.collection("analyticsEvents").add({
      uid,
      event: "romance_points_earned",
      planId,
      points,
      createdAt: Date.now(),
    });
  } catch (e) {
    logger.warn("Analytics logging failed", e as Error);
  }

  return {success: true, points};
});
