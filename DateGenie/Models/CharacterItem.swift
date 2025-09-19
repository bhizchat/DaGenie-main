import Foundation

struct CharacterItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let name: String
    let asset: String

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    static func allShuffled() -> [CharacterItem] {
        let names = ["jin","kang","seo","lee","park","choi","han","baek","yoon","im","ryu","kwon","nam","moon","joo","oh"]
        let items = names.map { n in CharacterItem(name: displayName(for: n), asset: n) }
        return items.shuffled()
    }

    private static func displayName(for key: String) -> String {
        switch key {
        case "jin": return "Jin Seongwoo"
        case "kang": return "Kang Hyunsoo"
        case "seo": return "Seo Joonhyuk"
        case "lee": return "Lee Minjae"
        case "park": return "Park Taegun"
        case "choi": return "Choi Doyun"
        case "han": return "Han Jiwoon"
        case "baek": return "Baek Sungho"
        case "yoon": return "Yoon Haewon"
        case "im": return "Im Nari"
        case "ryu": return "Ryu Dahye"
        case "kwon": return "Kwon Soyeon"
        case "nam": return "Nam Hana"
        case "moon": return "Moon Areum"
        case "joo": return "Joo Nari"
        case "oh": return "Oh Nayoung"
        default: return key.capitalized
        }
    }
}


