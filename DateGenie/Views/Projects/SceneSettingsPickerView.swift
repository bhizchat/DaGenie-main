import SwiftUI

struct SceneSettingItem: Identifiable, Hashable {
    let id = UUID()
    let key: String   // e.g., "ironline"
    let name: String  // display name
    let asset: String // image asset key
    let bio: String   // description shown on detail sheet
}

private let sceneSettingsCatalog: [SceneSettingItem] = [
    .init(key: "ironline", name: "Ironline Gym", asset: "ironline", bio: "Kang’s second home and the cast’s ground-truth hangout. Smells like sweat and tape; 6 a.m. classes, late-night sparring, and quiet talks between rounds. Perfect for training arcs, rival showdowns, and ‘earn it’ moments."),
    .init(key: "mid", name: "Mid-rise Apartment Exterior", asset: "mid", bio: "A sunlit neighborhood block where several characters live or visit. Delivery scooters hum past laundry-hung balconies and tangled powerlines. Slice-of-life intros, morning departures, rooftop chats."),
    .init(key: "back", name: "Back-Alley Service Lane", asset: "back", bio: "The city’s shadow vein—neon leaks, humming AC units, puddles that remember everything. Good for tense meet-ups, secrets traded, or chases that turn tight corners. Where street rumors become plot."),
    .init(key: "eclat", name: "Éclat Couture (Luxury Boutique)", asset: "eclat", bio: "Perfume, marble, and money—Ryu’s workplace and a runway for chance encounters. Elites browse in silence while drama whispers behind the counter. Great for fashion stakes, confrontations in heels, and ‘look who walked in’ beats."),
    .init(key: "seora", name: "Seora Designs (HQ Boardroom)", asset: "seora", bio: "Seo and VP Choi’s battleground: glass views, sharper deals. Real-estate maps, production timelines, and choices with fallout. Use for power plays, betrayals, and the cost of winning."),
    .init(key: "midnight", name: "Midnight Node (Moon’s Hacker Den)", asset: "midnight", bio: "Lights low, code bright. A double-life command center with a motorcycle helmet by the chair. Ideal for digital heists, quiet reveals, and dominoes tipped from the shadows."),
    .init(key: "petal", name: "Petal & Thorn (Flower Studio)", asset: "petal", bio: "Im’s sanctuary—soft petals, tougher decisions. Suppliers, invoices, and bouquets that carry messages. Perfect for heart-to-heart scenes, resolve after setbacks, and ‘beauty that fights back.’"),
    .init(key: "shutterspace", name: "ShutterSpace Loft (Photo Studio)", asset: "shutterspace", bio: "Han’s playground of light and lenses. Backdrop rolls, garment racks, and celebrity bookings that complicate lives. Great for photoshoots, media scandals, and candid truths between clicks."),
    .init(key: "idolworks", name: "IdolWorks Practice Hub", asset: "idolworks", bio: "Where Baek earns it—mirrors, scuffed floors, and the beat on repeat. Team drills, solo grind, and the moment the choreography finally lands. Use for rivalry, growth, and pre-debut nerves."),
    .init(key: "cheonho", name: "Cheonho High Classroom", asset: "cheonho", bio: "Yoon’s firm-but-warm class: pop-lyric drills, real confidence. Sunshine through big windows, tidy desks, and hopes scribbled in margins. Perfect for student arcs, teacher ally moments, and first sparks."),
    .init(key: "garosu", name: "Garosu-gil, Sinsa-dong", asset: "garosu", bio: "Tree-lined runway of cafés and boutiques. Day dates, street style shots, and chance run-ins with influencers. Use for lighthearted interludes and fashion-forward reveals."),
    .init(key: "cheongdam", name: "Cheongdam-dong", asset: "cheongdam", bio: "Luxury corridor where glass facades reflect quiet power. Flagship storefronts, valet cones, and unspoken hierarchies. Ideal for high-stakes meetings, status clashes, and ‘money changes the room’ scenes."),
    .init(key: "dongdaemun", name: "Dongdaemun Design Plaza", asset: "dongdaemun", bio: "Neo-futurist curves and event-night electricity. Fashion weeks, exhibits, and storms rolling over silver waves. Great for premieres, public showdowns, and city-scale spectacle."),
    .init(key: "myeong", name: "Myeong-dong", asset: "myeong", bio: "Neon, noodles, nonstop temptation. Cosmetics walls, food carts, and crowds you can disappear into—or get lost in. Use for energetic montages, street promotions, or chaotic rendezvous."),
    .init(key: "hongdae", name: "Hongdae", asset: "hongdae", bio: "Youth in motion—murals, buskers, indie clubs. Cheap eats, loud nights, and art that argues back. Perfect for band gigs, confession walks, and messy, alive choices."),
    .init(key: "seongsu", name: "Seongsu-dong Café Street", asset: "seongsu", bio: "Warehouse cafés turned creative hubs; green paths just beyond. Pitch decks by day, slow dates by dusk. Use for brainstorming scenes, soft reconciliations, and ‘a breath away from the city.’"),
    .init(key: "banpo", name: "Banpo Hangang Park", asset: "banpo", bio: "Night rainbow over the river; the bridge sings in color. Quiet benches for big feelings, confessions under the arc. Ideal for turning points, reconciliations, and end-of-episode fades.")
]

struct SceneSettingsPickerView: View {
    var onBack: (() -> Void)? = nil
    var onPick: ((SceneSettingItem) -> Void)? = nil

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 18, alignment: .top),
        GridItem(.flexible(), spacing: 18, alignment: .top)
    ]

    @State private var selected: SceneSettingItem? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(sceneSettingsCatalog) { item in
                        VStack(spacing: 10) {
                            Image(item.asset)
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(item.name)
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selected = item }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 56)
                .padding(.bottom, 24)
            }
            .background(Color(hex: 0xF7B451).ignoresSafeArea())
            .sheet(item: $selected) { item in
                SceneSettingDetailSheet(item: item, onSelect: { chosen in
                    selected = nil
                    onPick?(chosen)
                })
            }

            Button(action: { onBack?() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 6)
            .padding(.top, 6)
        }
    }
}

private struct SceneSettingDetailSheet: View {
    let item: SceneSettingItem
    let onSelect: (SceneSettingItem) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(item.asset)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20)

                Text(item.name.uppercased())
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                Text(item.bio)
                    .font(.system(size: 14))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.leading)

                Button(action: { onSelect(item) }) {
                    Text("Select \(item.name.split(separator: " ").first ?? "Setting")")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 24)
            }
            .padding(.top, 12)
        }
        .background(Color(hex: 0xF7B451).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.black)
                    .frame(width: 48, height: 48, alignment: .center)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 2)
            .padding(.top, 2)
        }
    }
}


