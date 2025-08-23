import {onRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";

const ASSEMBLYAI_API_KEY = defineSecret("ASSEMBLYAI_API_KEY");

export const getAssemblyToken = onRequest({
  region: "us-central1",
  cors: true,
  secrets: [ASSEMBLYAI_API_KEY],
}, async (_req, res) => {
  res.setHeader("Content-Type", "application/json");
  try {
    const url = new URL("https://streaming.assemblyai.com/v3/token");
    url.searchParams.set("expires_in_seconds", "60");
    const r = await fetch(url.toString(), {
      method: "GET",
      headers: {
        Authorization: process.env.ASSEMBLYAI_API_KEY as string,
      },
    });
    const data = await r.json();
    if (!r.ok) {
      res.status(r.status).send({error: data?.error || "failed to get token"});
      res.end();
      return;
    }
    res.status(200).send({token: data.token, expires_in_seconds: data.expires_in_seconds});
    res.end();
  } catch (e: any) {
    res.status(500).send({error: e?.message || "token error"});
    res.end();
  }
});


