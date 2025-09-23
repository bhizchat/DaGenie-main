import SwiftUI
import UIKit

struct AdGenChoiceView: View {
    @Environment(\.dismiss) private var dismiss
    var presentEditorOnSend: Bool = true

    var body: some View {
        ZStack {
            Color(red: 0xF7/255.0, green: 0xB4/255.0, blue: 0x51/255.0)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer().frame(height: 40)

                VStack(spacing: 12) {
                    Text("CREATE ORIGINAL CHARACTER")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                    Button(action: openCreateOriginalCharacter) {
                        Group {
                            if UIImage(named: "welcome_genie") != nil {
                                Image("welcome_genie")
                                    .resizable()
                                    .scaledToFit()
                            } else if UIImage(named: "Logo_DG") != nil {
                                Image("Logo_DG")
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.yellow)
                            }
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Text("OR")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.top, 8)

                VStack(spacing: 14) {
                    Text("EXPLORE A WORLD FULL OF CHARACTERS")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)

                    Button(action: openMemeverse) {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .frame(width: 300, height: 210)
                                .overlay(
                                    Image("memeverse")
                                        .resizable()
                                        .scaledToFit()
                                        .padding(12)
                                )

                            if UIImage(named: "memelogo") != nil {
                                Image("memelogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 104, height: 104)
                                    .offset(x: -20, y: 20)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                if UIImage(named: "back_arrow") != nil {
                    Image("back_arrow")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .padding(12)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Circle())
                } else {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                        .padding(12)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Circle())
                }
            }
            .padding(.top, 20)
            .padding(.leading, 25)
        }
    }

    private func openComposer(initial: UIImage?, intro: AdIntroContent = .stories) {
        let view = CustomCameraView(presentEditorOnSend: presentEditorOnSend, initialImage: initial, intro: intro)
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .overFullScreen
        UIApplication.shared.topMostViewController()?.present(host, animated: true)
    }

    private func openCreateOriginalCharacter() {
        let host = UIHostingController(rootView: CreateOriginalCharacterView())
        host.modalPresentationStyle = .overFullScreen
        UIApplication.shared.topMostViewController()?.present(host, animated: true)
    }

    

    private func openComposer(initialNamed name: String) {
        let img = UIImage(named: name)
        // Choose intro by name
        let intro: AdIntroContent
        switch name {
        case "Rufus": intro = .rufus
        case "Cory": intro = .cory
        case "Coca": intro = .stories
        default: intro = .stories
        }
        openComposer(initial: img, intro: intro)
    }

    private func openMemeverse() {
        let host = UIHostingController(rootView: MemeverseArchetypesView(presentEditorOnSend: presentEditorOnSend))
        host.modalPresentationStyle = .overFullScreen
        UIApplication.shared.topMostViewController()?.present(host, animated: true)
    }
}


struct MemeverseArchetypesView: View {
    @Environment(\.dismiss) private var dismiss
    var presentEditorOnSend: Bool
    @ObservedObject private var characterRepo = CharacterRepository.shared

    // Subtle pressed-state feedback for taps
    private struct CardPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
        }
    }

    private func lightHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    var body: some View {
        ZStack {
            Color(red: 0xF7/255.0, green: 0xB4/255.0, blue: 0x51/255.0)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer().frame(height: 40)

                Text("CHOOSE A CHARACTER")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)

                let columns: [GridItem] = [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)]

                ScrollView {
                    if !characterRepo.customCharacters.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("YOUR CHARACTERS")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(characterRepo.customCharacters) { cc in
                                    Button(action: { lightHaptic(); openUserCharacter(id: cc.id) }) {
                                        VStack(spacing: 8) {
                                            Group {
                                                if let u = URL(string: cc.defaultImageUrl), !cc.defaultImageUrl.isEmpty {
                                                    AsyncImage(url: u) { phase in
                                                        switch phase {
                                                        case .empty:
                                                            ProgressView()
                                                                .frame(width: 110, height: 160)
                                                        case .success(let img):
                                                            img.resizable()
                                                                .aspectRatio(contentMode: .fill)
                                                                .frame(width: 110, height: 160)
                                                                .clipped()
                                                        case .failure:
                                                            Image(systemName: "photo")
                                                                .resizable()
                                                                .scaledToFit()
                                                                .frame(width: 110, height: 160)
                                                                .padding(8)
                                                                .background(Color.white)
                                                        @unknown default:
                                                            EmptyView()
                                                                .frame(width: 110, height: 160)
                                                        }
                                                    }
                                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                                } else if let local = cc.localAssetName, let ui = UIImage(named: local) {
                                                    Image(uiImage: ui)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 110, height: 160)
                                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                                        .clipped()
                                                } else {
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .fill(Color.white)
                                                        .frame(width: 110, height: 160)
                                                        .overlay(
                                                            Image(systemName: "photo")
                                                                .resizable()
                                                                .scaledToFit()
                                                                .padding(20)
                                                                .foregroundColor(.gray)
                                                        )
                                                }
                                            }

                                            Text(cc.name)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.black)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                                .minimumScaleFactor(0.8)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(CardPressStyle())
                                    .accessibilityLabel(Text(cc.name))
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(Array(Self.characters.enumerated()), id: \.offset) { _, ch in
                            Button(action: { lightHaptic(); openCharacterOrLegacy(assetName: ch.assetName) }) {
                                VStack(spacing: 8) {
                                    let isCEO = ch.assetName == "CEO"
                                    let isPodcaster = ch.assetName == "podcaster"
                                    if isPodcaster {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(Color.black)
                                            Image("podcaster")
                                                .resizable()
                                                .scaledToFit()
                                                .padding(8)
                                        }
                                        .frame(width: 110, height: 160)
                                    } else {
                                        Image(ch.assetName)
                                            .resizable()
                                            .aspectRatio(contentMode: isCEO ? .fit : .fill)
                                            .frame(width: 110, height: 160)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                            .clipped()
                                    }

                                    Text(ch.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.black)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(CardPressStyle())
                            .gridCellColumns(ch.assetName == "Tech _Media" ? 2 : 1)
                            .accessibilityLabel(Text(ch.displayName))
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()
            }
        }
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                if UIImage(named: "back_arrow") != nil {
                    Image("back_arrow")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .padding(12)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Circle())
                } else {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                        .padding(12)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Circle())
                }
            }
            .padding(.top, 20)
            .padding(.leading, 25)
        }
    }

    private func openCharacterOrLegacy(assetName: String) {
        let slug = assetName.lowercased()
        // Map asset names to canonical ids to avoid misrouting due to case/spacing
        let explicitIds: [String: String] = [
            "50": "50", "Hormo": "hormo", "ishow": "ishow", "astro": "astro", "musk": "musk",
            "supertrump": "supertrump", "Cory": "cory", "CEO": "ceo", "tech": "tech",
            "giant": "giant", "Investor": "investor", "Philo": "philo", "Innovators": "innovators",
            "Doctor": "doctor", "talkshow": "talkshow", "gymnast": "gymnast", "T8": "t8",
            "activist": "activist", "speaker": "speaker", "kingpin": "kingpin", "VC": "vc",
            "athlete": "athlete", "player": "player", "baller": "baller", "wrestler": "wrestler",
            "Psychologist": "psychologist", "Contrarian": "contrarian", "Billionaire": "billionaire",
            "MrBeast": "mrbeast", "actress": "actress", "Self_Help": "self_help", "glinda": "glinda",
            "oprah": "oprah", "theswift": "theswift", "polymath": "polymath", "mentor": "mentor",
            "podcaster": "podcaster", "finance_woman": "finance_woman", "Mr.Wonderful": "mr.wonderful",
            "rob": "rob", "social": "social", "startup_advisor": "startup_advisor",
            // Newly added assets
            "philosopher": "philosopher", "creator": "creator", "eyelish": "eyelish", "charmer": "charmer",
            "singer": "singer", "TMA": "tma", "youtuber": "youtuber", "comedian": "comedian",
            "director": "director", "astronaut": "astronaut", "couple": "couple", "company": "company",
            // New character assets
            "steven_shot": "steven_shot", "monk_fist": "monk_fist", "jack_hood": "jack_hood",
            "dane": "dane", "bjlightning": "bjlightning", "justinharper": "justinharper",
            "willmanhattan": "willmanhattan", "martian_gary": "martian_gary", "super_mel": "super_mel",
            "boss": "boss",
            // Newly added grid characters
            "yacine": "yacine", "dario": "dario", "breaking_dad": "breaking_dad", "jobs": "jobs",
            "savant": "savant", "bender": "bender", "lucky_cyborg": "lucky_cyborg", "demis_riddler": "demis_riddler",
            "night": "night", "warrior": "warrior", "sweeney_star": "sweeney_star", "barker": "barker",
            "gaga": "gaga", "spice": "spice"
        ]
        let canonicalId = explicitIds[assetName] ?? slug
        // Known character ids we support in the new CharacterComposerView
        let supportedIds: Set<String> = [
            "cory", "50", "hormo", "ishow", "astro", "musk", "supertrump", "ceo", "tech",
            "giant", "investor", "philo", "innovators", "doctor", "talkshow", "gymnast", "t8", "activist",
            "speaker", "kingpin", "vc", "athlete", "player", "baller", "wrestler", "psychologist", "contrarian",
            "billionaire", "mrbeast", "actress", "self_help", "glinda", "oprah", "theswift",
            // Newly added set
            "polymath", "mentor", "podcaster", "finance_woman", "mr.wonderful", "rob", "social", "startup_advisor",
            // Newly added characters
            "philosopher", "creator", "eyelish", "charmer", "singer", "tma", "youtuber", "comedian", "director", "astronaut", "couple", "company",
            // New characters
            "steven_shot", "monk_fist", "jack_hood", "dane", "bjlightning", "justinharper", "willmanhattan", "martian_gary", "super_mel", "boss",
            // Newly added grid characters
            "yacine", "dario", "breaking_dad", "jobs", "savant", "bender", "lucky_cyborg", "demis_riddler", "night", "warrior", "sweeney_star", "barker", "gaga", "spice"
        ]
        // Route to user-created character if present
        if CharacterRepository.shared.customCharacters.contains(where: { $0.id.lowercased() == canonicalId }) {
            openUserCharacter(id: canonicalId)
            return
        }
        if supportedIds.contains(canonicalId) {
            let host = UIHostingController(rootView: CharacterComposerView(characterId: canonicalId))
            host.modalPresentationStyle = .overFullScreen
            UIApplication.shared.topMostViewController()?.present(host, animated: true)
        } else {
            openComposer(initialNamed: assetName)
        }
    }

    private func openUserCharacter(id: String) {
        let host = UIHostingController(rootView: CharacterComposerView(characterId: id))
        host.modalPresentationStyle = .overFullScreen
        UIApplication.shared.topMostViewController()?.present(host, animated: true)
    }

    private func openComposer(initial: UIImage?, intro: AdIntroContent = .stories) {
        let view = CustomCameraView(presentEditorOnSend: presentEditorOnSend, initialImage: initial, intro: intro)
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .overFullScreen
        UIApplication.shared.topMostViewController()?.present(host, animated: true)
    }

    private func openComposer(initialNamed name: String) {
        let img = UIImage(named: name)
        let intro: AdIntroContent
        switch name {
        case "Rufus": intro = .rufus
        case "Cory": intro = .cory
        case "Coca": intro = .stories
        default: intro = .scratch
        }
        openComposer(initial: img, intro: intro)
    }

    private struct Character: Hashable {
        let displayName: String
        let assetName: String
    }

    private static let characters: [Character] = [
        Character(displayName: "50 Cent", assetName: "50"),
        Character(displayName: "Hormo-Simpson", assetName: "Hormo"),
        Character(displayName: "Ishow-Speedster", assetName: "ishow"),
        Character(displayName: "The Astrophysicist", assetName: "astro"),
        Character(displayName: "Starship-Musk", assetName: "musk"),
        Character(displayName: "SuperTrump", assetName: "supertrump"),
        Character(displayName: "Cory the Lion", assetName: "Cory"),
        Character(displayName: "CEO", assetName: "CEO"),
        Character(displayName: "The Technologist", assetName: "tech"),
        Character(displayName: "The Giant", assetName: "giant"),
        Character(displayName: "The Investor", assetName: "Investor"),
        Character(displayName: "The Philanthropist", assetName: "Philo"),
        Character(displayName: "The Innovators", assetName: "Innovators"),
        Character(displayName: "The Doctor", assetName: "Doctor"),
        Character(displayName: "The Talk Show Host", assetName: "talkshow"),
        Character(displayName: "The Gymnast", assetName: "gymnast"),
        Character(displayName: "The Popstar", assetName: "T8"),
        Character(displayName: "The Activist", assetName: "activist"),
        Character(displayName: "The Speaker", assetName: "speaker"),
        Character(displayName: "The King Pin", assetName: "kingpin"),
        Character(displayName: "The Venture Capitalist", assetName: "VC"),
        Character(displayName: "The Athlete", assetName: "athlete"),
        Character(displayName: "The Player", assetName: "player"),
        Character(displayName: "The Baller", assetName: "baller"),
        Character(displayName: "The Wrestler", assetName: "wrestler"),
        Character(displayName: "The Psychologist", assetName: "Psychologist"),
        Character(displayName: "The Contrarian", assetName: "Contrarian"),
        Character(displayName: "The Billionaire", assetName: "Billionaire"),
        Character(displayName: "MR BEAST", assetName: "MrBeast"),
        Character(displayName: "The Actress", assetName: "actress"),
        Character(displayName: "The Self Help Teacher", assetName: "Self_Help"),
        Character(displayName: "Ariana Glinda", assetName: "glinda"),
        Character(displayName: "Oprah", assetName: "oprah"),
        Character(displayName: "The Swift", assetName: "theswift"),
        // Newly added row
        Character(displayName: "The Polymath", assetName: "polymath"),
        Character(displayName: "The Mentor", assetName: "mentor"),
        Character(displayName: "The Podcaster", assetName: "podcaster"),
        Character(displayName: "The Finance Woman", assetName: "finance_woman"),
        Character(displayName: "Mr.Wonderful", assetName: "Mr.Wonderful"),
        Character(displayName: "Rob the Bank", assetName: "rob"),
        Character(displayName: "The Social Entrepreneur", assetName: "social"),
        Character(displayName: "The Startup Advisor", assetName: "startup_advisor")
        ,
        // Newly added cards
        Character(displayName: "The Philosopher", assetName: "philosopher"),
        Character(displayName: "The Creator", assetName: "creator"),
        Character(displayName: "EyeLish", assetName: "eyelish"),
        Character(displayName: "The Charmer", assetName: "charmer"),
        Character(displayName: "The Singer", assetName: "singer"),
        Character(displayName: "The Martial Artist", assetName: "TMA"),
        Character(displayName: "The Youtuber", assetName: "youtuber"),
        Character(displayName: "The Comedian", assetName: "comedian"),
        Character(displayName: "The Director", assetName: "director"),
        Character(displayName: "The Astronaut", assetName: "astronaut"),
        Character(displayName: "The Couple", assetName: "couple"),
        Character(displayName: "The Company", assetName: "company"),
        // New cards
        Character(displayName: "Steven Shot", assetName: "steven_shot"),
        Character(displayName: "Monk Fist", assetName: "monk_fist"),
        Character(displayName: "Jack Hood", assetName: "jack_hood"),
        Character(displayName: "Dane", assetName: "dane"),
        Character(displayName: "BJ Lightning", assetName: "bjlightning"),
        Character(displayName: "Justin Harper", assetName: "justinharper"),
        Character(displayName: "Will Manhattan", assetName: "willmanhattan"),
        Character(displayName: "Martian Gary", assetName: "martian_gary"),
        Character(displayName: "Super Mel", assetName: "super_mel"),
        Character(displayName: "The BOSS", assetName: "boss"),
        // Extra grid characters
        Character(displayName: "Yacine", assetName: "yacine"),
        Character(displayName: "Dario and Claude", assetName: "dario"),
        Character(displayName: "Breaking Dad", assetName: "breaking_dad"),
        Character(displayName: "Jobs and Woz", assetName: "jobs"),
        Character(displayName: "The Savant", assetName: "savant"),
        Character(displayName: "Last Style Bender", assetName: "bender"),
        Character(displayName: "Lucky Cyborg", assetName: "lucky_cyborg"),
        Character(displayName: "Demis Riddler", assetName: "demis_riddler"),
        Character(displayName: "The Nigerian Nightmare", assetName: "night"),
        Character(displayName: "The African Warrior", assetName: "warrior"),
        Character(displayName: "Sweeney Star", assetName: "sweeney_star"),
        Character(displayName: "Red Barker", assetName: "barker"),
        Character(displayName: "Princess Gaga", assetName: "gaga"),
        Character(displayName: "Sharp Spice", assetName: "spice")
    ]
}

