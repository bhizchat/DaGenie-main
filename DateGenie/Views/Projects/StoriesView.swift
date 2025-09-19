import SwiftUI
import UIKit

struct StoriesView: View {
    var onBack: (() -> Void)? = nil
    var onPickCharacter: ((CharacterItem) -> Void)? = nil

    @State private var characters: [CharacterItem] = CharacterItem.allShuffled()
    @State private var draftText: String = ""
    @State private var pickedImage: UIImage? = nil
    @State private var showImagePicker: Bool = false
    @State private var selected: CharacterItem? = nil
    @State private var plannerCharacter: CharacterItem? = nil

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 18, alignment: .top),
        GridItem(.flexible(), spacing: 18, alignment: .top)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(characters) { item in
                            CharacterCard(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = item }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 120) // space for dock
                }
            }
            .background(Color(hex: 0xF7B451).ignoresSafeArea())
            .hideKeyboardOnTap()

            StoriesTypingDock(text: $draftText,
                              placeholder: "Generate a Main Character with AI",
                              onPlus: { showImagePicker = true },
                              onSubmit: {},
                              thumbnail: pickedImage,
                              onRemoveAttachment: { pickedImage = nil })
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $pickedImage, sourceType: .photoLibrary)
            }
            .sheet(item: $selected) { item in
                CharacterDetailSheet(item: item, onSelect: { chosen in
                    // Dismiss sheet first, then either return picked character or open planner
                    selected = nil
                    if let onPickCharacter {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onPickCharacter(chosen)
                        }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            plannerCharacter = chosen
                        }
                    }
                })
            }
            .fullScreenCover(item: $plannerCharacter) { item in
                ScenePlannerView(mainCharacter: item)
            }
        }
        .onAppear { characters.shuffle() }
        .hideKeyboardOnTap()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: { onBack?() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
            }
            Text("Choose or Create your Main Character")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

private struct CharacterCard: View {
    let item: CharacterItem

    var body: some View {
        VStack(spacing: 8) {
            Image(item.asset)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(item.name)
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Detail Sheet
private struct CharacterDetailSheet: View {
    let item: CharacterItem
    let onSelect: (CharacterItem) -> Void

    private var age: Int { CharacterBios.age(for: item.asset) }
    private var bio: String { CharacterBios.bio(for: item.asset) }

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

                HStack {
                    Text(item.firstName.uppercased())
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundColor(.white)
                    Text("\(age)")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 24)

                Text(bio)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.leading)

                Button(action: { onSelect(item) }) {
                    Text("Select \(item.firstName)")
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

private enum CharacterBios {
    static func age(for key: String) -> Int {
        switch key {
        case "jin": return 25
        case "kang": return 24
        case "seo": return 27
        case "lee": return 24
        case "park": return 27
        case "choi": return 26
        case "han": return 26
        case "baek": return 25
        case "oh": return 25
        case "im": return 24
        case "kwon": return 23
        case "yoon": return 25
        case "ryu": return 27
        case "moon": return 26
        case "nam": return 25
        case "joo": return 25
        default: return 24
        }
    }

    static func bio(for key: String) -> String {
        switch key {
        case "jin":
            return "He’s the calm and charismatic type — a rising fashion stylist and image director in Seoul. Known for his impeccable taste and cool demeanor, Jin designs outfits for elite runway shows and editorial shoots. Despite his success, he hides a secret: he started out as a tailor’s apprentice, stitching suits late into the night to save money for fabrics. His eye for detail is legendary, his confidence magnetic, and he rarely raises his voice — yet when he does, people listen."
        case "kang":
            return "Kang works as the operations manager at a local gym, where he also teaches boxing classes to make ends meet. Though the job isn’t glamorous, it gives him enough to support both himself and his little sister, the only family he has left since their parents passed away. Fiercely protective and grounded, Kang lives with a quiet strength, dedicating every ounce of effort to ensuring his sister has the stability he never did. His tough exterior hides a compassionate heart, but his skepticism of the elite and wealthy often puts him at odds with those from higher circles. To Kang, loyalty and hard work mean more than flashy clothes or big paychecks, and that principle guides everything he does."
        case "seo":
            return "Seo is the CEO of a rapidly growing furniture manufacturing company in Seoul, and one of the youngest wealthy entrepreneurs in the city. Born in a remote, unknown village in Korea, he moved to Seoul at age 15 chasing a dream — no connections, no safety net, just ambition and grit. He started off doing menial jobs, saving every last won, learning the business from the bottom up: from woodwork to logistics to negotiating big property deals. Over the years, he expanded into real estate and used those ventures to secure capital and influence, mastering both the tough streets and the polished elite circles. Seo is confident, sharp, and always impeccably styled. He has an intuitive sense of when someone’s bluffing, and he rarely lets anyone see how hard he had to claw his way up. Despite his wealth and power, he distrusts flattery, looks down on ostentation, and values authenticity above all else — qualities that sometimes isolate him even as he builds his empire."
        case "lee":
            return "Lee is a mechanical engineer at Samsung, balancing his demanding career with a part-time passion project teaching mathematics for fun. A recognized genius since high school, he was sent to the United States to study, where he excelled under immense pressure and constant expectations from those around him. Now back in Seoul, Lee chooses to focus on things that genuinely bring him joy rather than chasing external validation. He frequents the same gym where his close friend Kang works, finding balance in boxing and strength training. Warm, approachable, and quietly brilliant, Lee hides his past struggles behind an easy smile, determined to live life on his own terms — even if the world keeps demanding more from him."
        case "park":
            return "Park was once a child star flooded with lights, cameras, and applause, but as he grew, fame only became more complicated. Now he’s a well-known actor in Seoul, starring in dramas, movies, and commercials non-stop. Despite having all the perks: wealth, recognition, privilege he feels a deep pull toward realness. Park craves people who see him beyond the actor, beyond the brand. Because of this, he sometimes puts up walls—snubby comments, a sharp tone to test if others treat him normally when the cameras aren’t rolling. He has a romantic soft spot for Ryu Dahye, drawn not to her looks or her style, but to her sincerity. Under the spotlight, Park remains poised, charismatic but underneath, he carries the weight of expectations, both from the world and from the kid he once was: a boy who just wanted someone to see him."
        case "choi":
            return "Choi is the Vice President of Seo’s company, a position he earned through raw intelligence and a relentless work ethic. Like Seo, he came to Seoul from a small, unknown village, chasing nothing more than the hope of a steady corporate job. Seo quickly recognized his potential and pulled him into the company, where Choi now oversees massive operations. On the surface, he’s composed, efficient, and loyal—but behind the polished image is someone who’s made compromises and difficult choices to secure his place at the top. While he secretly yearns for a quiet, ordinary life, his role at the company and his relationship with his girlfriend Nam, a chaebol heiress, keep him trapped under immense pressure. Between boardroom battles and the silent judgment of Nam’s powerful family, Choi often wrestles with the uncomfortable truth: his success has come at costs he doesn’t always like to admit."
        case "han":
            return "Han is a freelance photographer who frequently collaborates with the fashion company where Jin works, giving the two a natural connection. Born into a middle-class family, Han discovered his love for photography at a young age, wandering around with a camera to capture the world through his curious eyes. That same curiosity defines him now he refuses to be tied down by a single organization, preferring the freedom of freelance work that lets him explore fashion shoots, news media assignments, and even exclusive private bookings for Seoul’s influencers and celebrities. Known for his sharp eye and knack for capturing authenticity in every shot, Han has built a reputation as one of the most in-demand photographers despite never chasing fame directly. His quiet confidence and relentless curiosity keep him moving, always searching for the next untold story hidden in plain sight."
        case "baek":
            return "Baek is a K-pop idol who grew up surrounded by chaebol circles in Seoul, though he never truly belonged to them. Coming from a privileged household, he could have coasted on comfort, but instead chose to prove himself through relentless training and sheer determination, eventually becoming the lead in his idol group. Now, at 25, he lives under the blinding lights of fame—discipline, rehearsals, and public image consuming nearly every hour of his day. But deep down, Baek wonders what it’s like to live as an ordinary young adult, free from fans, paparazzi, and expectations. To satisfy this yearning, he sometimes disguises himself and sneaks into the world of regular people, tasting moments of anonymity he can never truly claim."
        case "oh":
            return "Oh is a fitness instructor at the same gym where Kang works, known among clients for her upbeat energy and dedication. A marathon runner at heart, she starts every morning with a jog through the city, chasing both endurance and clarity. While she comes across as the perfect ‘girl next door’ type—friendly, approachable, and effortlessly likable—there’s a side of her that’s deeply protective, especially toward Kang’s younger sister, whom she treats almost like her own family. Though she hasn’t realized it herself, Oh carries a quiet crush on Kang, drawn to his strength and loyalty, even if he never seems to notice her in that way. To everyone else, she’s simply the reliable and kindhearted trainer everyone gravitates to—but beneath her warm smile lies a subtle longing for something more with the man who seems blind to her affection."
        case "im":
            return "Im is the owner of a flower shop, an entrepreneurial woman who balances elegance with resilience. Despite the stress of running her own business, she manages to maintain her striking appearance, a testament to both her discipline and inner strength. Growing up under the thumb of controlling parents, Im rebelled early, carving out her independence and vowing to never live by anyone else’s rules. In a world often dominated by men, she thrives by taking bold risks, navigating challenges with sharp instincts and determination. Her shop may look delicate from the outside, but it’s built on grit, ambition, and the courage of someone who refuses to be caged. Beneath her poised demeanor lies a woman who is constantly testing her limits, proving that beauty and strength can bloom together—even in the harshest environments."
        case "kwon":
            return "Kwon is a rising social media influencer with over 1.2 million followers, admired for her spontaneous content, adventurous spirit, and the way she turns every corner of her life into a story. Born in a well‑off neighborhood, she never needed to scramble for basics—but she always felt a restlessness, a pull toward something more thrilling than the life her family planned. Instead of staying comfortably in the world of glam posts, she chases the next exciting project: collaborations, travel, experimental fashion shots, anything that fuels her creativity. Though she’s made plenty of money for her age, Kwon often questions whether the attention is real or just a spotlight she fell into. Her ambitions reach beyond social media—she dreams of building something long‑lasting and authentic, but the line between true self‑expression and curated image is one she walks every day."
        case "yoon":
            return "Yoon is the school’s English teacher, well‑known for blending strict discipline with a fresh, relatable approach that her students adore. She often makes her classes stand out by having students sing popular American pop songs as part of their lessons, a method that keeps them both entertained and engaged. Though her youth makes students feel they can confide in her more easily, Yoon never loses her authority—she balances warmth with firmness, earning respect across the board. Beneath her polished exterior is a woman determined to make learning fun and meaningful, even when resources are limited. Outside of class, Yoon shares a connection with Lee, since they both teach at the same school in Seoul, making her presence in the story tied not just to her students, but to the wider circle of characters navigating ambition, trust, and everyday struggles."
        case "ryu":
            return "Ryu works in a luxury store in Seoul, earning a stable living enough to afford her own place and all the basics—something she values deeply. She met Baek while working there, though he’s admired her from afar long before their paths crossed. Quiet, composed, Ryu doesn’t crave the spotlight; she prefers to build her world on her own terms. She has ambitions outside the luxury industry’s glitter and is constantly pulled in by the complexity of people around her—the famous, the powerful, the wounded. Though her life looks serene to most, beneath the surface she wrestles with expectations she’s never signed up for—family obligations to get married, societal pressure, and the silent fear that she’ll be defined by others if she doesn’t define herself first."
        case "moon":
            return "Moon is a legendary hacker—quiet, clever, feared in elite online circles, and always one step ahead. From a young age she mined Bitcoin and taught herself code, later building a reputation in Korea as the best female hacker, taking high‑risk jobs that others wouldn’t touch. On the surface, she pretends to be just another girl from a wealthy family in Seoul, complete with the luxury image and a motorcycle she rides around at night, so no one gets suspicious. Beneath that facade, though, she lives with two identities: the high‑society persona the world sees, and the shadowy cyber‑artist who breaks into fortified systems and leaks secrets for the right price—or when she believes justice demands it. Despite her notoriety, she moves with a confidence born of necessity, aware that each hack, each lie, powerful though they are, cost her pieces of her conscience."
        case "nam":
            return "Nam is from a chaebol family and currently in a relationship with Choi. On the surface, her life looks perfect — the dresses, the parties, the privilege — but inside, she constantly feels the weight of expectations she never chose. Her parents expect her to follow a set path: attend the right events, marry well, maintain appearances. But Nam is quieter than her family imagines; she craves real connection and agency over her own choices. While she’s committed to Choi, their relationship is complicated by her family’s demands, and the constant tug between wanting tradition and wanting freedom. Even though being part of the elite gives her power and comfort, it also isolates her. She wonders whether love and respect are hers for being herself — or just for the image she projects."
        case "joo":
            return "Joo is a chaebol heiress who, despite her family’s power and wealth, longs to break free of her gilded cage. She moves to Seoul in search of purpose beyond privilege, determined to learn what life is like outside her family’s protected bubble. But it isn’t as simple as trading designer heels for independence—each step outside her comfort zone reveals how sheltered she’s been, forcing her to recognize how little she understood of the world. On a chance outing, Baek spots her among other chaebol children he once knew—but Joo doesn’t remember him, too young then to form lasting impressions. That moment sparks something—curiosity, shame, maybe even hope. As she keeps pushing herself to understand “real” life (and the people in it), she’ll face illusions from her past, misunderstandings, and the hard edges of a world she thought she knew."
        default:
            return ""
        }
    }
}

private struct StoriesTypingDock: View {
    @Binding var text: String
    let placeholder: String
    let onPlus: () -> Void
    let onSubmit: () -> Void
    var thumbnail: UIImage? = nil
    var onRemoveAttachment: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: 0x999CA0))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
            }
            HStack {
                Button(action: onPlus) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(Color(hex: 0x999CA0))
                        .clipShape(Circle())
                }
                if let img = thumbnail {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button(action: onRemoveAttachment) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .background(Color.white.opacity(0.95).clipShape(Circle()))
                        }
                        .padding(2)
                        .contentShape(Rectangle())
                    }
                }
                Spacer()
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(hex: 0x999CA0) : Color(hex: 0xF7B451))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Color(hex: 0x808080)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}


