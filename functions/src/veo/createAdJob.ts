/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {onCall, CallableRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}
const db = getFirestore();

export interface CreateAdJobInput {
  inputImagePath?: string; // gs:// path owned by caller
  transcript: string; // conversation text (wake phrase already stripped on client if present)
  aspectRatio?: "16:9";
  model?: "veo-3.0-fast-generate-preview" | "veo-3.0-generate-preview";
}

export const createAdJob = onCall({
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
  secrets: [OPENAI_API_KEY],
}, async (req: CallableRequest<CreateAdJobInput>) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("unauthenticated");
  const body = req.data || {} as CreateAdJobInput;
  const transcript = (body.transcript || "").trim();
  if (!transcript) throw new Error("missing transcript");

  const aspectRatio = body.aspectRatio || "16:9";
  const model = body.model || "veo-3.0-fast-generate-preview";

  // Basic ownership validation for image if provided
  if (body.inputImagePath) {
    if (!body.inputImagePath.startsWith("gs://")) {
      throw new Error("inputImagePath must be a gs:// path");
    }
    // Optional: ensure path contains uid segment
    if (!body.inputImagePath.includes(`/${uid}/`)) {
      throw new Error("image path not owned by user");
    }
  }

  // Compose prompt via internal builder (callable HTTP within the same project is simpler than importing OpenAI here)
  // For now, store the raw transcript and leave prompt fields empty; a follow-up worker can enrich.
  const jobRef = db.collection("adJobs").doc();
  await jobRef.set({
    uid,
    status: "generating",
    inputImagePath: body.inputImagePath || null,
    conversationTranscript: transcript,
    promptStructured: null,
    veoPrompt: null,
    negativePrompt: "",
    aspectRatio,
    model,
    operationName: null,
    videoPath: null,
    error: null,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  }, {merge: true});

  // TODO: trigger prompt build + Veo start via Firestore trigger or direct call (added in Phase 2).

  return {jobId: jobRef.id};
});


