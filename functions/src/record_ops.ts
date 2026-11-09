/**
 * Bulk changes to who belongs where, done on the server and recorded so they
 * can be undone.
 *
 * Fellowship merge, rename, dissolve and move, and merging two partner
 * records, used to run in the browser against whatever the screen had loaded.
 * That missed inactive partners, raced with anyone else editing, and left
 * nothing behind to reverse a wrong click. Every operation here:
 *
 *  - reads live data, inactive partners included;
 *  - refuses to start if the screen the person confirmed on is out of date;
 *  - holds a per-church lock so two bulk changes cannot interleave;
 *  - writes each document's before and after values in the same batch as the
 *    change itself, so the record of what happened can never disagree with
 *    what happened, even when a run fails half way;
 *  - writes the activity log itself rather than trusting the client to.
 *
 * Undo replays that record backwards, and only reverts a field that still
 * holds the value this operation wrote. Anything edited since is left alone
 * and listed.
 *
 * Nothing here deletes a document.
 */
import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {toTitleCase} from "./text_case";

const REGION = "us-central1";
const db = () => admin.firestore();

type Role = "pastor" | "admin" | "staff";

type OpKind =
  | "fellowship.merge"
  | "fellowship.rename"
  | "fellowship.dissolve"
  | "fellowship.move"
  | "partner.merge"
  | "partner.unmerge";

/** Who may run each kind. Undo follows the same table. */
const ALLOWED: Record<OpKind, Role[]> = {
  "fellowship.merge": ["pastor", "admin", "staff"],
  "fellowship.rename": ["pastor", "admin", "staff"],
  "fellowship.dissolve": ["pastor", "admin", "staff"],
  "fellowship.move": ["pastor", "admin", "staff"],
  "partner.merge": ["pastor", "staff"],
  "partner.unmerge": ["pastor", "staff"],
};

/** One document's change: the fields it had, and what this operation wrote. */
export interface Change {
  path: string;
  before: Record<string, unknown>;
  after: Record<string, unknown>;
  /** Fields that did not exist before. Undo deletes them again. */
  absent: string[];
  /** The operation made this document. Undo removes it again, if untouched. */
  created?: boolean;
}

interface Actor {
  uid: string;
  role: Role;
  snapshot: {fullName: string; role: string; email: string | null};
}

/** A lock older than this belongs to a run that died; the callable timeout is shorter. */
const LOCK_TTL_MS = 10 * 60 * 1000;

/** Two writes per change (the document and its record) plus the op counter. */
const CHANGES_PER_BATCH = 200;

const CATALOG_FIELD = "settings.fellowshipNames";

// ------------------------------------------------------------------ helpers

const nameKey = (s: unknown) => String(s ?? "").trim().toLowerCase();

/** Same as Dart `mergeKnownFellowships`: distinct, title-cased, A–Z. */
export function mergeKnownFellowships(catalog: unknown[], fromPartners: unknown[]): string[] {
  const byKey = new Map<string, string>();
  const add = (raw: unknown) => {
    const t = String(raw ?? "").trim();
    if (!t) return;
    const label = toTitleCase(t);
    if (!byKey.has(label.toLowerCase())) byKey.set(label.toLowerCase(), label);
  };
  catalog.forEach(add);
  fromPartners.forEach(add);
  return [...byKey.values()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
}

/** Deep equality that treats missing and null alike and compares timestamps by value. */
export function sameValue(a: unknown, b: unknown): boolean {
  if (a === undefined) a = null;
  if (b === undefined) b = null;
  if (a === b) return true;
  if (a instanceof Timestamp && b instanceof Timestamp) return a.isEqual(b);
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((v, i) => sameValue(v, b[i]));
  }
  if (a && b && typeof a === "object" && typeof b === "object") {
    const ma = a as Record<string, unknown>;
    const mb = b as Record<string, unknown>;
    const ka = Object.keys(ma).filter((k) => ma[k] != null);
    const kb = Object.keys(mb).filter((k) => mb[k] != null);
    if (ka.length !== kb.length) return false;
    return ka.every((k) => sameValue(ma[k], mb[k]));
  }
  return false;
}

const isDelete = (v: unknown) => v instanceof FieldValue && v.isEqual(FieldValue.delete());

/**
 * The change as it is stored. A field this operation deletes is recorded as
 * null — a delete marker cannot be saved — and undo reads null as "was not
 * there".
 */
function recordable(c: Change): Change {
  const after: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(c.after)) after[k] = isDelete(v) ? null : v;
  return {...c, after};
}

/** Builds a change from a snapshot, recording which fields were missing. */
function changeOf(
  snap: FirebaseFirestore.DocumentSnapshot,
  after: Record<string, unknown>,
): Change {
  const before: Record<string, unknown> = {};
  const absent: string[] = [];
  for (const field of Object.keys(after)) {
    const v = snap.get(field);
    if (v === undefined) {
      absent.push(field);
    } else {
      before[field] = v;
    }
  }
  return {path: snap.ref.path, before, after, absent};
}

function str(v: unknown): string {
  return String(v ?? "").trim();
}

async function actorFor(uid: string | undefined, churchId: string, kind: OpKind): Promise<Actor> {
  if (!uid) throw new HttpsError("unauthenticated", "You must be signed in.");
  if (!churchId) throw new HttpsError("invalid-argument", "churchId is required.");
  const idx = (await db().doc(`user_church_index/${uid}`).get()).data();
  if (!idx || idx.churchId !== churchId) {
    throw new HttpsError("permission-denied", "Wrong church.");
  }
  const role = idx.role as Role;
  if (!ALLOWED[kind].includes(role)) {
    throw new HttpsError("permission-denied", "Your role cannot make this change.");
  }
  const profile = (await db().doc(`churches/${churchId}/users/${uid}`).get()).data() ?? {};
  return {
    uid,
    role,
    snapshot: {
      fullName: str(profile.fullName) || str(profile.email) || uid,
      role,
      email: str(profile.email) || null,
    },
  };
}

async function withLock<T>(churchId: string, holder: string, body: () => Promise<T>): Promise<T> {
  const ref = db().doc(`churches/${churchId}/op_locks/records`);
  await db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const at = s.exists ? (s.get("acquiredAt") as Timestamp | undefined) : undefined;
    if (at && Date.now() - at.toMillis() < LOCK_TTL_MS) {
      throw new HttpsError(
        "aborted",
        "Another change to partners or fellowships is running. Try again in a moment.",
      );
    }
    tx.set(ref, {holder, acquiredAt: Timestamp.now()});
  });
  try {
    return await body();
  } finally {
    await db().runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (s.exists && s.get("holder") === holder) tx.delete(ref);
    }).catch((e) => console.warn("record_ops: could not release lock", e));
  }
}

/**
 * The activity log is read by admins, who never see what anyone gave: no
 * amount or total goes into it, at any depth.
 */
export function withoutFigures(v: Record<string, unknown>): Record<string, unknown> {
  const isFigure = (k: string) => /amount|total|cedis|pesewa/i.test(k);
  const clean = (x: unknown): unknown =>
    Array.isArray(x) ? x.map(clean) :
      x && typeof x === "object" && !(x instanceof Date) && x.constructor === Object ?
        withoutFigures(x as Record<string, unknown>) : x;
  const out: Record<string, unknown> = {};
  for (const [k, x] of Object.entries(v)) if (!isFigure(k)) out[k] = clean(x);
  return out;
}

async function logActivity(
  churchId: string,
  actor: Actor,
  action: string,
  entityType: string,
  entityId: string | null,
  entitySnapshot: Record<string, unknown>,
) {
  await db().collection(`churches/${churchId}/activity_logs`).add({
    churchId,
    actorUid: actor.uid,
    actorSnapshot: actor.snapshot,
    action,
    entityType,
    entityId,
    entitySnapshot: withoutFigures(entitySnapshot),
    metadata: {source: "server"},
    createdAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Applies [changes] and records them under a new operation document.
 *
 * Each batch carries the documents it changes and their change records, so a
 * failure part way leaves an operation that describes exactly what landed —
 * and that is what undo reverses.
 */
async function applyOperation(
  churchId: string,
  actor: Actor,
  kind: OpKind,
  summary: Record<string, unknown>,
  changes: Change[],
): Promise<string> {
  const opRef = db().collection(`churches/${churchId}/operations`).doc();
  await opRef.set({
    kind,
    status: "applying",
    summary,
    planned: changes.length,
    applied: 0,
    actorUid: actor.uid,
    actorSnapshot: actor.snapshot,
    createdAt: FieldValue.serverTimestamp(),
  });

  let seq = 0;
  try {
    for (let i = 0; i < changes.length; i += CHANGES_PER_BATCH) {
      const chunk = changes.slice(i, i + CHANGES_PER_BATCH);
      const batch = db().batch();
      for (const c of chunk) {
        if (c.created) {
          batch.set(db().doc(c.path), {...c.after, createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp()});
        } else {
          batch.update(db().doc(c.path), {...c.after, updatedAt: FieldValue.serverTimestamp()});
        }
        batch.set(opRef.collection("changes").doc(String(seq).padStart(6, "0")), {seq, ...recordable(c)});
        seq++;
      }
      batch.update(opRef, {applied: FieldValue.increment(chunk.length)});
      await batch.commit();
    }
  } catch (e) {
    await opRef.update({
      status: "failed",
      error: String((e as Error)?.message ?? e),
      failedAt: FieldValue.serverTimestamp(),
    });
    await logActivity(churchId, actor, `${kind}.failed`, "operation", opRef.id, {
      ...summary,
      opId: opRef.id,
      applied: seq,
      planned: changes.length,
    });
    throw new HttpsError(
      "internal",
      `The change stopped after ${seq} of ${changes.length} records. ` +
        "Nothing was lost: open Tools → Recent changes to undo the part that was saved, " +
        "or run it again to finish.",
      {opId: opRef.id, applied: seq},
    );
  }

  await opRef.update({status: "applied", appliedAt: FieldValue.serverTimestamp()});
  await logActivity(churchId, actor, kind, kind.startsWith("partner") ? "partner" : "fellowship",
    opRef.id, {...summary, opId: opRef.id, changed: changes.length});
  return opRef.id;
}

// -------------------------------------------------------------- fellowships

interface PartnerRow {
  snap: FirebaseFirestore.DocumentSnapshot;
  fellowship: string;
  isActive: boolean;
}

async function allPartners(churchId: string): Promise<PartnerRow[]> {
  const snap = await db().collection(`churches/${churchId}/partners`).get();
  return snap.docs.map((d) => ({
    snap: d,
    fellowship: str(d.get("fellowship")),
    isActive: d.get("isActive") !== false,
  }));
}

function fellowshipPatch(row: PartnerRow, target: string): Change {
  return changeOf(row.snap, {fellowship: target, fellowshipLower: target.toLowerCase()});
}

/** The catalog after a change, if it differs from what is stored. */
function catalogChange(
  churchSnap: FirebaseFirestore.DocumentSnapshot,
  nextCatalog: string[],
): Change | null {
  const current = churchSnap.get(CATALOG_FIELD);
  if (Array.isArray(current) && sameValue(current, nextCatalog)) return null;
  return changeOf(churchSnap, {[CATALOG_FIELD]: nextCatalog});
}

interface FellowshipRequest {
  churchId?: string;
  kind?: string;
  fromNames?: unknown[];
  partnerIds?: unknown[];
  toName?: string;
  /** Active partners the person saw moving when they confirmed. */
  expectActive?: number;
}

export const fellowshipChange = onCall(
  {region: REGION, timeoutSeconds: 540, memory: "512MiB"},
  async (request) => {
    const data = (request.data ?? {}) as FellowshipRequest;
    const churchId = str(data.churchId);
    const kind = `fellowship.${str(data.kind)}` as OpKind;
    if (!(kind in ALLOWED) || kind.startsWith("partner.")) {
      throw new HttpsError("invalid-argument", "Unknown fellowship change.");
    }
    const actor = await actorFor(request.auth?.uid, churchId, kind);
    const target = toTitleCase(str(data.toName));
    if (!target) throw new HttpsError("invalid-argument", "Name the fellowship to move into.");

    return withLock(churchId, `${actor.uid}:${Date.now()}`, async () => {
      const churchSnap = await db().doc(`churches/${churchId}`).get();
      const catalog = (churchSnap.get(CATALOG_FIELD) as unknown[] | undefined) ?? [];
      const partners = await allPartners(churchId);
      const known = mergeKnownFellowships(catalog,
        partners.filter((p) => p.isActive).map((p) => p.fellowship));

      let moving: PartnerRow[];
      let nextCatalog: string[];
      let skipped = 0;
      const summary: Record<string, unknown> = {to: target};

      if (kind === "fellowship.move") {
        const ids = [...new Set((data.partnerIds ?? []).map(str).filter(Boolean))];
        if (ids.length === 0) throw new HttpsError("invalid-argument", "Pick someone to move.");
        const byId = new Map(partners.map((p) => [p.snap.id, p]));
        const missing = ids.filter((id) => !byId.has(id));
        if (missing.length > 0) {
          throw new HttpsError("failed-precondition",
            `${missing.length} of the partners you picked no longer exist. Refresh and try again.`);
        }
        const picked = ids.map((id) => byId.get(id)!);
        moving = picked.filter((p) => nameKey(p.fellowship) !== target.toLowerCase());
        skipped = picked.length - moving.length;
        const ids2 = new Set(moving.map((p) => p.snap.id));
        nextCatalog = mergeKnownFellowships([...catalog, target], partners
          .filter((p) => p.isActive)
          .map((p) => (ids2.has(p.snap.id) ? target : p.fellowship)));
        summary.from = [...new Set(picked.map((p) => p.fellowship || "No fellowship"))].join(", ");
        summary.partners = picked.slice(0, 50).map((p) => str(p.snap.get("fullName")));
      } else {
        const fromNames = (data.fromNames ?? []).map(str).filter(Boolean);
        const fromKeys = new Set(fromNames.map(nameKey));
        fromKeys.delete(target.toLowerCase());
        if (fromKeys.size === 0) {
          throw new HttpsError("invalid-argument", "Pick a different fellowship to move into.");
        }
        if (kind === "fellowship.dissolve" &&
            !known.some((n) => nameKey(n) === target.toLowerCase())) {
          throw new HttpsError("failed-precondition",
            `${target} is not a fellowship any more. Refresh and pick another.`);
        }
        moving = partners.filter((p) => fromKeys.has(nameKey(p.fellowship)));
        const remaining = partners
          .filter((p) => p.isActive && !fromKeys.has(nameKey(p.fellowship)))
          .map((p) => p.fellowship);
        if (moving.some((p) => p.isActive)) remaining.push(target);
        nextCatalog = mergeKnownFellowships(
          [...catalog.filter((n) => !fromKeys.has(nameKey(n))), target], remaining);
        summary.from = fromNames.join(", ");
      }

      const activeMoving = moving.filter((p) => p.isActive).length;
      if (typeof data.expectActive === "number" && data.expectActive !== activeMoving) {
        throw new HttpsError("failed-precondition",
          `The list changed since you opened it: ${activeMoving} active ` +
          `${activeMoving === 1 ? "partner" : "partners"} would move, not ${data.expectActive}. ` +
          "Refresh and check again.", {activeMoving});
      }

      const changes = moving.map((p) => fellowshipPatch(p, target));
      const cat = catalogChange(churchSnap, nextCatalog);
      if (cat) changes.push(cat);

      summary.activeMoved = activeMoving;
      summary.inactiveMoved = moving.length - activeMoving;
      if (changes.length === 0) {
        return {opId: null, moved: 0, inactiveMoved: 0, skipped};
      }
      const opId = await applyOperation(churchId, actor, kind, summary, changes);
      return {opId, moved: activeMoving, inactiveMoved: moving.length - activeMoving, skipped};
    });
  },
);

// ---------------------------------------------------------------- partners

interface PartnerMergeRequest {
  churchId?: string;
  keepId?: string;
  /** One record, or several when one person was entered many times. */
  absorbId?: string;
  absorbIds?: unknown[];
  /** Entries the person saw moving when they confirmed. */
  expectEntries?: number;
}

const upper = (v: unknown) => str(v).toUpperCase();

/** Phones compared by their last nine digits, as the duplicate scan does. */
const phoneKey = (v: unknown) => {
  const d = str(v).replace(/\D/g, "");
  return d.length < 9 ? d : d.slice(-9);
};
const emailKey = (v: unknown) => str(v).toLowerCase();

/** Every phone or email a record holds: its list, plus the single field. */
function contactsOf(m: {get(f: string): unknown} | Record<string, unknown>, kind: "phone" | "email"): string[] {
  const get = (f: string) => ("get" in m && typeof m.get === "function" ? (m as {get(f: string): unknown}).get(f) :
    (m as Record<string, unknown>)[f]);
  const list = (get(kind === "phone" ? "phones" : "emails") as unknown[] | undefined) ?? [];
  return [str(get(kind)), ...list.map(str)].filter(Boolean);
}

/** Distinct values, first spelling kept, in the order given. */
function distinct(values: string[], key: (v: string) => string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const v of values) {
    const k = key(v);
    if (!k || seen.has(k)) continue;
    seen.add(k);
    out.push(v);
  }
  return out;
}

/** Letters at the front of a member ID: ACC from ACC682216. */
function memberIdPrefix(memberId: string): string {
  return /^[A-Z]+/.exec(memberId)?.[0] ?? "";
}

/** Same rule as Dart `churchInitialsFromName`, for a church whose IDs carry no prefix yet. */
function churchInitials(name: string): string {
  const skip = new Set(["the", "a", "an", "of", "and", "or", "to", "in", "at"]);
  const words = name.replace(/[^a-zA-Z\s]/g, " ").split(/\s+/)
    .filter((w) => w && !skip.has(w.toLowerCase()));
  if (words.length === 0) return "CH";
  let s = "";
  for (const w of words) {
    if (s.length >= 4) break;
    s += w[0].toUpperCase();
  }
  if (s.length === 1 && words[0].length > 1) s = words[0].slice(0, 2).toUpperCase();
  return s;
}

/**
 * A member ID nobody has held: not a current ID, and not one retired into a
 * merged person's former IDs — an old ID is never handed to someone new.
 */
async function freshMemberId(churchId: string, prefix: string): Promise<string> {
  const col = db().collection(`churches/${churchId}/partners`);
  for (let attempt = 0; attempt < 60; attempt++) {
    const id = `${prefix}${100000 + Math.floor(Math.random() * 900000)}`;
    const [now, former] = await Promise.all([
      col.where("memberId", "==", id).limit(1).get(),
      col.where("formerMemberIds", "array-contains", id).limit(1).get(),
    ]);
    if (now.empty && former.empty) return id;
  }
  throw new HttpsError("internal", "Could not find a free member ID. Try again.");
}

/** One record inside a merged person, as kept in `mergedAliases`. */
interface MergedAlias {
  partnerId: string;
  fullName: string;
  fellowship: string;
  memberId: string | null;
  phone: string | null;
  email: string | null;
  phones: string[];
  emails: string[];
  /** The record that was kept: its own details before the merge changed them. */
  self?: boolean;
}

function aliasOf(snap: FirebaseFirestore.DocumentSnapshot, memberId: string, self = false): MergedAlias {
  return {
    partnerId: snap.id,
    fullName: str(snap.get("fullName")),
    fellowship: str(snap.get("fellowship")),
    memberId: memberId || null,
    phone: str(snap.get("phone")) || null,
    email: str(snap.get("email")) || null,
    phones: distinct(contactsOf(snap, "phone"), phoneKey),
    emails: distinct(contactsOf(snap, "email"), emailKey),
    ...(self ? {self: true} : {}),
  };
}

/**
 * Merges one or more duplicate records into the record kept.
 *
 * The person comes out with a new member ID. Every ID they were known by —
 * the kept record's and each duplicate's — is kept on them as
 * `formerMemberIds`, and every phone number and email from every record is
 * kept in `phones` and `emails`. The duplicates are closed, not deleted, and
 * keep their own IDs. The kept record's own details and giving are recorded
 * too, so any one of the records — the kept one included — can be taken out
 * again by its ID ([partnerUnmerge]), or the whole merge undone.
 */
export const partnerMerge = onCall(
  {region: REGION, timeoutSeconds: 540, memory: "512MiB"},
  async (request) => {
    const data = (request.data ?? {}) as PartnerMergeRequest;
    const churchId = str(data.churchId);
    const actor = await actorFor(request.auth?.uid, churchId, "partner.merge");
    const keepId = str(data.keepId);
    const absorbIds = [...new Set([
      ...(data.absorbIds ?? []).map(str),
      str(data.absorbId),
    ].filter(Boolean))];
    if (!keepId || absorbIds.length === 0 || absorbIds.includes(keepId)) {
      throw new HttpsError("invalid-argument", "Pick the record to keep and at least one other.");
    }
    if (absorbIds.length > 50) {
      throw new HttpsError("invalid-argument", "Merge at most 50 records at once.");
    }

    return withLock(churchId, `${actor.uid}:${Date.now()}`, async () => {
      const partnersCol = db().collection(`churches/${churchId}/partners`);
      const snaps = await db().getAll(partnersCol.doc(keepId), ...absorbIds.map((id) => partnersCol.doc(id)));
      const [keep, ...absorbs] = snaps;
      if (snaps.some((s) => !s.exists)) {
        throw new HttpsError("failed-precondition", "One of these partners no longer exists. Refresh the list.");
      }
      if (str(keep.get("mergedInto"))) {
        throw new HttpsError("failed-precondition",
          `${str(keep.get("fullName"))} was already merged into another record. Merge into that one.`);
      }
      const already = absorbs.find((a) => str(a.get("mergedInto")));
      if (already) {
        throw new HttpsError("failed-precondition",
          `${str(already.get("fullName"))} was already merged. Refresh the list.`);
      }

      const entriesCol = db().collection(`churches/${churchId}/entries`);
      const entrySets = await Promise.all(absorbs.map((a) => entriesCol.where("partnerId", "==", a.id).get()));
      const entryCount = entrySets.reduce((n, s) => n + s.size, 0);
      if (typeof data.expectEntries === "number" && data.expectEntries !== entryCount) {
        throw new HttpsError("failed-precondition",
          `These records now have ${entryCount} entries, not ${data.expectEntries}. Refresh and check again.`,
          {entries: entryCount});
      }

      const oldKeepId = upper(keep.get("memberId"));
      const churchName = str((await db().doc(`churches/${churchId}`).get()).get("name"));
      const prefix = memberIdPrefix(oldKeepId) ||
        absorbs.map((a) => memberIdPrefix(upper(a.get("memberId")))).find(Boolean) ||
        churchInitials(churchName);
      const newMemberId = await freshMemberId(churchId, prefix);

      const keepSnapshot = {
        fullName: toTitleCase(str(keep.get("fullName"))),
        fellowship: toTitleCase(str(keep.get("fellowship"))),
        memberId: newMemberId,
      };

      // The kept record's own giving: its snapshot follows it to the new ID,
      // and each is marked as the kept record's, so the kept record can be
      // taken out again too.
      const keepEntries = await entriesCol.where("partnerId", "==", keepId).get();
      const changes: Change[] = keepEntries.docs.map((e) => changeOf(e, {
        partnerSnapshot: {...(e.get("partnerSnapshot") ?? {}), memberId: newMemberId},
        mergedFromPartnerId: str(e.get("mergedFromPartnerId")) || keepId,
      }));

      // Each moved entry remembers the record it first came from. A chain of
      // merges keeps the original, so any record can be taken out again.
      absorbs.forEach((a, i) => {
        for (const e of entrySets[i].docs) {
          changes.push(changeOf(e, {
            partnerId: keepId,
            partnerSnapshot: keepSnapshot,
            mergedFromPartnerId: str(e.get("mergedFromPartnerId")) || a.id,
          }));
        }
      });

      // Anything already merged into a duplicate follows it.
      for (const a of absorbs) {
        const chained = await partnersCol.where("mergedInto", "==", a.id).get();
        for (const c of chained.docs) changes.push(changeOf(c, {mergedInto: keepId}));
      }

      // Every ID this person has been known by.
      const former = new Set<string>(((keep.get("formerMemberIds") as unknown[] | undefined) ?? []).map(upper));
      if (oldKeepId) former.add(oldKeepId);
      for (const a of absorbs) {
        if (upper(a.get("memberId"))) former.add(upper(a.get("memberId")));
        for (const f of (a.get("formerMemberIds") as unknown[] | undefined) ?? []) former.add(upper(f));
      }
      former.delete(newMemberId);

      // Every phone and email from every record. The kept record's own stay
      // first, so its main contact does not change.
      const phones = distinct([...contactsOf(keep, "phone"), ...absorbs.flatMap((a) => contactsOf(a, "phone"))], phoneKey);
      const emails = distinct([...contactsOf(keep, "email"), ...absorbs.flatMap((a) => contactsOf(a, "email"))], emailKey);

      const aliases = ((keep.get("mergedAliases") as MergedAlias[] | undefined) ?? []).slice();
      if (!aliases.some((a) => a.self)) aliases.unshift(aliasOf(keep, oldKeepId, true));
      for (const a of absorbs) {
        aliases.push(aliasOf(a, upper(a.get("memberId"))));
        // A duplicate that was itself a merged person brings its records along.
        for (const inner of (a.get("mergedAliases") as MergedAlias[] | undefined) ?? []) {
          if (!inner.self) aliases.push(inner);
        }
      }

      const keepAfter: Record<string, unknown> = {
        memberId: newMemberId,
        formerMemberIds: [...former].filter(Boolean).sort(),
        phones,
        emails,
        mergedAliases: aliases,
      };
      const filled: string[] = [];
      if (!str(keep.get("phone")) && phones.length) {
        keepAfter.phone = phones[0];
        filled.push("phone");
      }
      if (!str(keep.get("email")) && emails.length) {
        keepAfter.email = emails[0];
        filled.push("email");
      }
      changes.push(changeOf(keep, keepAfter));

      const at = Timestamp.now();
      for (const a of absorbs) {
        changes.push(changeOf(a, {isActive: false, mergedInto: keepId, mergedBy: actor.uid, mergedAt: at}));
      }

      const absorbedNames = absorbs.map((a) => str(a.get("fullName")));
      const summary = {
        keptId: keepId,
        keptName: keepSnapshot.fullName,
        absorbedId: absorbs[0].id,
        absorbedIds: absorbs.map((a) => a.id),
        absorbedName: absorbedNames.length === 1 ? absorbedNames[0] : `${absorbedNames.length} records`,
        absorbedMemberIds: absorbs.map((a) => upper(a.get("memberId"))),
        oldMemberId: oldKeepId,
        newMemberId,
        moved: entryCount,
        phones: phones.length,
        emails: emails.length,
        filled,
      };
      const opId = await applyOperation(churchId, actor, "partner.merge", summary, changes);
      return {
        opId, moved: entryCount, filled, newMemberId,
        formerMemberIds: keepAfter.formerMemberIds, phones, emails,
      };
    });
  },
);

/**
 * Takes one person back out of a merge, found by the member ID they had.
 *
 * Their giving — the entries that came from their record — go back to them,
 * their record opens again with its own ID, phones and emails, and the merged
 * person loses only what came from them. The rest stays merged.
 *
 * Works for any record in the merge, including the one that was kept: that
 * record now belongs to the merged person, so a new record is made for it
 * from the details saved at merge time. Recorded like any other change, so it
 * can itself be undone.
 */
export const partnerUnmerge = onCall(
  {region: REGION, timeoutSeconds: 540, memory: "512MiB"},
  async (request) => {
    const churchId = str(request.data?.churchId);
    const actor = await actorFor(request.auth?.uid, churchId, "partner.unmerge");
    const memberId = upper(request.data?.memberId);
    if (!memberId) throw new HttpsError("invalid-argument", "Give the member ID to take out.");

    return withLock(churchId, `${actor.uid}:${Date.now()}`, async () => {
      const partnersCol = db().collection(`churches/${churchId}/partners`);
      const holders = await partnersCol.where("formerMemberIds", "array-contains", memberId).get();
      let survivor = holders.docs.find((d) => !str(d.get("mergedInto")));
      if (!survivor) {
        // A merge from before old IDs were kept: the closed record still holds
        // its ID and points at the person it went into.
        const closed = (await partnersCol.where("memberId", "==", memberId).get()).docs
          .find((d) => str(d.get("mergedInto")));
        if (closed) {
          const into = await partnersCol.doc(str(closed.get("mergedInto"))).get();
          if (into.exists) survivor = into as FirebaseFirestore.QueryDocumentSnapshot;
        }
      }
      if (!survivor) {
        const asCurrent = await partnersCol.where("memberId", "==", memberId).limit(1).get();
        throw new HttpsError("failed-precondition", asCurrent.empty ?
          `No record has member ID ${memberId}.` :
          `${memberId} is not part of a merge.`);
      }
      const aliases = (survivor.get("mergedAliases") as MergedAlias[] | undefined) ?? [];
      let alias = aliases.find((a) => upper(a.memberId) === memberId);
      if (!alias) {
        const closed = (await partnersCol.where("memberId", "==", memberId).get()).docs
          .find((d) => str(d.get("mergedInto")) === survivor!.id);
        if (closed) alias = aliasOf(closed, memberId);
      }
      if (!alias) {
        throw new HttpsError("failed-precondition",
          `${memberId} is an old ID of ${str(survivor.get("fullName"))} with no record of its own to take out.`);
      }

      const changes: Change[] = [];
      let targetId: string;
      if (alias.self) {
        // The kept record became the merged person, so its own details go
        // into a new record that takes its old ID back.
        const fresh = partnersCol.doc();
        targetId = fresh.id;
        const fullName = toTitleCase(alias.fullName);
        const fellowship = toTitleCase(alias.fellowship);
        changes.push({
          path: fresh.path,
          created: true,
          before: {},
          absent: [],
          after: {
            id: fresh.id, churchId, memberId, fullName, fellowship,
            fullNameLower: fullName.toLowerCase(), fellowshipLower: fellowship.toLowerCase(),
            phone: alias.phone, email: alias.email,
            phones: alias.phones ?? [], emails: alias.emails ?? [],
            isActive: true,
            createdBy: actor.uid, splitFrom: survivor.id,
          },
        });
      } else {
        const closed = await partnersCol.doc(alias.partnerId).get();
        if (!closed.exists) throw new HttpsError("failed-precondition", `The record for ${memberId} is missing.`);
        targetId = closed.id;
        changes.push(changeOf(closed, {
          isActive: true,
          mergedInto: FieldValue.delete(),
          mergedBy: FieldValue.delete(),
          mergedAt: FieldValue.delete(),
        }));
      }

      const snapshot = {fullName: toTitleCase(alias.fullName), fellowship: toTitleCase(alias.fellowship), memberId};
      const entries = await db().collection(`churches/${churchId}/entries`)
        .where("mergedFromPartnerId", "==", alias.partnerId).get();
      for (const e of entries.docs) {
        if (str(e.get("partnerId")) !== survivor.id) continue;
        changes.push(changeOf(e, {
          partnerId: targetId,
          partnerSnapshot: snapshot,
          mergedFromPartnerId: FieldValue.delete(),
        }));
      }
      const moved = changes.filter((c) => c.path.includes("/entries/")).length;

      // The merged person keeps every contact that some other record also
      // had; only what came from this one alone goes with it.
      const rest = aliases.filter((a) => a.partnerId !== alias!.partnerId);
      const keepsPhone = new Set(rest.flatMap((a) => [a.phone ?? "", ...(a.phones ?? [])]).map(phoneKey).filter(Boolean));
      const keepsEmail = new Set(rest.flatMap((a) => [a.email ?? "", ...(a.emails ?? [])]).map(emailKey).filter(Boolean));
      const leaving = (v: string, own: string[], keeps: Set<string>, key: (x: string) => string) =>
        own.map(key).includes(key(v)) && !keeps.has(key(v));
      const ownPhones = [alias.phone ?? "", ...(alias.phones ?? [])].filter(Boolean);
      const ownEmails = [alias.email ?? "", ...(alias.emails ?? [])].filter(Boolean);
      const phones = ((survivor.get("phones") as string[] | undefined) ?? [])
        .filter((p) => !leaving(p, ownPhones, keepsPhone, phoneKey));
      const emails = ((survivor.get("emails") as string[] | undefined) ?? [])
        .filter((e) => !leaving(e, ownEmails, keepsEmail, emailKey));
      const survivorAfter: Record<string, unknown> = {
        formerMemberIds: ((survivor.get("formerMemberIds") as unknown[] | undefined) ?? []).map(upper)
          .filter((f) => f !== memberId),
        mergedAliases: rest,
        phones,
        emails,
      };
      const mainPhone = str(survivor.get("phone"));
      if (mainPhone && leaving(mainPhone, ownPhones, keepsPhone, phoneKey)) survivorAfter.phone = phones[0] ?? null;
      const mainEmail = str(survivor.get("email"));
      if (mainEmail && leaving(mainEmail, ownEmails, keepsEmail, emailKey)) survivorAfter.email = emails[0] ?? null;
      changes.push(changeOf(survivor, survivorAfter));

      const summary = {
        keptId: survivor.id,
        keptName: str(survivor.get("fullName")),
        separatedId: targetId,
        separatedName: snapshot.fullName,
        separatedMemberId: memberId,
        wasKeptRecord: Boolean(alias.self),
        moved,
      };
      const opId = await applyOperation(churchId, actor, "partner.unmerge", summary, changes);
      return {opId, moved, partnerId: targetId};
    });
  },
);

// -------------------------------------------------------------------- undo

export const undoOperation = onCall(
  {region: REGION, timeoutSeconds: 540, memory: "512MiB"},
  async (request) => {
    const churchId = str(request.data?.churchId);
    const opId = str(request.data?.opId);
    if (!opId) throw new HttpsError("invalid-argument", "opId is required.");
    const opRef = db().doc(`churches/${churchId}/operations/${opId}`);
    const op = await opRef.get();
    if (!op.exists) throw new HttpsError("not-found", "That change is not on record.");
    const kind = op.get("kind") as OpKind;
    if (!(kind in ALLOWED)) throw new HttpsError("failed-precondition", "That change cannot be undone.");
    const actor = await actorFor(request.auth?.uid, churchId, kind);

    return withLock(churchId, `${actor.uid}:${Date.now()}`, async () => {
      const status = (await opRef.get()).get("status");
      if (status !== "applied" && status !== "failed") {
        throw new HttpsError("failed-precondition",
          status === "undone" ? "That change was already undone." : "That change is still running.");
      }
      await opRef.update({status: "undoing"});

      const recs = await opRef.collection("changes").orderBy("seq", "desc").get();
      const conflicts: string[] = [];
      let reverted = 0;
      try {
        for (let i = 0; i < recs.size; i += 400) {
          const chunk = recs.docs.slice(i, i + 400);
          const snaps = await db().getAll(...chunk.map((r) => db().doc(r.get("path"))));
          const batch = db().batch();
          let writes = 0;
          chunk.forEach((r, j) => {
            const c = r.data() as Change;
            const now = snaps[j];
            if (c.created) {
              // A record this operation made: remove it again, unless someone
              // has changed it since, in which case it stays and is listed.
              if (!now.exists) {
                reverted++;
              } else if (Object.keys(c.after).every((f) =>
                ["totalApprovedAmount", "totalApprovedPesewas", "entryCount"].includes(f) ||
                sameValue(now.get(f), c.after[f]))) {
                batch.delete(now.ref);
                writes++;
              } else {
                conflicts.push(c.path);
              }
              return;
            }
            const patch = now.exists ? revertPatch(c, now) : null;
            if (patch === null) {
              conflicts.push(c.path);
              return;
            }
            if (Object.keys(patch).length === 0) {
              reverted++;
              return;
            }
            batch.update(now.ref, {...patch, updatedAt: FieldValue.serverTimestamp()});
            writes++;
          });
          if (writes > 0) await batch.commit();
          reverted += writes;
        }
      } catch (e) {
        await opRef.update({status: "failed", error: `Undo stopped: ${String((e as Error)?.message ?? e)}`});
        throw new HttpsError("internal",
          `Undo stopped after ${reverted} records. Run undo again to finish.`);
      }

      await opRef.update({
        status: "undone",
        undoneAt: FieldValue.serverTimestamp(),
        undoneBy: actor.uid,
        reverted,
        undoConflicts: conflicts.slice(0, 100),
        undoConflictCount: conflicts.length,
      });
      await logActivity(churchId, actor, "operation.undo", "operation", opId, {
        kind,
        ...(op.get("summary") ?? {}),
        reverted,
        conflicts: conflicts.length,
      });
      return {reverted, conflicts: conflicts.length};
    });
  },
);

/**
 * What to write to put [now] back as it was, or null if someone has changed it
 * since and it should be left alone. An empty patch means it is already back —
 * a second run of an undo that stopped part way.
 *
 * The fellowship list is the exception: it is shared by every partner, so a
 * later edit is normal. Undo puts back the names this operation removed and
 * keeps everything else.
 */
export function revertPatch(
  c: Change,
  now: FirebaseFirestore.DocumentSnapshot,
): Record<string, unknown> | null {
  const fields = Object.keys(c.after);
  const restored = fields.every((f) =>
    (c.absent ?? []).includes(f) ? now.get(f) === undefined : sameValue(now.get(f), c.before[f]));
  if (restored) return {};
  const untouched = fields.every((f) => sameValue(now.get(f), c.after[f]));
  if (untouched) {
    const patch: Record<string, unknown> = {};
    for (const f of fields) {
      patch[f] = (c.absent ?? []).includes(f) ? FieldValue.delete() : c.before[f];
    }
    return patch;
  }
  if (fields.length === 1 && fields[0] === CATALOG_FIELD) {
    const before = (c.before[CATALOG_FIELD] as unknown[] | undefined) ?? [];
    const after = new Set(((c.after[CATALOG_FIELD] as unknown[]) ?? []).map(nameKey));
    const removed = before.filter((n) => !after.has(nameKey(n)));
    const current = (now.get(CATALOG_FIELD) as unknown[] | undefined) ?? [];
    return {[CATALOG_FIELD]: mergeKnownFellowships(current, removed)};
  }
  return null;
}
