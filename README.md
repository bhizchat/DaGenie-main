## DateGenie — AI Animation Studio

DateGenie is an AI-first iOS studio for planning storyboards, generating on-model scene imagery from scripts and reference art, editing with overlays and captions, and exporting finished cuts to Projects backed by Firebase.

### Capabilities
- Storyboard planning from prompts and character/background context
- Image generation per scene using script cues + reference images
- Timeline editing with overlays/captions and export
- Project storage with video and thumbnail in Firebase

---

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


