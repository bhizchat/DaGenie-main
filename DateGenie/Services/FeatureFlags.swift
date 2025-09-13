import Foundation

enum FeatureFlags {
    // Toggle to use the new custom camera. Defaults to true for internal testing.
    static var useCustomCamera: Bool {
        get {
            if let v = UserDefaults.standard.object(forKey: "ff_useCustomCamera") as? Bool { return v }
            return true
        }
        set { UserDefaults.standard.set(newValue, forKey: "ff_useCustomCamera") }
    }

    // Enable the new AR overlays camera mode (RealityKit-based). Default false until ready.
    static var useAROverlays: Bool {
        get {
            if let v = UserDefaults.standard.object(forKey: "ff_useAROverlays") as? Bool { return v }
            return false
        }
        set { UserDefaults.standard.set(newValue, forKey: "ff_useAROverlays") }
    }

    // Enable CI-based compositing for still-image overlays during export.
    // When true, PNG overlays are composited with CISourceOverCompositing via applyingCIFiltersWithHandler.
    static var useCIOverlayCompositing: Bool {
        get {
            if let v = UserDefaults.standard.object(forKey: "ff_useCIOverlayCompositing") as? Bool { return v }
            return false
        }
        set { UserDefaults.standard.set(newValue, forKey: "ff_useCIOverlayCompositing") }
    }

    // When true, project persistence (Firestore/Storage) is disabled.
    // Use this to run creation flows without saving projects.
    static var disableProjectSaving: Bool {
        get {
            if let v = UserDefaults.standard.object(forKey: "ff_disableProjectSaving") as? Bool { return v }
            return true
        }
        set { UserDefaults.standard.set(newValue, forKey: "ff_disableProjectSaving") }
    }
}


