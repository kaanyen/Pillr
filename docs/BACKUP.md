# Firestore backup and restore

Pillr stores tenant data in **Cloud Firestore** (`thepillr2`). This doc covers scheduled exports to **Google Cloud Storage (GCS)** for long-term backup and compliance.

## What runs automatically

After one-time setup and deploy, **`scheduledFirestoreBackup`** (Cloud Function) runs:

- **Schedule:** every **Sunday at 03:00 UTC**
- **Destination:** `gs://{projectId}-firestore-backups/scheduled/{timestamp}/`
- **Retention:** objects deleted after **365 days** (configurable at setup)

Each run starts a Firestore **export operation** (async). Exports include all collections unless you later add collection filters.

## One-time setup

From the repo root, with Firebase/GCP admin credentials (same as `seed-demo`):

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/to/serviceAccount.json"
npm run setup-firestore-backup --prefix functions
npm run build --prefix functions
firebase deploy --only functions:scheduledFirestoreBackup --project thepillr2
```

Optional env vars:

| Variable | Default | Purpose |
|----------|---------|---------|
| `FIREBASE_PROJECT_ID` | `thepillr2` | GCP project |
| `FIRESTORE_BACKUP_BUCKET` | `{projectId}-firestore-backups` | GCS bucket name |
| `FIRESTORE_BACKUP_RETENTION_DAYS` | `365` | Lifecycle delete age |
| `FIRESTORE_BACKUP_LOCATION` | `us-central1` | Bucket region |

### IAM (what setup configures)

1. **Firestore service agent** — `storage.admin` on the backup bucket (required to write export files)
2. **Cloud Functions compute SA** — `datastore.importExportAdmin` on the project (required to start exports)

## Manual export

```bash
gcloud firestore export gs://thepillr2-firestore-backups/manual/$(date +%Y-%m-%d) \
  --project=thepillr2
```

## Verify backups

**Cloud Console**

- [Firestore → Import/Export](https://console.firebase.google.com/project/thepillr2/firestore/databases/-default-/import-export)
- [Cloud Storage → backup bucket](https://console.cloud.google.com/storage/browser/thepillr2-firestore-backups)

**Logs**

- Cloud Functions → `scheduledFirestoreBackup` — look for `Firestore backup started` with operation name

## Restore (disaster recovery)

Exports are for **recovery**, not single-document undo.

1. Choose an export prefix, e.g. `gs://thepillr2-firestore-backups/scheduled/2026-06-08T03-00-00-000Z`
2. **Recommended:** import into a **staging project** or new database first and validate
3. Import:

```bash
gcloud firestore import gs://thepillr2-firestore-backups/scheduled/BACKUP_PREFIX \
  --project=thepillr2
```

Import **overwrites** existing data in the target database. For production recovery, prefer:

- Restore to a **separate** Firebase project, verify, then migrate; or
- Enable **Point-in-time recovery (PITR)** in Firestore for faster rollback within the recovery window

## Related

- **App / hosting rollback:** Firebase Hosting release history (does not restore DB data)
- **Bulk import drafts:** local Hive on device until Confirm — not a server backup
- **Activity logs:** audit trail only; not automatic restore

## Compliance notes

- Exports are **encrypted at rest** in GCS (Google-managed keys; CMEK optional)
- Restrict bucket access to platform admins; do not make the backup bucket public
- Document who can run imports and how often restore drills are tested
- Adjust `FIRESTORE_BACKUP_RETENTION_DAYS` to match your retention policy
