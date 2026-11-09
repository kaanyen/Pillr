/**
 * Notes every backup already in the backup bucket in `backups`, so the
 * Backups page lists the ones made before it existed. A backup counts as
 * finished when its .overall_export_metadata file is there. Skips any
 * backup already noted, so it is safe to run twice.
 *
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node functions/scripts/record-existing-backups.cjs
 *   PILLR_LIVE_PROJECT=thepillr2 node functions/scripts/record-existing-backups.cjs --live
 *
 * Reads the bucket with your application default credentials either way;
 * writes only to the emulator unless --live and PILLR_LIVE_PROJECT are both
 * given, after the owner's yes.
 */
const live = process.argv.includes("--live") && process.env.PILLR_LIVE_PROJECT === "thepillr2";
if (!process.env.FIRESTORE_EMULATOR_HOST && !live) {
  console.error("Refusing to run outside the emulator.");
  process.exit(1);
}
if (live && process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("--live with an emulator host set: pick one.");
  process.exit(1);
}

const admin = require("firebase-admin");
const {Timestamp} = require("firebase-admin/firestore");
const {GoogleAuth} = require("google-auth-library");

admin.initializeApp({projectId: "thepillr2"});
const db = admin.firestore();
const BUCKET = "thepillr2-firestore-backups";

async function list(token, prefix, delimiter) {
  const out = {prefixes: [], items: []};
  let page = "";
  do {
    const url = `https://storage.googleapis.com/storage/v1/b/${BUCKET}/o?prefix=${encodeURIComponent(prefix)}` +
      (delimiter ? "&delimiter=/" : "") + (page ? `&pageToken=${page}` : "");
    const res = await fetch(url, {headers: {"Authorization": `Bearer ${token}`, "x-goog-user-project": "thepillr2"}});
    if (!res.ok) throw new Error(`Listing ${prefix} failed: ${res.status} ${await res.text()}`);
    const d = await res.json();
    out.prefixes.push(...(d.prefixes ?? []));
    out.items.push(...(d.items ?? []));
    page = d.nextPageToken ?? "";
  } while (page);
  return out;
}

/** "2026-11-08T03-00-03-358Z" or "...-2026-11-08T20-05-16Z" → a Date. */
function stampOf(folder) {
  const m = folder.match(/(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})(?:-(\d{3}))?Z/);
  if (!m) return null;
  return new Date(`${m[1]}T${m[2]}:${m[3]}:${m[4]}.${m[5] ?? "000"}Z`);
}

async function main() {
  const auth = new GoogleAuth({scopes: ["https://www.googleapis.com/auth/cloud-platform"]});
  const token = (await (await auth.getClient()).getAccessToken()).token;
  const known = new Set((await db.collection("backups").get()).docs.map((d) => d.get("uri")));
  let added = 0;
  for (const kind of ["scheduled", "manual"]) {
    const {prefixes} = await list(token, `${kind}/`, true);
    for (const p of prefixes) {
      const uri = `gs://${BUCKET}/${p.replace(/\/$/, "")}`;
      if (known.has(uri)) continue;
      const started = stampOf(p);
      const {items} = await list(token, p, false);
      const meta = items.find((i) => i.name.endsWith(".overall_export_metadata"));
      await db.collection("backups").add({
        kind,
        uri,
        operation: null,
        state: meta ? "SUCCESSFUL" : "UNKNOWN",
        startedAt: started ? Timestamp.fromDate(started) : Timestamp.now(),
        completedAt: meta ? Timestamp.fromDate(new Date(meta.updated)) : null,
        documents: null,
        byName: null,
        recordedLater: true,
      });
      added++;
    }
  }
  console.log(`${live ? "LIVE" : "emulator"}: ${added} backups noted`);
}

main().then(() => process.exit(0), (e) => { console.error(e); process.exit(1); });
