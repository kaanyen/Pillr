import * as admin from "firebase-admin";

/**
 * Pure: the name each arm's giving is reported under. A sub-arm (one with a
 * `parentArmId` naming an arm that exists) reports under its main arm; every
 * other arm under its own name. Reports and emails show main arms only.
 */
export function mainArmNameById(
  arms: {id: string; name: string; parentArmId?: string | null}[],
): Map<string, string> {
  const byId = new Map(arms.map((a) => [a.id, a]));
  const out = new Map<string, string>();
  for (const a of arms) {
    const parent = a.parentArmId ? byId.get(a.parentArmId) : undefined;
    out.set(a.id, parent && parent.id !== a.id ? parent.name : a.name);
  }
  return out;
}

/** Reads a church's arms and returns [mainArmNameById] for them. */
export async function loadMainArmNames(
  db: admin.firestore.Firestore,
  churchId: string,
): Promise<Map<string, string>> {
  const snap = await db.collection(`churches/${churchId}/partnership_arms`).get();
  return mainArmNameById(snap.docs.map((d) => ({
    id: d.id,
    name: String(d.get("name") ?? ""),
    parentArmId: (d.get("parentArmId") as string | null | undefined) ?? null,
  })));
}
