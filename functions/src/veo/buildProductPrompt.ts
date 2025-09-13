/* eslint-disable max-len, @typescript-eslint/no-explicit-any */

export function buildStructuredPromptFromTemplate(category: string, productName?: string): { text: string; templateId: string } {
  const name = (productName || "product").trim();
  const cat = String(category || "").toLowerCase();
  if (cat.includes("electronics")) {
    const text = [
      `Futuristic minimal photoreal showroom for: ${name}.`,
      "Begin in softly lit void with reflective gradients; clean architecture phases in.",
      "Energy ripple or crate moment that constructs a wireframe silhouette, then dissolves into the real device.",
      "Macro glide highlights glass/metal curvature and sensors; volumetric beams across lens.",
      "End on centered hero frame; no text.",
    ].join(" ");
    return {text, templateId: "electronics_showroom_struct_v1"};
  }
  if (cat.includes("food") || cat.includes("beverage")) {
    const text = [
      `Crave cinematic black void for: ${name}.`,
      "Start with macro textures (fizz/steam/ice). A glowing wave reveals the product silhouette which fills with liquid.",
      "Condensation and chill fog build; hold a centered hero on reflective surface.",
      "No on-screen text.",
    ].join(" ");
    return {text, templateId: "food_crave_struct_v1"};
  }
  if (cat.includes("health") || cat.includes("beauty") || cat.includes("personal")) {
    const text = [
      `Luxury pastel cinematic for: ${name}.`,
      "A floating bloom/silk cradle opens to reveal the product; silk ribbons lift gently.",
      "Soft golden top-light; warm ambient fill; petals drift; end on soft hero hold.",
      "No text.",
    ].join(" ");
    return {text, templateId: "beauty_pastel_struct_v1"};
  }
  // default apparel
  const text = [
    `Fashion minimalism for: ${name}.`,
    "Fabric close-ups ripple; color swatches morph; garment rotates in clean void.",
    "Camera: slow parallax orbit; Lighting: studio white; No text.",
  ].join(" ");
  return {text, templateId: "apparel_minimal_struct_v1"};
}

/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {AdBrief, withDefaults} from "./brief";

export type ProductPromptSequence = {
  scene?: "animation";
  style: string;
  sequence: Array<Record<string, string>>;
  audio?: { soundtrack?: string; sfx?: string[] };
  dialogue?: string[];
  ending?: string;
  format?: string;
  text_overlay?: string | "none";
  keywords?: string[];
};

export type ProductPromptSetPiece = {
  description: string;
  style: string;
  camera: string;
  lighting: string;
  environment: string;
  elements: string[];
  motion: string;
  ending: string;
  audio?: { music?: string; sfx?: string[] };
  dialogue?: string[];
  text_overlay?: string | "none";
  format?: string;
  keywords?: string[];
};

export type ProductPrompt = ProductPromptSequence | ProductPromptSetPiece;

export function buildProductPrompt(input: AdBrief): ProductPrompt {
  const b = withDefaults(input);
  const brandWords = (b.desiredPerception || []).join(", ");
  const styleBase = (b.styleWords && b.styleWords.length) ?
    `${b.styleWords.join(", ")}` :
    (brandWords ? `photorealistic cinematic, ${brandWords}` : "photorealistic cinematic");

  const product = b.productName || "the product";
  const category = (b.category || "").toLowerCase();

  // Heuristic: tech/precision/luxury → sequence; food/beauty → set-piece
  const useSequence = /tech|device|electronics|watch|headset|phone|laptop|camera|luxury|premium/.test(category) ||
    /sleek|minimal|precision|futuristic/.test((b.styleWords || []).join(" ").toLowerCase());

  if (useSequence) {
    const seq: ProductPromptSequence = {
      scene: "animation",
      style: `${styleBase}, seamless transitions, controlled studio lighting`,
      sequence: [
        {shot: "Logo/mark intro", camera: "slow drift-in", description: `Begin in a clean void; abstract cues hint at ${product}.`},
        {transition: "A precise energy ripple morphs forms into the product silhouette."},
        {shot: "Hero form", camera: "continuous motion", description: `Contours of ${product} rise from ripples; environment phases into a minimal showroom.`},
        {motion: "Subtle rotations and light passes reveal material quality."},
        {closeup: "Macro glide to highlight craftsmanship and key surfaces."},
        {ending: `Pull back to centered hero frame on ${product}.`},
      ],
      audio: {soundtrack: brandWords ? `${brandWords} minimal ambience` : "minimal ambience", sfx: ["subtle ripple", "soft chimes"]},
      // No default narrator lines; dialogue should come from explicit storyboard or brief
      dialogue: [],
      ending: `Clean hero frame; ${b.cta ? `implied CTA vibe: ${b.cta}` : "no text"}.`,
      text_overlay: b.cta ? b.cta : "none",
      format: b.aspectRatio || "9:16",
      keywords: [b.aspectRatio || "9:16", "product reveal", "photorealistic", ...(brandWords ? [brandWords] : [])],
    };
    return seq;
  }

  const setPiece: ProductPromptSetPiece = {
    description: `A cinematic product-focused reveal for ${product}. Elements materialize with precise motion; frame remains elegant and clear. No on-screen text.`,
    style: `${styleBase}`,
    camera: "macro start, smooth dolly pullback to hero frame",
    lighting: "controlled studio glow with tasteful rim lights",
    environment: "clean void with subtle gradients and reflective ground plane",
    elements: [
      `${product} hero object (clean, instantly recognizable form)`,
      "energy cues or particles that cohere into form",
      "condensation/texture/finish details appropriate to category",
    ],
    motion: `energy cues cohere into outline; ${product} takes solid form; atmosphere settles`,
    ending: `fully formed ${product} centered and glowing softly; ${b.cta ? `CTA vibe: ${b.cta}` : "no text"}`,
    audio: {music: brandWords ? `${brandWords} ambient pulse` : "ambient pulse", sfx: ["subtle texture fizz"]},
    // No default narrator lines; dialogue should come from explicit storyboard or brief
    dialogue: [],
    text_overlay: b.cta ? b.cta : "none",
    format: b.aspectRatio || "9:16",
    keywords: [b.aspectRatio || "9:16", "product focus", "photorealistic", ...(brandWords ? [brandWords] : [])],
  };
  return setPiece;
}


