import {readFileSync} from "fs";
import path from "path";
import * as functions from "firebase-functions";

export interface VenueIdea {
  /** Unique identifier derived from venue name */
  slug: string;
  /** Optional alternate slugs that should map to the same idea */
  aliases?: string[];
  /** Single action suggestion for this venue */
  action: string;
  /** Single photo prompt for this venue */
  photoPrompt: string;
}

/**
 * Convert a venue name to a deterministic slug used as the lookup key.
 *
 * The algorithm lower-cases the string, replaces all non-alphanumeric
 * characters with underscores, and trims leading/trailing underscores.
 *
 * @param {string} name Raw venue name (e.g. "Tea Alley")
 * @return {string} Slugified string in snake_case (e.g. "tea_alley")
 */
export function slugify(name: string): string {
  // Normalize to improve matching across common variants
  // 1) Lowercase
  // 2) Replace common connectors with words: & and + -> "and"
  // 3) Strip diacritics: café -> cafe
  // 4) Replace non-alphanumeric with underscores and collapse repeats
  const lowered = name.toLowerCase();
  const connectors = lowered.replace(/[&+]/g, " and ");
  const noDiacritics = connectors
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
  return noDiacritics
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
}

const ideasPath = path.join(__dirname, "../config/venue_ideas.json");
let raw: VenueIdea[] = [];

function parseLooseVenueIdeas(text: string): VenueIdea[] {
  // Extract every top-level JSON object, ignoring arrays and commas between them.
  const items: VenueIdea[] = [];
  let depth = 0;
  let inStr = false;
  let esc = false;
  let start = -1;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inStr) {
      if (esc) {
        esc = false;
      } else if (ch === "\\") {
        esc = true;
      } else if (ch === "\"") {
        inStr = false;
      }
      continue;
    }
    if (ch === "\"") {
      inStr = true;
      continue;
    }
    if (ch === "{") {
      if (depth === 0) start = i;
      depth++;
    } else if (ch === "}") {
      depth--;
      if (depth === 0 && start >= 0) {
        const objStr = text.slice(start, i + 1);
        try {
          const obj = JSON.parse(objStr) as VenueIdea;
          if (obj && obj.slug && obj.action && obj.photoPrompt) items.push(obj);
        } catch {
          // ignore malformed object
        }
        start = -1;
      }
    }
  }
  return items;
}

try {
  const content = readFileSync(ideasPath, "utf8");
  try {
    const parsed = JSON.parse(content);
    if (Array.isArray(parsed)) {
      raw = parsed as VenueIdea[];
    } else {
      // Single object or wrong shape: fall back to loose parsing
      raw = parseLooseVenueIdeas(content);
    }
  } catch (inner) {
    // Fallback: tolerate NDJSON or object lists not wrapped in an array
    raw = parseLooseVenueIdeas(content);
  }
} catch (e) {
  // eslint-disable-next-line no-console
  console.warn("[venueIdeas] failed to read idea bank file", e);
}

const ideaMap = new Map<string, VenueIdea>();

// Stopwords for matching hygiene (not for alias generation)
const STOPWORDS = new Set<string>([
  "san", "jose", "sj", "the", "and", "bar", "pub", "brew", "brewing", "bakery", "cafe", "coffee", "tea", "boba", "market",
  "center", "garden", "park", "museum", "gallery", "studio", "house", "street", "st", "ave", "avenue", "blvd", "road", "rd",
]);

function normForMatch(s: string): string {
  const lowered = s.toLowerCase();
  const connectors = lowered.replace(/[&+]/g, " and ");
  const noDiacritics = connectors.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  return noDiacritics.replace(/[^a-z0-9\s]/g, " ").replace(/\s+/g, " ").trim();
}

function tokenize(s: string): string[] {
  return normForMatch(s).split(" ").filter((t) => t && !STOPWORDS.has(t));
}

function bigrams(ts: string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < ts.length - 1; i++) out.push(`${ts[i]} ${ts[i + 1]}`);
  return out;
}
for (const idea of raw) {
  ideaMap.set(idea.slug, idea);

  // Merge manual aliases with a light set of auto-aliases to catch
  // common Google Places variants like "... SJ" or "... San Jose".
  const aliasSet = new Set<string>(idea.aliases ?? []);
  aliasSet.add(`${idea.slug}_san_jose`);
  aliasSet.add(`${idea.slug}_sj`);

  // Add variants for connector differences (and/n) to catch names like
  // "Kitchen + Bar" vs "Kitchen and Bar" vs "Kitchen n Bar".
  if (idea.slug.includes("_and_")) {
    aliasSet.add(idea.slug.replace(/_and_/g, "_n_"));
    aliasSet.add(idea.slug.replace(/_and_/g, "_")); // drop connector
  }
  if (idea.slug.includes("_n_")) {
    aliasSet.add(idea.slug.replace(/_n_/g, "_and_"));
    aliasSet.add(idea.slug.replace(/_n_/g, "_")); // drop connector
  }

  // If the slug already contains "san_jose" or "sj", add a base variant
  // without that suffix, to catch the inverse case.
  if (idea.slug.endsWith("_san_jose")) {
    aliasSet.add(idea.slug.replace(/_san_jose$/, ""));
  }
  if (idea.slug.endsWith("_sj")) {
    aliasSet.add(idea.slug.replace(/_sj$/, ""));
  }

  aliasSet.forEach((a) => {
    if (!ideaMap.has(a)) {
      ideaMap.set(a, idea);
    } else {
      // Avoid overwriting an existing alias binding; collisions are likely generic tokens.
      functions.logger.debug("venueIdeas: alias collision skipped", {alias: a, slug: idea.slug});
    }
  });
}

export function ideaForVenue(name: string): VenueIdea | undefined {
  const slug = slugify(name);

  // 1) Exact match (slug or alias)
  const exact = ideaMap.get(slug);
  if (exact) {
    functions.logger.info("venueIdeas: exact matched venue", {
      inputName: name,
      inputSlug: slug,
      matchedSlug: exact.slug,
    });
    return exact;
  }
  // 2) Scored fuzzy match using tokens + bigrams + alias boost
  // Build per-idea metadata once (cached in closure via module scope)
  const getMatcher = (() => {
    let built: null | ((query: string) => { idea: VenueIdea; score: number; why: Record<string, unknown> } | null) = null;
    return () => {
      if (built) return built;
      // Build meta
      const metas = raw.map((v) => {
        const base = [v.slug.replace(/_/g, " "), ...(v.aliases ?? [])].join(" ");
        const ts = tokenize(base);
        const bs = bigrams(ts);
        return {idea: v, tset: new Set(ts), bset: new Set(bs)};
      });

      // Compute token document frequencies
      const df = new Map<string, number>();
      for (const m of metas) {
        m.tset.forEach((t) => df.set(t, (df.get(t) ?? 0) + 1));
        m.bset.forEach((b) => df.set(b, (df.get(b) ?? 0) + 1));
      }

      const NOISE_THRESHOLD = 10; // tokens that appear in >10 venues are ignored
      built = (query: string) => {
        const qTokens = tokenize(query);
        const qBigrams = bigrams(qTokens);

        let best: { idea: VenueIdea; score: number; why: Record<string, unknown> } | null = null;
        for (const m of metas) {
          const tokenMatches = qTokens.filter((t) => m.tset.has(t) && (df.get(t) ?? 0) <= NOISE_THRESHOLD);
          const bigramMatches = qBigrams.filter((b) => m.bset.has(b) && (df.get(b) ?? 0) <= NOISE_THRESHOLD);
          if (!tokenMatches.length && !bigramMatches.length) continue;

          // Score: 2x bigrams + 1x tokens
          let score = tokenMatches.length + 2 * bigramMatches.length;

          // Exact alias boost
          const hasExactAlias = (m.idea.aliases ?? []).some((a) => normForMatch(a) === normForMatch(query));
          if (hasExactAlias) score += 5;

          // Minimum acceptance: at least 2 total matches or score >= 3
          const totalMatches = tokenMatches.length + bigramMatches.length;
          if (totalMatches < 2 && score < 3) continue;

          const why = {
            qTokens,
            qBigrams,
            tokenMatches,
            bigramMatches,
            hasExactAlias,
            score,
          };

          if (!best || score > best.score || (
            score === best.score && (
              // tie-break: more bigrams > more tokens > lexical slug
              bigramMatches.length > (best.why as any).bigramMatches.length ||
              (bigramMatches.length === (best.why as any).bigramMatches.length && tokenMatches.length > (best.why as any).tokenMatches.length) ||
              (bigramMatches.length === (best.why as any).bigramMatches.length && tokenMatches.length === (best.why as any).tokenMatches.length && m.idea.slug < best.idea.slug)
            )
          )) {
            best = {idea: m.idea, score, why};
          }
        }
        return best;
      };
      return built;
    };
  })();

  const matcher = getMatcher();
  const result = matcher(name);
  if (result) {
    functions.logger.debug("venueIdeas: fuzzy matched venue (scored)", {
      inputName: name,
      inputSlug: slug,
      matchedSlug: result.idea.slug,
      why: result.why,
    });
    return result.idea;
  }

  // 3) Log misses so we can expand the dataset or adjust matching.
  const missTokens = slug.split("_").filter(Boolean);
  functions.logger.info("venueIdeas: no idea found for venue", {
    inputName: name,
    inputSlug: slug,
    tokens: missTokens,
  });
  return undefined;
}

export function pickRandom<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}
