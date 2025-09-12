import axios from "axios";
import * as admin from "firebase-admin";
import {geohashForLocation} from "geofire-common";
import yargs from "yargs";
import {hideBin} from "yargs/helpers";

/**
 * Simple seeding script that pulls nearby venues from Google Places API and
 * writes them into the `campusVenues` collection with the fields expected by
 * generateCampusPlans.ts.
 *
 * Usage (from functions/ directory):
 *   npx ts-node src/seedCampusVenues.ts --lat 34.02 --lng -118.28555 --radius 1600
 *
 * GOOGLE_PLACES_KEY must be configured as a secret in your Firebase project.
 */

const argv = yargs(hideBin(process.argv))
  .option("lat", {type: "number", demandOption: true})
  .option("lng", {type: "number", demandOption: true})
  .option("radius", {type: "number", default: 1600})
  .option("city", {type: "string", default: "campus"})
  .parseSync();

if (!process.env.GOOGLE_PLACES_KEY) {
  console.error("GOOGLE_PLACES_KEY env var/secret missing");
  process.exit(1);
}

admin.initializeApp();
const db = admin.firestore();

// Mapping from our vibes -> one or more Google Places search keywords/types.
// A value can be a single string or an array of strings.
const CATEGORIES: Record<string, string | string[]> = {
  // Drinks & hang-outs
  bubble_tea: ["bubble_tea", "boba", "tea_house"],
  cafe: ["cafe", "coffee", "coffee_shop"],
  bar: ["bar", "cocktail_bar", "speakeasy", "brewpub", "wine_bar"],

  // Sweets
  dessert_shop: ["bakery", "dessert", "ice_cream", "gelato"],

  // Entertainment
  arcade: [
    "amusement_arcade",
    "barcade",
    "arcade",
    "video_game_store",
    "entertainment_center",
    "recreation_center",
    "bowling_alley",
  ],
  music_venue: ["music_venue", "live_music", "concert_hall", "piano_bar", "jazz_club"],

  // Outdoors & culture (new)
  art_gallery: ["art_gallery", "museum", "exhibit", "modern_art"],
  outdoor_walk: ["park", "garden", "arboretum", "scenic_view"],

  // Games
  board_games: ["board_game_cafe", "board_games", "tabletop"],
  sports_bar: ["sports_bar", "sports_grill"],
};

async function fetchPlaces(lat: number, lng: number, radius: number, keyword: string) {
  const url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json";
  const params = {
    key: process.env.GOOGLE_PLACES_KEY,
    location: `${lat},${lng}`,
    radius,
    keyword,
    opennow: false,
  };
  const {data} = await axios.get(url, {params});
  return data.results || [];
}

async function run() {
  const {lat, lng, radius, city} = argv;

  for (const [cat, kw] of Object.entries(CATEGORIES)) {
    const keywords = Array.isArray(kw) ? kw : [kw];
    let combined: any[] = [];
    for (const keyword of keywords) {
      console.log(`Fetching ${cat} (${keyword})…`);
      const res = await fetchPlaces(lat, lng, radius, keyword);
      console.log(` → ${res.length} results`);
      combined = combined.concat(res);
    }
    // De-duplicate by place_id
    const unique = new Map<string, any>();
    combined.forEach((r) => unique.set(r.place_id, r));
    const results = Array.from(unique.values());

    const batch = db.batch();
    results.forEach((r: any) => {
      const doc = db.collection("campusVenues").doc(r.place_id);
      batch.set(doc, {
        placeId: r.place_id,
        name: r.name,
        lat: r.geometry.location.lat,
        lng: r.geometry.location.lng,
        geohash: geohashForLocation([r.geometry.location.lat, r.geometry.location.lng]),
        categories: [cat],
        price_level: r.price_level ?? 2,
        photoUrl: r.photos?.[0] ? `https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=${r.photos[0].photo_reference}&key=${process.env.GOOGLE_PLACES_KEY}` : "",
        source: "seedScript",
        city,
      });
    });
    await batch.commit();
  }

  console.log("Seeding complete ✓");
  process.exit(0);
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
