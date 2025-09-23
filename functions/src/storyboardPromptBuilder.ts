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

// Rap video oriented frame prompt (no club/street/crowd/stage archetype assumptions)
export type RapFramePromptInput = {
  style?: string;
  aspectRatio?: string;
  actionHint?: string;          // performance/pose intent
  animationHint?: string;       // camera/motion intent
  environment?: string;         // world/environment description from setting
  cameraMovementHint?: string;  // e.g., orbit 12–15°, push‑in, handheld sway
  lightingHint?: string;        // neon rim, tungsten practicals, etc.
  slotToNameMap?: { char1?: string; char2?: string };
  creativeHint?: string;        // user idea text (soft guidance)
};

export function buildRapFramePrompt(i: RapFramePromptInput): string {
  // Compact, Google-friendly scene template
  // [Avatar action] — setting — camera/framing — lighting — style/palette — props — constraints — negatives
  const style = i.style || "glossy 3D stylized";
  const ar = (i.aspectRatio || "4:5").trim();
  const action = (i.actionHint || "").trim();
  const setting = (i.environment || "stylized island set").trim();
  const camera = (i.animationHint || i.cameraMovementHint || "medium shot, eye‑level, gentle dolly‑in").trim();
  const lighting = (i.lightingHint || "soft key on face, neon rim, subtle fill").trim();
  const props = (i.creativeHint || "").trim();

  const idLine = (() => {
    const c1 = i.slotToNameMap?.char1 ? `Identity anchor: the person is ${i.slotToNameMap?.char1}.` : "";
    const c2 = i.slotToNameMap?.char2 ? ` Second anchor: ${i.slotToNameMap?.char2}.` : "";
    return (c1 + c2).trim();
  })();

  const constraints = `vertical ${ar}, one avatar only, face readable and centered priority, no duplicate characters, no text, no watermarks`;
  const negatives = `avoid crowds, avoid heavy fog, avoid extreme motion blur, avoid duplicate avatar`; // concise negatives

  const subject = action ? `Avatar ${action}` : `Avatar poses to camera`;
  const parts = [
    subject,
    setting ? `— ${setting}` : "",
    camera ? `— ${camera}` : "",
    lighting ? `— ${lighting}` : "",
    `— ${style}`,
    props ? `— ${props}` : "",
    `— ${constraints}`,
    `— ${negatives}`,
  ].filter(Boolean).join(" ");

  return [idLine, parts].filter(Boolean).join(" \n").trim();
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
