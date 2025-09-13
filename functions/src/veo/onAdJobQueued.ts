/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {defineSecret} from "firebase-functions/params";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {startVeoForJobCore} from "./startVeoForJob";

const VEO_API_KEY = defineSecret("VEO_API_KEY");

if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}
const db = getFirestore();

export const onAdJobQueued = onDocumentWritten({
  region: "us-central1",
  document: "adJobs/{jobId}",
  timeoutSeconds: 540,
  memory: "1GiB",
  secrets: [VEO_API_KEY],
}, async (event) => {
  const jobId = event.params.jobId as string;
  const before = event.data?.before?.data() as any | undefined;
  const after = event.data?.after?.data() as any | undefined;
  if (!after) return;

  // Hard guard: skip entirely for storyboard jobs or docs containing storyboard fields or storyboard lease
  if (
    String(after.mode).toLowerCase() === "storyboard" ||
    String(after.templateId || "").toLowerCase().startsWith("storyboard") ||
    typeof after.storyboardPrompt === "string" ||
    String(after?.processing?.startedBy || "").toLowerCase() === "storyboard_v2"
  ) {
    try { console.log("[onAdJobQueued] skip storyboard", {jobId}); } catch {}
    return;
  }

  // Ignore terminal states
  if (after.status === "ready" || after.status === "error") return;

  // Only act when the job is ready to start or has been re-queued
  const becameQueued = after.status === "queued";
  const wasQueued = before?.status === "queued";

  // If already processing, do nothing
  if (after.processing?.startedAt) return;

  // Require minimal fields
  const uid = after.uid as string | undefined;
  const hasPromptV1 = !!after.promptV1;
  const imageFromPrompt = after.promptV1?.product?.imageGsPath;
  const imageFromLegacy = after.inputImagePath;
  const hasAnyImage = (typeof imageFromPrompt === "string" && imageFromPrompt.startsWith("gs://")) || (typeof imageFromLegacy === "string" && imageFromLegacy.startsWith("gs://"));
  try {
    console.log("[onAdJobQueued] readiness", {jobId, hasPromptV1, hasAnyImage, imageFromPromptPrefix: typeof imageFromPrompt === "string" ? String(imageFromPrompt).slice(0, 24) : undefined, imageFromLegacyPrefix: typeof imageFromLegacy === "string" ? String(imageFromLegacy).slice(0, 24) : undefined});
  } catch (e) {
    console.debug("[onAdJobQueued] readiness log skipped", (e as Error)?.message);
  }
  if (!uid || !hasPromptV1 || !hasAnyImage) return;

  if (!becameQueued && !wasQueued) return;

  const jobRef = db.collection("adJobs").doc(jobId);

  // Idempotent claim via transaction
  let claimed = false;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(jobRef);
    const data = snap.data() as any;
    if (data?.processing?.startedAt || data?.status === "ready" || data?.status === "error") return;
    tx.set(jobRef, {processing: {startedAt: Timestamp.now()}}, {merge: true});
    claimed = true;
  });

  if (!claimed) return;

  console.log("[onAdJobQueued] starting core for", {jobId});
  try {
    await startVeoForJobCore(uid!, jobId);
  } catch (e: any) {
    console.error("[onAdJobQueued] core error", e?.message);
  }
});


