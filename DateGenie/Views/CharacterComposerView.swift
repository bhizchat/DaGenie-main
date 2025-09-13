import SwiftUI

struct CharacterComposerView: View {
    let characterId: String

    @StateObject private var characterRepo = CharacterRepository.shared
    @StateObject private var uploadRepo = UploadRepository.shared
    @State private var character: GenCharacter? = nil
    @State private var userRefs: [ImageAttachment] = []
    // Map attachment id -> uploaded asset metadata (for later phases)
    @State private var uploadedByAttachmentId: [UUID: UploadedImage] = [:]
    @State private var ideaText: String = ""
    @State private var showPicker: Bool = false
    @State private var pickedImage: UIImage? = nil
    @State private var isSubmitting: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    if let character { characterHeader(character) }
                }
                .padding(.horizontal, 16)
            }
            CreativeInputBar(
                text: $ideaText,
                attachments: $userRefs,
                onAddTapped: { if !isSubmitting { showPicker = true } },
                onSend: { submitPlan() },
                isUploading: uploadRepo.isUploading
            )
            .disabled(uploadRepo.isUploading || isSubmitting)
        }
        .background(Color.white.ignoresSafeArea())
        .overlay {
            if isSubmitting {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    Text("Loading…")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Button(action: { UIApplication.shared.topMostViewController()?.dismiss(animated: true) }) {
                Image("back_arrow")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .padding(14)
                    .background(Color.white.opacity(0.85))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.leading, 20)
        }
        .task { await loadCharacter() }
        .sheet(isPresented: $showPicker, onDismiss: handlePicked) {
            ImagePicker(image: $pickedImage, sourceType: .photoLibrary)
        }
    }

    private func loadCharacter() async {
        character = await characterRepo.fetchCharacter(id: characterId)
    }

    @ViewBuilder private func characterHeader(_ c: GenCharacter) -> some View {
        VStack(spacing: 10) {
            Group {
                if let url = URL(string: c.defaultImageUrl), !c.defaultImageUrl.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Color.clear
                        case .success(let img):
                            img.resizable().scaledToFit()
                        case .failure:
                            if let local = c.localAssetName, let ui = UIImage(named: local) {
                                Image(uiImage: ui).resizable().scaledToFit()
                            } else {
                                Image(systemName: "photo").resizable().scaledToFit().padding(20).foregroundColor(.gray)
                            }
                        @unknown default:
                            Color.clear
                        }
                    }
                } else if let local = c.localAssetName, let ui = UIImage(named: local) {
                    Image(uiImage: ui).resizable().scaledToFit()
                } else {
                    Image(systemName: "photo").resizable().scaledToFit().padding(20).foregroundColor(.gray)
                }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(c.name)
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.black)
                .padding(.top, 2)

            if let desc = userOrPresetDescription(for: c) {
                Text(desc)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 2)
                    .padding(.horizontal, 8)
            }

            if let tip = characterContentType(for: c) {
                Text("Content type: \(tip)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 2)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func handlePicked() {
        guard let img = pickedImage else { return }
        pickedImage = nil
        if userRefs.count >= 3 { return }
        let attachment = ImageAttachment(image: img)
        userRefs.append(attachment)
        Task {
            if let uploaded = try? await uploadRepo.uploadUserReference(img) {
                uploadedByAttachmentId[attachment.id] = uploaded
            }
        }
    }

    private func submitPlan() {
        // Gate sending while uploads in progress or unresolved attachments
        guard !uploadRepo.isUploading, !isSubmitting else { return }
        isSubmitting = true
        let uploaded = userRefs.compactMap { uploadedByAttachmentId[$0.id] }
        let ids: [String] = uploaded.map { $0.id }
        let urls: [String] = uploaded.map { $0.url }
        let background = character.flatMap { userOrPresetDescription(for: $0) }
        let req = GenerationRequest(characterId: characterId, ideaText: ideaText, userReferenceImageIds: ids, characterBackground: background, userReferenceImageUrls: urls)
        Task {
            do {
                let plan = try await PlannerService.shared.plan(request: req)
                let vc = UIHostingController(rootView: StoryboardNavigatorView(plan: plan))
                vc.modalPresentationStyle = .overFullScreen
                UIApplication.shared.topMostViewController()?.present(vc, animated: true)
                isSubmitting = false
            } catch {
                // TODO: surface error UI
                isSubmitting = false
            }
        }
    }
    private func userOrPresetDescription(for c: GenCharacter) -> String? {
        if let bio = c.bio, !bio.isEmpty { return bio }
        return characterDescriptionPreset(for: c)
    }

    private func characterDescriptionPreset(for c: GenCharacter) -> String? {
        let id = c.id.lowercased()
        switch id {
        case "cory":
            return "Cory the Lion is the official mascot of Campus Burgers. He crushes 25 Campus Cheeseburgers a day and once held the record for most burgers eaten in America in a year. When he’s not snacking, Cory’s out playing competitive Topgolf against rival mascots or flipping like a gymnast across campus."
        case "50":
            return "9 shots couldn’t stop him. Labels couldn’t box him. This NYC hustler flipped the script on fate. He didn’t just survive the streets – he mastered them. Follow the crazy animated stories of 50 Cent."
        case "hormo":
            return "Imagine if Homer Simpson hit the gym, read 100 biz books, and started yelling value propositions. That’s Hormo‑Simpson. Built for memes. Born to monetize."
        case "ishow":
            return "Part streamer, part sprinter, Ishow‑Speedster doesn’t walk anywhere—he races, flips, or dives through life. From jumping Lambos to bungee off billboards, this kid’s got no brakes and infinite WiFi. Find out what world adventure he’s off doing."
        case "astro":
            return "He doesn’t just look at the stars—he talks to them. Inspired by Neil deGrasse Tyson, this Astrophysicist turns the mysteries of black holes, wormholes, and time travel into bedtime stories for your curious mind. Science never sounded so smooth."
        case "musk":
            return "Captain of the Starship and architect of the Mars dream, Starship‑Musk charts courses where no tweet has gone before. Half genius, half chaos, this space pioneer builds rockets by day and memes by starlight."
        case "supertrump":
            return "When the AI wars broke out, America didn’t send in its best… they sent in SuperTrump. Part superhero, part negotiator, part chaos tornado. Armed with a golden S on his chest and a constitution in his cape, he’s rewriting history in real time."
        case "ceo":
            return "He walks like a founder, thinks in token embeddings, and talks like a philosopher. Behind the shades is one of the sharpest minds of our time. Inspired by Sam Altman, this CEO isn’t just running an AI company—he’s orchestrating the birth of a digital god. Meet the final boss before AGI replaces us all."
        case "tech":
            return "Social networks? Done. Now he builds realities. Inspired by Mark Zuckerberg, The Technologist is on a mission to move the world from scrolls to spatial. With smart glasses on every face and the metaverse in every step, he’s coding a new dimension of human connection."
        case "giant":
            return "Today he’s slam‑dunking over double‑deckers in London; tomorrow he’s riding elephants in Thailand. Inspired by Shaq, The Giant stands 7 feet tall and once ruled the court—now he’s a globe‑trotting adventurer on a never‑ending spree of strange and wonderful side quests."
        case "investor":
            return "You don’t have to be the smartest in the room—just the one who waits the longest. Inspired by Warren Buffett, The Investor is a master of compounding and calm, teaching money like your favorite grandpa tells bedtime stories—except these stories end with portfolios and life lessons."
        case "philo":
            return "Once the world’s most powerful software mogul. Inspired by Bill Gates, this coder‑turned‑philanthropist now travels the globe tackling humanity’s toughest bugs—poverty, pandemics, climate change, and more—using data, vaccines, and relentless curiosity."
        case "innovators":
            return "The Innovators are a legendary duo—one’s the visionary, the other the operator. One dreams in product metaphors; the other delivers with surgical precision. Inspired by Tim Cook and Steve Jobs, together they simplify, explain, and demystify how cutting‑edge technology is reshaping our lives."
        case "doctor":
            return "The Doctor isn’t your average physician—he’s a walking encyclopedia with the heart of a teacher and the charm of a storyteller. Inspired by Ben Carson, decades in the operating room shaped his craft; now he travels the world making complex medical science simple. You don’t need to be a doctor to understand your body—you just need someone to explain it like a story, and he’s got plenty of those."
        case "talkshow":
            return "If the news had a game show and a dance‑off, he’d host both. The Talk Show Host is king of the couch and master of the monologue. Inspired by Jimmy Fallon, he’s the only person who can explain world events and challenge an alien guest to a lip‑sync battle in the same episode."
        case "gymnast":
            return "From Olympic gold to globe‑trotting star, she flips through life with style and soul. The Gymnast is more than an elite athlete—she’s a movement. Inspired by champions like Suni Lee, she defied gravity, made history on the mat, and now inspires millions through stories, stunts, and snapshots from her travels around the world."
        case "t8":
            return "Sabrina is the dazzling definition of a modern pop idol—playful, bold, and endlessly magnetic. From her early days as a child star to owning the stage on her record‑breaking tours, she’s proven she’s more than just a voice; she’s a force of personality. Known for her witty storytelling, cheeky charisma, and powerhouse vocals, Sabrina connects with fans through both her music and her larger‑than‑life stage presence. She embodies the popstar dream: someone who grew up chasing melodies and now commands the spotlight with confidence, sparkle, and undeniable star power."
        case "activist":
            return "The Activist is more than a speaker—she’s a generational voice. Inspired by the grace, strength, and authenticity of Michelle Obama, she lifts every room, whether you’re 16 or 65. Her stories carry truth, power, and a touch of humor that makes you feel like you’ve known her forever."
        case "speaker":
            return "Big laughs. Bigger truth. He’s your favorite voice of reason and realness. The Speaker is the guy you want on the mic and in your corner. With smooth delivery, soulful perspective, and razor‑sharp timing, he blends humor and heart that makes people lean in—then laugh out loud. Inspired by Craig Robinson’s cool charm and grounded wit, he’s not here to crack jokes—he’s here to drop wisdom."
        case "kingpin":
            return "He doesn’t chase trends—he funds the future. The King Pin is a Silicon Valley legend. Inspired by real‑world kingmakers like Marc Andreessen, he’s known for bold bets, sharp instincts, and a tech IQ that borders on prophetic. When others hesitate, he doubles down and cashes out in style—the man behind the curtain, the voice on every AI panel, and the investor who turns ‘maybe’ into massive."
        case "vc":
            return "Built on bold bets, business bars, and stories from the trenches. The Venture Capitalist isn’t loud—he doesn’t need to be. With a calm voice and battle‑tested brain, he breaks billion‑dollar thinking into words even a first‑time founder can understand. Inspired by Ben Horowitz’s sharp logic and streetwise wisdom, he’s seen every startup pattern in the book—and knows when to tear that book up. Real advice. No fluff. Just actionable truth—usually with a killer analogy and a cup of black coffee."
        case "athlete":
            return "The Athlete is more than a basketball star—he’s a living blueprint of greatness. Inspired by LeBron James, he fuses superhuman athleticism, elite basketball IQ, and leadership that turns teammates into believers and games into history. He doesn’t just dunk—he dissects defenses. He doesn’t just win—he elevates."
        case "player":
            return "Trained like a machine. Plays like a myth. The Player isn’t just a footballer—he’s a force of nature. Inspired by Cristiano Ronaldo, he’s an icon of discipline, power, and surgical precision. With 5‑star skills, a goal‑hungry mindset, and a physique carved in ambition, he commands the field like a battlefield and inspires a generation with every strike."
        case "baller":
            return "Light‑hearted, humble, and impossible to stop. Inspired by Stephen Curry, The Baller redefined basketball with 3‑point shooting and joyful style. He’s the underdog turned king of the court, beloved by fans and kids alike. They said he was too small—he said, ‘watch me.’"
        case "psychologist":
            return "The Psychologist is a warm, introspective thinker who brings calm and clarity to a noisy world. With a sharp understanding of human behavior and emotional dynamics, inspired by Bailey Schildbach, she unpacks complex personal issues with compassion and insight. Whether breaking down self‑sabotage, unpacking childhood trauma, or offering relationship advice, her words land—and she’s reaching millions while doing it."
        case "contrarian":
            return "Unafraid to challenge consensus, The Contrarian is a high‑IQ maverick inspired by Peter Thiel. He questions everything—from academia to tech trends—and funds the most radical dreamers. Love him or loathe him, he brings rare clarity and courage to every conversation, redefining what’s possible."
        case "wrestler":
            return "The Wrestler is a larger‑than‑life superstar whose mantra is ‘Never Give Up.’ Built like a tank and moving with rockstar energy, inspired by John Cena, his story is perseverance, resilience, and inspiration to an entire generation. From massive lifts to lifting spirits, he’s strength—inside and outside the ring."
        case "billionaire":
            return "Savvy, outspoken, and dripping with business acumen. The Billionaire made his fortune with brains and hustle—now he’s helping others do the same. Inspired by Mark Cuban from Shark Tank, he turns ideas into ownership and deals into realities. He’s the mentor every entrepreneur wants in their corner. No fluff—just facts, funding, and the push to build."
        case "mrbeast":
            return "A modern legend of the internet, Mr Beast is the king of viral generosity and architect of the wildest YouTube stunts ever pulled off. With hundreds of millions of subscribers, he commands a digital empire built on jaw‑dropping challenges, real‑life impact, and an obsession with going bigger every time. Whether he’s giving away islands or planting 20 million trees, everything he does is designed to break the algorithm—and the mold."
        case "actress":
            return "The Actress is the breakout dreamer‑turned‑star, inspired by Xochitl Gomez. She left home to chase her Hollywood ambitions, starting out in theater productions and kids’ shows before capturing the spotlight on the big screen. With resilience, charm, and undeniable talent, she’s built for the red carpet—her story is about perseverance, growth, and finally making it big in the world’s most competitive stage."
        case "self_help":
            return "The Self Help Teacher is a warm yet no‑nonsense guide who helps people break free from self‑doubt and hesitation. Inspired by the transformative story of Mel Robbins, she knows what it means to hit rock bottom and claw your way back with courage and discipline. Her superpower is simplicity: she distills life’s most overwhelming problems into clear, actionable steps that anyone can follow."
        case "glinda":
            return "Ariana Glinda sparkles with charm, wit, and heart. Inspired by Ariana Grande’s portrayal of Glinda in Wicked, she represents the magic of transformation from an ambitious dreamer to a true star. With her dazzling gowns, radiant optimism, and a voice that can light up a kingdom, Glinda embodies the aura of fame mixed with the complexity of responsibility. She’s not just a pretty face with a wand—she’s clever, resourceful, and knows how to shine in the spotlight while staying true to herself."
        case "oprah":
            return "The ultimate storyteller and mentor, Oprah embodies resilience, empathy, and the power of reinvention. Rising from hardship to become one of the most influential voices in the world, she built an empire on listening deeply, sharing courageous stories, and elevating voices that matter. With wisdom, warmth, and unshakable presence, she represents the belief that anyone can transform their life—and, in doing so, change the world."
        case "mr.wonderful":
            return "Sharp, shrewd, and unapologetically direct, Mr. Wonderful is the embodiment of financial discipline and tough love in business. Inspired by Kevin O’Leary, he’s the investor who cuts through the noise with brutal honesty, teaching entrepreneurs the hard truths of money, valuation, and strategy. With his mix of wit, authority, and no‑nonsense wisdom, he’s both feared and respected as the ultimate dealmaker."
        case "rob":
            return "Charismatic, bold, and unapologetically flashy, Rob the Bank is the digital hustler who turned internet culture into an empire. Inspired by the influencer Rob the Bank, he built his following by blending humor, shock value, and street‑smart lessons in money and marketing. Always loud, always entertaining, Rob thrives on going viral while showing the world that unconventional paths can lead to big paydays."
        case "social":
            return "Fueled by hustle and heart, The Social Entrepreneur is the motivational powerhouse who preaches empathy, legacy, and relentless grind. Inspired by Gary Vee, he mixes street‑level grit with visionary business sense, teaching people to create, operate with ambition, and build community. Whether it’s building brands, uplifting creators, or encouraging kindness in the pursuit of success, he’s the mentor for dreamers ready to turn passion into impact."
        case "theswift":
            return "From Tumblr posts and MySpace playlists to stadiums filled with millions, The Swift is the ultimate story of reinvention and connection. Inspired by Taylor Swift’s arc, she embodies the power of storytelling, resilience, and unwavering fan devotion. Her character bridges multiple ‘eras’—showing how growth, vulnerability, and fan interaction online can become culture‑shaping forces. She’s not just a perfect decaf country icon; she reminds the biggest shows on the planet that authenticity and perseverance can turn whispers into anthems sung around the world."
        case "polymath":
            return "Fearless, curious, and defiantly versatile, The Polymath embodies the curious grind of a modern renaissance man. He’s a cross between a battle‑tested entrepreneur and an unfiltered philosopher, unafraid to explore uncomfortable ideas. With a voice built for long‑form, he dissects fitness, finance, psychology, and society with uncommon clarity—always pushing toward first‑principles thinking and self‑mastery."
        case "podcaster":
            return "A voice of curiosity and depth, The Podcaster brings modern wisdom to a global audience by asking the questions others are afraid to ask. Known for thought‑provoking conversations with world‑class thinkers, athletes, scientists, and entrepreneurs, he transforms complex ideas into engaging, digestible insights. Balancing intellect with relatability, his rise reflects the power of long‑form storytelling in a short‑attention‑span world—creating a platform where knowledge becomes both entertaining and transformative."
        case "finance_woman":
            return "The Finance Woman is a bold voice for financial independence and unconventional wealth building. Inspired by Codie Sanchez, she blends sharp entrepreneurial insight with practical street‑smart strategies, helping people see opportunities where others see obstacles. From buying overlooked businesses to teaching audiences how to flip the script on traditional investing, she embodies resilience, creativity, and the power of questioning the status quo—proving that smart money moves aren’t just for Wall Street."
        default:
            return nil
        }
    }

    private func characterContentType(for c: GenCharacter) -> String? {
        let id = c.id.lowercased()
        switch id {
        case "theswift":
            return "You can make era storytelling, lyric prompts, and music‑narrative teasers with them."
        case "polymath":
            return "You can make long‑form commentary, Q&A clips, and self‑mastery guides with them."
        case "mentor":
            return "You can make coaching sessions, accountability prompts, and leadership advice with them."
        case "podcaster":
            return "You can make podcast clip cuts, guest highlights, and key‑takeaway recaps with them."
        case "finance_woman":
            return "You can make small‑business acquisition explainers, cash‑flow breakdowns, and side‑hustle playbooks with them."
        case "mr.wonderful":
            return "You can make pitch critiques, valuation tips, and finance rule‑of‑thumb content with them."
        case "rob":
            return "You can make edgy finance humor, anti‑fragile money lessons, and hot‑take commentary with them."
        case "social":
            return "You can make impact startup stories, nonprofit scaling tips, and social‑good explainers with them."
        case "startup_advisor":
            return "You can make tactical growth tips, fundraising playbooks, and PMF guidance with them."
        case "cory":
            return "You can make campus mascot comedy skits, playful challenges, and brand promos with them."
        case "50":
            return "You can make gritty storytelling, hustle motivation, and street‑smart business takes with them."
        case "hormo":
            return "You can make meme marketing riffs, sales breakdowns, and comedic biz skits with them."
        case "ishow":
            return "You can make high‑energy stunts, viral challenges, and IRL reactions with them."
        case "astro":
            return "You can make science explainers, space fact shorts, and educational animations with them."
        case "musk", "tech":
            return "You can make tech futurism updates, product explainers, and AR/VR demos with them."
        case "supertrump":
            return "You can make satirical political skits, parody news, and comedic monologues with them."
        case "giant":
            return "You can make humorous endorsements, larger‑than‑life stories, and travel/variety content with them."
        case "investor":
            return "You can make patient‑investing lessons, finance explainers, and market commentary with them."
        case "philo":
            return "You can make global‑health explainers, impact stories, and data‑driven insights with them."
        case "innovators":
            return "You can make product philosophy talks, design lessons, and tech history mini‑docs with them."
        case "doctor":
            return "You can make medical explainers, health‑myth debunks, and surgery stories with them."
        case "talkshow":
            return "You can make late‑night monologues, interview bits, and game skits with them."
        case "gymnast":
            return "You can make training tutorials, athlete BTS vlogs, and inspirational montages with them."
        case "t8":
            return "You can make performance teasers, dance challenges, and music‑video snippets with them."
        case "activist":
            return "You can make motivational speeches, community uplift stories, and leadership talks with them."
        case "speaker":
            return "You can make comedic life advice, storytelling sets, and motivational bits with them."
        case "kingpin":
            return "You can make venture analysis, pitch critiques, and startup teardowns with them."
        case "vc":
            return "You can make founder lessons, management tips, and hard‑truth leadership content with them."
        case "athlete":
            return "You can make highlight reels, workout tutorials, and mindset talks with them."
        case "player":
            return "You can make skills drills, training clips, and goal highlights with them."
        case "baller":
            return "You can make shooting tutorials, practice routines, and inspirational shorts with them."
        case "wrestler":
            return "You can make fitness motivation, challenge videos, and perseverance stories with them."
        case "psychologist":
            return "You can make mental‑health explainers, relationship advice, and therapy frameworks with them."
        case "contrarian":
            return "You can make contrarian takes, tech/policy debates, and thesis content with them."
        case "billionaire":
            return "You can make business critiques, deal analysis, and entrepreneurial coaching with them."
        case "mrbeast":
            return "You can make challenge concepts, philanthropy stunts, and big‑reveal teasers with them."
        case "actress":
            return "You can make acting tips, behind‑the‑scenes bits, and red‑carpet stories with them."
        case "self_help":
            return "You can make habit coaching, actionable challenges, and mindset bites with them."
        case "glinda":
            return "You can make whimsical fairytale scenes, transformation stories, and character vignettes with them."
        case "oprah":
            return "You can make interview snippets, life‑lesson spotlights, and book/insight features with them."
        default:
            return nil
        }
    }
}


