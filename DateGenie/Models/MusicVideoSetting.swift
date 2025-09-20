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
        )
    ]
}


