/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {onCall, CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}
const db = getFirestore();

type SceneIn = {
  index: number;
  action?: string;
  animation?: string;
  speechType?: string;
  speech?: string;
  accent?: string;
  imageUrl?: string;
};

export interface CreateStoryboardJobInput {
  character?: string; // e.g., "cory"
  model?: string;     // e.g., "veo-3.0-generate-preview" (others accepted but not yet supported server-side)
  aspectRatio?: "9:16" | "16:9" | "1:1";
  scenes: SceneIn[];
}

function normalizeHttpsToGs(url?: string): string | undefined {
  if (!url) return undefined;
  const s = url.trim();
  const m1 = s.match(/^https?:\/\/firebasestorage\.googleapis\.com\/v0\/b\/([^/]+)\/o\/([^?]+)(?:\?.*)?$/i);
  if (m1) return `gs://${m1[1]}/${decodeURIComponent(m1[2])}`;
  const m2 = s.match(/^https?:\/\/storage\.googleapis\.com\/([^/]+)\/(.+)$/i);
  if (m2) return `gs://${m2[1]}/${m2[2]}`;
  const m3 = s.match(/^https?:\/\/([^/.]+)\.firebasestorage\.app\/(?:v0\/)?o\/([^?]+)(?:\?.*)?$/i);
  if (m3) return `gs://${m3[1]}.appspot.com/${decodeURIComponent(m3[2])}`;
  return undefined;
}

export const createStoryboardJob = onCall({
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
}, async (req: CallableRequest<CreateStoryboardJobInput>) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in");
  const body = req.data || ({} as CreateStoryboardJobInput);
  const scenes = Array.isArray(body.scenes) ? body.scenes : [];
  if (!scenes.length) throw new HttpsError("invalid-argument", "scenes required");

  const firstImageUrl = scenes.find((s) => typeof s.imageUrl === "string" && s.imageUrl!.length > 0)?.imageUrl as string | undefined;
  const imageGs = normalizeHttpsToGs(firstImageUrl);

  const jobRef = db.collection("adJobs").doc();

  // Build a light-weight structured prompt that mirrors our storyboard
  const dialogueLines = scenes.map((s) => s.speech).filter(Boolean) as string[];
  const prompt: any = {
    scene: "animation",
    style: "animated mascot short, playful, campus vibe",
    sequence: scenes.map((s) => {
      const descParts: string[] = [];
      if (s.action) descParts.push(s.action);
      if (s.animation) descParts.push(s.animation);
      const desc = descParts.join(" ").trim();
      const cam = (s.animation && /pan|tilt|dolly|crane|push|pull|handheld/i.test(s.animation)) ? s.animation : "controlled";
      return {shot: "storyboard_beat", camera: cam, description: desc || "beat"};
    }),
    dialogue: dialogueLines.length ? dialogueLines : undefined,
    format: body.aspectRatio || "9:16",
  };

  // Minimal VideoPromptV1 scaffold for downstream pipeline
  const promptV1 = {
    meta: {version: "1", createdAt: new Date().toISOString()},
    product: {description: (body.character || "mascot") + " storyboard", imageGsPath: imageGs},
    style: "creative_animation" as const,
    audio: {preference: dialogueLines.length ? "with_sound" : "no_sound"},
    cta: {key: "none", copy: ""},
    scenes: scenes.map((s, i) => ({id: `scene_${i+1}`, duration_s: 5, beats: [s.action, s.animation].filter(Boolean) as string[], shots: [{camera: "controlled", subject: "mascot", action: (s.action || "pose")}]})),
    output: {resolution: body.aspectRatio || "9:16", duration_s: Math.max(6, Math.min(scenes.length * 5, 20))},
  };

  await jobRef.set({
    uid,
    status: "queued",
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    archetype: (body.character || "cory").toLowerCase(),
    model: body.model || "veo-3.0-generate-preview",
    promptV1,
    veoPrompt: JSON.stringify(prompt),
    // Back-compat fields to help image resolution
    inputImagePath: imageGs || null,
    inputImageUrl: firstImageUrl || null,
  }, {merge: true});

  // Structured logs to debug pass-through
  try {
    console.log("[createStoryboardJob] enqueued", {
      jobId: jobRef.id,
      model: body.model || "veo-3.0-generate-preview",
      imageUrlPrefix: firstImageUrl ? String(firstImageUrl).slice(0, 60) : null,
      imageGs: imageGs || null,
      scenes: scenes.length,
      promptHead: JSON.stringify(prompt).slice(0, 180),
    });
  } catch { /* noop */ }

  return {jobId: jobRef.id, prompt, imageUrl: firstImageUrl, imageGsPath: imageGs};
});


