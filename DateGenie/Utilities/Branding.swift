import Foundation
import UIKit

enum Branding {
    /// Returns the stored transparent logo image if available.
    static func loadStoredLogo() -> UIImage? {
        let defaults = UserDefaults.standard
        let key = "onboarding.logoPath"
        guard let path = defaults.string(forKey: key), !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}


