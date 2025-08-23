# Screens

## Screen: Plan Generator

- __Location__: `DateGenie/GenerateView.swift`
- **What it does**: Finds nearby places and generates a simple date plan with:
  - Place recommendations
  - A “Do This” activity prompt
  - A “Photo Idea” to capture during the date

### UI Inputs
- **College**: campus/area context for suggestions
- **Mood/Vibe**: multi-select chips (e.g., Artsy, Outdoorsy, Boba Stop, Comfort Bites, Bar Hop, Romantic, Arcade, Live Music)
- **Extra Detail**: optional free text to steer ideas
- **Time of Day**: Any / Morning / Afternoon / Evening
- **Action**: “Generate Options” button

### Results
- **Cards include**:
  - Venue name, category, and basic context
  - “Do This” prompt (what to do there)
  - “Photo Idea” (what to capture)
  - Optional tags (budget/time/context)
- **Save**: Save a plan to your profile.
  - Client: `SavedPlansVM.swift`, `Repositories/UserRepository.swift`
  - Display: `SavedDatesView.swift`

### How it works
- **Service**: `Services/CampusPlanService.swift` orchestrates generation/fetch.
- **Backend (Firebase Functions)**:
  - `functions/src/generatePlans.ts`, `functions/src/generateCampusPlans.ts`
  - Uses seeds/config: `functions/config/venue_ideas.json`, `functions/config/vibe_time_rules.yaml`
- **Data flow**:
  1) App sends preferences (location/college, vibes, time-of-day, extra detail)
  2) Cloud Functions build candidate venues and craft activity + photo prompts
  3) App displays results; user can save, regenerate, or refine

### Analytics
- **Client**: `AnalyticsManager.swift`
  - Logs plan generation and saves with privacy-first parameters (e.g., vibes, time-of-day, result count).
- **Backend**: Functions also log generation metadata for admin insights.

### Error/Loading States
- **Loading**: `LoadingOverlay.swift` / `LoadingBarOverlay.swift`
- **Failures**: Graceful error messages with retry; degraded mode if offline/unavailable.

### Notes
- **Push menu** available via top-left toolbar (side menu).
- **Permissions**: Not required for generation; location is optional if using college context.

---

## Screen: Generated Plans (Results)

- __Location__: `DateGenie/GenerateView.swift` (handles the display of results)
- __What it does__: After the user taps “Generate Options,” this view displays a list or carousel of date plan cards.

### UI Components
- **Plan Cards**: Each card is a self-contained date idea, showing:
  - **Venue Name**: The name of the place (e.g., "The Art Corner Cafe").
  - **Do This**: A specific, fun activity to do there (e.g., "Try to draw each other's portraits on a napkin.").
  - **Photo Idea**: A creative prompt for a photo to capture the memory (e.g., "Take a picture of your finished napkin portraits.").
  - **Tags**: Optional metadata like budget (`$`, `$$`), time estimate, or vibe.
- **Actions per Card**:
  - **Save**: A button (likely a heart or bookmark icon) to save the plan to the user's profile. This action is handled by `SavedPlansVM.swift`.
  - **More Info/Details**: (Potentially) Tapping the card could expand it or navigate to a detail view with more information about the venue.
- **Overall Actions**:
  - **Refine/Regenerate**: A button to go back to the generator screen to tweak the inputs and get new options.
  - **Navigation**: A way to access saved plans, likely leading to `SavedDatesView.swift`.

### How it works
1. `GenerateView.swift` receives an array of `CampusPlan` objects from the `CampusPlanService`.
2. It iterates through this array, rendering a card for each plan.
3. The view listens for user actions like tapping the save button, which triggers a function in `SavedPlansVM.swift` to persist the plan to Firestore via `UserRepository.swift`.

### Notes
- The design is focused on being scannable and visually engaging, encouraging users to quickly evaluate and save plans that look interesting.

---

## Screen: Saved Plans

- __Location__: `DateGenie/SavedDatesView.swift`
- __What it does__: Displays a list of all the date plans the user has previously saved.

### UI Components
- **Plans List**: A vertically scrollable list or grid of saved date ideas.
- **Plan Summary Card**: Each item in the list represents a saved plan, likely showing:
  - The venue name.
  - A snippet of the "Do This" activity or the vibe.
- **Actions**:
  - **View Details**: Tapping a card would navigate to a detailed view of the plan.
  - **Delete/Unsave**: An option (e.g., a swipe action or an edit button) to remove a plan from the saved list.
- **Empty State**: A message that appears when the user has not saved any plans yet (e.g., "Your saved date ideas will appear here.").

### How it works
1. The view is managed by `SavedPlansVM.swift`, which acts as the view model.
2. On appear, the view model calls `UserRepository.swift` to fetch the current user's saved plans from Firestore.
3. The view model publishes the list of plans, and `SavedDatesView.swift` updates to display them.
4. When a user deletes a plan, the view model updates the state and calls the repository to remove the plan from the user's document in Firestore.

### Analytics
- **Client**: `AnalyticsManager.swift` logs events for:
  - Viewing the saved plans screen.
  - Deleting a saved plan.

### Notes
- This screen is key for user retention, as it contains their curated collection of ideas.
- It provides a quick way for users to access their favorite plans without having to use the generator again.

---

## Screen: Theme Swipe (Adventure Setup)

- __Location__: `DateGenie/Views/ThemeSwipeView.swift`
- __What it does__: Allows the user to browse a deck of date "themes" and select a few to build a custom "Adventure." This is the entry point to the app's main gameplay loop.

### UI Components
- **Theme Cards**: A stack of cards, each representing a theme (e.g., "Campus Legends," "City Explorer"). Each card likely displays an image and the theme title.
- **Swipe Gesture**: Users can swipe right to accept a theme or left to reject it.
- **Progress Indicator**: A UI element showing how many themes have been accepted out of the required number (e.g., "3/5 selected").
- **Start Adventure Button**: Becomes active once the user has selected the required number of themes. Tapping this navigates to the `AdventureMapView`.

### How it works
1. `ThemeSwipeView.swift` fetches a collection of `CampusTheme` objects to display.
2. The view maintains the state of the card deck (`current`, `accepted`, `history`).
3. As the user swipes, themes are moved from the `current` deck to either the `accepted` or `history` arrays.
4. Once the `accepted` array reaches the required size (e.g., 5), the "Start Adventure" button is enabled.
5. Tapping "Start Adventure" triggers a navigation to `AdventureMapView.swift`, passing along the selected themes.

### Analytics
- **Client**: `AnalyticsManager.swift` logs events for:
  - Starting a theme swipe session.
  - Accepting or rejecting individual themes.
  - Successfully creating an adventure.

### Notes
- This screen acts as a fun "character creation" or "level setup" phase for the date adventure.
- The themes themselves are likely generated or curated on the backend.

---

## Screen: Adventure Map

- __Location__: `DateGenie/Views/AdventureMapView.swift`
- __What it does__: Displays the main "level map" for the date adventure. It shows a series of 5 "missions" or nodes that the couple must complete in order.

### UI Components
- **Map Background**: A visual background for the level.
- **Mission Nodes**: A path of 5 nodes, visually represented by `MapNodeView.swift`. Each node has a state:
  - `.pending`: A future mission.
  - `.active`: The current mission, tappable.
  - `.done`: A completed mission.
- **Timer**: A countdown timer showing the time remaining for the adventure.
- **Back/Quit Button**: A custom navigation button to exit the adventure, which likely shows a confirmation alert.

### How it works
1. This view is presented after the user creates an adventure from the `ThemeSwipeView`.
2. It initializes a new "run" using `RunManager.swift` to track the progress of this specific adventure.
3. The view displays 5 nodes. The first node is `.active`, and the rest are `.pending`.
4. Tapping the `.active` node presents the `MissionFlowView` as a sheet or modal, starting the mission for that node.
5. When a mission is completed (when `MissionFlowView` is dismissed with a success state), `AdventureMapView` updates the node's state to `.done` and sets the next node to `.active`.
6. The view uses `DisableBackSwipe.swift` to prevent accidental navigation away from the adventure.

### Analytics
- **Client**: `AnalyticsManager.swift` logs events for:
  - Starting an adventure (viewing the map for the first time).
  - Starting each mission (tapping a node).
  - Completing each mission.
  - Quitting an adventure mid-way.

### Notes
- This screen acts as the central hub for the date. Users will return here after completing each mission.
- The state of completed missions is persisted, likely using `JourneyPersistence.swift`, so users can resume an adventure later.

---

## Screen: Mission Flow

- __Location__: `DateGenie/Views/MissionFlowView.swift`
- __What it does__: A modal view that manages the three-step sequence for a single mission: Game → Task → Checkpoint Photo.

### UI Components & Steps
1.  **Game** (`GameToPlayView.swift`):
    -   Displays the description of a mini-game or challenge.
    -   Includes buttons to open the camera (`PhotoCaptureView.swift` or `VideoCaptureView.swift`) to record evidence of completing the game.
    -   Allows users to preview the captured media.

2.  **Task** (`TaskView.swift`):
    -   A simpler screen that shows a text-based task or question for the couple to complete.
    -   Includes simple "Back" and "Next" navigation buttons to move within the `MissionFlowView`.

3.  **Checkpoint Photo** (`CheckpointPhotoView.swift`):
    -   The final step of the mission.
    -   Prompts the user to take a final photo or video to mark the mission as complete.
    -   The "Finish" button completes the mission and dismisses the `MissionFlowView`.

### How it works
1.  `MissionFlowView` is presented modally when an active node is tapped in `AdventureMapView`.
2.  It maintains an internal `step` state to control which of the three sub-views is currently visible.
3.  It interacts with `RunManager.swift` to get the current `runId`.
4.  For each step that involves media, it uses `JourneyPersistence.swift` to save the captured media locally and `MediaUploadManager.swift` to handle the background upload to Firebase Storage.
5.  When the user clicks "Finish" on the final step, the view calls its `onFinish` closure, signaling to `AdventureMapView` that the mission is complete.

### Analytics
- **Client**: `AnalyticsManager.swift` logs events for:
    -   Starting each step of the mission (game, task, checkpoint).
    -   Capturing media for a step.
    -   Successfully completing the entire mission flow.

### Notes
-   This view is the heart of the app's gameplay, containing the actual date activities.
-   Like the Adventure Map, it uses `DisableBackSwipe.swift` and a custom back button with a confirmation dialog to prevent users from accidentally losing their mission progress.

---

## Feature: Romance Points & Levels

- __Locations__: `RomanceLevelsView.swift`, `PointsPhotoCaptureView.swift`, `LevelView.swift`
- __Backend__: `functions/src/awardRomancePoints.ts`
- __What it does__: A gamification system that rewards users with "Romance Points" for completing dates and other in-app activities. As users accumulate points, they level up.

### How to Earn Points
- **Completing Adventures**: The primary way to earn points.
- **Specific Photo Tasks**: `PointsPhotoCaptureView.swift` is a dedicated view for capturing photos related to specific point-earning challenges or events.
- **Other Activities**: Points can also be awarded for activities like saving plans, trying new features, etc., as defined in `PointsEvents.swift`.

### Viewing Progress
- **Levels Screen** (`RomanceLevelsView.swift`):
  - Shows the user's current level and a progress bar towards the next level.
  - May include a history of points earned.
- **Level Component** (`LevelView.swift`):
  - A reusable UI component that displays the user's current level, possibly used in various places like the user's profile or side menu.

### How it works
1.  The app triggers point-earning events (e.g., `PointsEvents.missionComplete`).
2.  These events are securely processed by the `awardRomancePoints.ts` Cloud Function on the backend to prevent client-side manipulation.
3.  The backend function updates the user's points and level in their Firestore document.
4.  The app listens for changes to the user's profile and updates the UI in `RomanceLevelsView.swift` and other relevant places.

### Analytics
- **Client**: `AnalyticsManager.swift` logs when points are earned and when a user levels up.

---

## Feature: Subscriptions & Monetization

- __Locations__: `PaywallView.swift`, `SubscriptionManager.swift`
- __Backend__: `functions/src/validateReceipt.ts`, `functions/src/activateSubscription.ts`
- __What it does__: Manages in-app purchases to unlock premium features, such as unlimited plan generation or access to exclusive adventure content.

### UI Components
- **Paywall** (`PaywallView.swift`):
  - A screen that is presented to non-subscribed users when they attempt to access a premium feature.
  - It clearly lists the benefits of subscribing and displays the different subscription options (e.g., monthly, yearly).

### How it works
1.  **Client-Side (Purchase)**:
    -   `SubscriptionManager.swift` is a singleton that manages all interactions with Apple's StoreKit.
    -   It fetches available subscription products, handles the purchase flow, and listens for transaction updates.
    -   When a user initiates a purchase from `PaywallView.swift`, it calls the `SubscriptionManager`.

2.  **Backend (Validation)**:
    -   Upon a successful transaction, the client sends the purchase receipt to the backend.
    -   The `validateReceipt.ts` Cloud Function communicates with Apple's servers to verify that the receipt is valid.
    -   If the receipt is valid, the `activateSubscription.ts` function is triggered, which updates the user's document in Firestore with their current subscription status and expiration date.

3.  **Unlocking Features**:
    -   The app's UI (e.g., `GenerateView.swift`) checks the user's subscription status from their Firestore profile to determine whether to show the paywall or grant access to premium features.

### Analytics
- **Client**: `AnalyticsManager.swift` logs events for:
    -   When a paywall is displayed.
    -   When a user starts the purchase process.
    -   When a purchase is successful or fails.

---

## UI Implementation: Cards & Scrollable List

- __Context__: This implementation is used in screens like `GenerateView` (for results) and `SavedDatesView` (for saved plans) to display a list of date ideas.
- __What it does__: Renders a vertical, scrollable list of custom-designed cards, each representing a single date plan or adventure.

### Core Components
1.  **Scrollable Container**:
    -   A `ScrollView` is used as the root container to allow vertical scrolling through the list of cards.
    -   Inside the `ScrollView`, a `VStack` arranges the cards vertically with appropriate spacing.

2.  **Data Iteration**:
    -   A `ForEach` loop iterates over an array of plan models (e.g., `[CampusPlan]`).
    -   Each iteration creates an instance of a custom card view, passing in the data for a single plan.

3.  **Custom Card View** (e.g., `PlanCardView.swift` - hypothetical name):
    -   **Root**: The card is typically a `VStack` with a background color and rounded corners (`.cornerRadius()`).
    -   **Image**: An `AsyncImage` is used to load and display the venue's photo from a URL.
    -   **Text Content**: A `VStack` within the card holds the textual information:
        -   `Text("Jack's Adventure")` for the title, with a large, bold font.
        -   `Text` for distance, address, and the main description/activity.
        -   `Text("Photo Idea: ...")` for the photo prompt.
    -   **Action Buttons**: An `HStack` at the bottom of the card contains the action buttons:
        -   A `Button` with a bookmark `Image(systemName: "bookmark")` to save/unsave the plan.
        -   A `Button` with a camera `Image(systemName: "camera")` to either start the adventure or capture a specific photo.

### Example Structure (Conceptual)

```swift
// In a view like SavedDatesView.swift

import SwiftUI

struct SavedDatesView: View {
    @StateObject var viewModel = SavedPlansViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(viewModel.savedPlans) { plan in
                    PlanCardView(plan: plan)
                }
            }
            .padding()
        }
        .navigationTitle("Saved Adventures")
    }
}

// A dedicated view for the card itself
struct PlanCardView: View {
    let plan: CampusPlan

    var body: some View {
        VStack(alignment: .leading) {
            AsyncImage(url: URL(string: plan.imageUrl))
                .aspectRatio(contentMode: .fill)
                .frame(height: 200)
                .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(plan.title).font(.title).bold()
                Text("\(plan.distance) miles away")
                Text(plan.address)
                Text(plan.activityDescription)
                Text("Photo Idea: \(plan.photoIdea)")

                HStack {
                    Button(action: { /* Save action */ }) {
                        Image(systemName: "bookmark")
                    }
                    Button(action: { /* Camera action */ }) {
                        Image(systemName: "camera")
                    }
                }
            }
            .padding()
        }
        .background(Color.pink.opacity(0.8))
        .cornerRadius(15)
    }
}
```

---

## UI Implementation: Camera

- __Context__: The camera is a core component of the "Adventure" gameplay, used to capture photos and videos for mission tasks (`GameToPlayView.swift`, `CheckpointPhotoView.swift`) and point-earning events (`PointsPhotoCaptureView.swift`).
- __Locations__: `PhotoCaptureView.swift`, `VideoCaptureView.swift`, and the `Camera/` directory.

### Core Components
1.  **SwiftUI and UIKit Integration**:
    -   The camera functionality is built using Apple's `AVFoundation` framework, which is part of UIKit.
    -   To use it within the SwiftUI app, a wrapper view using `UIViewControllerRepresentable` is created. This allows the UIKit-based camera controller to be embedded seamlessly into SwiftUI views.

2.  **Capture Views**:
    -   `PhotoCaptureView.swift`: A dedicated view that handles the setup and presentation of the camera for taking still photos.
    -   `VideoCaptureView.swift`: A similar view, but configured for recording videos.

3.  **Camera UI Controls**:
    -   **Camera Preview**: A live feed from the selected camera (front or back).
    -   **Shutter Button**: The main circular button at the bottom to capture a photo or start/stop video recording.
    -   **Flash Toggle**: An icon button (often a lightning bolt) at the top to cycle through flash modes (on, off, auto).
    -   **Camera Switcher**: An icon button to toggle between the front-facing and rear-facing cameras.

4.  **Presentation**:
    -   The camera is typically presented as a full-screen modal sheet that covers the entire screen, providing an immersive capture experience. This is likely handled by a view like `CameraSheet.swift` which would contain the `PhotoCaptureView` or `VideoCaptureView`.

### How it works (Conceptual)
1.  A parent view (e.g., `GameToPlayView`) has a button that, when tapped, sets a state variable like `@State private var showCamera = true`.
2.  This state variable controls the presentation of the camera sheet using the `.sheet()` or `.fullScreenCover()` modifier in SwiftUI.
3.  The camera view (`PhotoCaptureView`) is displayed. It manages the `AVCaptureSession` to show the live preview.
4.  When the user presses the shutter, the view captures the image data.
5.  The captured image is then passed back to the parent view via a completion handler or a binding. The parent view can then display a preview of the captured image or begin uploading it.

### Example Structure (Conceptual)

```swift
// In a view that needs to open the camera

struct GameToPlayView: View {
    @State private var showCamera = false
    @State private var capturedImage: UIImage?

    var body: some View {
        VStack {
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Button("Complete Game: Take a Photo") {
                    showCamera = true
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            PhotoCaptureView { image in
                self.capturedImage = image
                self.showCamera = false
            }
        }
    }
}
```

---

## Feature: AR Camera Filter Overlay

- __Locations__: `DateGenie/Views/Camera/CustomCameraView.swift`, `DateGenie/AR/Filters/`, `DateGenie/Views/Camera/ARViewContainer.swift`
- __What it does__: Provides an augmented reality camera experience that overlays 2D stickers (like the Kappa Sigma sticker) on top of the live camera feed, allowing users to take photos with custom AR filters.

### Core Architecture

#### 1. **Dual Camera System**
- **Standard Camera Mode**: Uses `AVFoundation` (`AVCaptureSession`) for normal photo/video capture
- **AR Filter Mode**: Uses `ARKit` + `RealityKit` for AR overlay rendering
- **Seamless Switching**: Handles camera handoff between modes without crashes or darkening

#### 2. **AR Filter Components**
- **Filter Registry** (`FilterRegistry.swift`):
  - Defines available AR filters (currently `kappaSigmaSticker`)
  - Each filter has properties: `assetName` (Texture Set), `uiThumbnailName` (Image Set), scale, interaction permissions
- **Element Factory** (`ElementFactory.swift`):
  - Creates RealityKit entities from filter definitions
  - Handles texture loading with fallback strategies
  - Generates 2D planes with proper materials for stickers

#### 3. **Camera Integration**
- **CustomCameraView**: Main SwiftUI view that orchestrates both camera modes
- **CameraController**: Manages AVCaptureSession lifecycle and teardown
- **ARViewContainer**: SwiftUI wrapper for RealityKit's ARView

### Current Implementation Details

#### **Filter Configuration**
```swift
// FilterRegistry.swift
static let kappaSigmaSticker = FilterElement(
    name: "Kappa Sigma",
    kind: .sticker2D,
    assetName: "kappa_sigma_sticker",        // RealityKit Texture Set
    defaultScale: 0.25,
    allowsDrag: true,
    allowsRotate: true,
    allowsScale: true,
    billboard: true,
    uiThumbnailName: "kappa_sigma_thumbnail" // UIKit Image Set for UI
)
```

#### **Asset Setup Requirements**
- **Texture Set**: `kappa_sigma_sticker` - configured for RealityKit with:
  - sRGB color space
  - Alpha channel enabled
  - Mipmaps enabled
  - Lossless compression
- **Image Set**: `kappa_sigma_thumbnail` - for UI elements (shutter overlay, picker button)

#### **Camera Mode Switching**
```swift
// When enabling AR mode:
controller.stopRunning()
controller.teardownSession { /* AR starts via task(id: arView) */ }

// When disabling AR mode:
removeFilterOverlay()
controller.configure { ok in if ok { controller.startRunning() } }
```

#### **AR Session Management**
- **Startup**: Uses `.task(id: arView)` to ensure AR session starts once when view binds
- **Readiness Check**: Waits for `trackingState == .normal` before adding overlay
- **Two-Stage Attachment**:
  1. **Stage 1**: Immediately add placeholder entity (white plane)
  2. **Stage 2**: After 0.15s delay, load texture and apply to entity

#### **Texture Loading Strategy**
```swift
// Priority order for texture loading:
1. UIImage(named: uiThumbnailName) → CGImage → TextureResource.generate(from:)
2. TextureResource(named: assetName) [iOS 18+]
3. TextureResource.load(named: assetName) [iOS 17]
4. Fallback to white material if all fail
```

#### **Photo Capture in AR Mode**
```swift
if filterActive {
    // Use ARView snapshot instead of AVCapturePhotoOutput
    arView?.snapshot(saveToHDR: false) { image in
        // Process AR scene as JPEG
    }
} else {
    // Use standard AVCapturePhotoOutput
    controller.capturePhoto(flashMode: flashMode, delegate: delegate)
}
```

#### **Gesture Controls Implementation**
```swift
// Gesture state tracking
@State private var dragPrev: CGSize = .zero
@State private var baseScale: Float = 1.0
@State private var currentScale: Float = 1.0
@State private var baseRotationZ: Float = 0.0
@State private var currentRotationZ: Float = 0.0

// Full-screen gesture layer (when filterActive == true)
Color.clear
    .contentShape(Rectangle())
    .gesture(
        DragGesture()
            .onChanged { value in
                let dx = value.translation.width - dragPrev.width
                let dy = value.translation.height - dragPrev.height
                dragPrev = value.translation
                let metersPerPoint: Float = 0.001 // approx at ~0.5m
                if var pos = overlayEntity?.position {
                    pos.x += Float(dx) * metersPerPoint
                    pos.y -= Float(dy) * metersPerPoint
                    overlayEntity?.position = pos
                }
            }
            .onEnded { _ in dragPrev = .zero }
    )
    .simultaneousGesture(
        MagnificationGesture()
            .onChanged { value in
                let newScale = max(0.1, min(4.0, baseScale * Float(truncating: value as NSNumber)))
                currentScale = newScale
                overlayEntity?.setScale(SIMD3<Float>(repeating: newScale), relativeTo: nil)
            }
            .onEnded { _ in baseScale = currentScale }
    )
    .simultaneousGesture(
        RotationGesture()
            .onChanged { value in
                let angle = baseRotationZ + Float(value.radians)
                currentRotationZ = angle
                overlayEntity?.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0,0,1))
            }
            .onEnded { _ in baseRotationZ = currentRotation }
    )
```

**Gesture Behavior Details:**
- **Positioning**: Drag moves the sticker in camera space (anchored to `.camera`)
- **Scaling**: Pinch scales from 0.1x to 4.0x with smooth transitions
- **Rotation**: Two-finger rotation spins around the Z-axis (perpendicular to screen)
- **Simultaneous**: All three gestures can be used together for complex manipulation
- **Persistence**: Gesture state is maintained between interactions
- **Performance**: Updates apply directly to RealityKit entities on main thread

### Current Status & Known Issues

#### **✅ Working Features**
- Camera mode switching (standard ↔ AR) without crashes
- AR sticker appears and renders correctly
- Photo capture works in both modes
- UI thumbnail displays properly
- Stable AR session startup
- **Gesture Controls**: Drag, rotate, and scale the AR overlay
  - **Drag**: Touch and drag to move the sticker around the screen
  - **Scale**: Pinch to zoom in/out (range: 0.1x to 4.0x)
  - **Rotation**: Two-finger rotate to spin the sticker

#### **⚠️ Current Issues**
1. **Transparency**: Sticker has black background instead of transparent
   - **Cause**: Material setup may not be preserving PNG alpha channel
   - **Location**: `ElementFactory.makeSticker2D()` material configuration

2. ~~**Missing Gestures**: No drag/rotate/scale controls for the filter~~ ✅ **RESOLVED**
   - **Status**: Gesture controls are now fully implemented and working
   - **Implementation**: Full-screen gesture layer in `CustomCameraView` with:
     - `DragGesture()` for positioning
     - `MagnificationGesture()` for scaling (0.1x - 4.0x range)
     - `RotationGesture()` for rotation around Z-axis

#### **🔧 Technical Constraints**
- **iOS Compatibility**: Supports iOS 17+ with fallbacks for older APIs
- **Camera Handoff**: Must fully teardown AVCaptureSession before ARKit starts
- **Thread Safety**: All RealityKit operations must be on main thread
- **Memory Management**: Proper cleanup of camera resources and AR entities

### File Structure & Dependencies

```
DateGenie/
├── Views/Camera/
│   ├── CustomCameraView.swift      # Main camera view with mode switching
│   ├── ARViewContainer.swift       # SwiftUI wrapper for ARView
│   ├── FilterPickerButton.swift    # UI button for filter selection
│   └── CameraPreviewView.swift    # Standard camera preview
├── AR/Filters/
│   ├── FilterElement.swift         # Data model for filter properties
│   ├── FilterRegistry.swift        # Available filters configuration
│   └── ElementFactory.swift        # RealityKit entity creation
├── Camera/
│   └── CameraController.swift      # AVCaptureSession management
└── Assets.xcassets/
    ├── kappa_sigma_sticker.imageset/    # Texture Set for AR
    └── kappa_sigma_thumbnail.imageset/  # Image Set for UI
```

### Usage Flow

1. **User opens camera** → `CustomCameraView` loads with standard camera mode
2. **User taps filter picker** → `setFilterActive(true)` called
3. **Camera handoff** → AVCaptureSession stopped and torn down
4. **AR session starts** → ARView initializes via `.task(id: arView)`
5. **Overlay attachment** → Placeholder entity added, then textured after delay
6. **User takes photo** → ARView snapshot captures scene with overlay
7. **User disables filter** → AR session stopped, standard camera resumes

### Future Enhancements

#### **Planned Features**
- **Gesture Controls**: Drag, rotate, scale the AR overlay
- **Multiple Filters**: Support for additional sticker types
- **Filter Categories**: Organize filters by theme or style
- **Custom Positioning**: Save user's preferred filter positions

#### **Technical Improvements**
- **Performance**: Optimize texture loading and material switching
- **Stability**: Add error recovery for failed texture loads
- **Accessibility**: Voice control and assistive technology support
- **Analytics**: Track filter usage and user preferences

### Troubleshooting Guide

#### **Common Issues**
1. **Camera goes dark**: Check AVCaptureSession teardown in `CameraController.teardownSession()`
2. **Sticker doesn't appear**: Verify `trackingState == .normal` before overlay attachment
3. **App crashes on filter**: Check asset catalog configuration and texture loading fallbacks
4. **Black background**: Verify PNG alpha channel and material setup in `ElementFactory`

#### **Debug Steps**
1. Check console for "Video texture allocator is not initialized" errors
2. Verify asset names match between code and asset catalog
3. Test texture loading with `UIImage(named:)` outside AR context
4. Monitor AR session state transitions in debugger

### Notes
- **Testing**: AR features require physical device (not simulator)
- **Performance**: AR mode is more resource-intensive than standard camera
- **Battery**: Extended AR usage may impact device battery life
- **Permissions**: Camera and AR permissions required for full functionality