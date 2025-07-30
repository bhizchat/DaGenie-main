/* eslint-disable max-len, require-jsdoc, @typescript-eslint/no-explicit-any, operator-linebreak */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

// Ensure Admin SDK initialised
if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}

const db = getFirestore();

/**
 * Validates an App Store receipt sent from the client. Follows Apple's
 * recommendation to always verify with the production endpoint first and
 * fall back to the sandbox endpoint if status = 21007 (sandbox receipt used
 * in production).
 *
 * Request: { receiptData: string }
 * Response: { active: boolean, expiryMillis: number }
 *
 * Environment variable required:
 *   APPLE_SHARED_SECRET – the app-specific shared secret from App Store Connect.
 */
export const validateReceipt = onCall({region: "us-central1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const {receiptData} = request.data ?? {};
  if (!receiptData || typeof receiptData !== "string") {
    throw new HttpsError("invalid-argument", "receiptData required");
  }

  const sharedSecret = process.env.APPLE_SHARED_SECRET;
  if (!sharedSecret) {
    throw new HttpsError("failed-precondition", "Server missing APPLE_SHARED_SECRET env var");
  }

  const payload = {
    "receipt-data": receiptData,
    "password": sharedSecret,
    "exclude-old-transactions": true,
  };

  async function verify(url: string): Promise<any> {
    const resp = await fetch(url, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(payload),
    });
    return resp.json();
  }

  // 1️⃣ Validate against production App Store first
  let result = await verify("https://buy.itunes.apple.com/verifyReceipt");
  if (result.status === 21007) {
    // 2️⃣ Receipt is from sandbox, validate against sandbox
    result = await verify("https://sandbox.itunes.apple.com/verifyReceipt");
  }

  if (result.status !== 0) {
    throw new HttpsError("failed-precondition", `Receipt validation failed (status=${result.status})`);
  }

  // Find the latest subscription transaction to determine expiry.
  const latestInfo = Array.isArray(result.latest_receipt_info)
    ? result.latest_receipt_info[result.latest_receipt_info.length - 1]
    : null;
  const expiryMillis = latestInfo ? Number(latestInfo.expires_date_ms) : 0;

  if (!expiryMillis) {
    throw new HttpsError("failed-precondition", "Could not determine subscription expiry from receipt");
  }

  // Persist subscription status under the user document.
  const uid = request.auth.uid;
  await db.collection("users").doc(uid).set({
    subscription: {
      active: expiryMillis > Date.now(),
      expiry: expiryMillis,
    },
  }, {merge: true});

  return {active: expiryMillis > Date.now(), expiryMillis};
});
