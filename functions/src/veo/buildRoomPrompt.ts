/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {AdBrief, withDefaults} from "./brief";

export type RoomPrompt = {
  description: string;
  style: string;
  camera: string;
  lighting: string;
  room: string;
  elements: string[];
  motion: string;
  ending: string;
  text: string;
  keywords: string[];
};

export function buildRoomPrompt(input: AdBrief): RoomPrompt {
  const b = withDefaults(input);
  const brandWords = (b.desiredPerception || []).join(", ");
  const style = (b.styleWords && b.styleWords.length) ?
    `${b.styleWords.join(", ")}` :
    (brandWords ? `photorealistic cinematic, ${brandWords}` : "photorealistic cinematic");

  const roomDesc = b.proofMoment?.trim() || "blank room transforms into a brand-aligned space";
  const product = b.productName || "the product";

  const description = `Photorealistic cinematic shot of an empty room. ${product} acts as a catalyst. Items appear mid-air and snap into place to form a ${brandWords || "cohesive"} space. No text.`;
  const camera = "fixed wide angle, front-facing for symmetrical reveal";
  const lighting = brandWords.includes("cozy") || brandWords.includes("warm") ?
    "soft daylight with warm golden tones" :
    "soft diffused light with gentle highlights";
  const room = roomDesc;
  const elements: string[] = [
    `${product} as the transformation trigger`,
    "textiles gaining warmer highlights",
    "surface objects settling into tasteful arrangement",
    "subtle decor accents appearing (books, plant, lamp)",
  ];
  const motion = `${product} triggers a clean hyper-lapse; items assemble mid-air and settle precisely`;
  const ending = "camera holds on fully transformed room; no container visible";
  const text = b.cta ? b.cta : "none";
  const keywords = [b.aspectRatio || "9:16", "room transformation", "photorealistic", ...(brandWords ? [brandWords] : [])];

  return {description, style, camera, lighting, room, elements, motion, ending, text, keywords};
}


