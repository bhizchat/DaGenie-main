import Foundation

@MainActor
final class CharacterRepository: ObservableObject {
    static let shared = CharacterRepository()
    private init() { loadCustomCharacters() }

    enum FeatureFlags {
        static var characterReferenceV2: Bool { true }
    }

    private let customStoreKey = "custom_characters_v1"
    @Published var customCharacters: [GenCharacter] = []

    private func loadCustomCharacters() {
        if let data = UserDefaults.standard.data(forKey: customStoreKey) {
            if let arr = try? JSONDecoder().decode([GenCharacter].self, from: data) {
                self.customCharacters = arr
            }
        }
    }

    func addCustomCharacter(_ character: GenCharacter) {
        var set = customCharacters
        // Replace if existing id matches
        if let idx = set.firstIndex(where: { $0.id == character.id }) {
            set[idx] = character
        } else {
            set.append(character)
        }
        customCharacters = set
        if let data = try? JSONEncoder().encode(set) {
            UserDefaults.standard.set(data, forKey: customStoreKey)
        }
    }

    /// Temporary stub: return local header-capable characters until backend is wired.
    func fetchCharacter(id: String) async -> GenCharacter? {
        let normalized = id.lowercased()
        // Check custom characters first
        if let found = customCharacters.first(where: { $0.id.lowercased() == normalized }) {
            return found
        }
        let characters: [String: GenCharacter] = [
            // Primary example (already shown in app)
            "cory": GenCharacter(
                id: "cory",
                name: "Cory the Lion",
                defaultImageUrl: "https://storage.googleapis.com/dategenie-static/characters/cory/default.png",
                assetImageUrls: ["https://storage.googleapis.com/dategenie-static/characters/cory/pose1.png"],
                localAssetName: "Cory"
            ),
            // Characters from the selection grid (second screenshot)
            "50": GenCharacter(id: "50", name: "50 Cent", defaultImageUrl: "", assetImageUrls: [], localAssetName: "50"),
            "hormo": GenCharacter(id: "hormo", name: "Hormo-Simpson", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Hormo"),
            "ishow": GenCharacter(id: "ishow", name: "Ishow-Speedster", defaultImageUrl: "", assetImageUrls: [], localAssetName: "ishow"),
            "astro": GenCharacter(id: "astro", name: "The Astrophysicist", defaultImageUrl: "", assetImageUrls: [], localAssetName: "astro"),
            "musk": GenCharacter(id: "musk", name: "Starship-Musk", defaultImageUrl: "", assetImageUrls: [], localAssetName: "musk"),
            "supertrump": GenCharacter(id: "supertrump", name: "SuperTrump", defaultImageUrl: "", assetImageUrls: [], localAssetName: "supertrump"),
            "ceo": GenCharacter(id: "ceo", name: "CEO", defaultImageUrl: "", assetImageUrls: [], localAssetName: "CEO"),
            "tech": GenCharacter(id: "tech", name: "The Technologist", defaultImageUrl: "", assetImageUrls: [], localAssetName: "tech"),
            // Additional characters from screenshots
            "giant": GenCharacter(id: "giant", name: "The Giant", defaultImageUrl: "", assetImageUrls: [], localAssetName: "giant"),
            "investor": GenCharacter(id: "investor", name: "The Investor", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Investor"),
            "philo": GenCharacter(id: "philo", name: "The Philanthropist", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Philo"),
            "innovators": GenCharacter(id: "innovators", name: "The Innovators", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Innovators"),
            "doctor": GenCharacter(id: "doctor", name: "The Doctor", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Doctor"),
            "talkshow": GenCharacter(id: "talkshow", name: "The Talk Show Host", defaultImageUrl: "", assetImageUrls: [], localAssetName: "talkshow"),
            "gymnast": GenCharacter(id: "gymnast", name: "The Gymnast", defaultImageUrl: "", assetImageUrls: [], localAssetName: "gymnast"),
            "t8": GenCharacter(id: "t8", name: "The Popstar", defaultImageUrl: "", assetImageUrls: [], localAssetName: "T8"),
            "activist": GenCharacter(id: "activist", name: "The Activist", defaultImageUrl: "", assetImageUrls: [], localAssetName: "activist"),
            "speaker": GenCharacter(id: "speaker", name: "The Speaker", defaultImageUrl: "", assetImageUrls: [], localAssetName: "speaker"),
            "kingpin": GenCharacter(id: "kingpin", name: "The King Pin", defaultImageUrl: "", assetImageUrls: [], localAssetName: "kingpin"),
            "vc": GenCharacter(id: "vc", name: "The Venture Capitalist", defaultImageUrl: "", assetImageUrls: [], localAssetName: "VC"),
            "athlete": GenCharacter(id: "athlete", name: "The Athlete", defaultImageUrl: "", assetImageUrls: [], localAssetName: "athlete"),
            "player": GenCharacter(id: "player", name: "The Player", defaultImageUrl: "", assetImageUrls: [], localAssetName: "player"),
            "baller": GenCharacter(id: "baller", name: "The Baller", defaultImageUrl: "", assetImageUrls: [], localAssetName: "baller"),
            "wrestler": GenCharacter(id: "wrestler", name: "The Wrestler", defaultImageUrl: "", assetImageUrls: [], localAssetName: "wrestler"),
            "psychologist": GenCharacter(id: "psychologist", name: "The Psychologist", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Psychologist"),
            "contrarian": GenCharacter(id: "contrarian", name: "The Contrarian", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Contrarian"),
            // Final batch
            "billionaire": GenCharacter(id: "billionaire", name: "The Billionaire", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Billionaire"),
            "mrbeast": GenCharacter(id: "mrbeast", name: "MR BEAST", defaultImageUrl: "", assetImageUrls: [], localAssetName: "MrBeast"),
            "actress": GenCharacter(id: "actress", name: "The Actress", defaultImageUrl: "", assetImageUrls: [], localAssetName: "actress"),
            "self_help": GenCharacter(id: "self_help", name: "The Self Help Teacher", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Self_Help"),
            "glinda": GenCharacter(id: "glinda", name: "Ariana Glinda", defaultImageUrl: "", assetImageUrls: [], localAssetName: "glinda"),
            "oprah": GenCharacter(id: "oprah", name: "Oprah", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Oprah"),
            "theswift": GenCharacter(id: "theswift", name: "The Swift", defaultImageUrl: "", assetImageUrls: [], localAssetName: "theswift"),
            // Newly added row
            "polymath": GenCharacter(id: "polymath", name: "The Polymath", defaultImageUrl: "", assetImageUrls: [], localAssetName: "polymath"),
            "mentor": GenCharacter(
                id: "mentor",
                name: "The Mentor",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "mentor",
                bio: "A calm voice in a noisy world, The Mentor is a modern philosopher who blends timeless wisdom with practical guidance. Inspired by Naval Ravikant, he challenges people to step back from the chaos, reflect deeply, and uncover their true path. As both an entrepreneur and investor, he teaches not just about building wealth, but about building a meaningful life. His presence is steady and grounding—helping others unlock clarity, self-knowledge, and freedom while navigating the complexities of ambition and existence."
            ),
            "podcaster": GenCharacter(id: "podcaster", name: "The Podcaster", defaultImageUrl: "", assetImageUrls: [], localAssetName: "podcaster"),
            "finance_woman": GenCharacter(id: "finance_woman", name: "The Finance Woman", defaultImageUrl: "", assetImageUrls: [], localAssetName: "finance_woman"),
            "mr.wonderful": GenCharacter(id: "mr.wonderful", name: "Mr.Wonderful", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Mr.Wonderful"),
            "rob": GenCharacter(id: "rob", name: "Rob the Bank", defaultImageUrl: "", assetImageUrls: [], localAssetName: "rob"),
            "social": GenCharacter(id: "social", name: "The Social Entrepreneur", defaultImageUrl: "", assetImageUrls: [], localAssetName: "social"),
            "tech_media": GenCharacter(id: "tech_media", name: "TECH  MEDIA", defaultImageUrl: "", assetImageUrls: [], localAssetName: "Tech _Media"),
            "startup_advisor": GenCharacter(
                id: "startup_advisor",
                name: "The Startup Advisor",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "startup_advisor",
                bio: "The Startup Advisor is the wise architect of Silicon Valley dreams, a mentor whose words have launched countless founders on their journeys. Inspired by Paul Graham, he blends sharp intellect with practical frameworks, teaching the art of product‑market fit, fundraising strategies, and building enduring companies. With a mix of philosophy and tactical wisdom, he helps entrepreneurs cut through noise, focus on what matters, and scale ideas into generational businesses."
            )
            ,
            // Newly added characters (local assets pre-bundled)
            "philosopher": GenCharacter(id: "philosopher", name: "The Philosopher", defaultImageUrl: "", assetImageUrls: [], localAssetName: "philosopher"),
            "creator": GenCharacter(id: "creator", name: "The Creator", defaultImageUrl: "", assetImageUrls: [], localAssetName: "creator"),
            "eyelish": GenCharacter(id: "eyelish", name: "EyeLish", defaultImageUrl: "", assetImageUrls: [], localAssetName: "eyelish"),
            "charmer": GenCharacter(id: "charmer", name: "The Charmer", defaultImageUrl: "", assetImageUrls: [], localAssetName: "charmer"),
            "singer": GenCharacter(id: "singer", name: "The Singer", defaultImageUrl: "", assetImageUrls: [], localAssetName: "singer"),
            "tma": GenCharacter(id: "tma", name: "The Martial Artist", defaultImageUrl: "", assetImageUrls: [], localAssetName: "TMA"),
            "youtuber": GenCharacter(id: "youtuber", name: "The Youtuber", defaultImageUrl: "", assetImageUrls: [], localAssetName: "youtuber"),
            "comedian": GenCharacter(id: "comedian", name: "The Comedian", defaultImageUrl: "", assetImageUrls: [], localAssetName: "comedian"),
            "director": GenCharacter(id: "director", name: "The Director", defaultImageUrl: "", assetImageUrls: [], localAssetName: "director"),
            "astronaut": GenCharacter(id: "astronaut", name: "The Astronaut", defaultImageUrl: "", assetImageUrls: [], localAssetName: "astronaut"),
            "couple": GenCharacter(id: "couple", name: "The Couple", defaultImageUrl: "", assetImageUrls: [], localAssetName: "couple"),
            "company": GenCharacter(id: "company", name: "The Company", defaultImageUrl: "", assetImageUrls: [], localAssetName: "company")
        ]

        return characters[normalized]
    }
}


