## DateGenie — AI Animation Studio

DateGenie is an AI-first iOS studio for planning storyboards, generating on-model scene imagery from scripts and reference art, editing with overlays and captions, and exporting finished cuts to Projects backed by Firebase.

### Capabilities
- Storyboard planning from prompts and character/background context
- Image generation per scene using script cues + reference images
- Timeline editing with overlays/captions and export
- Project storage with video and thumbnail in Firebase



## Architecture overview

- Client (SwiftUI)
  - Planning: `DateGenie/Services/PlannerService.swift`
  - Rendering: `DateGenie/Services/RenderService.swift`
  - Editing: `DateGenie/Views/Editor/CapcutEditorView.swift`, `DateGenie/Overlays/*`
  - Projects: `DateGenie/Repositories/ProjectsRepository.swift`, `DateGenie/Views/Projects/ProjectsView.swift`
  - Analytics: `DateGenie/AnalyticsManager.swift`

- Backend (Firebase)
  - Firestore: user `projects` metadata
  - Storage: generated frames, exported videos, thumbnails
  - Functions: `functions/src/generateStoryboardPlan.ts`, `functions/src/generateStoryboardImages.ts`

---

## Core data model

Defined in `DateGenie/Models/StoryboardPlan.swift`:
- `StoryboardPlan` — character, `PlanSettings`, `[PlanScene]`, `referenceImageUrls`
- `PlanScene` — index, prompt, script, structured `action`, `speechType`, `speech`, `animation`, `imageUrl`
- `PlanSettings` — aspectRatio, style, camera

Model flow: planner → renderer (attaches `imageUrl`) → editor → export.

---

## Pipeline

### 1) Plan storyboard
- Client: `PlannerService.plan(_:)` builds a `StoryboardPlan` from `GenerationRequest`
- Optional backend: `generateStoryboardPlan` cloud function

Key files:
- `DateGenie/Services/PlannerService.swift`
- `DateGenie/Models/StoryboardPlan.swift`
- `DateGenie/Models/GenerationRequest.swift`

### 2) Render scenes
- Client: `RenderService.render(plan:)` posts scenes + references; attaches `imageUrl`
- Backend: `functions/src/generateStoryboardImages.ts` calls Gemini and uploads to Storage

Key files:
- `DateGenie/Services/RenderService.swift`
- `functions/src/generateStoryboardImages.ts`

### 3) Edit and export
- Timeline editor: `DateGenie/Views/Editor/CapcutEditorView.swift`
- Overlays & export: `DateGenie/Overlays/OverlayEditorView.swift`, `MediaOverlayView.swift`, `OverlayExporter.swift`, `VideoRenderConfig.swift`

### 4) Save to Projects
- Repository: `DateGenie/Repositories/ProjectsRepository.swift`
  - `create(userId:)` → create project doc
  - `attachVideo(userId:projectId:localURL:)` → upload final mp4 and set `videoURL`
  - `uploadThumbnail(userId:projectId:image:)` → upload jpg and set `thumbURL`
- Model/UI: `DateGenie/Models/Project.swift`, `DateGenie/Views/Projects/ProjectsView.swift`

---

## Analytics
`DateGenie/AnalyticsManager.swift` logs planner, renderer, editor, and export events.

---

## Backend endpoints
- `generateStoryboardPlan` (HTTP) — returns `{ scenes: [...] }`
- `generateStoryboardImages` (HTTP) — returns `{ scenes: [{ index, imageUrl }] }`

---

## Storyboard generation pipeline (current behavior)

This documents the exact, current end‑to‑end for creating a video clip from a storyboard scene so we can revert here if future changes regress behavior.

### Client → enqueue job
- Screen: `DateGenie/Views/StoryboardNavigatorView.swift`
- When a user taps “Generate clip” on a scene:
  - Chooses model string:
    - WAN: `"wan-video"`
    - Veo 3: `"veo-3.0-generate-001"`
  - Builds payload with the entire storyboard and the selected scene index:
    - `character`: mascot id (e.g., `"investor"`, `"cory"`)
    - `model`: as above
    - `aspectRatio`: from plan settings
    - `selectedIndex`: the tapped scene’s `index`
    - `scenes`: array of scene inputs `{ index, action?, animation?, speechType?, speech?, imageUrl? }`
  - Calls callable HTTPS endpoint: `createStoryboardJob`

### Server: create job doc
- File: `functions/src/veo/createStoryboardJob.ts`
- Resolves anchor image:
  - Prefers image from `selectedIndex` scene if present; falls back to first scene with an image
  - Normalizes HTTPS storage URLs → `gs://...`
- Writes `adJobs/{jobId}` with:
  - `uid`, `status: "queued"`, timestamps
  - `model` (as sent by client)
  - `promptV1` scaffold used for downstream checks
  - `veoPrompt` — JSON prompt assembled from the entire storyboard (current behavior):
    - `scene: "animation"`, `style: "animated mascot short, playful, campus vibe"`
    - `sequence`: built by mapping over all scenes: `{ shot: "storyboard_beat", camera, description }`
    - `dialogue`: array of all non‑empty `speech` lines from all scenes (if any)
    - `format`: aspect ratio (e.g., `"9:16"` or `"16:9"`)
  - `inputImagePath` and `inputImageUrl` for image resolution/debug
  - Debug log: `[createStoryboardJob] enqueued { jobId, model, imageUrlPrefix, imageGs, scenes, selectedIndex, anchorSource, promptHead }`

### Server: queue trigger → renderer
- File: `functions/src/veo/onAdJobQueued.ts`
- Trigger: Firestore `onDocumentWritten` on `adJobs/{jobId}`
- Validates readiness: has `promptV1`, has an `inputImagePath` or `promptV1.product.imageGsPath`
- Idempotently claims the job (`processing.startedAt`) and invokes `startVeoForJobCore(uid, jobId)`

### Server: Veo/WAN start (renderer)
- File: `functions/src/veo/startVeoForJob.ts`
- Image preparation:
  - Ensures a valid `gs://...` path
  - Attempts direct GCS download to inline base64; else builds a signed URL/token URL
- Prompt selection (current):
  - Primary: `job.veoPrompt` if present (the JSON built from the entire storyboard)
  - Fallback: a minimal JSON `{ scene: "animation", description: promptV1.product.description }`
- Dialogue handling (current):
  - If the JSON prompt includes a `dialogue` array, the function prepends a textual cue to the final string sent to Veo:
    - Prefix: `Voiceover: "...all lines joined..."` then a blank line, then the JSON prompt string
- Model routing:
  - Veo: `models/veo-3.0-generate-001:predictLongRunning`
    - Request `instances: [{ prompt: <final string>, image: { imageBytes, mimeType } }]`
    - Polls the operation until `done`
    - Output extraction:
      - Prefers `response.generateVideoResponse.generatedSamples[0].video.uri`
      - Otherwise handles Files API: `response.generated_videos[0].video` → `files/{id}:download` or `downloadUri`
    - Rehosts bytes/URL to Firebase Storage `generated_ads/{jobId}/output.mp4`, sets `finalVideoUrl`
  - WAN: posts `{ image, prompt, fps, num_frames, resolution }` to the WAN endpoint; rehosts to Storage

### Logging and debug fields
- Cloud logs:
  - `[createStoryboardJob] enqueued {...}`
  - `[onAdJobQueued] readiness {...}`
  - `[startVeoForJob] prompt_preview { len, head }`
  - `[startVeoForJob] final_prompt_head { len, head, hasVoiceoverPrefix, dialogueLinesCount }`
  - `[startVeoForJob] FINAL_PROMPT <entire string>` (may be truncated in Cloud Logging UI)
  - Poll heartbeats and ready/errors
- Firestore `adJobs/{jobId}.debug`:
  - `promptPreview`: first ~800 chars of `veoPrompt`
  - `finalPromptHead`: first ~220 chars of the final string sent
  - `finalPromptFull`: entire final string (non‑truncated, persisted)
  - `hasJsonDialogue`: boolean
  - `dialogueLinesCount`: number of dialogue lines detected
  - `imageInlineBytesLen`: size of inlined image bytes when applicable

### Recovery checklist
1) From `adJobs/{jobId}.debug`, confirm `finalPromptFull` and `finalVideoUrl`
2) Verify model: `veo-3.0-generate-001` or WAN path
3) Confirm image source resolution path (inline bytes vs signed URL)
4) If Veo returns Files handle, confirm `files/{id}:download` fallback taken
5) If audio behavior is unexpected, check `hasJsonDialogue`, `dialogueLinesCount`, and whether `Voiceover:` prefix appears in `finalPromptHead`


---

## Getting started
1) iOS app
- Open `DateGenie.xcodeproj`
- Provide `GoogleService-Info.plist`

2) Functions
- `cd functions && npm i`
- `firebase functions:secrets:set GEMINI_API_KEY`
- `firebase deploy --only functions`

3) Firestore/Storage
- Ensure rules permit authenticated project reads/writes

---

## Legacy scope note
Legacy “date generator” and “mission/adventure” screens remain for reference but are not core to the AI animation studio pipeline.


