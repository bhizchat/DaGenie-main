/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {AdBrief} from "./brief";
import {RoomPrompt} from "./buildRoomPrompt";
import {ProductPrompt, ProductPromptSequence, ProductPromptSetPiece} from "./buildProductPrompt";

export type VideoPromptV1 = {
  meta: { version: string; createdAt: string };
  product: { description: string; imageGsPath?: string };
  style: "cinematic" | "creative_animation";
  audio: { preference: "with_sound" | "no_sound"; voiceoverScript?: string; sfxHints?: string[] };
  cta: { key: string; copy: string };
  scenes: Array<{ id: string; duration_s: number; beats: string[]; shots: Array<{ camera: string; subject: string; action: string; textOverlay?: string }> }>;
  output: { resolution: string; duration_s: number };
};

const pickStyle = (brief: AdBrief): "cinematic" | "creative_animation" => {
  const all = ((brief.styleWords || []).join(" ") + " " + (brief.desiredPerception || []).join(" ")).toLowerCase();
  if (/animation|cartoon|playful/.test(all)) return "creative_animation";
  return "cinematic";
};

export function fromRoomPrompt(brief: AdBrief, rp: RoomPrompt): VideoPromptV1 {
  const duration = Math.max(6, Math.min(brief.durationSeconds || 15, 20));
  const style = pickStyle(brief);
  const productDesc = brief.productName || brief.category || "product";
  return {
    meta: {version: "1", createdAt: new Date().toISOString()},
    product: {description: productDesc, imageGsPath: brief.assets?.productImageGsPath},
    style,
    audio: {preference: "no_sound"},
    cta: {key: brief.cta ? "cta" : "none", copy: brief.cta || ""},
    scenes: [
      {
        id: "room_transform",
        duration_s: duration,
        beats: [rp.description, rp.motion, rp.ending].filter(Boolean),
        shots: [
          {camera: rp.camera, subject: productDesc, action: "trigger subtle transformation", textOverlay: brief.cta || undefined},
        ],
      },
    ],
    output: {resolution: (brief.aspectRatio || "9:16"), duration_s: duration},
  };
}

export function fromProductPrompt(brief: AdBrief, pp: ProductPrompt): VideoPromptV1 {
  const duration = Math.max(6, Math.min(brief.durationSeconds || 15, 20));
  const style = pickStyle(brief);
  const productDesc = brief.productName || brief.category || "product";

  // Sequence subtype
  if ((pp as ProductPromptSequence).sequence) {
    const seq = pp as ProductPromptSequence;
    const beats: string[] = [];
    const shots: Array<{camera: string; subject: string; action: string; textOverlay?: string}> = [];
    seq.sequence.forEach((s: any) => {
      const desc = s.description || s.transition || s.motion || s.closeup || s.ending || "";
      if (desc) beats.push(desc);
      const cam = s.camera || "controlled";
      if (s.shot || s.closeup || s.motion) {
        shots.push({camera: cam, subject: productDesc, action: (s.shot || s.motion || s.closeup || "reveal details")});
      }
    });
    return {
      meta: {version: "1", createdAt: new Date().toISOString()},
      product: {description: productDesc, imageGsPath: brief.assets?.productImageGsPath},
      style,
      audio: {preference: brief.cta ? "with_sound" : "no_sound"},
      cta: {key: brief.cta ? "cta" : "none", copy: brief.cta || ""},
      scenes: [{id: "product_sequence", duration_s: duration, beats, shots}],
      output: {resolution: (brief.aspectRatio || "9:16"), duration_s: duration},
    };
  }

  // Set‑piece subtype
  const sp = pp as ProductPromptSetPiece;
  const beats = [sp.description, sp.motion, sp.ending].filter(Boolean);
  const shots = [
    {camera: sp.camera, subject: productDesc, action: sp.motion || "reveal"},
  ];
  return {
    meta: {version: "1", createdAt: new Date().toISOString()},
    product: {description: productDesc, imageGsPath: brief.assets?.productImageGsPath},
    style,
    audio: {preference: brief.cta ? "with_sound" : "no_sound"},
    cta: {key: brief.cta ? "cta" : "none", copy: brief.cta || ""},
    scenes: [{id: "product_setpiece", duration_s: duration, beats, shots}],
    output: {resolution: (brief.aspectRatio || "9:16"), duration_s: duration},
  };
}


