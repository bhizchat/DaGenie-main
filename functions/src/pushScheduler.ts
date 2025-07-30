/* eslint-disable max-len */
/**
 * Logic for automated, research-backed re-engagement push notifications.
 */

import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {initializeApp, applicationDefault, getApps} from "firebase-admin/app";

if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}

const db = getFirestore();
const messaging = getMessaging();

const DAY_MS = 24 * 60 * 60 * 1000;

export type Stage = "new_0_2d" | "week1" | "week2" | "active" | "dormant";

interface CadenceRule {
  stage: Stage;
  nextOffsetMs: number | null; // null → no automatic push
}

const CADENCE: Record<Stage, CadenceRule> = {
  new_0_2d: {stage: "new_0_2d", nextOffsetMs: 24 * DAY_MS},
  week1: {stage: "week1", nextOffsetMs: 2 * DAY_MS},
  week2: {stage: "week2", nextOffsetMs: 7 * DAY_MS},
  active: {stage: "active", nextOffsetMs: null},
  dormant: {stage: "dormant", nextOffsetMs: 14 * DAY_MS},
};

/**
 * Calculate the current lifecycle engagement stage for a user.
 *
 * @param {number} createdAt  Unix epoch ms when the account was created.
 * @param {number} lastOpenAt Unix epoch ms of the user’s most recent session_start.
 * @return {Stage} Lifecycle stage name used for cadence look-up.
 */
export function calculateStage(createdAt: number, lastOpenAt: number): Stage {
  const now = Date.now();
  const inactiveMs = now - lastOpenAt;
  const ageMs = now - createdAt;

  if (ageMs <= 2 * DAY_MS) return "new_0_2d";
  if (inactiveMs <= 7 * DAY_MS) return "week1";
  if (inactiveMs <= 14 * DAY_MS) return "week2";
  if (inactiveMs <= 14 * DAY_MS) return "active"; // keep compiler happy
  return "dormant";
}

/**
 * Compute timestamp for the next automatic push.
 *
 * @param {Stage} stage Stage to evaluate.
 * @return {number|null} Unix epoch ms or null when no push is scheduled.
 */
function nextPushTimestamp(stage: Stage): number | null {
  const rule = CADENCE[stage];
  if (rule.nextOffsetMs === null) return null;
  return Date.now() + rule.nextOffsetMs;
}

/** Firestore trigger: recalc stage & nextPushAt whenever a user doc is updated. */
export const onUserUpdate = onDocumentWritten("users/{uid}", async (event) => {
  if (!event.data) return;
  const after = event.data?.after?.data();
  if (!after) return; // deletion

  const {createdAt, lastOpenAt} = after;
  if (!createdAt || !lastOpenAt) return;

  const stage = calculateStage(createdAt, lastOpenAt);
  const next = nextPushTimestamp(stage);

  await event.data.after.ref.update({
    stage,
    nextPushAt: next === null ? FieldValue.delete() : next,
  });
});

/** Message templates per stage */
const TEMPLATES: Record<Stage, string[]> = {
  new_0_2d: [
    "Ready for your next date idea? 💖 Tap to generate one now!",
    "Need inspiration for date #2? We’ve got you covered!",
  ],
  week1: [
    "Weekend’s coming—need inspiration? Check today’s fresh plans!",
    "How about a surprise outing? New ideas await.",
  ],
  week2: [
    "We’ve added new ideas since you visited. Explore 🌟",
  ],
  active: [""], // not used – no automatic push
  dormant: [
    "We miss you! 50 bonus Romance Points if you create a plan this week.",
  ],
};

/**
 * Pick a random message template for a given stage.
 *
 * @param {Stage} stage Lifecycle stage.
 * @return {string|null} Message body or null when none defined.
 */
function pickTemplate(stage: Stage): string | null {
  const pool = TEMPLATES[stage] ?? [];
  if (!pool.length) return null;
  return pool[Math.floor(Math.random() * pool.length)];
}

/**
 * Cloud Scheduler entry-point – runs every 5 min.
 * Sends notifications whose `nextPushAt` is due and reschedules.
 */
export const scheduledPushes = onSchedule("every 5 minutes", async () => {
  const now = Date.now();
  const snap = await db.collection("users")
    .where("nextPushAt", "<=", now)
    .where("fcmToken", "!=", null)
    .limit(500)
    .get();

  if (snap.empty) return;

  const batch = db.batch();
  const sendTasks: Promise<void>[] = [];

  snap.forEach((doc) => {
    const data = doc.data();
    const token = data.fcmToken as string;
    const stage = data.stage as Stage;

    const body = pickTemplate(stage);
    if (!body) return;

    // Build APNs / FCM message
    sendTasks.push(messaging.send({
      token,
      notification: {
        title: "DateGenie",
        body,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
      data: {
        deepLink: "dategenie://home", // Adjust to real deep-link
      },
    }).then(() => {
      logger.info(`🔔 Sent push to ${doc.id}`);
    }).catch((err) => {
      logger.warn(`Failed push to ${doc.id}`, err);
    }));

    // Schedule next push (or clear) per cadence
    const next = nextPushTimestamp(stage);
    batch.update(doc.ref, {
      lastPushAt: now,
      nextPushAt: next === null ? FieldValue.delete() : next,
    });
  });

  await Promise.all(sendTasks);
  await batch.commit();
});
