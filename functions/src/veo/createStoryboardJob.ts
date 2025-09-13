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
  selectedIndex?: number;
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

  // Isolation: pick the active scene (selected), do not fall back to other scenes' data
  const selectedIdx: number | undefined = (typeof (body as any).selectedIndex === "number" ? (body as any).selectedIndex : undefined);
  const activeScene: SceneIn = (Number.isInteger(selectedIdx) ? (scenes.find((s) => s.index === selectedIdx) || scenes[0]) : scenes[0]);
  // Require the image from the active scene only
  const selectedImageUrl = (typeof activeScene?.imageUrl === "string" && activeScene.imageUrl!.trim().length > 0) ? activeScene.imageUrl!.trim() : undefined;
  const anchorImageUrl = selectedImageUrl; // no cross-scene fallback to preserve isolation
  const imageGs = normalizeHttpsToGs(anchorImageUrl);
  if (!imageGs) {
    throw new HttpsError("failed-precondition", "scene_image_required");
  }

  const jobRef = db.collection("adJobs").doc();

  // Build a per-scene structured prompt (one sequence item, ≤1 dialogue line)
  const descParts: string[] = [];
  if (activeScene.action) descParts.push(activeScene.action);
  if (activeScene.animation) descParts.push(activeScene.animation);
  const desc = descParts.join(" ").trim();
  const cam = (activeScene.animation && /pan|tilt|dolly|crane|push|pull|handheld|zoom/i.test(activeScene.animation)) ? activeScene.animation : "controlled";
  const singleLine = (typeof activeScene.speech === "string" && activeScene.speech!.trim().length > 0) ? activeScene.speech!.trim() : undefined;
  const prompt: any = {
    scene: "animation",
    style: "animated mascot short, playful, campus vibe",
    sequence: [{shot: "storyboard_beat", camera: cam, description: (desc || "beat")}],
    dialogue: singleLine ? [singleLine] : undefined,
    accent: (typeof activeScene.accent === "string" && activeScene.accent!.trim().length > 0) ? activeScene.accent!.trim() : undefined,
    format: body.aspectRatio || "9:16",
  };

  // Minimal VideoPromptV1 scaffold for downstream pipeline (single-scene)
  const promptV1 = {
    meta: {version: "1", createdAt: new Date().toISOString()},
    product: {description: (body.character || "mascot") + " storyboard", imageGsPath: imageGs},
    style: "creative_animation" as const,
    audio: {preference: (singleLine ? "with_sound" : "no_sound")},
    cta: {key: "none", copy: ""},
    scenes: [{id: `scene_${(Number.isInteger(selectedIdx) ? (selectedIdx as number) : activeScene.index) ?? 0}`, duration_s: 5, beats: [activeScene.action, activeScene.animation].filter(Boolean) as string[], shots: [{camera: "controlled", subject: "mascot", action: (activeScene.action || "pose")}]}],
    output: {resolution: body.aspectRatio || "9:16", duration_s: 5},
  };

  await jobRef.set({
    uid,
    status: "queued",
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    archetype: (body.character || "cory").toLowerCase(),
    model: body.model || "veo-3.0-generate-preview",
    // Storyboard-only tagging and prompt field to avoid ad-template collisions
    mode: "storyboard",
    templateId: "storyboard",
    promptV1,
    storyboardPrompt: JSON.stringify(prompt),
    // Back-compat fields to help image resolution
    inputImagePath: imageGs || null,
    inputImageUrl: anchorImageUrl || null,
    honoredSelection: {
      selectedIndex: (typeof selectedIdx === "number" ? selectedIdx : (activeScene?.index ?? null)),
      anchorSource: (selectedImageUrl ? "selected" : "none"),
    },
    debug: { isolationContract: true, promptHead: JSON.stringify(prompt).slice(0, 180) },
  }, {merge: true});

  // Structured logs to debug pass-through
  try {
    console.log("[createStoryboardJob] enqueued", {
      jobId: jobRef.id,
      model: body.model || "veo-3.0-generate-preview",
      imageUrlPrefix: anchorImageUrl ? String(anchorImageUrl).slice(0, 60) : null,
      imageGs: imageGs || null,
      scenes: scenes.length,
      selectedIndex: (typeof selectedIdx === "number" ? selectedIdx : null),
      anchorSource: (selectedImageUrl ? "selected" : "none"),
      promptHead: JSON.stringify(prompt).slice(0, 180),
      mode: "storyboard",
    });
  } catch { /* noop */ }

  return {jobId: jobRef.id, prompt, imageUrl: anchorImageUrl, imageGsPath: imageGs};
});


