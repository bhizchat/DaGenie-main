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
  sceneId?: string;
};

export interface CreateStoryboardJobV2Input {
  character?: string;
  model?: string;
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

export const createStoryboardJobV2 = onCall({
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "1GiB",
}, async (req: CallableRequest<CreateStoryboardJobV2Input>) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in");
  const body = req.data || ({} as CreateStoryboardJobV2Input);
  const scenes = Array.isArray(body.scenes) ? body.scenes : [];
  if (!scenes.length) throw new HttpsError("invalid-argument", "scenes required");

  // Active scene selection (by index for now)
  const selectedIdx: number | undefined = (typeof (body as any).selectedIndex === "number" ? (body as any).selectedIndex : undefined);
  const activeScene: SceneIn = (Number.isInteger(selectedIdx) ? (scenes.find((s) => s.index === selectedIdx) || scenes[0]) : scenes[0]);

  // Require the image from the active scene only
  const selectedImageUrl = (typeof activeScene?.imageUrl === "string" && activeScene.imageUrl!.trim().length > 0) ? activeScene.imageUrl!.trim() : undefined;
  const imageGs = normalizeHttpsToGs(selectedImageUrl);
  if (!imageGs) throw new HttpsError("failed-precondition", "scene_image_required");

  const jobRef = db.collection("adJobs").doc();

  // Coerce AR to allowed values for Veo parameters later
  const preferred = body.aspectRatio || "9:16";
  const safeFormat: "9:16" | "16:9" = (preferred === "16:9" ? "16:9" : preferred === "9:16" ? "9:16" : "9:16");

  // Build single-scene prompt JSON
  const descParts: string[] = [];
  if (activeScene.action) descParts.push(activeScene.action);
  if (activeScene.animation) descParts.push(activeScene.animation);
  const desc = descParts.join(" ").trim();
  const cam = (activeScene.animation && /pan|tilt|dolly|crane|push|pull|handheld|zoom/i.test(activeScene.animation)) ? activeScene.animation : "controlled";
  const singleLine = (typeof activeScene.speech === "string" && activeScene.speech!.trim().length > 0) ? activeScene.speech!.trim() : undefined;
  const storyboardPrompt: any = {
    scene: "animation",
    style: "animated mascot short, playful, campus vibe",
    sequence: [{shot: "storyboard_beat", camera: cam, description: (desc || "beat")}],
    dialogue: singleLine ? [singleLine] : undefined,
    accent: (typeof activeScene.accent === "string" && activeScene.accent!.trim().length > 0) ? activeScene.accent!.trim() : undefined,
    format: safeFormat,
  };

  const sceneId = activeScene.sceneId || `scene_${(Number.isInteger(selectedIdx) ? (selectedIdx as number) : activeScene.index) ?? 0}`;

  const promptV1 = {
    meta: {version: "1", createdAt: new Date().toISOString()},
    product: {description: (body.character || "mascot"), imageGsPath: imageGs},
    style: "creative_animation" as const,
    audio: {preference: (singleLine ? "with_sound" : "no_sound")},
    cta: {key: "none", copy: ""},
    scenes: [{id: sceneId, duration_s: 5, beats: [activeScene.action, activeScene.animation].filter(Boolean) as string[], shots: [{camera: "controlled", subject: "mascot", action: (activeScene.action || "pose")}]}],
    output: {resolution: safeFormat, duration_s: 5},
  };

  await jobRef.set({
    uid,
    status: "pending",
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    mode: "storyboard",
    templateId: "storyboard_v2",
    archetype: (body.character || "cory").toLowerCase(),
    model: body.model || "veo-3.0-generate-001",
    promptV1,
    storyboardPrompt: JSON.stringify(storyboardPrompt),
    inputImagePath: imageGs,
    inputImageUrl: selectedImageUrl || null,
    honoredSelection: { selectedIndex: (typeof selectedIdx === "number" ? selectedIdx : (activeScene?.index ?? null)), sceneId },
    debug: {isolationContract: true, promptHead: JSON.stringify(storyboardPrompt).slice(0, 180)},
  }, {merge: true});

  // Flip to queued after identifiers are in place (race-safe for background watchers)
  await jobRef.update({ status: "queued", updatedAt: Timestamp.now() });

  try {
    console.log("[createStoryboardJobV2] enqueued", {
      jobId: jobRef.id,
      model: body.model || "veo-3.0-generate-001",
      imageUrlPrefix: selectedImageUrl ? String(selectedImageUrl).slice(0, 60) : null,
      imageGs,
      selectedIndex: (typeof selectedIdx === "number" ? selectedIdx : null),
      mode: "storyboard",
      promptHead: JSON.stringify(storyboardPrompt).slice(0, 180),
    });
  } catch {}

  return {jobId: jobRef.id, prompt: storyboardPrompt, imageUrl: selectedImageUrl, imageGsPath: imageGs};
});


