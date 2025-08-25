/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {onCall, CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {AdBrief} from "./brief";
import {inferFormatWithScores} from "./inferFormat";
import {buildRoomPrompt} from "./buildRoomPrompt";
import {buildProductPrompt} from "./buildProductPrompt";
import {fromRoomPrompt, fromProductPrompt, VideoPromptV1} from "./translateToV1";
import {startVeoForJobCore} from "./startVeoForJob";

if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}
const db = getFirestore();
try {
  // Silence undefined Firestore fields across admin versions
  (db as any).settings({ignoreUndefinedProperties: true});
} catch (e) {
  console.warn("[createAdFromConversation] ignoreUndefinedProperties not supported", (e as Error)?.message);
}

function pruneUndefined<T>(obj: T): T {
  return JSON.parse(JSON.stringify(obj)) as T;
}

export interface CreateFromConversationInput {
  messages: Array<{role: "user"|"assistant"; content: string}>;
  assets?: {productImageGsPath?: string; logoGsPath?: string; brandColors?: string[]};
  aspectRatio?: "9:16" | "16:9" | "1:1";
  model?: "veo-3.0-fast-generate-preview" | "veo-3.0-generate-preview";
}

export const createAdFromConversation = onCall({
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
}, async (req: CallableRequest<CreateFromConversationInput>) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in");
  const body = req.data || {} as CreateFromConversationInput;
  const messages = (body.messages || []).filter((m) => typeof m?.content === "string");
  if (!messages.length) throw new HttpsError("invalid-argument", "messages required");

  // Store job early
  const jobRef = db.collection("adJobs").doc();
  await jobRef.set({
    uid, status: "structuring", createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
  }, {merge: true});

  // Convert conversation → brief via local heuristic prompt (reuse existing callable if preferred later)
  // Here, do a minimal extraction inline to avoid another round trip (client can also call conversationToBrief first).
  const firstUser = messages.find((m) => m.role === "user")?.content || "";
  const brief: AdBrief = {
    productName: undefined,
    category: undefined,
    productTraits: [],
    audience: undefined,
    desiredPerception: [],
    proofMoment: undefined,
    styleWords: [],
    cta: null,
    durationSeconds: null,
    aspectRatio: body.aspectRatio || "9:16",
    brand: {},
    assets: {productImageGsPath: body.assets?.productImageGsPath},
  };
  // naive cues
  if (/candle|sofa|lamp|blanket|home|room/i.test(firstUser)) brief.category = "home decor";
  if (/phone|laptop|headset|watch|camera|device|gadget/i.test(firstUser)) brief.category = "electronics";
  // Perception words
  const vibes = firstUser.match(/(cozy|calm|premium|luxurious|playful|bold|excited|trustworthy|modern|minimal)/gi) || [];
  brief.desiredPerception = Array.from(new Set(vibes.map((v) => v.toLowerCase())));

  // Infer format and build prompt
  const {format, roomScore, prodScore} = inferFormatWithScores(brief);
  brief.inferredFormat = format;
  let prompt: any;
  let promptV1: VideoPromptV1 | null = null;
  if (format === "room_transformation") {
    prompt = buildRoomPrompt(brief);
    promptV1 = fromRoomPrompt(brief, prompt);
  } else {
    prompt = buildProductPrompt(brief);
    promptV1 = fromProductPrompt(brief, prompt);
  }

  const safeBrief = pruneUndefined(brief);
  const safePrompt = pruneUndefined(prompt);
  const safePromptV1 = pruneUndefined(promptV1);

  const hasImage = !!(safePromptV1 as any)?.product?.imageGsPath && typeof (safePromptV1 as any)?.product?.imageGsPath === "string";

  if (!hasImage) {
    // Fail fast: no image provided → mark job as error to avoid indefinite "generating"
    try {
      console.log("[createAdFromConversation] auto_start=false reason=missing_image", {format});
      await jobRef.set({
        status: "error",
        error: "image_required",
        brief: safeBrief,
        inferredFormat: format,
        veoPrompt: safePrompt,
        promptV1: safePromptV1,
        model: body.model || "veo-3.0-fast-generate-preview",
        updatedAt: Timestamp.now(),
      }, {merge: true});
      await db.collection("analyticsEvents").add({
        uid,
        event: "ad_job_not_started",
        jobId: jobRef.id,
        reason: "missing_image",
        format,
        createdAt: Date.now(),
      });
    } catch (e) {
      console.error("[createAdFromConversation] failfast missing_image error", (e as Error)?.message);
    }
    return {jobId: jobRef.id, brief, inferredFormat: format, error: "image_required"};
  }

  await jobRef.set({
    status: "generating",
    brief: safeBrief,
    inferredFormat: format,
    veoPrompt: safePrompt,
    promptV1: safePromptV1,
    model: body.model || "veo-3.0-fast-generate-preview",
    updatedAt: Timestamp.now(),
  }, {merge: true});

  // Structured logs + analytics for format decision
  try {
    console.log("[createAdFromConversation] format_decision", {format, roomScore, prodScore, category: brief.category, aspect: brief.aspectRatio});
    await db.collection("analyticsEvents").add({
      uid,
      event: "ad_format_decided",
      jobId: jobRef.id,
      format,
      roomScore,
      prodScore,
      category: brief.category || null,
      createdAt: Date.now(),
    });
  } catch (e) {
    console.error("[createAdFromConversation] format analytics error", (e as Error)?.message);
  }

  // Kick off generation in the background (image presence already validated)
  if (promptV1?.product?.imageGsPath) {
    try {
      console.log("[createAdFromConversation] auto_start=true", {format});
      await db.collection("analyticsEvents").add({uid, event: "ad_job_structured", jobId: jobRef.id, format, createdAt: Date.now()});
      await db.collection("analyticsEvents").add({uid, event: "ad_job_auto_start", jobId: jobRef.id, format, createdAt: Date.now()});
      // fire-and-forget; client can also call startVeoForJob explicitly if preferred
      // eslint-disable-next-line @typescript-eslint/no-floating-promises
      startVeoForJobCore(uid, jobRef.id);
    } catch (err) {
      // Best-effort analytics; do not fail the callable for analytics issues
      console.error("[createAdFromConversation] background start error", (err as Error)?.message);
    }
  }

  return {jobId: jobRef.id, brief, inferredFormat: format, veoPrompt: prompt, promptV1};
});


