/* eslint-disable max-len, require-jsdoc, valid-jsdoc, operator-linebreak, quotes, @typescript-eslint/no-explicit-any, indent */
import * as functions from "firebase-functions/v1";
import * as logger from "firebase-functions/logger";
import {initializeApp, applicationDefault, getApps} from "firebase-admin/app";
import OpenAI from "openai";

if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}

const OPENAI_KEY: string | undefined = process.env.OPENAI_KEY;
let openaiClient: OpenAI | null = null;
function getOpenAI(): OpenAI {
  if (!openaiClient) openaiClient = new OpenAI({apiKey: OPENAI_KEY});
  return openaiClient;
}

interface StoryboardRequest {
  ideaText: string;
  characterBackground?: string;
  imageUrls?: string[]; // optional; tags may be sent later
  sceneCount?: number; // default 10
}

export const generateStoryboardPlan = functions
  .runWith({timeoutSeconds: 120, secrets: ["OPENAI_KEY"]})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (!OPENAI_KEY) {
        logger.error("OPENAI_KEY undefined");
        res.status(500).json({error: "openai_key_missing"});
        return;
      }

      const {ideaText = "", characterBackground = "", imageUrls = [], sceneCount = 10} = (req.body || {}) as StoryboardRequest;
      if (!ideaText || typeof ideaText !== "string") {
        res.status(400).json({error: "bad_request", message: "ideaText is required"});
        return;
      }

      const openai = getOpenAI();
      const systemPrompt = "You are DaGenie Planner, an expert storyboard writer. Return strict JSON only.";
      const personaControls = [
        "Derive 3 persona traits from CharacterBackground (e.g., stoic, calculating, conflicted).",
        "Maintain persona-consistent behavior in all scenes (no sudden cheerful outbursts unless bio implies).",
        "Choose one internal emotion per scene from: wary, determined, conflicted, tense, cautious, resigned, hopeful, calculating. Reflect via word choice and subtext; DO NOT output the label.",
        "Avoid generic affect: forbid words 'laugh', 'smile', 'grin', 'giggle', 'cheer', 'scream', 'excited', 'exciting' unless explicitly required by CharacterBackground or IdeaText.",
        "Prefer subtle cues over overt emotion: micro‑expressions, glances, pauses, evasions, withheld truths.",
      ].join("\n- ");
      const themeControls = [
        "If IdeaText specifies a theme, reinforce it in every scene via stakes, subtext, and leverage.",
        "If not specified, prefer intrigue/secrets: information is traded, concealed, or discovered; power comes from what is known and when it is revealed.",
      ].join("\n- ");
      const userPrompt = `Plan a ${sceneCount}-scene storyboard for short 5–8s clips. Use the inputs below.\n\n` +
        `IdeaText: ${ideaText}\n` +
        `CharacterBackground: ${characterBackground}\n` +
        `ImageEntities: ${imageUrls.length ? imageUrls.join(", ") : "[]"}\n\n` +
        `Style & Tone Controls:\n- ${personaControls}\n- ${themeControls}\n\n` +
        `Rules:\n` +
        `- For each scene, provide: action (≤30 words), speechType (Dialogue or Narration), speech (≤30 words), animation (≤30 words).\n` +
        `- Keep total words for a scene (action + speech + animation) ≤90.\n` +
        `- End each scene with a transitional beat that sets up the next scene (match cut, sound cue, insert detail, or movement). For the final scene, provide a soft wrap-up/teaser.\n` +
        `- Alternate speechType across scenes. Keep character voice consistent. Strictly respect the word budgets.\n` +
        `Return JSON ONLY in the shape { "scenes": [ { "scene": 1, "action": "", "speechType": "Dialogue", "speech": "", "animation": "" }, ... ] }`;

      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        temperature: 0.5,
        response_format: {type: "json_object"},
        messages: [
          {role: "system", content: systemPrompt},
          {role: "user", content: userPrompt},
        ],
      });

      const content = completion.choices[0]?.message?.content ?? "{}";
      let parsed: any;
      try {
        parsed = JSON.parse(content);
      } catch (e) {
        logger.error("Storyboard JSON parse failed", e as Error, content);
        res.status(502).json({error: "invalid_json_from_model"});
        return;
      }

      res.status(200).json(parsed);
    } catch (err) {
      logger.error("generateStoryboardPlan failed", err as Error);
      res.status(500).json({error: "internal_error"});
    }
  });


