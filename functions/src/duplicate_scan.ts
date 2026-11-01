/**
 * The nightly duplicate check.
 *
 * The same rules as the app's Tools → Merge duplicate partners
 * (lib/features/maintenance/domain/data_health.dart): member ID, phones and
 * emails in any format, and names with titles, word order, initials, Akan
 * day-name spellings, short forms and typos. It writes only counts, to
 * `churches/{id}/health/duplicates`, so the Tools badge can say there is
 * something to look at; the list itself is still worked out, and merged, in
 * Tools.
 *
 * Keep the scoring in step with data_health.dart.
 */
import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

const REGION = "us-central1";
const db = () => admin.firestore();

const TITLES = new Set((
  "mr mrs ms miss mst dr doc prof rev revd reverend pastor ps pst elder eld deacon dcn deaconess dcns " +
  "apostle apst prophet prophetess bishop evangelist evang sir madam mad hon engr eng lady bro brother " +
  "sis sister snr sr jnr jr").split(" "));

const DAY: Record<string, string> = {};
for (const [day, words] of Object.entries({
  "sun-m": "kwasi kwesi akwasi siisi kwasie", "sun-f": "akosua esi essi akos",
  "mon-m": "kwadwo kojo kodwo jojo kwadjo", "mon-f": "adwoa adjoa adjowa",
  "tue-m": "kwabena kobina ebo kwabina kobena", "tue-f": "abena araba abenaa",
  "wed-m": "kwaku kweku kuuku kwaaku", "wed-f": "akua ekua akuah",
  "thu-m": "yaw ekow yao kwaw", "thu-f": "yaa aba",
  "fri-m": "kofi fiifi fifi fiofi", "fri-f": "afua efua afia afuah",
  "sat-m": "kwame kwamena kwamina kwami", "sat-f": "ama amma ame amah",
})) {
  for (const w of words.split(" ")) DAY[w] = day;
}

export function spellingKey(w: string): string {
  let s = w.replace(/ph/g, "f").replace(/(.)\1+/g, "$1");
  if (s.length > 3 && s.endsWith("h")) s = s.slice(0, -1);
  return s;
}
const canonWord = (w: string) => (DAY[w] ? `day:${DAY[w]}` : spellingKey(w));

interface Name {
  exact: string;
  core: string[];
  initials: string[];
  joined: string;
  canonJoined: string;
  spelledJoined: string;
}

export function parseName(raw: string): Name {
  const words = raw.toLowerCase().replace(/[^a-z0-9\s]/g, " ").split(/\s+/).filter(Boolean);
  const core: string[] = [];
  const initials: string[] = [];
  for (const w of words) {
    if (TITLES.has(w)) continue;
    (w.length === 1 ? initials : core).push(w);
  }
  core.sort();
  return {
    exact: words.join(" "),
    core,
    initials,
    joined: core.join(" "),
    canonJoined: core.map(canonWord).sort().join(" "),
    spelledJoined: core.map(spellingKey).sort().join(" "),
  };
}

/** 1.0 for identical strings; two swapped letters count as one edit. */
export function textSimilarity(a: string, b: string): number {
  if (a === b) return 1;
  if (!a || !b) return 0;
  const m = a.length;
  const n = b.length;
  const d: number[][] = Array.from({length: m + 1}, (_, i) =>
    Array.from({length: n + 1}, (_, j) => (i === 0 ? j : j === 0 ? i : 0)));
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
      }
    }
  }
  return 1 - d[m][n] / Math.max(m, n);
}

/** How alike two names are; null when they are not. Mirrors `_nameSignal`. */
export function nameWeight(x: Name, y: Name): number | null {
  if (!x.exact || !y.exact) return null;
  if (x.exact === y.exact) return 0.6;
  if (!x.core.length || !y.core.length) return null;
  if (x.joined === y.joined) return 0.55;
  if (x.core.length >= 2 && x.canonJoined === y.canonJoined) return 0.5;

  const xs = new Set(x.core);
  const ys = new Set(y.core);
  const shared = [...xs].filter((w) => ys.has(w));
  const covers = (s: Name, S: Set<string>, L: Set<string>) => {
    if (!s.initials.length || ![...S].every((w) => L.has(w))) return false;
    const missing = [...L].filter((w) => !S.has(w));
    return missing.length > 0 && missing.length <= s.initials.length &&
      missing.every((w) => s.initials.includes(w[0]));
  };
  if (shared.length && (covers(x, xs, ys) || covers(y, ys, xs))) return 0.5;
  if (shared.length >= 2 && (shared.length === xs.size || shared.length === ys.size)) return 0.45;
  if (x.core.length === y.core.length && x.joined.length >= 6 &&
      textSimilarity(x.spelledJoined, y.spelledJoined) >= 0.85) return 0.45;

  const [short, long] = x.core.length <= y.core.length ? [x, y] : [y, x];
  if (short.core.length >= 2) {
    let exact = 0;
    const fits = short.core.every((w) => {
      if (long.core.some((v) => v === w || canonWord(v) === canonWord(w))) {
        exact++;
        return true;
      }
      return long.core.some((v) =>
        (w.length >= 3 && (v.startsWith(w) || v.endsWith(w))) ||
        (v.length >= 3 && (w.startsWith(v) || w.endsWith(v))) ||
        textSimilarity(spellingKey(w), spellingKey(v)) >= 0.8);
    });
    if (fits && exact >= 1) return 0.4;
  }
  return null;
}

export interface ScanPartner {
  id: string;
  fullName: string;
  memberId: string;
  fellowship: string;
  phones: string[];
  emails: string[];
}

const phoneKey = (s: string) => {
  const d = s.replace(/\D/g, "");
  return d.length < 9 ? "" : d.slice(-9);
};
const emailKey = (s: string) => {
  const e = s.trim().toLowerCase();
  return e.includes("@") ? e : "";
};

/** Score for one pair; null below the report floor. Mirrors `_score`. */
export function scorePair(a: ScanPartner, b: ScanPartner, na: Name, nb: Name): {score: number; name: boolean} | null {
  const pa = new Set(a.phones.map(phoneKey).filter(Boolean));
  const pb = new Set(b.phones.map(phoneKey).filter(Boolean));
  const ea = new Set(a.emails.map(emailKey).filter(Boolean));
  const eb = new Set(b.emails.map(emailKey).filter(Boolean));
  const name = nameWeight(na, nb);
  const contact = name === null ? 0 : name >= 0.45 ? 0.9 : 0.7;
  const weights: number[] = [];
  const idMatch = Boolean(a.memberId) && a.memberId === b.memberId;
  if (idMatch) weights.push(1);
  if ([...pa].some((p) => pb.has(p))) weights.push(name === null ? 0.45 : contact);
  if ([...ea].some((e) => eb.has(e))) weights.push(name === null ? 0.45 : contact);
  if (name !== null) weights.push(name);
  if (!weights.length) return null;
  const fa = a.fellowship.trim().toLowerCase();
  if (fa && fa === b.fellowship.trim().toLowerCase()) weights.push(0.1);
  let score = 1 - weights.reduce((m, w) => m * (1 - w), 1);
  if (!idMatch && pa.size && pb.size && ![...pa].some((p) => pb.has(p))) {
    const sameFull = name === 0.6 && na.core.length >= 2;
    score *= sameFull && fa && fa === b.fellowship.trim().toLowerCase() ? 0.9 : 0.8;
  }
  return score < 0.4 ? null : {score: Math.min(1, score), name: name !== null};
}

export interface ScanCounts {
  almostCertain: number;
  likely: number;
  check: number;
  /** People entered three or more times. */
  groups: number;
}

/** Counts suspected duplicates among [partners], leaving out [dismissed] pair keys. */
export function countDuplicates(partners: ScanPartner[], dismissed: Set<string>): ScanCounts {
  const names = partners.map((p) => parseName(p.fullName));
  const buckets = new Map<string, Set<number>>();
  const put = (k: string, i: number) => {
    if (!buckets.has(k)) buckets.set(k, new Set());
    buckets.get(k)!.add(i);
  };
  partners.forEach((p, i) => {
    if (p.memberId) put(`m:${p.memberId}`, i);
    for (const ph of p.phones.map(phoneKey).filter(Boolean)) put(`p:${ph}`, i);
    for (const em of p.emails.map(emailKey).filter(Boolean)) put(`e:${em}`, i);
    if (names[i].exact) put(`n:${names[i].exact}`, i);
    for (const w of names[i].core) {
      put(`w:${w}`, i);
      if (w.length >= 4) {
        put(`s:${w.slice(0, 3)}`, i);
        put(`t:${w.slice(-3)}`, i);
      }
    }
  });

  const seen = new Set<string>();
  const counts: ScanCounts = {almostCertain: 0, likely: 0, check: 0, groups: 0};
  const parent = new Map<string, string>();
  const find = (k: string): string => {
    let r = parent.get(k) ?? k;
    while (r !== (parent.get(r) ?? r)) r = parent.get(r) ?? r;
    parent.set(k, r);
    return r;
  };
  const linked = new Set<string>();
  for (const set of buckets.values()) {
    const idx = [...set];
    if (idx.length < 2) continue;
    for (let i = 0; i < idx.length; i++) {
      for (let j = i + 1; j < idx.length; j++) {
        const a = partners[idx[i]];
        const b = partners[idx[j]];
        if (a.id === b.id) continue;
        const key = [a.id, b.id].sort().join("|");
        if (seen.has(key) || dismissed.has(key)) continue;
        seen.add(key);
        const r = scorePair(a, b, names[idx[i]], names[idx[j]]);
        if (!r) continue;
        if (r.score >= 0.9) counts.almostCertain++;
        else if (r.score >= 0.6) counts.likely++;
        else counts.check++;
        if (r.name && r.score >= 0.6) {
          parent.set(find(a.id), find(b.id));
          linked.add(a.id).add(b.id);
        }
      }
    }
  }
  const sizes = new Map<string, number>();
  for (const id of linked) sizes.set(find(id), (sizes.get(find(id)) ?? 0) + 1);
  counts.groups = [...sizes.values()].filter((n) => n >= 3).length;
  return counts;
}

async function scanChurch(churchId: string): Promise<ScanCounts> {
  const [partners, dismissals] = await Promise.all([
    db().collection(`churches/${churchId}/partners`).get(),
    db().collection(`churches/${churchId}/duplicate_dismissals`).get(),
  ]);
  const list: ScanPartner[] = partners.docs
    .filter((d) => !String(d.get("mergedInto") ?? "").trim())
    .map((d) => {
      const list = (v: unknown) => (Array.isArray(v) ? v.map(String) : []);
      return {
        id: d.id,
        fullName: String(d.get("fullName") ?? ""),
        memberId: String(d.get("memberId") ?? "").trim().toUpperCase(),
        fellowship: String(d.get("fellowship") ?? ""),
        phones: [String(d.get("phone") ?? ""), ...list(d.get("phones"))].filter(Boolean),
        emails: [String(d.get("email") ?? ""), ...list(d.get("emails"))].filter(Boolean),
      };
    });
  const counts = countDuplicates(list, new Set(dismissals.docs.map((d) => d.id)));
  await db().doc(`churches/${churchId}/health/duplicates`).set({
    ...counts,
    open: counts.almostCertain + counts.likely,
    partners: list.length,
    checkedAt: FieldValue.serverTimestamp(),
  });
  return counts;
}

/** Every night at 02:00 Accra time, after the day's imports. */
export const nightlyDuplicateCheck = onSchedule(
  {schedule: "0 2 * * *", timeZone: "Africa/Accra", region: REGION, timeoutSeconds: 540, memory: "512MiB"},
  async () => {
    const churches = await db().collection("churches").get();
    for (const c of churches.docs) {
      if (c.get("isActive") === false) continue;
      try {
        const counts = await scanChurch(c.id);
        console.log(`duplicate check ${c.id}:`, JSON.stringify(counts));
      } catch (e) {
        console.error(`duplicate check failed for ${c.id}`, e);
      }
    }
  },
);

export {scanChurch as scanChurchForDuplicates};
