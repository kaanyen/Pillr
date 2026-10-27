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
  | "partner.merge";

/** Who may run each kind. Undo follows the same table. */
const ALLOWED: Record<OpKind, Role[]> = {
  "fellowship.merge": ["pastor", "admin", "staff"],
  "fellowship.rename": ["pastor", "admin", "staff"],
  "fellowship.dissolve": ["pastor", "admin", "staff"],
  "fellowship.move": ["pastor", "admin", "staff"],
  "partner.merge": ["pastor", "staff"],
};

/** One document's change: the fields it had, and what this operation wrote. */
export interface Change {
  path: string;
  before: Record<string, unknown>;
  after: Record<string, unknown>;
  /** Fields that did not exist before. Undo deletes them again. */
  absent: string[];
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
    entitySnapshot,
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
        batch.update(db().doc(c.path), {...c.after, updatedAt: FieldValue.serverTimestamp()});
        batch.set(opRef.collection("changes").doc(String(seq).padStart(6, "0")), {seq, ...c});
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
    if (!(kind in ALLOWED) || kind === "partner.merge") {
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
  absorbId?: string;
  /** Entries the person saw moving when they confirmed. */
  expectEntries?: number;
}

/** Contact fields copied onto the kept record when it has none of its own. */
const FILLABLE = ["phone", "email", "memberId"] as const;

export const partnerMerge = onCall(
  {region: REGION, timeoutSeconds: 540, memory: "512MiB"},
  async (request) => {
    const data = (request.data ?? {}) as PartnerMergeRequest;
    const churchId = str(data.churchId);
    const actor = await actorFor(request.auth?.uid, churchId, "partner.merge");
    const keepId = str(data.keepId);
    const absorbId = str(data.absorbId);
    if (!keepId || !absorbId || keepId === absorbId) {
      throw new HttpsError("invalid-argument", "Pick two different partners.");
    }

    return withLock(churchId, `${actor.uid}:${Date.now()}`, async () => {
      const partnersCol = db().collection(`churches/${churchId}/partners`);
      const [keep, absorb] = await db().getAll(partnersCol.doc(keepId), partnersCol.doc(absorbId));
      if (!keep.exists || !absorb.exists) {
        throw new HttpsError("failed-precondition", "One of these partners no longer exists.");
      }
      if (str(keep.get("mergedInto"))) {
        throw new HttpsError("failed-precondition",
          `${str(keep.get("fullName"))} was already merged into another record. Merge into that one.`);
      }
      if (str(absorb.get("mergedInto"))) {
        throw new HttpsError("failed-precondition",
          `${str(absorb.get("fullName"))} was already merged. Refresh the list.`);
      }

      const entries = await db().collection(`churches/${churchId}/entries`)
        .where("partnerId", "==", absorbId).get();
      if (typeof data.expectEntries === "number" && data.expectEntries !== entries.size) {
        throw new HttpsError("failed-precondition",
          `${str(absorb.get("fullName"))} now has ${entries.size} entries, not ${data.expectEntries}. ` +
          "Refresh and check again.", {entries: entries.size});
      }

      const keepSnapshot = {
        fullName: toTitleCase(str(keep.get("fullName"))),
        fellowship: toTitleCase(str(keep.get("fellowship"))),
        memberId: str(keep.get("memberId")),
      };
      const changes: Change[] = entries.docs.map((e) =>
        changeOf(e, {partnerId: keepId, partnerSnapshot: keepSnapshot}));

      // Anything already merged into the absorbed record follows it, so a
      // chain of merges always ends at one live partner.
      const chained = await partnersCol.where("mergedInto", "==", absorbId).get();
      for (const c of chained.docs) changes.push(changeOf(c, {mergedInto: keepId}));

      // The kept record takes contact details it lacks; nothing it has is overwritten.
      const keepAfter: Record<string, unknown> = {};
      const filled: string[] = [];
      for (const f of FILLABLE) {
        if (!str(keep.get(f)) && str(absorb.get(f))) {
          keepAfter[f] = f === "memberId" ? str(absorb.get(f)).toUpperCase() : str(absorb.get(f));
          filled.push(f);
        }
      }
      const aliases = (keep.get("mergedAliases") as unknown[] | undefined) ?? [];
      keepAfter.mergedAliases = [...aliases, {
        partnerId: absorbId,
        fullName: str(absorb.get("fullName")),
        memberId: str(absorb.get("memberId")) || null,
        phone: str(absorb.get("phone")) || null,
        email: str(absorb.get("email")) || null,
      }];
      changes.push(changeOf(keep, keepAfter));

      changes.push(changeOf(absorb, {
        isActive: false,
        mergedInto: keepId,
        mergedBy: actor.uid,
        mergedAt: Timestamp.now(),
      }));

      const summary = {
        keptId: keepId,
        keptName: keepSnapshot.fullName,
        absorbedId: absorbId,
        absorbedName: str(absorb.get("fullName")),
        moved: entries.size,
        filled,
      };
      const opId = await applyOperation(churchId, actor, "partner.merge", summary, changes);
      return {opId, moved: entries.size, filled};
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
