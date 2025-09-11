/* eslint-disable max-len, indent */
import * as functions from "firebase-functions/v1";
const {HttpsError} = functions.https;
import {getFirestore} from "firebase-admin/firestore";

const db = getFirestore();

/**
 * Client callable functions that activates/renews a user subscription.
 * Expects { expiryMillis: number } where expiryMillis is the Unix epoch ms
 * specifying when the current subscription period ends.
 */
export const activateSubscription = functions
  .region("us-central1")
  .https.onCall(async (data: any, context: functions.https.CallableContext): Promise<void> => {
  if (!context.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const {expiryMillis} = data ?? {};
  if (typeof expiryMillis !== "number" || expiryMillis <= Date.now()) {
    throw new HttpsError("invalid-argument", "expiryMillis required and must be in the future");
  }

  const uid = context.auth!.uid;
  const userRef = db.collection("users").doc(uid);
  await userRef.set({
    subscription: {
      active: true,
      expiry: expiryMillis,
    },
  }, {merge: true});
});
