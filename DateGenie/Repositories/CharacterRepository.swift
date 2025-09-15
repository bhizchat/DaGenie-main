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
            "boss": GenCharacter(
                id: "boss",
                name: "The BOSS",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "boss",
                bio: "Databases? Built them. Companies? Scaled them. Inspired by Larry Ellison's rise with Oracle, The BOSS embodies relentless ambition and the will to fight for every win. He doesn't just play the game—he rewrites the rules. With sharp instincts, unshakable confidence, and an unyielding drive, The BOSS thrives in high-stakes battles where others fold. Every setback fuels his climb, every challenge sharpens his edge. He's not here to follow—he's here to dominate."
            ),
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
            "philosopher": GenCharacter(
                id: "philosopher",
                name: "The Philosopher",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "philosopher",
                bio: "Power, strategy, and timeless truths—he studies them all. Inspired by Robert Greene, The Philosopher is a seeker of wisdom who turns ancient lessons into modern insights. By candlelight, he dissects the hidden laws that govern ambition, influence, and human nature. He’s not just reading history—he’s distilling it into principles for today’s battles, guiding anyone bold enough to think deeper."
            ),
            "creator": GenCharacter(
                id: "creator",
                name: "The Creator",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "creator",
                bio: "Safe? Predictable? Not his style. Inspired by Tyler, the Creator, this artist lives at the edge of imagination—bold, fearless, and unapologetically original. Every performance, every lyric, every look is a challenge to the ordinary. The Creator doesn’t just make music; he makes worlds, bending sound, fashion, and art into something entirely his own."
            ),
            "eyelish": GenCharacter(
                id: "eyelish",
                name: "EyeLish",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "eyelish",
                bio: "Whispers turned into anthems, vulnerability into strength. Inspired by Billie Eilish, EyeLish is a musical creative with a voice that bends genres and moods. With haunting melodies, raw honesty, and a style all her own, she transforms emotion into soundscapes that linger long after the song ends. She’s not just making music—she’s reshaping what it means to be heard."
            ),
            "charmer": GenCharacter(
                id: "charmer",
                name: "The Charmer",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "charmer",
                bio: "A smile, a glance, a perfectly timed word—he makes it look effortless. Inspired by Pedro Pascal, The Charmer is a man who knows how to win hearts and command attention. Whether on screen as a celebrated actor or off screen where his charm disarms even the toughest crowd, he’s always in control of the moment. He doesn’t just walk into a room—he owns it, leaving everyone wondering how they got caught under his spell."
            ),
            "singer": GenCharacter(
                id: "singer",
                name: "The Singer",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "singer",
                bio: "From bedroom covers to stadium lights, he’s lived the dream. Inspired by Justin Bieber, The Singer is the teenage heartthrob who defined a generation of pop stardom. With chart‑topping hits, effortless stage presence, and undeniable swag, he knows exactly how to win hearts everywhere he goes. He’s not just performing songs—he’s setting the soundtrack to growing up."
            ),
            "tma": GenCharacter(
                id: "tma",
                name: "The Martial Artist",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "TMA",
                bio: "Strength, speed, and discipline—he embodies them all. Inspired by Bruce Lee, The Martial Artist is a born fighter whose mastery of movement turns combat into poetry. With precision strikes, unshakable focus, and a will forged through relentless training, he’s proof that the mind and body can move as one. He’s not just fighting battles—he’s living a philosophy of power, balance, and self‑mastery."
            ),
            "youtuber": GenCharacter(
                id: "youtuber",
                name: "The Youtuber",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "youtuber",
                bio: "From bedroom uploads to global fame, he built an empire one video at a time. Inspired by the rise of PewDiePie, The Youtuber turned gameplay, jokes, and pure personality into a cultural phenomenon. With a camera, a mic, and a fearless sense of humor, he transformed internet entertainment forever. He’s not just creating content—he’s creating a community."
            ),
            "comedian": GenCharacter(
                id: "comedian",
                name: "The Comedian",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "comedian",
                bio: "Every punchline lands, every story leaves you laughing harder than the last. Inspired by the funny nature of Kevin Hart, The Comedian turns everyday life into comedy gold. With quick wit, boundless energy, and a knack for timing, he can turn any stage into his own. He’s not just telling jokes—he’s bringing people together through laughter."
            ),
            "director": GenCharacter(
                id: "director",
                name: "The Director",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "director",
                bio: "Every frame a story, every detail an obsession. Inspired by Steven Spielberg, The Director lives for the magic of cinema. With relentless dedication, he builds entire worlds from behind the camera, blending vision, heart, and craft into films that move generations."
            ),
            "astronaut": GenCharacter(
                id: "astronaut",
                name: "The Astronaut",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "astronaut",
                bio: "A giant leap into the unknown, a fearless step onto history’s stage. Inspired by Neil Armstrong, The Astronaut represents the bravery that carried humanity to the moon. With steady resolve, relentless training, and the courage to go where no one had gone before, he embodies the spirit of exploration. He’s not just reaching for the stars—he’s proving the impossible is within our grasp."
            ),
            "couple": GenCharacter(
                id: "couple",
                name: "The Couple",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "couple",
                bio: "Stronger together, unstoppable as one. Inspired by the dynamic partnership of Alex and Leila Hormozi, The Couple blends strategy and resilience with loyalty and love. In business, in life, and in every challenge, they amplify each other’s strengths and face the world side by side. They’re not just partners—they’re proof that the right team can conquer anything."
            ),
            "company": GenCharacter(
                id: "company",
                name: "The Company",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "company",
                bio: "Strategy at scale, power in execution. Inspired by Jeff Bezos, The Company reflects the relentless drive that built Amazon into a global empire. With bold vision, meticulous operations, and an eye on the future, he redefined how the world shops. But this story isn’t his alone—alongside the dynamic presence of Lauren Sánchez, there’s an added spark of partnership, ambition, and flair. They’re not just building a business—they’re shaping the future of commerce together."
            )
        ]

        return characters[normalized]
    }
}


