/* eslint-disable @typescript-eslint/no-explicit-any */
import crypto from "crypto";
import {getStorage} from "firebase-admin/storage";

const storage = getStorage();

export function parseGsUri(gs: string): {bucket: string; object: string} {
  const m = gs.match(/^gs:\/\/([^/]+)\/(.+)$/);
  if (!m) throw new Error(`bad_gs_uri: ${gs}`);
  return {bucket: m[1], object: m[2]};
}

export async function candidatesForBucket(name: string): Promise<string[]> {
  const defaultBucket = storage.bucket().name;
  const variants = new Set<string>([
    name,
    name.replace(/\.appspot\.com$/i, ".firebasestorage.app"),
    name.replace(/\.firebasestorage\.app$/i, ".appspot.com"),
    defaultBucket,
  ]);
  return Array.from(variants).filter(Boolean);
}

/** Tiered resolution: Signed URL → Token URL → Data URI */
export async function gsToFetchableUrl(gs: string, log?: (msg: string, extra?: any)=>void): Promise<string> {
  const {bucket, object} = parseGsUri(gs);
  const buckets = await candidatesForBucket(bucket);

  for (const b of buckets) {
    const file = storage.bucket(b).file(object);
    // 1) Signed URL
    try {
      const [signed] = await file.getSignedUrl({action: "read", expires: Date.now() + 60 * 60 * 1000});
      log?.("gsToFetchableUrl:signed", {bucket: b});
      return signed;
    } catch { /* next path */ }

    // 2) Token URL
    try {
      const [meta] = await file.getMetadata();
      let token: string | undefined = meta?.metadata?.firebaseStorageDownloadTokens as string | undefined;
      if (!token) {
        token = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        await file.setMetadata({metadata: {firebaseStorageDownloadTokens: token}});
      }
      log?.("gsToFetchableUrl:token", {bucket: b});
      return `https://firebasestorage.googleapis.com/v0/b/${b}/o/${encodeURIComponent(object)}?alt=media&token=${token}`;
    } catch { /* next path */ }

    // 3) Data URI
    try {
      const [meta] = await file.getMetadata();
      const mime = meta?.contentType || "image/png";
      const [buf] = await file.download();
      log?.("gsToFetchableUrl:data", {bucket: b});
      return `data:${mime};base64,${buf.toString("base64")}`;
    } catch { /* continue */ }
  }

  throw new Error(`gs_to_url_failed: ${gs}`);
}


