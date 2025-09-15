import Foundation

@MainActor
final class PlannerService {
    static let shared = PlannerService()
    private init() {}

    func plan(request: GenerationRequest) async throws -> StoryboardPlan {
        // TODO: Replace with real backend URL. For now, use local stub.
        let imageCount = request.userReferenceImageIds.count
        let hasBackground = (request.characterBackground?.isEmpty == false)
        Log.info("Planner.start", [
            "characterId": request.characterId,
            "textLen": request.ideaText.count,
            "imageCount": imageCount,
            "hasBackground": hasBackground
        ])

        // Basic image id validation (placeholder for Firebase resolution)
        let validatedImageIds = validateImageIds(request.userReferenceImageIds)
        Log.info("Planner.images.validated", ["validatedCount": validatedImageIds.count])
        if let url = URL(string: "https://us-central1-dategenie-dev.cloudfunctions.net/generateStoryboardPlan") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            // Prefer URLs when available
            let body: [String: Any] = [
                "ideaText": request.ideaText,
                "characterBackground": request.characterBackground ?? "",
                "imageUrls": request.userReferenceImageUrls ?? []
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    // Expect shape: { scenes: [{ scene, action, speechType, speech, animation }] }
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let arr = json["scenes"] as? [[String: Any]] {
                        var scenes: [PlanScene] = []
                        var i = 1
                        for obj in arr {
                            let action = obj["action"] as? String ?? ""
                            let speechType = obj["speechType"] as? String ?? "Dialogue"
                            let speech = obj["speech"] as? String ?? ""
                            let animation = obj["animation"] as? String ?? ""
                            let script = "Action: \(action)\n\(speechType): \(speech)\nAnimation: \(animation)"
                            scenes.append(PlanScene(index: i, prompt: "", script: script, durationSec: 6, wordsPerSec: 2.0, wordBudget: 60, imageUrl: nil, action: action, speechType: speechType, speech: speech, animation: animation))
                            i += 1
                        }
                        let settings = PlanSettings(aspectRatio: "1:1", style: "illustrated", camera: "mixed")
                        let baseRefs = request.userReferenceImageUrls ?? []
                        let refs = (Self.defaultCharacterImageURL(for: request.characterId)).map { [$0] + baseRefs } ?? baseRefs
                        let scenesWithAccent = scenes.map { s -> PlanScene in
                            var c = s
                            c.speech = Self.applyDefaultAccentIfMissing(to: c.speech, type: c.speechType)
                            c.wordBudget = 60
                            return c
                        }
                        var plan = StoryboardPlan(character: PlanCharacter(id: request.characterId), settings: settings, scenes: scenesWithAccent.map(PlannerService.enforceBudget), referenceImageUrls: refs)
                        Log.info("Planner.success", ["scenes": plan.scenes.count])
                        return plan
                    }
                }
            } catch {
                Log.warn("Planner.network.fail", ["error": String(describing: error)])
            }
        }
        // Local composition fallback using constraints + budgets
        let fallback = Self.composePlan(from: request, imageIds: validatedImageIds)
        Log.warn("Planner.fallback.stub", ["scenes": fallback.scenes.count])
        return fallback
    }

    // MARK: Local composition fallback
    private static func composePlan(from req: GenerationRequest, imageIds: [String]) -> StoryboardPlan {
        let c = extractConstraints(idea: req.ideaText, background: req.characterBackground)
        let scenesRaw = outlineScenes(constraints: c)
        // Apply defaults (accent & budgets), then enforce limits
        let prepared = scenesRaw.map { s -> PlanScene in
            var c = s
            c.speech = Self.applyDefaultAccentIfMissing(to: c.speech, type: c.speechType)
            c.wordBudget = 60
            return c
        }.map(enforceBudget)
        let settings = PlanSettings(aspectRatio: "1:1", style: "illustrated", camera: "mixed")
        let baseRefs = req.userReferenceImageUrls ?? []
        let refs = (Self.defaultCharacterImageURL(for: req.characterId)).map { [$0] + baseRefs } ?? baseRefs
        return StoryboardPlan(character: PlanCharacter(id: req.characterId), settings: settings, scenes: prepared, referenceImageUrls: refs)
    }

    // Constraints
    private struct Constraints {
        var location: String
        var wardrobe: [String]
        var props: [String]
        var theme: String?
        var tone: String // "humorous", etc.
    }

    private static func extractConstraints(idea: String, background: String?) -> Constraints {
        let lower = idea.lowercased()
        // naive picks
        // Use Unicode letter class via ICU (\\p{L}) instead of explicit \u ranges
        let location = match(in: lower, patterns: [" at ([a-z0-9\\p{L}\\-\\s]+)", " in ([a-z0-9\\p{L}\\-\\s]+)"]) ?? "the Campus Burgers location"
        var wardrobe: [String] = []
        if lower.contains("jean") { wardrobe.append("jeans") }
        var props: [String] = []
        if lower.contains("coca") || lower.contains("coke") { props.append("Coca‑Cola bottle") }
        let theme = lower.contains("history") ? "history of Campus Burgers" : nil
        let tone = (background?.lowercased().contains("humor") == true) ? "humorous" : "confident"
        return Constraints(location: location, wardrobe: wardrobe, props: props, theme: theme, tone: tone)
    }

    private static func match(in text: String, patterns: [String]) -> String? {
        for p in patterns {
            if let r = try? NSRegularExpression(pattern: p) {
                let ns = text as NSString
                if let m = r.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                    let range = m.range(at: 1)
                    if range.location != NSNotFound { return ns.substring(with: range).trimmingCharacters(in: .whitespaces) }
                }
            }
        }
        return nil
    }

    // Outline 6 scenes alternating Dialogue/Narration
    private static func outlineScenes(constraints c: Constraints) -> [PlanScene] {
        func label(_ i: Int) -> String { i % 2 == 1 ? "Dialogue" : "Narration" }
        func composeScript(_ a: String, _ sp: String, _ an: String, _ l: String) -> String {
            "Action: \(a)\n\(l): \(sp)\nAnimation: \(an)"
        }

        let introAction = "Cory arrives at \(c.location) \(c.wardrobe.contains("jeans") ? "wearing jeans" : "").".replacingOccurrences(of: "  ", with: " ")
        let introSpeech = "This place holds stories you can almost taste!"
        let introAnim = "Dolly-in from wide to medium as ambient chatter rises."

        let s1 = PlanScene(index: 1, prompt: "Talking-head intro at \(c.location)",
                           script: composeScript(introAction, introSpeech, introAnim, label(1)),
                           durationSec: 6, wordsPerSec: 2.2, wordBudget: 22, imageUrl: nil,
                           action: introAction, speechType: label(1), speech: introSpeech, animation: introAnim)

        let s2a = "A marquee sign flickers over the entrance; \(c.props.first ?? "a soda bottle") glints in Cory's paw."
        let s2s = "(V.O.) We started as a tiny stand—campus legends say the first grill was a drum."
        let s2n = "Slow tilt up the sign; rack focus to the bottle label."
        let s2 = PlanScene(index: 2, prompt: "Exterior context at \(c.location)",
                           script: composeScript(s2a, s2s, s2n, label(2)),
                           durationSec: 5, wordsPerSec: 2.0, wordBudget: 20, imageUrl: nil,
                           action: s2a, speechType: label(2), speech: s2s, animation: s2n)

        let s3a = "Cory laughs with students, lifting the \(c.props.first ?? "drink") like a toast."
        let s3s = c.tone == "humorous" ? "Here's to the campus classic—crispy, cheesy, and way too good!" : "Here's to the campus classic—always made with heart!"
        let s3n = "Handheld sway, quick push-in on Cory's grin."
        let s3 = PlanScene(index: 3, prompt: "Crowd beat with prop", script: composeScript(s3a, s3s, s3n, label(3)),
                           durationSec: 6, wordsPerSec: 2.1, wordBudget: 22, imageUrl: nil,
                           action: s3a, speechType: label(3), speech: s3s, animation: s3n)

        let s4a = "Old photos/posters along the wall showcase early Campus Burgers days."
        let s4s = "(V.O.) From paper hats to packed game nights—this place grew with every class."
        let s4n = "Lateral pan across frames; match cuts between decades."
        let s4 = PlanScene(index: 4, prompt: "History wall", script: composeScript(s4a, s4s, s4n, label(4)),
                           durationSec: 5, wordsPerSec: 2.0, wordBudget: 20, imageUrl: nil,
                           action: s4a, speechType: label(4), speech: s4s, animation: s4n)

        let s5a = "Cory takes a playful bow, jeans dusty from the day; crowd cheers."
        let s5s = c.tone == "humorous" ? "Okay, legend status: confirmed. Who's hungry?" : "Thanks for keeping the tradition alive—who's hungry?"
        let s5n = "Crane sweep; confetti pops in the background."
        let s5 = PlanScene(index: 5, prompt: "Peak moment", script: composeScript(s5a, s5s, s5n, label(5)),
                           durationSec: 6, wordsPerSec: 2.1, wordBudget: 22, imageUrl: nil,
                           action: s5a, speechType: label(5), speech: s5s, animation: s5n)

        let s6a = "Sunset glow over \(c.location); neon hum settles."
        let s6s = "(V.O.) Every bite has a story—and we're still writing the next chapter."
        let s6n = "Fade with a gentle tilt up to the sky."
        let s6 = PlanScene(index: 6, prompt: "Outro", script: composeScript(s6a, s6s, s6n, label(6)),
                           durationSec: 5, wordsPerSec: 2.0, wordBudget: 20, imageUrl: nil,
                           action: s6a, speechType: label(6), speech: s6s, animation: s6n)

        return [s1, s2, s3, s4, s5, s6]
    }

    // Budget enforcement
    private static func enforceBudget(scene s: PlanScene) -> PlanScene {
        let budget = s.wordBudget ?? 60
        func words(_ t: String?) -> Int { (t ?? "").split{ !$0.isLetter && !$0.isNumber && $0 != "-" }.count }
        var a = s.action ?? ""
        var sp = s.speech ?? ""
        var an = s.animation ?? ""
        func total() -> Int { words(a) + words(sp) + words(an) }
        // Trim helpers
        func dropOneWord(_ text: String) -> String {
            var comps = text.split(separator: " ")
            if comps.count > 1 { comps.removeLast() }
            return comps.joined(separator: " ")
        }
        func smartTrim(_ text: String) -> String {
            var t = text
            for sep in [";", "—", ",", " and ", " then "] {
                if let r = t.range(of: sep, options: .backwards) { return String(t[..<r.lowerBound]) }
            }
            return dropOneWord(t)
        }
        // First, enforce per-section caps (20 words each)
        func capToTwenty(_ text: String) -> String {
            var t = text
            while t.split{ !$0.isLetter && !$0.isNumber && $0 != "-" }.count > 20 { t = smartTrim(t) }
            return t
        }
        a = capToTwenty(a)
        sp = capToTwenty(sp)
        an = capToTwenty(an)
        // Then, ensure total budget (default 60)
        while total() > budget {
            let wa = words(a), ws = words(sp), wn = words(an)
            if wa >= ws && wa >= wn && wa > 1 { a = smartTrim(a) }
            else if ws >= wa && ws >= wn && ws > 1 { sp = smartTrim(sp) }
            else if wn > 1 { an = smartTrim(an) }
            else { break }
        }
        let label = s.speechType ?? "Dialogue"
        let script = "Action: \(a)\n\(label): \(sp)\nAnimation: \(an)"
        var out = s
        out.action = a; out.speech = sp; out.animation = an
        out.script = script
        return out
    }

    // MARK: - Helpers
    private func validateImageIds(_ ids: [String]) -> [String] {
        // Placeholder: accept non-empty strings; in real impl, resolve Firebase Storage URLs
        let valid = ids.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if valid.count != ids.count { Log.warn("Planner.images.filtered", ["input": ids.count, "valid": valid.count]) }
        return valid
    }

    // MARK: - Character assets (temp mapping until backend)
    private static func defaultCharacterImageURL(for id: String) -> String? {
        // Use Firebase Storage anchors (gs:// supported by the function)
        // Upload the corresponding PNGs to: gs://dategenie-dev.firebasestorage.app/refs/characters/
        // The dictionary maps character ids -> file name in Storage
        let base = "gs://dategenie-dev.firebasestorage.app/refs/characters"
        let map: [String: String] = [
            // Core set
            "cory": "Cory.png",
            "50": "50.png",
            "hormo": "Hormo.png",
            "ishow": "ishow.png",
            "astro": "astro.png",
            "musk": "musk.png",
            "supertrump": "supertrump.png",
            // Business/tech
            "ceo": "CEO.png",
            "tech": "tech.png",
            "innovators": "Innovators.png",
            "philo": "Philo.png",
            // Careers
            "doctor": "Doctor.png",
            "talkshow": "talkshow.png",
            "gymnast": "gymnast.png",
            "t8": "T8.png",
            // Finance + power
            "giant": "giant.png",
            "investor": "Investor.png",
            "kingpin": "kingpin.png",
            "vc": "VC.png",
            // Society
            "activist": "activist.png",
            "speaker": "speaker.png",
            // Sports + entertainment misc
            "athlete": "athlete.png",
            "player": "player.png",
            "baller": "baller.png",
            "wrestler": "wrestler.png",
            // Minds
            "psychologist": "Psychologist.png",
            "contrarian": "Contrarian.png",
            // Celebrities
            "billionaire": "Billionaire.png",
            "mrbeast": "MrBeast.png",
            "actress": "actress.png",
            "self_help": "Self_Help.png",
            "glinda": "glinda.png",
            "oprah": "oprah.png",
            "theswift": "theswift.png",
            // New row
            "polymath": "polymath.png",
            "mentor": "mentor.png",
            "podcaster": "podcaster.png",
            "finance_woman": "finance_woman.png",
            "mr.wonderful": "Mr.Wonderful.png",
            "rob": "rob.png",
            "social": "social.png",
            "tech_media": "Tech _Media.png",
            "startup_advisor": "startup_advisor.png"
            ,
            // Newly added characters (ensure these files exist in Storage)
            "philosopher": "philosopher.png",
            "creator": "creator.png",
            "eyelish": "eyelish.png",
            "charmer": "charmer.png",
            "singer": "singer.png",
            "tma": "tma.png",
            "youtuber": "youtuber.png",
            "comedian": "comedian.png",
            "director": "director.png",
            "astronaut": "astronaut.png",
            "couple": "couple.png",
            "company": "company.png"
        ]
        if let file = map[id.lowercased()] { return "\(base)/\(file)" }
        return nil
    }

    // Apply default accent suffix for speech if missing
    private static func applyDefaultAccentIfMissing(to text: String?, type: String?) -> String {
        let base = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return base }
        // If user already specified an accent via parentheses, keep it
        if base.contains("(") && base.contains(")") { return base }
        return base + " (American Accent)"
    }
}


