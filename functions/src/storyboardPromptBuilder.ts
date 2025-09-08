export type StoryboardPromptInput = {
  style?: string;          // e.g., "3D stylized", "illustrated"
  aspectRatio?: string;    // default "1:1"
  actionHint?: string;     // short clause; no dialogue text
  settingHint?: string;    // environment/props summary
  cameraHint?: string;     // e.g., "medium shot, slight low angle"
  lightingHint?: string;   // e.g., "warm stage lights"
  moodHint?: string;       // e.g., "energetic"
};

export function buildStoryboardPrompt(i: StoryboardPromptInput): string {
  const style = i.style || "3D stylized";
  const ar = i.aspectRatio || "1:1";
  const parts: string[] = [
    `Storyboard frame in a ${style} style.`,
    `Use the FIRST reference image as the strict character identity and rendering-style anchor.`,
    i.actionHint ? `Foreground: the referenced character ${i.actionHint}.` : `Foreground: include the referenced character clearly.`,
    i.settingHint ? `Background: ${i.settingHint}.` : `Background: coherent scene context.`,
    i.cameraHint ? `Cinematic camera: ${i.cameraHint}.` : "",
    i.lightingHint ? `Lighting: ${i.lightingHint}.` : "",
    i.moodHint ? `Mood: ${i.moodHint}.` : "",
    `Square composition (${ar}). Clean composition.`,
    `Do NOT generate any speech bubbles, captions, or on-image text/logos/watermarks.`,
  ];
  return parts.filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
}

export type EditPromptInput = {
  style?: string;          // target rendering style to preserve (e.g., "3D stylized")
  actionHint?: string;     // what the character should do
  animationHint?: string;  // camera/motion hint (used as nuance, not as on-image text)
  settingHint?: string;    // optional context, but we avoid scene layout
};

// Build a prompt that edits ONLY the provided image (text+image-to-image).
// Emphasis: preserve identity/style; modify pose/prop/outfit per script; no on-image text.
export function buildEditPromptFromScript(i: EditPromptInput): string {
  const style = i.style || "3D stylized";
  const parts: string[] = [
    `Storyboard frame edit. Using the provided image of the main character, edit the image while preserving the character's identity, proportions, outfit materials, and the ${style} rendering style.`,
    i.actionHint ? `Change the character's pose/action so the character ${i.actionHint}.` : "",
    i.animationHint ? `Subtle camera/energy hint: ${i.animationHint}.` : "",
    i.settingHint ? `Optional context: ${i.settingHint}.` : "",
    `Do not add any speech bubbles, captions, or on-image text. Keep background and lighting coherent with the original photo.`,
  ];
  return parts.filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
}


