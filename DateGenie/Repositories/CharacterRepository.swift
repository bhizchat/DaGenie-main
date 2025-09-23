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
            ,
            // Newly designed characters (assets bundled in app)
            "steven_shot": GenCharacter(
                id: "steven_shot",
                name: "Steven Shot",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "steven_shot",
                bio: "Steven Shot is more than just a part‑time podcaster — he’s a voice that cuts through noise with sharp insight and fearless honesty. But when night falls, he becomes something else entirely: a part‑time sniper superhero, armed with precision, patience, and purpose. Inspired by Steven Bartlett, he blends the wisdom of deep conversation with the accuracy of a marksman. On the mic, he dissects stories, pulling lessons from every guest. In the shadows, he dismantles chaos with flawless aim and unshakable focus."
            ),
            "monk_fist": GenCharacter(
                id: "monk_fist",
                name: "Monk Fist",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "monk_fist",
                bio: "Monk Fist is a martial arts hero who unites discipline and spirit. A master of Shaolin traditions and modern Chi‑projection, he blends meditative wisdom with explosive power. Inspired by Iron Fist’s mystical chi mastery and Shi Heng Yi’s Shaolin teachings, Monk Fist fights with balance, clarity, and purpose — every strike carrying intention, every breath channeling strength."
            ),
            "jack_hood": GenCharacter(
                id: "jack_hood",
                name: "Jack Hood",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "jack_hood",
                bio: "Jack Hood is a tech‑visionary turned vigilante. By day, he’s a sharp strategist and entrepreneur inspired by Jack Altman — building platforms, leading teams, shaping futures. By night, he dons the Red Hood mask: a former protégé who walks the line between justice and intensity, fueled by purpose and moral clarity."
            ),
            "dane": GenCharacter(
                id: "dane",
                name: "Dane",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "dane",
                bio: "Dane is a financial powerhouse with the mind of a strategist and the might of a warrior. Inspired by Dave Ramsey, he brings discipline, no‑nonsense principles, and unshakable wisdom about money, debt, and financial freedom. Fused with the fearsome presence of Bane, he channels raw strength, resilience, and intimidation into every encounter."
            ),
            "bjlightning": GenCharacter(
                id: "bjlightning",
                name: "BJ Lightning",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "bjlightning",
                bio: "BJ Lightning is a force of energy, conviction, and leadership. Inspired by Michael B. Jordan, he carries unshakable determination, charisma, and the spirit of a fighter who never backs down. Combined with the electrifying powers of Black Lightning, he channels storms of raw voltage through every battle — defending his community while igniting change."
            ),
            "justinharper": GenCharacter(
                id: "justinharper",
                name: "Justin Harper",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "justinharper",
                bio: "Justin Harper is the archer with attitude — a fusion of sharp aim and star power. Inspired by Roy Harper, he brings precision, street‑smart grit, and a fearless edge to every fight. Layered with the charisma and stage presence of Justin Bieber, he adds style, swagger, and a magnetic energy that makes him impossible to ignore."
            ),
            "willmanhattan": GenCharacter(
                id: "willmanhattan",
                name: "Will Manhattan",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "willmanhattan",
                bio: "Will Manhattan embodies charm, wisdom, and cosmic power. Inspired by Will Smith, he brings wit, relatability, and a magnetic presence — a storyteller who can command any room. Blended with the godlike abilities of Dr. Manhattan, he wields near‑infinite knowledge, time awareness, and energy manipulation — a calm force who sees beyond the moment to shape what comes next."
            ),
            "martian_gary": GenCharacter(
                id: "martian_gary",
                name: "Martian Gary",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "martian_gary",
                bio: "Martian Gary is the ultimate shape‑shifting strategist — part alien guardian, part relentless motivator. Inspired by Martian Manhunter, he wields telepathy, super strength, and the power to adapt to any form, embodying resilience and quiet wisdom. Infused with the energy of Gary Vee, he channels raw hustle, sharp vision, and unapologetic drive to inspire those around him."
            ),
            "super_mel": GenCharacter(
                id: "super_mel",
                name: "Super Mel",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "super_mel",
                bio: "Super Mel is the embodiment of courage and action. Inspired by Supergirl, she carries strength, flight, and unshakable hope — a protector who leads with heart. Combined with the fearless motivation of Mel Robbins, she champions bold decisions, practical wisdom, and the power of taking action now."
            )
            ,
            // Grid characters (local assets bundled)
            "yacine": GenCharacter(
                id: "yacine",
                name: "Yacine",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "yacine",
                bio: "Yacine is a sharp‑witted engineer with code in his veins and zero patience for the ordinary. Known online for tearing into flawed assumptions and fighting for clean architecture, he built his reputation patching big services, hunting bugs, and loving scale. Now he’s stepping into hardware—boards, circuits, and physical builds—blending soldering‑iron swagger with software supremacy."
            ),
            "dario": GenCharacter(
                id: "dario",
                name: "Dario and Claude",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "dario",
                bio: "Dario is the cerebral leader—an AI researcher with a mission to build powerful, ethical intelligence. As CEO of a safety‑focused lab, he argues for interpretability, alignment, and steering AI so it serves humanity. Claude is his creation: an orange robot AI who codes like a champ. Fluent in logic and language, delightfully unpredictable—sometimes literal, sometimes mischievous, occasionally flustered, but always surprisingly effective."
            ),
            "breaking_dad": GenCharacter(
                id: "breaking_dad",
                name: "Breaking Dad",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "breaking_dad",
                bio: "A parody twist on a legendary crime drama—but instead of cooking, this father‑and‑son duo are plumbers trying to make a living. Walter is now Jesse’s dad, and together they run a small plumbing business. Simple jobs spiral into bizarre adventures: bursting pipes flooding blocks, shady customers with ‘special requests,’ and rival plumbers who play dirty. The comedy comes from Dad’s stern, methodical approach clashing with Jesse’s impulsive, wild ideas."
            ),
            "jobs": GenCharacter(
                id: "jobs",
                name: "Jobs and Woz",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "jobs",
                bio: "Jobs and Woz is a sci‑fi reimagining of Steve Jobs and Steve Wozniak—now legendary space travelers navigating a futuristic galaxy. Apple has evolved into a vast, sustainable space civilization, an ecosystem floating among the stars in the shape of Apple’s ring campus. Jobs is the bold visionary, reinventing how society thrives; Woz is the ingenious engineer whose humor and practicality keep the world running. Together they explore interstellar frontiers where technology, design, and sustainability intertwine—with satire, brilliance, and friendship projected onto a cosmic scale."
            ),
            "savant": GenCharacter(
                id: "savant",
                name: "The Savant",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "savant",
                bio: "The Savant is a brilliant anti‑hero/genius whose mind is as razor‑sharp as his wit. He possesses superhuman intellect, mastery of computers and code, fluency in many languages, and the uncanny ability to see patterns and possibilities others miss."
            ),
            "bender": GenCharacter(
                id: "bender",
                name: "Last Style Bender",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "bender",
                bio: "Last Style Bender is a fierce martial arts champion who blends the artistry of striking with the creativity of a true performer. Inspired by real‑life MMA legend Israel Adesanya, he dominates the arena with precision, agility, and showmanship. Known for his unique ability to adapt his ‘style’ mid‑fight, he turns every match into both a battle and a performance. Carrying the energy of a fighter and the vision of an artist, Last Style Bender is as much a storyteller as he is a warrior — bending styles, breaking limits, and leaving flames in his path."
            ),
            "lucky_cyborg": GenCharacter(
                id: "lucky_cyborg",
                name: "Lucky Cyborg",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "lucky_cyborg",
                bio: "Lucky Cyborg is a fusion of cutting‑edge warfare and eccentric tech genius. Inspired by a visionary defense founder and the cybernetic power of classic comic book cyborgs, he is equal parts innovator and warrior. With a robotic arm engineered to interface with drones, weapons, and AI‑driven defense systems, he commands a high‑tech arsenal from his underground war lab. Brash, bold, and unfiltered, Lucky Cyborg blends entrepreneurial recklessness with battlefield precision, straddling the line between visionary protector and unpredictable wildcard in a future where machines define power."
            ),
            "demis_riddler": GenCharacter(
                id: "demis_riddler",
                name: "Demis Riddler",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "demis_riddler",
                bio: "Demis Riddler is a mastermind at the intersection of artificial intelligence and puzzles, embodying both genius innovation and cryptic mischief. He designs labyrinthine challenges powered by AI, forcing heroes and rivals alike to solve his riddles or be trapped in his ever‑evolving games. Behind his calm and intellectual demeanor lies a chaotic edge — a figure who blurs the line between visionary scientist and theatrical trickster, wielding AI as both a tool of progress and a weapon of riddling chaos."
            ),
            "night": GenCharacter(
                id: "night",
                name: "The Nigerian Nightmare",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "night",
                bio: "Inspired by a champion fighter, The Nigerian Nightmare is reimagined as a superhuman warrior radiating unstoppable aura powers. Embodying strength, resilience, and national pride, he channels the spirit of Nigeria itself — his skin glowing with the green and white energy of the flag, his presence guarded by celestial horses and crowned with the red eagle of unity. With each strike, he summons waves of raw power, shaking his enemies with both physical force and spiritual energy. A symbol of determination and dominance, he turns every battle into a legendary clash of will and heritage."
            ),
            "warrior": GenCharacter(
                id: "warrior",
                name: "The African Warrior",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "warrior",
                bio: "The African Warrior, inspired by a world‑class heavyweight, channels unstoppable power and resilience — turning raw strength and fiery spirit into an aura of victory. A symbol of Africa’s warrior pride and triumph against all odds."
            ),
            "sweeney_star": GenCharacter(
                id: "sweeney_star",
                name: "Sweeney Star",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "sweeney_star",
                bio: "Sweeney Star is a radiant young heroine who blends the charisma of a rising starlet with the cosmic courage of a stargazing warrior. Wielding her blazing cosmic staff, she channels both star‑powered energy and grounded determination. As the new face of hope, Sweeney Star shines with charm, resilience, and a spark that inspires others to rise and fight for a brighter tomorrow — a legacy of the women warrior tribes."
            ),
            "barker": GenCharacter(
                id: "barker",
                name: "Red Barker",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "barker",
                bio: "Red Barker is a fierce young warrior forged from the spirit of a modern icon and another legacy of women warrior tribes. Draped in red‑and‑blue battle armor with floral insignias, she channels both modern boldness and ancestral strength. Red Barker wields a great sword infused with lightning, symbolizing her power to cut through challenges with resilience and style. She stands as a protector and rebel, blending the glamour of a rising star with the unshakable courage of warrior women who came before her."
            ),
            "gaga": GenCharacter(
                id: "gaga",
                name: "Princess Gaga",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "gaga",
                bio: "Princess Gaga is a dazzling fusion of a Disney‑like princess and Lady Gaga’s bold artistic spirit. With magical powers fueled by her radiant wand, she rules a fantastical kingdom where music and magic intertwine. Her wardrobe is ever‑changing—glamorous, outrageous, and enchanting—reflecting Gaga’s iconic style evolution. Beyond her beauty and grace, Princess Gaga wields a powerful voice capable of moving mountains and enchanting hearts."
            ),
            "spice": GenCharacter(
                id: "spice",
                name: "Sharp Spice",
                defaultImageUrl: "",
                assetImageUrls: [],
                localAssetName: "spice",
                bio: "Sharp Spice is a bold fusion of Ice Spice’s fearless energy and the legendary warrior women tribes. Clad in armor and wielding a blade, she embodies the sharp wit, confidence, and unapologetic charisma of her modern counterpart while carrying the ancestral strength and honor of warrior queens. Her story is one of resilience and cultural pride — a heroine who blends rhythm, power, and legacy into a force that cuts through any challenge."
            )
        ]

        return characters[normalized]
    }
}


