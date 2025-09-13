/* eslint-disable max-len, @typescript-eslint/no-explicit-any */
import * as functions from "firebase-functions/v1";
import {getApps, initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldValue, Timestamp, DocumentReference} from "firebase-admin/firestore";

if (!getApps().length) {
  initializeApp({credential: applicationDefault()});
}
const db = getFirestore();

type PlanSettingsIn = { aspectRatio: string; style: string; camera?: string | null };
type PlanSceneIn = {
  index: number;
  prompt: string;
  script?: string;
  action?: string | null;
  animation?: string | null;
  speechType?: string | null;
  speech?: string | null;
  durationSec?: number | null;
  wordsPerSec?: number | null;
  wordBudget?: number | null;
  imageUrl?: string | null;
};

interface SaveStoryboardSetRequest {
  uid: string;
  projectId: string;
  characterId: string;
  settings: PlanSettingsIn;
  referenceImageUrls?: string[];
  scenes: PlanSceneIn[];
  providerDefault?: string; // "wan" | "veo"
  storyboardId?: string;    // optional explicit id (deterministic/idempotent)
  idempotencyKey?: string;  // optional client-sent key to guard retries
  bumpVersion?: boolean;    // if true, read current latest and write new version
}

/**
 * saveStoryboardSet
 * HTTP: POST body of SaveStoryboardSetRequest
 * Atomically upserts a storyboard header + scene docs under
 * users/{uid}/projects/{projectId}/storyboards/{storyboardId}
 * Also updates the project pointer (storyboardId, totalScenes).
 */
export const saveStoryboardSet = functions
  .runWith({timeoutSeconds: 120, memory: "256MB"})
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    try {
      if (req.method !== "POST") { res.status(405).json({error: "method_not_allowed"}); return; }
      const body = (req.body || {}) as SaveStoryboardSetRequest;
      const {uid, projectId, characterId, settings, scenes} = body;
      if (!uid || !projectId || !characterId || !settings || !Array.isArray(scenes)) {
        res.status(400).json({error: "bad_request"});
        return;
      }

      const sbColl = db.collection("users").doc(uid).collection("projects").doc(projectId).collection("storyboards");
      let storyboardId = (body.storyboardId && String(body.storyboardId).trim()) || "";
      const now = Timestamp.now();

      // Idempotency guard: if storyboardId provided, short-circuit if it already exists
      if (storyboardId) {
        const existing = await sbColl.doc(storyboardId).get();
        if (existing.exists && body.idempotencyKey && existing.get("idempotencyKey") === body.idempotencyKey) {
          res.status(200).json({storyboardId});
          return;
        }
      }

      await db.runTransaction(async (tx) => {
        let version = 1;
        let previousLatestRef: DocumentReference | null = null;

        if (body.bumpVersion) {
          const q = await tx.get(sbColl.where("isLatest", "==", true).limit(1));
          const prev = q.docs[0];
          if (prev) {
            previousLatestRef = prev.ref;
            const prevVersion = Number(prev.get("version") || 0);
            version = (Number.isFinite(prevVersion) ? prevVersion : 0) + 1;
          }
        }

        if (!storyboardId) storyboardId = sbColl.doc().id;
        const sbRef = sbColl.doc(storyboardId);

        const header = {
          projectId,
          characterId,
          settings: {
            aspectRatio: settings.aspectRatio,
            style: settings.style,
            camera: settings.camera ?? null,
          },
          referenceImageUrls: Array.isArray(body.referenceImageUrls) ? body.referenceImageUrls.slice(0, 10) : [],
          providerDefault: body.providerDefault || null,
          sceneCount: scenes.length,
          version,
          isLatest: true,
          idempotencyKey: body.idempotencyKey || null,
          updatedAt: now,
          createdAt: FieldValue.serverTimestamp(),
        } as any;

        // Flip previous latest if present
        if (previousLatestRef) {
          tx.set(previousLatestRef, {isLatest: false, updatedAt: now}, {merge: true});
        }

        // Upsert header
        tx.set(sbRef, header, {merge: true});

        // Upsert scenes
        const scenesColl = sbRef.collection("scenes");
        for (const s of scenes) {
          const sceneId = String(s.index).padStart(4, "0");
          const sceneDoc = {
            index: Number(s.index),
            prompt: String(s.prompt || ""),
            script: s.script ?? null,
            action: s.action ?? null,
            animation: s.animation ?? null,
            speechType: s.speechType ?? null,
            speech: s.speech ?? null,
            durationSec: (typeof s.durationSec === "number" ? s.durationSec : null),
            wordsPerSec: (typeof s.wordsPerSec === "number" ? s.wordsPerSec : null),
            wordBudget: (typeof s.wordBudget === "number" ? s.wordBudget : null),
            imageUrl: s.imageUrl ?? null,
            video: { status: "idle" },
            updatedAt: now,
            createdAt: FieldValue.serverTimestamp(),
          } as any;
          tx.set(scenesColl.doc(sceneId), sceneDoc, {merge: true});
        }

        // Update project pointer
        tx.set(db.collection("users").doc(uid).collection("projects").doc(projectId), {
          storyboardId,
          totalScenes: scenes.length,
          lastEditedAt: now,
        }, {merge: true});
      });

      res.status(200).json({storyboardId});
    } catch (e: any) {
      functions.logger.error("saveStoryboardSet.failed", {message: String(e?.message || e)});
      res.status(500).json({error: "internal_error", message: String(e?.message || e)});
    }
  });


