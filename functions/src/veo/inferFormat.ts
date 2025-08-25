/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {AdBrief, AdFormat} from "./brief";

const ROOM_HINTS = [
  "room", "living room", "bedroom", "interior", "cozy", "ambience", "ambiance", "home",
  "transform", "transformation",
  "sofa", "chair", "lamp", "rug", "curtains", "shelves",
];

const PRODUCT_HINTS = [
  "feature", "features", "close-up", "macro", "precision", "rotate", "turntable", "unbox", "unboxing",
  "hero product", "studio", "void", "showroom", "wireframe", "reveal", "logo",
  "tech", "gadget", "device", "bottle", "perfume", "drink", "food",
];

const CATEGORY_ROOM = ["furniture", "home decor", "lighting", "bedding", "interior", "home fragrance"];
const CATEGORY_PRODUCT = ["electronics", "tech", "beauty", "perfume", "beverage", "food", "toys", "tools"];

export function inferFormatWithScores(brief: AdBrief): { format: AdFormat; roomScore: number; prodScore: number } {
  const text = [
    brief.productName,
    brief.category,
    ...(brief.productTraits || []),
    brief.proofMoment,
    ...(brief.styleWords || []),
    ...(brief.desiredPerception || []),
  ].join(" ").toLowerCase();

  // Category heuristics first
  if (brief.category) {
    const cat = brief.category.toLowerCase();
    if (CATEGORY_ROOM.some((k) => cat.includes(k))) return {format: "room_transformation", roomScore: 1, prodScore: 0};
    if (CATEGORY_PRODUCT.some((k) => cat.includes(k))) return {format: "product_commercial", roomScore: 0, prodScore: 1};
  }

  // Keyword scoring
  let roomScore = 0;
  let prodScore = 0;
  ROOM_HINTS.forEach((k) => {
    if (text.includes(k)) roomScore++;
  });
  PRODUCT_HINTS.forEach((k) => {
    if (text.includes(k)) prodScore++;
  });

  if (roomScore > prodScore) return {format: "room_transformation", roomScore, prodScore};
  if (prodScore > roomScore) return {format: "product_commercial", roomScore, prodScore};

  // Ambiguous: default to product commercial (safer, general)
  return {format: "product_commercial", roomScore, prodScore};
}

export function inferFormat(brief: AdBrief): AdFormat {
  const {format} = inferFormatWithScores(brief);
  return format;
}


