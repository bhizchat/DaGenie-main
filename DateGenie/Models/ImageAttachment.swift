import Foundation
import SwiftUI

struct ImageAttachment: Identifiable, Equatable {
    let id: UUID
    var image: UIImage
    var originalAssetId: String?

    init(id: UUID = UUID(), image: UIImage, originalAssetId: String? = nil) {
        self.id = id
        self.image = image
        self.originalAssetId = originalAssetId
    }
}


