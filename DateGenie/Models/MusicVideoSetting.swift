import Foundation

struct MusicVideoSetting: Identifiable, Hashable {
    let id: String
    let name: String
    let imageAssetName: String // preview image in assets
    // Optional style metadata for prompts (can expand later)
    let environment: String
    let palette: [String]
    let bio: String
    let promptKit: PromptKit
}

struct PromptKit: Hashable {
    let worldPillars: [String]
    let formatBeats: [String]
    let setPacks: [String]
    let loopGags: [String]
    let cameraGrammar: [String]
    let fpsHint: String
}

enum MusicVideoSettingsCatalog {
    /// Designer-provided catalog; add more as assets land.
    static let all: [MusicVideoSetting] = [
        MusicVideoSetting(
            id: "mango_island",
            name: "Man-GO !",
            imageAssetName: "mango-island",
            environment: "bioluminescent tropical island at night",
            palette: ["#0b1023", "#00d4ff", "#ffb000", "#ff6a00"],
            bio: "Zoetrope-style loops on a glowing bio-bay island. Mango iconography, carnival accents, and stop-motion toy-real feel.",
            promptKit: PromptKit(
                worldPillars: [
                    "Zoetrope/loop mini-sets (carousel/turntable)",
                    "Bioluminescent water and glowing footprints",
                    "Mango as symbol of abundance (garlands/toran)",
                    "Stop-motion vibe with micro-jitter",
                    "Ghibli-style appetizing food closeups"
                ],
                formatBeats: [
                    "Arrival orbit at night with glowing rivers",
                    "Verse: stacked micro-loops on downbeats",
                    "Hook: carnival procession across sandbar",
                    "Verse: carousel of trades turntable",
                    "Hook: biolume river ride calligraphy",
                    "Bridge: macro mango closeups",
                    "Finale: festival spiral & leaf logo"
                ],
                setPacks: [
                    "Bio-River Boardwalk",
                    "Carousel of Trades (press, slicer, seed-car, DJ treehouse)",
                    "Carnival Pass",
                    "Temple Grove with leaf toran",
                    "Star-Kitchen Cove"
                ],
                loopGags: [
                    "Seed-car drift neon skid marks",
                    "Juice waterfall beat-skip",
                    "Mango balloon lifts",
                    "Crab percussion line",
                    "Bio-wake calligraphy"
                ],
                cameraGrammar: ["orbit 8–15°", "mini-dolly through garlands", "crane-up reveal", "rack-focus from mango texture to horizon"],
                fpsHint: "12–16 fps, slight frame jitter/grain"
            )
        ),
        MusicVideoSetting(
            id: "candy_island",
            name: "CandyLand",
            imageAssetName: "candy-land",
            environment: "neon candy architecture, rivers of soda, chocolate volcano",
            palette: ["#ff99cc", "#ffee66", "#66ddff", "#8844ff"],
            bio: "Surreal candy metropolis with loopable factory, parade, and raceway gags—pop-art pastel energy.",
            promptKit: PromptKit(
                worldPillars: [
                    "Candy architecture canon (Sugar Rush/Adventure Time)",
                    "Zoetrope/loop logic",
                    "Absurdist pop-candy humor"
                ],
                formatBeats: [
                    "Arrival orbit across peppermint city",
                    "Factory flex carousel (taffy, gumdrops, chocolate river)",
                    "Parade of sweets",
                    "Raceway / Sugar Rush",
                    "Pop-art candyland fashion board",
                    "Finale: storm of sweets"
                ],
                setPacks: ["Peppermint City", "Chocolate River Works", "Candy Kingdom Plaza", "Sugar Speedway", "Pop-Video Board"],
                loopGags: ["Gummy crowd bounce", "Lollipop windmill", "Taffy pull sync", "Chocolate-river 808 ripples", "Skittles downpour"],
                cameraGrammar: ["orbit 12°", "micro-dolly in", "parallax bridge pass", "crane-up reveal", "rack-focus from sugar crystals"],
                fpsHint: "12–16 fps with slight jitter for toy-real"
            )
        ),
        MusicVideoSetting(
            id: "afro_japan",
            name: "Afro Japan",
            imageAssetName: "afro-japan",
            environment: "neon temple courtyards, sakura night skies, Afrocentric motifs blended with Edo architecture",
            palette: ["#0c0c12", "#ff3b6e", "#ffd166", "#66e0ff"],
            bio: "Hip‑hop × Edo fusion: samurai energy, neon kanji with Adinkra patterns, respectful cultural blend.",
            promptKit: PromptKit(
                worldPillars: [
                    "Samurai Champloo / Afro Samurai lineage",
                    "Hip-hop attitude with modern electronic score",
                    "Respectful symbol fusion (kanji + Adinkra/Nsibidi)"
                ],
                formatBeats: [
                    "Arrival: lanterns & low end",
                    "Verse: training montage on vinyl mats",
                    "Hook: Yosakoi parade across torii gates",
                    "Verse: night market cypher macros",
                    "Hook: storm garden lightning",
                    "Finale: blade dance spiral"
                ],
                setPacks: ["Temple Courtyard Orbit", "Kendo on Vinyl", "Yosakoi Bridge Pass", "Night‑Market Inserts", "Storm Garden Crane-Up"],
                loopGags: ["Lyrical petals", "Animated graffiti spirits", "Beat blades light trails"],
                cameraGrammar: ["orbit 8–15°", "parallax hallway passes", "crane-up reveals", "rack-focus from glyphs to dancers"],
                fpsHint: "14–16 fps with slight grain/jitter"
            )
        ),
        MusicVideoSetting(
            id: "astro_world",
            name: "Astro-World",
            imageAssetName: "astro-world",
            environment: "surreal theme-park city with golden head portal, parade midways, coasters and sky balloons; pastel day that flips to neon night",
            palette: ["#f6a623", "#66ccff", "#ff66cc", "#0b1023"],
            bio: "A mythic amusement world crowned by a golden head portal. Parade midways, retro Houston easter eggs, and sky carnivals flip from pastel day to neon night. Built for ride‑POV hooks, funhouse loops, and giant‑scale concert moments.",
            promptKit: PromptKit(
                worldPillars: [
                    "Golden head portal opening to different park ‘lands’",
                    "Pastel day palette → neon night palette transformation",
                    "Giant‑scale performer in miniature park",
                    "Sky carnival of balloons, blimps, dirigibles",
                    "Homages to historic Houston AstroWorld rides",
                    "Zoetrope carousel logic for AI‑friendly loops"
                ],
                formatBeats: [
                    "Intro: Portal Quest — enter through the glowing mouth into the park",
                    "V1: Theme‑Park Takeover parade performance down the midway",
                    "Hook: Ride‑POV montage — coaster climb/drop, ferris parallax, log‑flume splash",
                    "V2: Dark‑Ride Funhouse — neon mirrors, lasers, animatronic toys",
                    "Hook: Day–Night Flip + Sky Carnival blimps over park",
                    "Finale: Giant‑Scale virtual show set with physics‑bending moments"
                ],
                setPacks: [
                    "Golden Head Portal Gate",
                    "Midway Parade Route & Floats",
                    "Ride POV Pack (coaster, ferris wheel, log flume)",
                    "Neon Funhouse / Tunnel‑of‑Love",
                    "Day–Night Flip Park Lighting",
                    "Giant‑Scale City Plaza",
                    "Sky Carnival Airspace",
                    "Houston Homage Retro Rides",
                    "Midway Games Heist Alley",
                    "Carousel Zoetrope Stage"
                ],
                loopGags: [
                    "Coaster climb → drop timed to hook",
                    "Ferris‑wheel parallax passes",
                    "Log‑flume splash accents on ad‑libs",
                    "Mirror room infinity reflections",
                    "Blimp/balloon silhouettes drifting over chorus",
                    "Ring‑toss / milk‑bottle win recurring plush prop",
                    "Title signage nods (Texas Cyclone, Thunder River)"
                ],
                cameraGrammar: [
                    "orbit 8–15° around floats and rides",
                    "parallax dolly past props on the midway",
                    "crane‑up reveals over gates and coasters",
                    "slow aerial orbits for sky‑parade hooks",
                    "rack‑focus from signage to performer"
                ],
                fpsHint: "12–16 fps with slight frame jitter for toy‑world/zoetrope vibe"
            )
        ),
        MusicVideoSetting(
            id: "grand_theft_arena",
            name: "Grand Theft Arena",
            imageAssetName: "grandtheftarena",
            environment: "high‑octane drift coliseum with sand floor, neon LED megascreens, pyro, drones and roaring crowd",
            palette: ["#ff3b6e", "#66ccff", "#f6a623", "#0b1023"],
            bio: "A stadium‑scale drift arena turned concert stage. Choreographed cars, pyro and drone light shows surround the performer while the sand floor becomes a projection‑mapped canvas. Built for trap/EDM hooks, pop spectacle and cinematic gladiator stories.",
            promptKit: PromptKit(
                worldPillars: [
                    "Drift choreography around center circle",
                    "LED megascreens and hologram stage",
                    "Pyro lines and fireworks synced to beat",
                    "Drone swarm light shows overhead",
                    "Projection‑mapped sand floor visuals",
                    "Grand Drift Tournament: rivals, crowd, scoreboard"
                ],
                formatBeats: [
                    "Intro: drone fly‑in over arena; lights ramp; artist steps into center",
                    "V1: High‑Energy Rap Performance with choreographed car donuts",
                    "Hook: Electronic/Dance Visualizer — LEDs, pyro bursts, fireworks",
                    "V2: Futuristic Gladiator challenges with scoreboard drama",
                    "Hook: Pop spectacle — dancers weaving between cars, ramps transform",
                    "Finale: Virtual Collab hologram stage and synchronized drift closer"
                ],
                setPacks: [
                    "Center Circle Stage",
                    "Drift Track Patterns (figure‑8, donut, banked turns)",
                    "LED Megascreens & Holograms",
                    "Pyro Lines & Firework Racks",
                    "Drone Light‑Show Grid",
                    "Projection‑Mapped Sand Floor",
                    "Grand Drift Tournament Props (ramps, obelisks, podium)",
                    "Collab Hologram Stage",
                    "Crowd & Scoreboard Package"
                ],
                loopGags: [
                    "Donut drift smoke rings on snares",
                    "Spark fountains on downbeats",
                    "Drone swarm morphs into logo",
                    "Scoreboard flips on drops",
                    "Car LED outlines strobe",
                    "Dancers weaving between cars",
                    "Micro camera shake on engine revs"
                ],
                cameraGrammar: [
                    "orbit 8–15° around center circle",
                    "low‑angle dolly‑in across sand",
                    "overhead crane‑down into formation",
                    "tracking pan following drift path",
                    "telephoto parallax through heat‑haze",
                    "rack‑focus from LED screen to performer"
                ],
                fpsHint: "12–16 fps, slight jitter; add subtle camera vibration on hits"
            )
        )
    ]
}


