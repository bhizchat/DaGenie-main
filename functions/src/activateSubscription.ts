/* eslint-disable max-len */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";

const db = getFirestore();

/**
 * Client callable functions that activates/renews a user subscription.
 * Expects { expiryMillis: number } where expiryMillis is the Unix epoch ms
 * specifying when the current subscription period ends.
 */
export const activateSubscription = onCall({region: "us-central1"}, async (request): Promise<void> => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const {expiryMillis} = request.data ?? {};
  if (typeof expiryMillis !== "number" || expiryMillis <= Date.now()) {
    throw new HttpsError("invalid-argument", "expiryMillis required and must be in the future");
  }

  const uid = request.auth.uid;
  const userRef = db.collection("users").doc(uid);
  await userRef.set({
    subscription: {
      active: true,
      expiry: expiryMillis,
    },
  }, {merge: true});
});
