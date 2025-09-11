import {onRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";

const ASSEMBLYAI_API_KEY = defineSecret("ASSEMBLYAI_API_KEY");

interface VerifyPayload {
  audioPcm16kB64: string;
  draft: string;
  keyterms?: string[];
  language_code?: string;
}

function sanitizeKeyterms(input?: string[]): string[] | undefined {
  if (!input || !Array.isArray(input)) return undefined;
  const trimmed = input
    .map((s) => (typeof s === "string" ? s.trim() : ""))
    .filter((s) => s.length >= 3)
    .map((s) => (s.split(/\s+/).slice(0, 6).join(" ")))
    .slice(0, 1000);
  // Deduplicate, preserve order
  const seen = new Set<string>();
  const out: string[] = [];
  for (const k of trimmed) {
    if (!seen.has(k)) {
      seen.add(k); out.push(k);
    }
  }
  return out;
}

function extractNumbers(s: string): string[] {
  return (s.match(/\d+[\d,.:-]*/g) || []).map((x) => x.replace(/[,]/g, ""));
}

function extractEmails(s: string): string[] {
  const re = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
  return (s.match(re) || []).map((x) => x.toLowerCase());
}

function containsAnyKeyterm(text: string, keyterms: string[]): boolean {
  const lower = text.toLowerCase();
  return keyterms.some((k) => lower.includes(k.toLowerCase()));
}

function materialImprovement(draft: string, fixed: string, keyterms?: string[]): boolean {
  const d = draft.trim();
  const f = fixed.trim();
  if (!f || f.toLowerCase() === d.toLowerCase()) return false;
  // Numbers
  const dn = extractNumbers(d).join("|");
  const fn = extractNumbers(f).join("|");
  if (dn !== fn && fn.length > 0) return true;
  // Emails
  const de = extractEmails(d).join("|");
  const fe = extractEmails(f).join("|");
  if (de !== fe && fe.length > 0) return true;
  // Brands / keyterms
  if (keyterms && keyterms.length > 0) {
    const had = containsAnyKeyterm(d, keyterms);
    const now = containsAnyKeyterm(f, keyterms);
    if (!had && now) return true;
    // Near-miss correction: if fixed now contains a keyterm and draft had a close token, accept
    if (now && !had) return true;
    // Even if both contained keyterms, accept when a near-match improves spelling significantly
    const nearestImproved = hasNearMissImprovement(d, f, keyterms);
    if (nearestImproved) return true;
  }
  // Fallback: substantial length difference
  if (Math.abs(f.length - d.length) >= 6) return true;
  return false;
}

// Simple Levenshtein distance (cap at 2 for speed)
function lev2(a: string, b: string): number {
  const la = a.length; const lb = b.length;
  if (Math.abs(la - lb) > 2) return 3;
  const dp = Array.from({length: la + 1}, (_, i) => i);
  for (let j = 1; j <= lb; j++) {
    let prev = dp[0];
    dp[0] = j;
    for (let i = 1; i <= la; i++) {
      const tmp = dp[i];
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      dp[i] = Math.min(
        dp[i] + 1,
        dp[i - 1] + 1,
        prev + cost,
      );
      prev = tmp;
    }
  }
  return dp[la];
}

function tokenizeWords(s: string): string[] {
  return (s.toLowerCase().match(/[a-z0-9][a-z0-9-]{1,}/g) || []);
}

function hasNearMissImprovement(draft: string, fixed: string, keyterms: string[]): boolean {
  const dTokens = tokenizeWords(draft);
  const fTokens = tokenizeWords(fixed);
  const kset = new Set(keyterms.map((k) => k.toLowerCase()));
  // If fixed includes any keyterm token
  for (const fTok of fTokens) {
    if (kset.has(fTok)) {
      // Did draft contain a near-miss of that token?
      for (const dTok of dTokens) {
        if (lev2(dTok, fTok) <= 2) return true;
      }
    }
  }
  // Repetition clean-up: if draft had duplicated adjacent tokens and fixed deduped
  for (let i = 1; i < dTokens.length; i++) {
    if (dTokens[i] === dTokens[i - 1]) {
      // accept if fixed collapses duplicates
      for (let j = 1; j < fTokens.length; j++) {
        if (fTokens[j] === fTokens[j - 1]) {
          // still duplicated in fixed – not an improvement here
          return false;
        }
      }
      return true;
    }
  }
  return false;
}

export const verifyTranscript = onRequest({
  region: "us-central1",
  cors: true,
  secrets: [ASSEMBLYAI_API_KEY],
  timeoutSeconds: 300,
  memory: "512MiB",
}, async (req, res) => {
  res.setHeader("Content-Type", "application/json");
  try {
    if (req.method !== "POST") {
      res.status(405).send({error: "method_not_allowed"});
      return;
    }
    const data = (req.body?.data || req.body) as VerifyPayload;
    if (!data || !data.audioPcm16kB64 || !data.draft) {
      res.status(400).send({error: "missing_fields"});
      return;
    }
    const keyterms = sanitizeKeyterms(data.keyterms);
    const lang = (data.language_code && data.language_code.length > 0) ? data.language_code : "en";

    // 1) Upload raw audio to AssemblyAI
    const audioBytes = Buffer.from(data.audioPcm16kB64, "base64");
    const uploadResp = await fetch("https://api.assemblyai.com/v2/upload", {
      method: "POST",
      headers: {
        "Authorization": process.env.ASSEMBLYAI_API_KEY as string,
        "Content-Type": "application/octet-stream",
      },
      body: audioBytes,
    });
    const uploadJson: any = await uploadResp.json();
    if (!uploadResp.ok || !uploadJson.upload_url) {
      res.status(500).send({error: "upload_failed", detail: uploadJson});
      return;
    }

    // 2) Create transcript using Slam-1 and keyterms_prompt
    const tResp = await fetch("https://api.assemblyai.com/v2/transcript", {
      method: "POST",
      headers: {
        "Authorization": process.env.ASSEMBLYAI_API_KEY as string,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        audio_url: uploadJson.upload_url,
        speech_model: "slam-1",
        language_code: lang,
        punctuate: true,
        format_text: true,
        keyterms_prompt: keyterms && keyterms.length > 0 ? keyterms : undefined,
      }),
    });
    const tJson: any = await tResp.json();
    if (!tResp.ok || !tJson.id) {
      res.status(500).send({error: "transcript_create_failed", detail: tJson});
      return;
    }

    // 3) Poll for completion
    let status = tJson.status as string;
    let text = "";
    let tries = 0;
    while (tries < 120) { // up to ~60s
      await new Promise((r) => setTimeout(r, 500));
      const g = await fetch(`https://api.assemblyai.com/v2/transcript/${tJson.id}`, {
        headers: {Authorization: process.env.ASSEMBLYAI_API_KEY as string},
      });
      const gj: any = await g.json();
      status = gj.status;
      if (status === "completed") {
        text = gj.text || ""; break;
      }
      if (status === "error") {
        res.status(500).send({error: "transcript_error", detail: gj.error});
        return;
      }
      tries++;
    }
    if (status !== "completed") {
      res.status(504).send({error: "transcript_timeout"});
      return;
    }

    const draft = data.draft;
    const improved = materialImprovement(draft, text, keyterms);
    if (improved) {
      res.status(200).send({fixed: text});
    } else {
      res.status(200).send({});
    }
  } catch (e: any) {
    res.status(500).send({error: e?.message || "verify_error"});
  }
});


