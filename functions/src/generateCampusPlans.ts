import * as functions from "firebase-functions/v1";
// import OpenAI from "openai";
import * as admin from "firebase-admin";
// removed getStorage import
// import yaml from "yaml";
import {geohashQueryBounds, distanceBetween} from "geofire-common";
import {ideaForVenue} from "./venueIdeas";

// minimal stub for rules; full rules logic removed
async function loadVibeTimeRules(): Promise<any> {
  return {};
}

// -----------------------------
// Mission & Game templates
// -----------------------------
// function pick<T>(arr: T[]): T {
//   return arr[Math.floor(Math.random() * arr.length)];
// }

// --------------- Photo Prompts ---------------
// Retained lists (temporarily disabled to satisfy build)
/* const LOSER_PUNISHMENTS = [
  "Loser carries winner’s stuff for the next 20 min.",
  "Loser has to order something in a British accent.",
  "Loser buys something random under $5.",
  "Loser does a TikTok dance. No questions.",
  "Loser sings one bar of their favorite embarrassing song out loud.",
  "Loser takes a dramatic slow-mo walk like it’s a runway.",
  "Loser has to ask 5 strangers for gum.",
  "Loser speaks only in rhyme for the next challenge.",
  "Loser has to “seriously” explain what a rizz god is to someone nearby.",
  "Loser picks up the next Uber/Lyft.",
  "Loser talks in the third person for the next 10 min.",
  "Loser has to compliment an employee like it’s a Yelp review.",
  "Loser shouts “BESTIE VIBES ONLY” in public while you hold hands.",
  "Loser walks backwards out of the building without explanation.",
  "Loser prank calls their mom and say they are having a baby.",
  "Loser gives a short TED talk about why frogs should be president.",
  "Loser does a fake paparazzi interview to the winner.",
];

const PHOTO_PROMPTS = [
  "Stack up like you’re a human totem pole",
  "Cram 3 people in the tiniest mirror",
  "Take a ‘we just committed a crime’ group pic",
  "Pose like y’all are making a mixtape cover",
  "Do a fake yearbook photo: Best Smile & Class Clown edition",
  "Recreate a boyband album cover — awkward hands included",
  "Look like you just got exposed on main",
  "Pose like your ex just walked in",
  "Reenact a horror movie moment — but camp",
  "One of you acts possessed. Go.",
  "Take a blurry cursed photo like it’s 2011 again",
  "Use the front cam and betray everyone’s angles",
  "Act like it’s prom night and you're in love",
  "Do a forehead-touch like it’s a romcom finale",
  "Pose like you’re telling each other a secret",
  "Kiss the air near their cheek. Now laugh.",
  "Take a soft photo with ✌️ but make it ✨aesthetic✨",
  "Pretend you're lost tourists asking for help",
  "Give me ‘high school hallway breakup’ vibes",
  "Stare into the distance like you’re in an indie film",
  "Pretend you’re on a Netflix dating show",
  "Do the ‘Model Walk’ freeze frame mid-stride",
  "Put your hoodie hood up. Now act mysterious.",
  "Lean on each other like y’all just aced a final",
  "Snap a candid while sipping boba or coffee",
  "Find a cool wall and pose like it’s your album drop",
  "Take a no-smile photo. Be ✨artsy✨ about it.",
  "Pose with the snack like it’s your soulmate",
  "Forehead cam realness",
  "Do the ‘caught off guard but I’m still hot’ pose",
  "Spin around and stop mid-motion",
  "Duckface but make it Gen Z irony",
  "Do ✌️✌️✌️ and nothing else. Trust.",
]; */


// ---------------- Game Tasks (Artsy) ----------------
const ARTSY_TASKS = [
  "Strike a pose mimicking the weirdest statue or art piece you can find nearby",
  "Find some graffiti or mural and do your best interpretive pose in front of it for a photo",
  "Recreate the pose famous painting using yourselves as the subjects and snap a photo",
  "Give a dramatic critique of a totally ordinary object nearby like it's avant-garde art, partner records your posh accent",
  "Spot a random object and declare it a modern art piece with a fancy title (e.g., 'Chaotic Coffee Cup #5'), snap a pic",
  "Take an ultra-zoomed artsy photo of something around and have your partner guess what it is (everything's art up close)",
  "Make your most 'tortured artist' faces and take a moody black-and-white selfie together",
  "Find a statue or portrait (or each other) and mimic its facial expression for a side-by-side photo",
  "Tiptoe around like the floor is a sacred art installation and you must not disturb it, have your partner record your stealth",
  "Use a phone filter or drawing app to turn a selfie into 'abstract art' and give it a pretentious title then take a selfie with your masterpiece",
  "Balance on one foot in a weird pose for ten seconds and call it an 'interpretive still life', have partner document it",
  "Take turns making the most exaggerated 'aha' face like you just understood modern art, snap the best one",
  "Do a slow-mo video twirling like you're a ballerina in a music box art piece",
  "Use your shadows on a wall to create a funny shadow puppet scene and take a pic",
  "High-five in front of a piece of art or cool wall so it looks like a freeze-frame high-five sculpture",
  "Invent a new artsy hashtag for your day (like #CaféCubism or #ParkPicasso) and whisper it like it's a secret password whenever you snap a pic",
  "Pretend to be statues for one minute and see if anyone notices; partner can secretly record",
  "Swap an accessory (hat, glasses) with each other and say it's a 'collaboration piece', snap a model-esque photo",
  "Take a panorama shot while one of you runs to appear in it twice (double exposure art!)",
  "Try a perspective trick photo (like 'pinching' your partner's head between your fingers) as if you’re a giant artist",
  "Find a reflection (window, puddle, shiny car) and take a mysterious artsy reflection selfie together",
  "Take a video doing the mannequin challenge (freeze in an artsy pose) for ten seconds in a public spot",
  "End the artsy adventure by taking a final 'gallery opening' style selfie — very chic, very mysterious expressions",
];

// ---------------- Game Tasks (Outdoorsy) ----------------
/* const ROMANTIC_TASKS = [
  "Lean in and whisper the cheesiest pick-up line you can think of to your partner with a straight face (Film the cringe!)",
  "Recreate the iconic Titanic \"I'm flying\" pose: one partner spreads their arms and the other holds them from behind ask a stranger to take a pic ",
  "Take turns whispering ridiculous things as sweet nothings (like \"I love that you always steal my fries\") until one of you cracks up. Capture that laughter in a selfie",
  "Do a classic romance movie dip kiss pose, but instead of a kiss, one of you give a goofy face or peace sign. Snap a pic of the almost-kiss moment",
  "Invent a secret handshake that ends in a big hug. Practice it until smooth and then film your final perfect take",
  "Take turns saying \"I love you\" in different accents or languages and record this.",
  "Compose a super short poem (4 lines) about your partner on the spot (the cheesier, the better) and recite it in an overly dramatic poet voice while the other films ",
  "Each give a 30-second totally fictional account of how you first met (the more wildly inaccurate and rom-com worthy, the better and make sure to record)",
  "Make a heart shape together with your hands (each of you does one half) and snap a picture of your combined heart in front of both your faces",
  "Find the least romantic spot nearby (like by a trash can or an ATM) and strike an over-the-top romantic pose there. Snap a photo to prove love blooms even in silly places",
  "If you have an aging filter on your phone, take a selfie and see what you might look like as an old couple. Share a laugh at your future selves",
  "Together, build a heart or the word \"LOVE\" out of random objects you find nearby (sticks, napkins, anything). Take a pic of your masterpiece of love",
  "Attempt the upside-down Spider-Man kiss pose: one partner tilts their head or hangs off a couch/bench while the other leans in for an almost-kiss. Snap a selfie if you pull it off!",
  "Each of you act out an overly dramatic love confession scene (think movie climax) for 30 seconds while the other watches or records. Give it all the fake tears and passion you've got",
  "End the date by taking a selfie of you two giving each other bunny ears or funny faces instead of a typical lovey-dovey pose—because that's your style",
]; */

const ARCADE_TASKS = [
  "Strike a pose at an arcade machine as if you're in the final round of a world championship (serious gamer face on) and snap a pic",
  "Team up for a dance game (or just dance next to a machine) and intentionally do the goofiest moves instead of the right ones. Capture a short video of the chaos",
  "Bravely take on the claw machine. If you win a prize, do an over-the-top victory pose with it. If not, take a sad selfie with the claw machine as your \"nemesis\"",
  "If there's a photo booth, cram in and make four of the silliest faces possible for each snapshot. If no booth, take four rapid-fire selfies pulling different crazy faces",
  "Take a selfie mimicking the expression of a character or mascot on an arcade machine. Try to get the machine in the background for comparison",
  "Do a synchronized gaming stance pose back-to-back, holding imaginary controllers, and have someone (or a timer) snap a photo of you two serious gamers",
  "Pose at the skee-ball lane like it's the most important bowl of your life, with your partner capturing your intense concentration face",
  "Pretend one arcade machine is secretly a portal to another dimension. One of you act out entering it and describe the crazy world on the other side while the other records your \"voyage\"",
  "End your arcade adventure by each striking a triumphant pose with your favorite game of the night in the background. Take a selfie to commemorate your high-score date",
  "From opposite ends of an arcade aisle, run toward each other in slow motion and meet in an overly dramatic hug, like a reunion scene in a movie (have someone film if possible!)",
  "Pretend you're livestreaming: one person holds up a phone and narrates your arcade action like a Twitch stream while the other plays with over-the-top reactions. End with a big \"Thanks for watching!\"",
  "Secretly pose inside an empty claw machine or prize case (if accessible) pressing your face to the glass, and have your partner snap a pic like you're the prize they've always wanted",
  "End the arcade date by each striking a triumphant pose in front of your favorite game. Take a celebratory selfie with all your tickets and prizes on display",
];

const OUTDOORSY_TASKS = [
  "Find a weird-looking tree or rock and pose with it like it's your long-lost friend in a selfie",
  "Race each other to a nearby bench or tree; loser has to do a goofy victory pose for the winner's camera",
  "Attempt a piggyback ride photo: one hops on and strike a triumphant pose (carefully!)",
  "Collect three different leaves or objects and arrange them into a smiley face on the ground, snap a pic of your nature art",
  "Pretend you're wilderness explorers: give an overly dramatic survival tip about this park while your partner films (e.g., 'Beware of the ferocious park pigeons...')",
  "Do a synchronized jump off a low step or curb and try to get a mid-air photo (superhero landing optional)",
  "Pretend to have a mini picnic with invisible food; set the scene, pour imaginary tea and take a classy selfie",
  "Sing a line from a song about nature (or make one up) out loud and have your partner dramatically join in (Record this )",
  "Find something that resembles a heart shape in nature (leaf, rock, cloud) and take a photo of you both with it for good vibes",
  "Hold up two big leaves or twigs behind your partner's head like bunny ears and snap a pic of the wild forest creature you created",
  "If there's a playground, both go down a slide at the same time and make the silliest face for the camera (childhood nostalgia!)",
  "Lie down on the grass and make 'grass angels' (like snow angels but with grass) while your partner records the randomness",
  "Perform a fake wildlife documentary: one films while the other whispers a dramatic narration about a squirrel or pigeon nearby",
  "Snap a selfie mid-walk with your best 'exhausted adventurer' faces even if you're not tired at all",
  "Treat a random bench like a famous landmark and vlog about it like travel influencers (e.g., 'Here we are at the legendary Bench of Secrets...')",
  "Do 5 jumping jacks together then strike a yoga tree pose like you're suddenly zen masters, catch the combo on camera",
  "Write your initials with sticks or rocks on the ground (no carving into trees!) and take a pic of your nature art",
  "Find a sign or map and mimic the pose of any stick figure or icon on it (like the restroom sign person) for a photo",
  "Pose as if you're lost explorers checking a map (even if it's just Google Maps on your phone) and snap a selfie of your dramatic confusion",
  "Attempt to catch a selfie with a bird or squirrel in the background — bonus points if the animal poses too",
  "Use a stick or your finger to draw a smiley face in the dirt, then take a pic with your masterpiece",
  "Hold a tiny rock or acorn like it's a precious artifact and give your best shocked archaeologist face for a photo",
  "Throw leaves in the air (or just mime it if none around) and dance like you're in a cheesy movie montage while your partner films",
  "Finish your outdoor adventure with a victory pose on a park bench or rock, fists in the air, and capture that champion moment",
];

// ---------------- Game Tasks (Boba Stop) ----------------
const BOBA_TASKS = [
  "Snap a selfie sipping boba with an exaggerated fancy pose, like you're living the sophisticated boba life",
  "Give your drinks names & personalities (Bob and Boba Fett?) and introduce them on video as your new friends",
  "Do a mini \"cheers\" Boomerang clinking your boba cups with pinkies out",
  "Take a pic of both of you sporting a boba \"mustache\" (milk tea foam on your lip) without cracking up",
  "Hold your boba like a wine glass, swirl it, sniff it, then take a tiny sip and give a ridiculously posh review on camera",
  "Take a photo doing the Lady and the Tramp move with two straws in one cup like you're sharing one drink",
  "Pose with your boba like you're in a bubble tea ad: big smiles, maybe a thumbs up, total product placement vibes",
  "Film a slow-motion cheers and sip like it's the climax of a romance movie (wind in your hair, optional)",
  "Create some boba art: spin your cup and snap a pic of the swirling pearls (artsy smoothie tornado!)",
  "Find a cool wall art or neon sign in the shop and mimic it or pose with it for a fun photo",
  "Snap a candid photo of your partner mid-sip and turn it into a meme with a funny caption (show them after!)",
  "Pretend your boba cup is a phone and have a very serious fake conversation on it. Partner snaps a pic of your 'important call'",
  "Take a photo of you two holding your bobas like trophies and doing over-the-top victory smiles (timer mode is your friend)",
  "Do a one-sentence TikTok-style review of your boba (e.g., 'This taro slaps harder than my Monday alarm') to your partner",
  "Film the epic moment of stabbing the seal with your straw in slow-mo like it's an action scene (if you haven't done it yet)",
  "Pose with any quirky decor or sign in the shop like it's a famous tourist attraction and you just discovered it",
  "Get down on one knee and 'propose' with a boba cup instead of a ring, complete with a dramatic gasp. Snap a pic of the romantic moment",
  "Strike your best brain-freeze face (even if you don't actually have one) and snap a pic to see who looks more dramatic",
  "Pretend to host a quick 'Boba 101' tutorial: one teaches the proper way to sip (with totally extra steps) while the other follows along on video",
  "End the boba stop with a selfie outside the shop doing jazz hands with your cups to show off how hyped you are for bubble tea",
];

// ---------------- Game Tasks (Comfort Bites) ----------------
const COMFORT_TASKS = [
  "Record a dramatic slow-mo video of the first glorious bite or sip of your comfort food like it's a food commercial",
  "Pretend to host a cooking show reviewing your meal with over-the-top enthusiasm while your partner films the 'celebrity chef' critique",
  "Take a mid-bite selfie making your best 'mmm delicious' face (embrace the messy, authenticity at its finest)",
  "Make up a quick 3-line rap about how tasty the food is and perform it quietly for your partner",
  "Arrange a few fries or chips (or any food if either aren't available) into a smiley face on a plate to show appreciation for the meal and snap a pic",
  "Impersonate a famous chef or food show host for one minute while tasting your food (bonus points for a Gordon Ramsay or Julia Child impression)",
  "Combine a little of every item on your plate into one ultimate bite. Eat it and have your partner film your reaction to the flavor combo",
  "Take a glamorous photo of your partner posing with their food like it's a high-fashion photoshoot (smize with that burger!)",
  "Make the ugliest face you can right after taking a sip or bite (even if it's delicious) and have your partner capture it. Compare who looks crazier",
  "Pretend the salt shaker is an award you just won for Best Diner Duo and give a thank-you speech while your partner records",
  "See how high you can toss a piece of popcorn or candy and catch it in your own mouth. Record this",
  "Pose for a 'family photo' with your food: both of you smile and hold up your plates as if you're at a holiday dinner",
  "Carve a little shape (a heart or smiley) in your mashed potatoes or sauce and have your partner guess what it is (Record this)",
  "Treat every bite like a dramatic plot twist in a telenovela—gasp or cheer with each taste and catch one reaction on video",
  "Both try to balance a spoon on your noses. Whoever lasts longer gets to steal a bite from the other's plate(Record this)",
  "Build a mini food person on your plate (like a nugget body with fry arms) and introduce your new friend to your partner (Record this)",
  "Use a spoon as a microphone and ask your partner for a 'dining experience' update like you're a reporter on live TV (Record this)",
  "Photobomb your own food pic: one person tries to take a nice food photo while the other sneaks a goofy face in the background",
];

// ---------------- Game Tasks (Live Music) ----------------
const LIVE_MUSIC_TASKS = [
  "Film a 3-second clip of both of you headbanging or dancing like maniacs during a hype song, then immediately stop and pose like nothing happened",
  "Throw up your rock hands 🤘 and take a selfie together pulling your best rockstar faces during the craziest part of a song",
  "Each of you record a 5-second video of yourselves belting out the highest (or worst) note of a song and compare who hit the more \"impressive\" note",
  "Pose in front of a band poster or stage backdrop like you're the performers on the poster. One of you can do a 'call me' hand by your face. Snapshot that superstar moment",
  "Attempt to harmonize (terribly) with the chorus and record a few seconds. Play it back later to appreciate how you're not quitting your day jobs",
  "During an epic guitar solo, play invisible air guitar with full rockstar energy while your partner pretends to faint from your sheer awesomeness. Photo evidence encouraged",
  "Pretend one of you is a reporter and the other is a superfan. Conduct a post-concert interview on video, gushing about how mind-blowing the show was (two thumbs up, 5 stars!)",
  "Take a selfie at the end of the show looking completely exhausted and sweaty, like you just ran a marathon. (We survived! #BestNight)",
  "End the night by humming the last song together on the way out. Bonus points if you add dramatic hand gestures like you're performing on stage. Take one last selfie doing jazz hands to commemorate the concert vibes",
  "Hold an impromptu dance-off in your little space: you and your partner each freestyle goofy dance moves for 5 seconds during a jam. Record this",
  "During a big drum solo, mime playing the drums on your partner's shoulders or head very gently. Instant drum set! Applaud their 'support' after the solo ends",
];

// ---------------- Game Tasks (Bar Hop) ----------------
const BAR_TASKS = [
  "Order or find the most colorful drink and make a dramatic cheers boomerang video with it",
  "Snap a selfie where you're both 'hiding' behind your drinks like you're celebrities avoiding paparazzi",
  "Dare: request a totally danceable song or hum your own tune and bust out a 10-second dance together.Record the moment.",
  "Balance an empty cup on your head for 5 seconds. If it falls you lose (Record this)",
  "Clink glasses while maintaining absurdly intense eye contact and take a photo (unbreaking stare = power move)",
  "On the count of three, both take a sip with pinkies out like the classiest people ever. Snap a pic of those fancy vibes",
  "Take a perspective photo that makes your partner look tiny standing on your glass or hand (bar magic photography!)",
  "Perform a slow-motion 'failed cheers' – go for a toast and intentionally miss – capture it on video for dramatic effect",
  "Take a moody, film noir-style photo of your partner sipping their drink like a detective on a case, caption it 'Undercover at the bar...'",
  "Think up a fake cool band name that matches the vibe here and announce to your partner as they record you. ",
  "Lip sync the chorus of the current song to your partner with pop star passion, then go back to sipping like nothing happened",
  "Secret snap: take a sneaky photo of your partner and add a goofy caption or sticker (like '#HotMess') and show them for laughs",
  "Swap phones and write a funny one-sentence summary of the night in each other's notes. Dramatically read out the 'reviews'",
  "Strike a pose clinking your drinks like you're on a magazine cover, give that camera your best smolder",
  "Challenge your partner to mimic the next person who orders a drink (quietly and good-naturedly) Record this .",
  "Hold your drink up to cover your mouth and make a ridiculous face with just your eyes showing. See if your partner can guess your expression while they record you",
  "If there's a mirror or reflective bar sign, take a mirror selfie of both of you making goofy faces with the bar vibe behind you",
  "Both of you rate this bar using only facial expressions. Snap a selfie showcasing your over-the-top 'rating' faces as the grand finale",
];

// GPT/OpenAI helpers removed for curated-only emulator flow

// ------------ helper to pick task list based on venue categories --------------
// Category to tasks map retained for future non-curated modes
const CAT_TO_TASKS: Record<string, string[]> = {
  arcade: ARCADE_TASKS,
  bar: BAR_TASKS,
  barcade: ARCADE_TASKS,
  video_game_store: ARCADE_TASKS,
  live_music: LIVE_MUSIC_TASKS,
  music_venue: LIVE_MUSIC_TASKS,
  bubble_tea: BOBA_TASKS,
  cafe: BOBA_TASKS,
  dessert_shop: COMFORT_TASKS,
  restaurant: COMFORT_TASKS,
  park: OUTDOORSY_TASKS,
  trail: OUTDOORSY_TASKS,
  museum: ARTSY_TASKS,
  art_gallery: ARTSY_TASKS,
};

// ------------- Category-aware fallback prompts when venueIdeas has no match -------------
function buildCategoryAwareFallback(name: string, categories: string[] | undefined): { action: string; photo: string } {
  const cats = (categories || []).map((c) => c.toLowerCase());
  const has = (...keys: string[]) => keys.some((k) => cats.includes(k));

  if (has("arcade", "barcade", "video_game_store")) {
    return {
      action: `Team up at ${name} and chase high scores or try the photo booth — loser buys the next round of tokens!`,
      photo: "Pose mid-game at your favorite machine with your most intense gamer face",
    };
  }
  if (has("bar", "wine_bar", "brewpub")) {
    return {
      action: `Grab a cozy corner at ${name}, compare sips, and trade a one-line review of your drink`,
      photo: "Clink glasses and capture a moody cheers shot at the bar",
    };
  }
  if (has("bubble_tea", "cafe", "dessert_shop")) {
    return {
      action: `Pick two treats at ${name} and swap first bites while you people-watch`,
      photo: "Hold your drinks or sweets for a playful product-shot selfie",
    };
  }
  if (has("restaurant")) {
    return {
      action: `Share plates at ${name} and each declare an over-the-top 'dish of the night'`,
      photo: "Snap a foodie glam shot with your favorite plate front and center",
    };
  }
  return {
    action: `Explore ${name} together and each call out one detail you’d steal for your dream date spot`,
    photo: "Take a candid walking shot outside the venue sign",
  };
}

// Mark CAT_TO_TASKS as used to satisfy noUnusedLocals
void CAT_TO_TASKS;


// Ensure Firebase app initialized for admin SDK
try {
  admin.app();
} catch {
  admin.initializeApp();
}

// --- Rules loader ---
// rules loader removed

// ----------------- Activity lines loader -----------------


// ---- helper: fallback categories per vibe ----
const DEFAULT_VIBE_CATS: Record<string, string[]> = {
  "artsy": ["museum", "art_gallery"],
  "outdoorsy": ["park", "trail", "outdoor_walk"],
  "romantic": ["restaurant", "dessert_shop"],
  "arcade": ["arcade", "board_games"],
  "live music": ["live_music", "music_venue", "bar"],
  "boba stop": ["bubble_tea", "cafe", "dessert_shop"],
  "comfort bites": ["restaurant", "dessert_shop"],
  "bar hop": ["bar", "sports_bar"],
};

// ---- advanced generator ----
async function advancedGenerate(lat: number, lng: number, _college: string, moodsCsv: string, tod: string, radiusM: number, includeAliases = false, requireCuratedOnly = false) {
  const rules = await loadVibeTimeRules();
  const moods = moodsCsv.toLowerCase().split(/,\s*/);
  const allowedCats = new Set<string>();
  const ALIAS_MAP: Record<string, string[]> = {
    bubble_tea: ["cafe", "dessert_shop"],
    arcade: ["barcade", "video_game_store"],
  };
  for (const vibe of moods) {
    const rule = (rules as any)[vibe];
    if (rule) {
      const timeKey = rule[tod] ? tod : "any";
      (rule[timeKey] || []).forEach((c: string) => {
        allowedCats.add(c);
        if (includeAliases && ALIAS_MAP[c]) ALIAS_MAP[c].forEach((a) => allowedCats.add(a));
      });
    } else if (DEFAULT_VIBE_CATS[vibe]) {
      DEFAULT_VIBE_CATS[vibe].forEach((c) => allowedCats.add(c));
    }
  }
  if (!allowedCats.size) return [];
  const catsArr = [...allowedCats];
  const catChunks = catsArr.length > 10 ? [catsArr.slice(0, 10), catsArr.slice(10)] : [catsArr];
  const center: [number, number] = [lat, lng];
  const bounds = geohashQueryBounds(center, radiusM);
  const db = admin.firestore();
  const venueDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  for (const b of bounds) {
    for (const chunk of catChunks) {
      const snap = await db.collection("campusVenues")
        .where("categories", "array-contains-any", chunk)
        .orderBy("geohash")
        .startAt(b[0]).endAt(b[1])
        .get();
      functions.logger.debug("chunk", chunk.length, "bounds", b, "docs", snap.size);
      snap.docs.forEach((d) => venueDocs.push(d));
    }
  }
  const seen = new Set<string>();
  const candidates = venueDocs.filter((doc) => {
    const v = doc.data();
    if (seen.has(v.placeId)) return false;
    seen.add(v.placeId);
    return distanceBetween(center, [v.lat, v.lng]) * 1000 <= radiusM;
  });
  functions.logger.debug("candidates", candidates.length);
  // Shuffle to interleave different vibes
  for (let i = candidates.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [candidates[i], candidates[j]] = [candidates[j], candidates[i]];
  }
  const PLACES_KEY = process.env.GOOGLE_PLACES_KEY;
  async function fetchAddress(placeId: string): Promise<{address?: string; mapsUrl?: string}> {
    if (!PLACES_KEY) return {};
    try {
      const url = `https://places.googleapis.com/v1/places/${placeId}?fields=formattedAddress,googleMapsUri&key=${PLACES_KEY}`;
      const res = await fetch(url as any);
      if (!res.ok) return {};
      const j = await res.json();
      return {address: j.formattedAddress, mapsUrl: j.googleMapsUri};
    } catch (e) {
      functions.logger.warn("fetchAddress failed", {placeId, e});
      return {};
    }
  }

  const slice = candidates.slice(0, 40); // take a wider slice to allow filtering
  const results = await Promise.all(slice.map(async (doc) => {
    const v = doc.data();
    const idea = ideaForVenue(v.name);
    if (requireCuratedOnly && !idea) {
      return null;
    }

    // Skip GPT/category game tasks and checkpoint photo for curated-only cards.
    // no-op placeholders kept for shape consistency
    // placeholders removed

    // Ensure address is available; fetch lazily if missing
    let address: string | undefined = v.address;
    let mapsUrl: string | undefined = v.mapsUrl;
    if (!address) {
      const fetched = await fetchAddress(v.placeId);
      address = fetched.address || undefined;
      mapsUrl = fetched.mapsUrl || mapsUrl;
      if (address || mapsUrl) {
        try {
          await doc.ref.set({address, mapsUrl}, {merge: true});
        } catch (e) {
          functions.logger.warn("address merge failed", {placeId: v.placeId, e});
        }
      }
    }

    const chosen = idea ? {action: idea.action, photo: idea.photoPrompt} : buildCategoryAwareFallback(v.name, v.categories);
    const allMissionLines = [chosen.action, `Photo Idea: ${chosen.photo}`];
    return {
      id: v.placeId,
      title: `${v.name} Adventure`,
      venueName: v.name,
      photoUrl: v.photoUrl || "",
      distanceMeters: Math.round(distanceBetween(center, [v.lat, v.lng]) * 1000),
      address: address || null,
      missionLines: allMissionLines,
      missions: {gamesToPlay: [], checkpointPhoto: ""},
      curated: Boolean(idea),
      matchedSlug: idea ? idea.slug : undefined,
    } as any;
  }));

  const filtered = results.filter((r) => r !== null) as any[];

  if (requireCuratedOnly) {
    const dropped = results.length - filtered.length;
    const curatedMatches = filtered.length; // all remaining are curated
    functions.logger.info("curationCoverage", {
      radiusM,
      includeAliases,
      considered: results.length,
      curatedMatches,
      droppedForCuratedOnly: dropped,
    });
  } else {
    const curatedMatches = filtered.filter((r) => r.curated).length;
    functions.logger.debug("curationCoverageSample", {
      radiusM,
      includeAliases,
      considered: filtered.length,
      curatedMatches,
    });
  }

  return filtered;
}

interface GenerateCampusInput {
  college: string;
  latitude: number;
  longitude: number;
  mood: string;
  timeOfDay: string;
  maxDistanceMeters?: number;
  pageCursor?: string;
  pageSize?: number;
  requireCuratedOnly?: boolean;
}

export const generateCampusPlans = functions
  .region("us-central1")
  .runWith({secrets: ["OPENAI_KEY", "GOOGLE_PLACES_KEY"]})
  .https.onCall(async (data: GenerateCampusInput, _context) => {
    const {college, latitude, longitude, mood, timeOfDay, maxDistanceMeters = 1600, pageCursor, pageSize} = data;
    const requireCuratedOnly = typeof data.requireCuratedOnly === "boolean" ?
      data.requireCuratedOnly :
      ["1", "true", "yes"].includes(String(process.env.REQUIRE_CURATED_ONLY || "").toLowerCase());
    functions.logger.info("generateCampusPlans", {college, latitude, longitude, mood, timeOfDay, pageCursor, pageSize});

    const ladders: Array<{ includeAliases: boolean; radius: number }> = [
      {includeAliases: false, radius: maxDistanceMeters}, // 0 strict
      {includeAliases: true, radius: maxDistanceMeters}, // 1 alias cats
      {includeAliases: true, radius: maxDistanceMeters * 2}, // 2 radius ×2
      {includeAliases: true, radius: maxDistanceMeters * 5}, // 3 radius ×5 (≈5 mi if slider was 1 mi)
    ];

    const DESIRED_THEMES = 100; // build a larger pool server-side
    let themes: any[] = [];
    let step = 0;
    for (const [idx, cfg] of ladders.entries()) {
      try {
        themes = await advancedGenerate(latitude, longitude, college, mood, timeOfDay, cfg.radius, cfg.includeAliases, requireCuratedOnly);
      } catch (e) {
        functions.logger.error("advancedGenerate step failed", {idx}, e);
      }
      if (themes.length >= DESIRED_THEMES) {
        step = idx; break;
      }
    }

    // fallback if still insufficient
    if (themes.length < DESIRED_THEMES) {
      step = ladders.length;
      themes = await advancedGenerate(latitude, longitude, college, mood, timeOfDay, maxDistanceMeters * 5, true, requireCuratedOnly);
    }

    // --- Auto-expand radius until we hit the desired count or 10 km ---
    let dynamicRadius = ladders[ladders.length - 1].radius;
    while (themes.length < DESIRED_THEMES && dynamicRadius < 10000) {
      dynamicRadius += 2000; // expand by 2 km each iteration
      try {
        const extra = await advancedGenerate(latitude, longitude, college, mood, timeOfDay, dynamicRadius, true, requireCuratedOnly);
        // merge, preferring earlier items and unique placeIds
        const seen = new Set(themes.map((t:any) => t.id));
        for (const t of extra) {
          if (!seen.has(t.id)) {
            themes.push(t); seen.add(t.id);
          }
          if (themes.length >= DESIRED_THEMES) break;
        }
      } catch (e) {
        functions.logger.error("dynamic expand failed", {dynamicRadius}, e);
        break; // avoid infinite loop on persistent failure
      }
    }

    // Cursorized paging: make a stable shuffle once per request and slice by cursor
    const limit = typeof pageSize === "number" && pageSize > 0 ? pageSize : undefined; // backend may choose default
    // cursor is an index encoded as string
    const startIndex = pageCursor ? parseInt(pageCursor, 10) || 0 : 0;
    const endIndex = limit ? Math.min(startIndex + limit, themes.length) : Math.min(startIndex + 36, themes.length);
    const slice = themes.slice(startIndex, endIndex);
    const coverage = {
      totalReturned: slice.length,
      curatedReturned: slice.filter((t:any) => t.curated).length,
      requireCuratedOnly,
    };
    functions.logger.info("curationReturnCoverage", coverage);
    const nextCursor = endIndex < themes.length ? String(endIndex) : null;
    return {themes: slice, nextCursor, relaxationLevel: step, radiusUsed: dynamicRadius};
  });
