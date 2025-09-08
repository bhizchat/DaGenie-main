#!/usr/bin/env ts-node
/* eslint-disable no-console, indent */
/**
 * Simple seeding script – upload flagship hunt templates from JSON to Firestore.
 * Usage:
 *   npx ts-node scripts/seedHunts.ts [path/to/json]
 * Requires GOOGLE_APPLICATION_CREDENTIALS or firebase login for admin SDK.
 */
import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";

const jsonPath = process.argv[2] || path.join(__dirname, "flagshipHunts.json");
if (!fs.existsSync(jsonPath)) {
  console.error("❌ JSON file not found:", jsonPath);
  process.exit(1);
}

const raw = fs.readFileSync(jsonPath, "utf-8");
const hunts = JSON.parse(raw) as any[];

if (!admin.apps.length) {
  // Prefer GOOGLE_APPLICATION_CREDENTIALS but fall back to keys/dategenie-sa.json
  const explicitCred = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const fallbackPath = path.join(__dirname, "..", "keys", "dategenie-sa.json");
  let credential: admin.credential.Credential | undefined;
  if (explicitCred && fs.existsSync(explicitCred)) {
    credential = admin.credential.cert(JSON.parse(fs.readFileSync(explicitCred, "utf8")) as admin.ServiceAccount);
  } else if (fs.existsSync(fallbackPath)) {
    credential = admin.credential.cert(JSON.parse(fs.readFileSync(fallbackPath, "utf8")) as admin.ServiceAccount);
  }

  if (credential) {
    admin.initializeApp({credential});
  } else {
    // Will attempt ADC which may prompt error if none
    admin.initializeApp();
  }
}
const db = admin.firestore();

(async () => {
  const batch = db.batch();
  hunts.forEach((hunt) => {
    const ref = db.collection("hunts").doc(hunt.id);
    batch.set(ref, hunt, {merge: true});
  });
  await batch.commit();
  console.log(`✅ Seeded ${hunts.length} hunts to Firestore`);
  process.exit(0);
})();
