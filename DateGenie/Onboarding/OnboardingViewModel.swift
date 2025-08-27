import Foundation
import SwiftUI

final class OnboardingViewModel: ObservableObject {
    enum Step { case name, upload }

    @Published var step: Step = .name
    @Published var businessName: String = "" {
        didSet { storedBusinessName = businessName }
    }
    @Published var logoImage: UIImage? = nil
    @Published var businessSlogan: String = "" {
        didSet { storedBusinessSlogan = businessSlogan }
    }

    @AppStorage("onboarding.businessName") private var storedBusinessName: String = ""
    @AppStorage("onboarding.logoPath") private var storedLogoPath: String = ""
    @AppStorage("onboarding.businessSlogan") private var storedBusinessSlogan: String = ""
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false

    init() {
        businessName = storedBusinessName
        if let img = Self.loadImage(atPath: storedLogoPath) { logoImage = img }
        businessSlogan = storedBusinessSlogan
    }

    var isBusinessNameValid: Bool { !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canGetStarted: Bool { logoImage != nil }

    func advanceFromName() {
        guard isBusinessNameValid else { return }
        step = .upload
    }

    func setLogoImage(_ image: UIImage) {
        logoImage = image
        if let path = Self.saveImageToDocuments(image: image) { storedLogoPath = path }
    }

    func completeOnboarding() {
        guard canGetStarted else { return }
        hasSeenOnboarding = true
    }

    private static func saveImageToDocuments(image: UIImage) -> String? {
        guard let data = image.pngData() else { return nil }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("onboarding_logo.png")
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    private static func loadImage(atPath path: String) -> UIImage? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
        return img
    }
}


