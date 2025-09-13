import SwiftUI

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

    private func openComposer(initial: UIImage?, intro: AdIntroContent = .commercial) {
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
        case "Coca": intro = .commercial
        default: intro = .scratch
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
                                ForEach(characterRepo.customCharacters, id: \.id) { cc in
                                    VStack(spacing: 8) {
                                        Button(action: { openUserCharacter(id: cc.id) }) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .fill(Color.white)
                                                if let u = URL(string: cc.defaultImageUrl) {
                                                    AsyncImage(url: u) { phase in
                                                        switch phase {
                                                        case .empty: ProgressView().frame(width: 110, height: 160)
                                                        case .success(let img): img.resizable().scaledToFill()
                                                        case .failure: Image(systemName: "photo")
                                                        @unknown default: EmptyView()
                                                        }
                                                    }
                                                    .frame(width: 110, height: 160)
                                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                                    .clipped()
                                                }
                                            }
                                            .frame(width: 110, height: 160)
                                        }
                                        .buttonStyle(.plain)
                                        Text(cc.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.black)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(Self.characters, id: \.assetName) { ch in
                            VStack(spacing: 8) {
                                Button(action: { openCharacterOrLegacy(assetName: ch.assetName) }) {
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
                                }
                                .buttonStyle(.plain)

                                Text(ch.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.black)
                                    .multilineTextAlignment(.center)
                            }
                            .gridCellColumns(ch.assetName == "Tech _Media" ? 2 : 1)
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
            "rob": "rob", "social": "social", "startup_advisor": "startup_advisor"
        ]
        let canonicalId = explicitIds[assetName] ?? slug
        // Known character ids we support in the new CharacterComposerView
        let supportedIds: Set<String> = [
            "cory", "50", "hormo", "ishow", "astro", "musk", "supertrump", "ceo", "tech",
            "giant", "investor", "philo", "innovators", "doctor", "talkshow", "gymnast", "t8", "activist",
            "speaker", "kingpin", "vc", "athlete", "player", "baller", "wrestler", "psychologist", "contrarian",
            "billionaire", "mrbeast", "actress", "self_help", "glinda", "oprah", "theswift",
            // Newly added set
            "polymath", "mentor", "podcaster", "finance_woman", "mr.wonderful", "rob", "social", "startup_advisor"
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

    private func openComposer(initial: UIImage?, intro: AdIntroContent = .commercial) {
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
        case "Coca": intro = .commercial
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
    ]
}

