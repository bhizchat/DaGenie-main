import * as admin from "firebase-admin";
import {geohashForLocation} from "geofire-common";

/*
  Seeds a minimal set of campusVenues into the Firestore Emulator
  so we can exercise curated-only matching locally.

  Usage (with emulator running on 8080):
    FIRESTORE_EMULATOR_HOST=localhost:8080 npx ts-node scripts/seedEmuCampusVenues.ts
*/

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  // eslint-disable-next-line no-console
  console.warn("FIRESTORE_EMULATOR_HOST not set. This will write to production if credentials are present. Aborting.");
  process.exit(1);
}

try {
  admin.app();
} catch {
  admin.initializeApp({projectId: "demo-project"});
}

const db = admin.firestore();

const centerLat = 37.3352;
const centerLng = -121.8811;

type SeedVenue = {
  placeId: string;
  name: string;
  lat: number;
  lng: number;
  categories: string[];
  photoUrl?: string;
};

const near = (dx: number, dy: number) => ({
  lat: centerLat + dx,
  lng: centerLng + dy,
});

const seeds: SeedVenue[] = [
  {placeId: "emu_market_bar", name: "Market Bar", ...near(0.002, -0.0015), categories: ["bar"]},
  {placeId: "emu_ancora_vino", name: "Ancora Vino by Enoteca La Storia", ...near(0.0022, -0.0012), categories: ["bar"]},
  {placeId: "emu_save_n_continue", name: "SAVE n CONTINUE", ...near(0.0015, -0.0025), categories: ["arcade"]},
  {placeId: "emu_55_south", name: "55 South", ...near(0.0018, -0.0018), categories: ["bar"]},
  {placeId: "emu_bijan_wine_bar", name: "Bijan Wine Bar", ...near(0.0021, -0.0016), categories: ["bar"]},
  {placeId: "emu_narrative_fermentations", name: "Narrative Fermentations", ...near(0.0045, -0.003), categories: ["bar"]},
  {placeId: "emu_san_pedro_social", name: "San Pedro Social", ...near(0.0013, -0.0014), categories: ["arcade", "bar"]},
  {placeId: "emu_old_wagon", name: "The Old Wagon Saloon & Grill", ...near(0.0016, -0.0011), categories: ["bar", "restaurant"]},
  {placeId: "emu_a_m_craft", name: "A.M. Craft", ...near(0.0024, -0.0017), categories: ["bar"]},
  {placeId: "emu_slingshot_pinball", name: "Slingshot Pinball", ...near(0.0032, -0.002), categories: ["arcade"]},
];

async function run(): Promise<void> {
  const batch = db.batch();
  for (const v of seeds) {
    const geohash = geohashForLocation([v.lat, v.lng]);
    const ref = db.collection("campusVenues").doc(v.placeId);
    batch.set(ref, {
      placeId: v.placeId,
      name: v.name,
      lat: v.lat,
      lng: v.lng,
      geohash,
      categories: v.categories,
      photoUrl: v.photoUrl ?? "",
      source: "emuSeed",
      city: "san_jose",
    });
  }
  await batch.commit();
  // eslint-disable-next-line no-console
  console.log(`Seeded ${seeds.length} venues into emulator ✓`);
}

run().catch((e) => {
  // eslint-disable-next-line no-console
  console.error(e);
  process.exit(1);
});


