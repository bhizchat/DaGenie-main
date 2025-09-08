import Foundation

/// Small in-app registry of demo elements. Replace/extend as we design filters.
enum FilterRegistry {
    static let demoSticker = FilterElement(
        name: "Heart Sticker",
        kind: .sticker2D,
        assetName: "Logo_DG", // reuse an existing asset name for now
        defaultScale: 0.22,
        allowsDrag: true,
        allowsRotate: true,
        allowsScale: true,
        billboard: true
    )

    static let kappaSigmaSticker = FilterElement(
        name: "Kappa Sigma",
        kind: .sticker2D,
        assetName: "kappa_sigma_sticker", // your new PNG asset
        defaultScale: 0.25,
        allowsDrag: true,
        allowsRotate: true,
        allowsScale: true,
        billboard: true,
        uiThumbnailName: "kappa_sigma_thumbnail"
    )

    static let blackScholarsSticker = FilterElement(
        name: "Black Scholars",
        kind: .sticker2D,
        assetName: "black_scholars_sticker",
        defaultScale: 0.25,
        allowsDrag: true,
        allowsRotate: true,
        allowsScale: true,
        billboard: true,
        uiThumbnailName: "black-scholars-thumbnail"
    )

    // New filters
    static let artsVillage = FilterElement(
        name: "Arts Village",
        kind: .sticker2D,
        assetName: "arts_village",
        defaultScale: 0.28,
        allowsDrag: true,
        allowsRotate: true,
        allowsScale: true,
        billboard: true,
        uiThumbnailName: "arts_village"
    )

    static let sustainableSpartans = FilterElement(
        name: "Sustainable Spartans",
        kind: .sticker2D,
        assetName: "sus_spartan",
        defaultScale: 0.30,
        allowsDrag: true,
        allowsRotate: true,
        allowsScale: true,
        billboard: true,
        uiThumbnailName: "sus_spartan"
    )

    static let rainbowVillage = FilterElement(
        name: "Rainbow Village",
        kind: .sticker2D,
        assetName: "rainbow_village",
        defaultScale: 0.28,
        allowsDrag: true,
        allowsRotate: true,
        allowsScale: true,
        billboard: true,
        uiThumbnailName: "rainbow_village"
    )

    static let addamsHalloween = FilterElement(
        name: "Addams Halloween",
        kind: .sticker2D,
        assetName: "addams_halloween",
        defaultScale: 0.30,
        allowsDrag: true,
        allowsRotate: true,
        allowsScale: true,
        billboard: true,
        uiThumbnailName: "addams_halloween"
    )

    static let marioBlock = FilterElement(
        name: "Mario Block",
        kind: .sticker2D,
        assetName: "mario_block",
        defaultScale: 0.26,
        allowsDrag: true,
        allowsRotate: true,
        allowsScale: true,
        billboard: true,
        uiThumbnailName: "mario_block"
    )

    /// Index of the element that should be selected when the camera UI first appears.
    static let defaultIndex = 0 // kappaSigmaSticker

    static let all: [FilterElement] = [
        kappaSigmaSticker,
        blackScholarsSticker,
        artsVillage,
        sustainableSpartans,
        rainbowVillage,
        addamsHalloween,
        marioBlock
    ]
}


