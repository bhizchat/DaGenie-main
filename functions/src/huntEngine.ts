/* eslint-disable max-len, indent */
/**
 * Hunt Engine – minimal MVP backend logic for DateGenie scavenger hunts.
 *
 * Collections
 *  - hunts/{id}        : master templates (seeded offline / script)
 *  - dates/{id}        : per-couple live instance { uidA, uidB, huntId, status, startedAt, finishedAt?, abortReason? }
 *
 * This file provides Firestore triggers that
 *  1. Stamp metadata when a hunt instance (dates/*) is first created
 *  2. When the status transitions to "finished", increment XP for both users
 *  3. When the status transitions to "aborted", write analytics doc
 */
import {firestore as firestoreV1, Change} from "firebase-functions/v1";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

export interface DateInstance {
  uidA: string;
  uidB: string | null; // allow solo test runs
  huntId: string;
  status: "in_progress" | "finished" | "aborted";
  startedAt: FirebaseFirestore.Timestamp;
  finishedAt?: FirebaseFirestore.Timestamp;
  abortReason?: string;
  xpAwarded?: boolean;
}

const XP_PER_HUNT = 50;

/**
 * Firestore trigger – ensure default fields on create.
 */
export const onDateCreated = firestoreV1
  .document("dates/{dateId}")
  .onCreate(async (snap) => {
    const data = snap.data() as DateInstance;
    // Defensive defaults
    if (!data.status) {
      await snap.ref.update({status: "in_progress"});
    }
  });

/**
 * Firestore trigger – award XP when hunt finishes and log aborts.
 */
export const onDateUpdated = firestoreV1
  .document("dates/{dateId}")
  .onUpdate(async (change: Change<FirebaseFirestore.DocumentData>) => {
    const before = change.before.data() as DateInstance;
    const after = change.after.data() as DateInstance;

    // Award XP once when status becomes finished
    if (before.status !== "finished" && after.status === "finished") {
      if (after.xpAwarded) return null;

      const batch = db.batch();
      const users: string[] = [after.uidA];
      if (after.uidB) users.push(after.uidB);

      users.forEach((uid) => {
        const userRef = db.collection("users").doc(uid);
        batch.set(userRef, {xp: admin.firestore.FieldValue.increment(XP_PER_HUNT)}, {merge: true});
      });
      batch.update(change.after.ref, {xpAwarded: true});

      logger.info("XP awarded for hunt", {dateId: change.after.id, users});
      await batch.commit();
      return null;
    }

    // Log abort reasons
    if (before.status !== "aborted" && after.status === "aborted") {
      await db.collection("huntAborts").add({
        dateId: change.after.id,
        uidA: after.uidA,
        uidB: after.uidB,
        huntId: after.huntId,
        reason: after.abortReason || "unknown",
        ts: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.warn("Hunt aborted", {dateId: change.after.id, reason: after.abortReason});
    }

    return null;
  });
