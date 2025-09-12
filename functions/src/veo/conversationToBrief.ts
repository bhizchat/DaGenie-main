/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import {defineSecret} from "firebase-functions/params";
import {CallableRequest, onCall} from "firebase-functions/v2/https";
import OpenAI from "openai";
import {AdBrief, withDefaults} from "./brief";

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

export interface ConversationToBriefInput { messages: Array<{role: "user"|"assistant"; content: string}>; assets?: {productImageGsPath?: string; logoGsPath?: string; brandColors?: string[]}; }

export const conversationToBrief = onCall({
  region: "us-central1",
  timeoutSeconds: 300,
  memory: "512MiB",
  secrets: [OPENAI_API_KEY],
}, async (req: CallableRequest<ConversationToBriefInput>) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("unauthenticated");
  const msgs = (req.data?.messages || []).filter((m) => typeof m?.content === "string");
  if (!msgs.length) throw new Error("missing messages");

  const system = `You are a helpful creative companion. Extract a structured ad brief from a friendly, open-ended chat. Never ask the user to choose a format.
Output ONLY JSON in this schema with nulls when unknown:
{
  "productName": null,
  "category": null,
  "productTraits": [],
  "audience": null,
  "desiredPerception": [],
  "proofMoment": null,
  "styleWords": [],
  "cta": null,
  "durationSeconds": null,
  "aspectRatio": null,
  "brand": {"name": null, "colors": [], "voice": [], "logoGsPath": null},
  "assets": {"productImageGsPath": null}
}`;

  const openai = new OpenAI({apiKey: process.env.OPENAI_API_KEY});
  const completion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    temperature: 0.3,
    messages: [
      {role: "system", content: system},
      ...msgs.map((m) => ({role: m.role, content: m.content})),
    ],
    response_format: {type: "json_object"},
  });

  let brief: AdBrief = {} as any;
  try {
    brief = JSON.parse(completion.choices?.[0]?.message?.content || "{}");
  } catch {
    brief = {} as any;
  }

  // Merge provided assets
  const assets = req.data?.assets || {};
  brief.assets = {
    productImageGsPath: assets.productImageGsPath || brief.assets?.productImageGsPath,
  };
  if (!brief.brand) brief.brand = {};
  if (assets.logoGsPath && !brief.brand.logoGsPath) brief.brand.logoGsPath = assets.logoGsPath;
  if (assets.brandColors && (!brief.brand.colors || !brief.brand.colors.length)) brief.brand.colors = assets.brandColors;

  return {brief: withDefaults(brief)};
});


