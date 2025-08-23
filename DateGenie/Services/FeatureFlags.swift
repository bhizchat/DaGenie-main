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
}


