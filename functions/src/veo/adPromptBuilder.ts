/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {onCall, CallableRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import OpenAI from "openai";

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

export interface BuildPromptInput {
  transcript: string;
}

export const adPromptBuilder = onCall({
  region: "us-central1",
  timeoutSeconds: 300,
  memory: "512MiB",
  secrets: [OPENAI_API_KEY],
}, async (req: CallableRequest<BuildPromptInput>) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("unauthenticated");
  const transcript = (req.data?.transcript || "").trim();
  if (!transcript) throw new Error("missing transcript");

  const system = `You are Genie, a friendly creative ad producer.
Ask at most 3 concise follow-up questions only if essential data is missing.
Output ONLY valid JSON matching this schema:
{
  "brand": {"name": "", "tone": ""},
  "product": {"name": "", "category": "", "key_benefit": ""},
  "audience": "",
  "objective": "awareness | conversion | launch",
  "cta": "",
  "style": "cinematic_realism | creative_animation | dialogue_sfx",
  "aspect_ratio": "16:9",
  "negative_prompt": "",
  "shot": {},
  "subject": {},
  "scene": {},
  "visual_details": {},
  "cinematography": {},
  "audio": {},
  "dialogue": {},
  "final_text_prompt_for_ai": ""
}
The field final_text_prompt_for_ai must be a compact text prompt for Veo 3 (<= 900 tokens), and must not include the wake phrase.`;

  const openai = new OpenAI({apiKey: process.env.OPENAI_API_KEY});
  const completion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    temperature: 0.7,
    messages: [
      {role: "system", content: system},
      {role: "user", content: transcript},
    ],
    response_format: {type: "json_object"},
  });

  const jsonRaw = completion.choices?.[0]?.message?.content || "{}";
  let parsed: any;
  try {
    parsed = JSON.parse(jsonRaw);
  } catch {
    parsed = {};
  }
  return {structured: parsed};
});


