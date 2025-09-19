export type EditPromptInput = {
  style?: string;
  actionHint?: string;
  animationHint?: string;
  dialogueText?: string;
  speechType?: string; // "Dialogue" or "Narration"
  speakerSlot?: "char1" | "char2" | null;
  slotToNameMap?: { char1?: string; char2?: string };
};

export function buildEditPromptFromScript(i: EditPromptInput): string {
  const style = i.style ? `Style: ${i.style}.` : "";
  const idHeader = (() => {
    const c1 = i.slotToNameMap?.char1 ? `Character 1 = ${i.slotToNameMap?.char1}` : undefined;
    const c2 = i.slotToNameMap?.char2 ? `Character 2 = ${i.slotToNameMap?.char2}` : undefined;
    const parts = [c1, c2].filter(Boolean).join("; ");
    return parts ? `Identity anchors: ${parts}. Do not swap identities.` : "";
  })();
  const action = i.actionHint ? `Frame intent: ${i.actionHint}.` : "";
  const anim = i.animationHint ? `Camera/animation hint: ${i.animationHint}.` : "";
  // Speech rendering instructions (model will draw bubbles/captions)
  const speech = (i.dialogueText || "").trim();
  const isNarr = String(i.speechType || "").toLowerCase().startsWith("narrat");
  const speechInstr = speech ? (
    isNarr
      ? `Add a comic caption box containing: "${speech}". Place caption at the TOP‑LEFT inside the frame, small rounded rectangle, solid white fill with thin black stroke. Do NOT cover faces.`
      : (
          i.speakerSlot === "char1"
            ? `Add a COMIC SPEECH BUBBLE containing: "${speech}". Use a white bubble with a thin black stroke and a small tail pointing to Character 1's mouth. Ensure the bubble does not block faces.`
            : i.speakerSlot === "char2"
            ? `Add a COMIC SPEECH BUBBLE containing: "${speech}". Use a white bubble with a thin black stroke and a small tail pointing to Character 2's mouth. Ensure the bubble does not block faces.`
            : `Add a COMIC SPEECH BUBBLE containing: "${speech}". Render a circular bubble WITHOUT a tail when the speaker is unknown. Ensure the bubble does not block faces.`
        )
  ) : "Do NOT add any text overlays.";

  const safety = `Do not add UI chrome, watermarks, or external text. Keep identity consistent with the reference image(s).`;
  return [idHeader, style, action, anim, speechInstr, safety].filter(Boolean).join(" \n");
}

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
  const ar = i.aspectRatio || "16:9";
  const parts: string[] = [
    `Storyboard frame in a ${style} style.`,
    `Use the FIRST reference image as the strict character identity and rendering-style anchor.`,
    i.actionHint ? `Foreground: the referenced character ${i.actionHint}.` : `Foreground: include the referenced character clearly.`,
    i.settingHint ? `Background: ${i.settingHint}.` : `Background: coherent scene context.`,
    i.cameraHint ? `Cinematic camera: ${i.cameraHint}.` : "",
    i.lightingHint ? `Lighting: ${i.lightingHint}.` : "",
    i.moodHint ? `Mood: ${i.moodHint}.` : "",
    `Compose in horizontal ${ar} (widescreen). Clean composition.`,
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
    `Compose in horizontal 16:9 (1920x1080) framing. Keep the subject well framed without black bars.`,
    `Do not add any speech bubbles, captions, or on-image text. Keep background and lighting coherent with the original photo.`,
  ];
  return parts.filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
}


