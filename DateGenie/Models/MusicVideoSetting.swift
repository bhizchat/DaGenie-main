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
    let storyTemplates: [[String]]
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
                storyTemplates: [
                    [
                        "Boat lands at biolume bay; step onto dock",
                        "Shades on; grin to camera",
                        "Mango grove path; hands brush leaves",
                        "Taste test; goofy face then smirk",
                        "Friends appear from trees; bounce",
                        "Jet pack ignition; mini lift‑off gag",
                        "Rocket POV to Mango Planet",
                        "Low‑angle hover; hand chops on snare",
                        "Photo‑shoot montage with props",
                        "Peel‑swirl transition; outfit swap",
                        "Confetti cannon of petals on hook",
                        "Crane pull‑back; island fireworks"
                    ],
                    [
                        "Dock arrival at golden hour",
                        "Counting bars; ring sparkle close‑up",
                        "Fruit market tease; money fan",
                        "Light‑painting with LED sticks",
                        "Drone orbit over throne of mangos",
                        "Crew tunnel with lanterns",
                        "Reverse splash gag on drop",
                        "Rocket cockpit wink to skyline",
                        "Mist walk‑through in slow‑mo",
                        "Leaf logo reveal in sand",
                        "Friends wave from jetty",
                        "Final goodbye from Mango Rocket"
                    ],
                    [
                        "Glowing river boardwalk walk‑in",
                        "Palm‑up ‘watch this’",
                        "Seed‑car drift passes behind",
                        "Macro mango texture to horizon rack‑focus",
                        "Orange fit swap jump‑cut",
                        "Drone circles as you pose",
                        "Call‑me hand cue; fruit drones orbit",
                        "Chain flash; head nod",
                        "Juice lens drip gag",
                        "Slow strut through mist",
                        "Peel swirl transition",
                        "Rocket streaks into night"
                    ],
                    [
                        "Island map stamp intro",
                        "Outfit check in mirror water",
                        "Follow fireflies into grove",
                        "Friends pop from behind trees",
                        "Climb mango throne; laugh",
                        "Whip‑pan to jet pack spark",
                        "Sky ride over island",
                        "POV cockpit countdown 3‑2‑1",
                        "Orbit at cloud level",
                        "Drop back to parade beach",
                        "Waves glitter on beat",
                        "Slow crane‑out to star field"
                    ]
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
                storyTemplates: [
                    [
                        "Entrance under peppermint arch; palm‑out ‘follow’",
                        "Candy‑striped shades on; wink",
                        "Licorice runway walk; look‑back",
                        "Lollipop taste; playful reaction",
                        "Gummy parade bounce",
                        "Chocolate fountain push‑in",
                        "Shopping cart POV; point to lens",
                        "Soda spray pop; laugh",
                        "Split screens sweet vs sour",
                        "Drone over gumdrop hill",
                        "Hook outfit swaps on snares",
                        "Fireworks over candy city"
                    ],
                    [
                        "Neon gummy tunnel walk‑through",
                        "Jawbreaker sparkle close‑up",
                        "Candy drone initials in sky",
                        "Cape sprinkles trail twirl",
                        "Peppermint club strobe hits",
                        "Reverse sprinkle fall catch",
                        "Taffy pull sync to beat",
                        "Boardwalk friends wave",
                        "Soda‑pop jacket foams",
                        "Marshmallow step sequence",
                        "Dutch‑angle at chocolate river",
                        "Final pull‑out city fireworks"
                    ],
                    [
                        "Ticket booth intro; grin",
                        "Sugar market montage",
                        "Candy‑letter name spell",
                        "Bridge pass parallax",
                        "Candy drone swarm",
                        "Pop‑art fashion board",
                        "Gummy crowd bounce",
                        "Raceway POV rush",
                        "Peppermint skyline wide",
                        "Windmill lollipop sweep",
                        "Hook jump‑cut outfit swaps",
                        "Sky glitter finale"
                    ],
                    [
                        "Cotton‑candy clouds reveal",
                        "Street dance with friends",
                        "Macro sugar crystals rack‑focus",
                        "Candy cart ride‑along",
                        "Sticker bomb frame edge",
                        "Lego workers cameo",
                        "Light‑paint initials",
                        "Candy confetti rain",
                        "Giant jelly wobble gag",
                        "Posed hero frame",
                        "Slow pull‑back",
                        "Final wink to camera"
                    ]
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
                storyTemplates: [
                    [
                        "Torii gate arrival; respectful nod",
                        "Shoes off at genkan; enter townhouse",
                        "Tea ceremony with a local — quiet smiles",
                        "Lantern alley walk; neon kanji wake",
                        "Training kata in courtyard; brush-stroke light",
                        "Market lane cypher; call-and-response",
                        "Cherry blossoms drift; close-up hands catching petals",
                        "Rooftop look‑out; city glows below",
                        "Paper fan flourish; playful bow",
                        "Night parade passes; you lead the step",
                        "Temple drums hit; head‑nod to camera",
                        "Final rooftop pose; blossoms rain"
                    ],
                    [
                        "Alley projection‑graffiti animates to beat",
                        "Kimono‑streetwear fit reveal",
                        "Meet‑cute at tea counter; share a pour",
                        "Shrine courtyard cypher spin",
                        "Calligraphy swipe reveals name",
                        "Bridge crossing in light mist",
                        "Taiko rim shots; hand chops in sync",
                        "Festival masks crowd tunnel; high‑five",
                        "Neon kanji skyline crane‑up",
                        "Haiku punchline freeze pose",
                        "Paper lanterns rise to sky",
                        "Rooftop ‘throne’ pose, city beyond"
                    ],
                    [
                        "Temple gate slow walk‑in",
                        "Tatami tea set out; steam curls",
                        "Low‑angle hero frame under lanterns",
                        "Street vendor exchange; nod and smile",
                        "Kendo footwork on vinyl mats (no blade)",
                        "Fish‑eye courtyard spin",
                        "Profile glide past shoji silhouettes",
                        "Coin toss lands in bowl, grin",
                        "Brush‑stroke projections across jacket",
                        "Top‑down crosswalk symmetry",
                        "Friends gather; synchronized two‑step",
                        "Rooftop fireworks flicker on faces"
                    ],
                    [
                        "Rains clears; door slides open to night",
                        "Gift a paper fan; shared laugh",
                        "Tea steam close‑up; eyes meet",
                        "Neon alley walk‑and‑rap tracking",
                        "Shrine steps pose; petals fly",
                        "Taiko sticks hit; edit on snare",
                        "Bridge rails parallax; hand trace",
                        "Street mural reveal; point to lens",
                        "Roofline run; stop at edge",
                        "Bells ring; camera crane‑out",
                        "Crew joins; wide hero frame",
                        "Final bow; city sparkle pull‑back"
                    ]
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
                storyTemplates: [
                    [
                        "Gates open to golden head; palm sweep",
                        "Midway parade performance",
                        "Ride‑POV coaster climb",
                        "LED tunnel walk; constellations trace",
                        "Prize booth money fan",
                        "Astronaut streetwear swap",
                        "Zero‑g hop freeze",
                        "Whip‑pan between rides",
                        "Ferris wheel drone orbit",
                        "Blimps drift over chorus",
                        "Spark fountains on drop",
                        "Final skyline + golden head"
                    ],
                    [
                        "Ticket scan close‑up",
                        "Neon funhouse mirrors",
                        "Game stall montage",
                        "Slate clap BTS wink",
                        "Laser grid floor glide",
                        "Hologram doubles moonwalk",
                        "Dark‑ride glow silhouettes",
                        "Strobe alley walk",
                        "Balloon silhouettes in sky",
                        "Friends chant wave",
                        "Day–night flip timelapse",
                        "Fireworks finale"
                    ],
                    [
                        "Map reveal with route line",
                        "Entrance photo pose",
                        "Parade float orbit",
                        "Coaster drop hands‑up",
                        "Ferris slow spin POV",
                        "Prize win celebration",
                        "Midway dance circle",
                        "Mirror room infinity",
                        "Tunnel of light sway",
                        "Rooftop view of park",
                        "Sky carnival blimps",
                        "Crane pull‑out farewell"
                    ],
                    [
                        "Golden head portal intro",
                        "LED tunnel walk‑and‑rap",
                        "Pop‑up photo ops montage",
                        "Friends join parade",
                        "Ride montage quick cuts",
                        "Cotton candy laugh",
                        "Hologram stage tease",
                        "Drone pull‑back crowd",
                        "Sparkler line on beat",
                        "Balloon release",
                        "Glow city wide",
                        "Signature pose end"
                    ]
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
                storyTemplates: [
                    [
                        "Tunnel walk‑in; lights flicker",
                        "Center court step; chain flash",
                        "LED ribbons pulse to beat",
                        "Two‑step with crew at logo",
                        "Top‑down symmetry drone",
                        "Strobe hits on drops",
                        "Locker room confetti test",
                        "Smoke fan slow‑mo strut",
                        "Split screen locker/court/jumbotron",
                        "Parking deck whip‑pan",
                        "Circle of headlights rim‑light",
                        "Jumbotron hero pull‑out"
                    ],
                    [
                        "Arena gates open exterior",
                        "Put on tinted shades; look up",
                        "Court line chalk reveal",
                        "Crew huddle clap",
                        "Drift car lap outside",
                        "Scoreboard flip on drop",
                        "Pyro line burst",
                        "Drone light‑show grid",
                        "Sand‑floor projection map",
                        "Champagne locker room",
                        "Trophy lift freeze",
                        "Stadium wide finale"
                    ],
                    [
                        "Echoing footsteps through tunnel",
                        "First step into light",
                        "Slow push‑in to center logo",
                        "Camera orbit as you perform",
                        "Wide empty seats mood",
                        "Crew enters from tunnel",
                        "Quick rack‑focus to rings",
                        "Fans fill seats (loop VFX)",
                        "Overhead crane‑down",
                        "Parking deck performance",
                        "Circle cars headlights",
                        "Helicopter city reveal"
                    ],
                    [
                        "Press room mic check",
                        "Walk to court corridor",
                        "Open arena to reveal",
                        "Warm‑up stretch sequence",
                        "First verse at center",
                        "Crowd wave B‑roll",
                        "Mascot dance cameo",
                        "Score bug overlay gag",
                        "Cut to parking lap",
                        "Return to court finale",
                        "Glitter drop on hook",
                        "Jumbotron flash end"
                    ]
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


