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
                    Text("GENERATE FROM SCRATCH")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                    Button(action: { openComposer(initial: nil, intro: .scratch) }) {
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


private struct MemeverseArchetypesView: View {
    @Environment(\.dismiss) private var dismiss
    var presentEditorOnSend: Bool

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
        // Known character ids we support in the new CharacterComposerView
        let supportedIds: Set<String> = [
            "cory", "50", "hormo", "ishow", "astro", "musk", "supertrump", "ceo", "tech",
            "giant", "investor", "philo", "innovators", "doctor", "talkshow", "gymnast", "t8", "activist",
            "speaker", "kingpin", "vc", "athlete", "player", "baller", "wrestler", "psychologist", "contrarian",
            "billionaire", "mrbeast", "actress", "self_help", "glinda", "oprah", "theswift"
        ]
        if supportedIds.contains(slug) {
            let host = UIHostingController(rootView: CharacterComposerView(characterId: slug))
            host.modalPresentationStyle = .overFullScreen
            UIApplication.shared.topMostViewController()?.present(host, animated: true)
        } else {
            openComposer(initialNamed: assetName)
        }
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
        Character(displayName: "Money Machine 50", assetName: "50"),
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
        Character(displayName: "The Popstar T8", assetName: "T8"),
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
        Character(displayName: "The Swift", assetName: "theswift")
    ]
}

