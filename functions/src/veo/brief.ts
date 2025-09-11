/* eslint-disable max-len, @typescript-eslint/no-explicit-any */

export type AdFormat = "room_transformation" | "product_commercial";

export interface BrandInfo {
  name?: string;
  colors?: string[]; // hex or names
  voice?: string[]; // adjectives like "playful", "premium"
  logoGsPath?: string; // gs:// path
}

export interface AssetsInfo {
  productImageGsPath?: string; // required by generator
}

export interface AdBrief {
  productName?: string;
  category?: string;
  productTraits?: string[];
  audience?: string;
  desiredPerception?: string[]; // emotion/brand words
  proofMoment?: string; // one scene/value proof the user imagines
  styleWords?: string[]; // optional stylistic cues from user
  cta?: string | null;
  durationSeconds?: number | null;
  aspectRatio?: "16:9" | "9:16" | "1:1" | null;
  brand?: BrandInfo;
  assets?: AssetsInfo;
  // Derived/inferred
  inferredFormat?: AdFormat;
}

export const sanitizeWords = (arr?: string[]): string[] => {
  if (!Array.isArray(arr)) return [];
  return arr
    .map((s) => String(s || "").trim())
    .filter((s) => s.length > 0)
    .slice(0, 12);
};

export const withDefaults = (b: AdBrief): AdBrief => {
  const aspect = b.aspectRatio || "9:16"; // mobile-first default
  const duration = typeof b.durationSeconds === "number" && b.durationSeconds > 0 ? Math.min(b.durationSeconds, 20) : 15;
  return {
    ...b,
    aspectRatio: aspect,
    durationSeconds: duration,
    productTraits: sanitizeWords(b.productTraits),
    desiredPerception: sanitizeWords(b.desiredPerception),
    styleWords: sanitizeWords(b.styleWords),
    cta: b.cta ? String(b.cta).slice(0, 120) : null,
  };
};


