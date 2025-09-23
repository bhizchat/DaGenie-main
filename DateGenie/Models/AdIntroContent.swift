import Foundation

enum Archetype: String {
    case scratch
    case rufus
    case cory
    case stories
}

struct AdIntroContent {
    let title: String?
    let description: String?
    let example: String?
    let imageName: String?
    let archetype: Archetype

    static let stories = AdIntroContent(
        title: "Animated Stories",
        description: "Create short animated stories. Start by uploading a photo and typing what happens in the scene.",
        example: "e.g. ‘Show the hero discovering a hidden portal in the forest.’",
        imageName: "glinda",
        archetype: .stories
    )

    static let rufus = AdIntroContent(
        title: "Rufus",
        description: "If your brand is about food, lifestyle, or anything fun, a Chill Panda persona brings humor, laid-back vibes, and street-smart charm. With a “fuhgeddaboudit” attitude and a New York accent, this archetype signals approachability and entertainment. Perfect for brands that want to emphasize being real, relatable, and a little funny",
        example: "e.g. Show the chill panda promoting a snack brand [Name your brand], relaxing in a bamboo lounge crib [Location], while cracking a funny joke and sipping from a soda can [Action].",
        imageName: "Rufus",
        archetype: .rufus
    )

    static let cory = AdIntroContent(
        title: "Cory the Lion",
        description: "Cory the Lion is the official Mascot for Campus Burgers , he eats about 25 Campus Cheese Burgers everyday and holds the record for the most burgers eaten in america for a year. In his free time Cory like to play competitive top golf with other mascots in various campuses and is also a gymnast",
        example: "e.g  Show Cory eating about 5 burgers in a row and doing a backflip to celebrate",
        imageName: "Cory",
        archetype: .cory
    )

    static let scratch = AdIntroContent(
        title: nil,
        description: nil,
        example: nil,
        imageName: "welcome_genie",
        archetype: .scratch
    )
}


