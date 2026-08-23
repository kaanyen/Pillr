# Pillr — working rules

## Never write to production. Use the emulators.

`thepillr2` is the live Firebase project. It holds **The Airport City Church**, a
real congregation with real giving records (800+ entries, 450+ partners). Nothing
an agent does may reach it.

**Every** run of the app, every script, every test goes through the local
emulator suite. Reading production is allowed only for a specific, stated
purpose (an audit, a bug report). Writing to production requires the user to say
so in that conversation — a previous "yes" does not carry over.

### The flag that actually does it

```bash
firebase emulators:start          # auth 9099 · firestore 8080 · storage 9199 · ui 4000

flutter build web \
  --dart-define=USE_EMULATORS=true \
  --dart-define=EMULATOR_HOST=127.0.0.1
```

`USE_EMULATORS` is the only switch that reroutes the SDKs — see
`lib/services/firebase_service.dart`. **`APP_ENV=emulator` does not do this.** It
sets an unrelated variable, the build looks like it is on the emulator, and every
read and write goes to the live project. That mistake has already happened once;
it approved six real entries and wrote an arm alias before it was caught.

### Verify before trusting the run

Do not assume the flag worked. Check where the traffic actually went:

```js
// Playwright: hosts must be 127.0.0.1 only
pg.on("request", r => console.log(new URL(r.url).host));
```

`firestore.googleapis.com` or `identitytoolkit.googleapis.com` in that list means
you are on production — stop, and tell the user what has already been written.
The app also prints `Firebase: using LOCAL EMULATORS …` on boot when wired
correctly.

### Node and admin scripts

Any script using `firebase-admin` refuses to start unless the emulator is set:

```js
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('Refusing to run outside the emulator.');
  process.exit(1);
}
```

`FIRESTORE_EMULATOR_HOST=127.0.0.1:8080` and
`FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099` must both be exported.
`~/.config/gcloud/application_default_credentials.json` grants live write access
to this project, so a script without that guard will silently hit production.

### If something reaches production anyway

Say so immediately and in full: which church, which documents, which fields,
with timestamps. Do not repair it unprompted — the user decides what gets
reverted.

## Testing the app

- `demo-church` ("Demo Community Church") is the throwaway tenant. Use it, not
  the Airport City data.
- Emulator sign-ins: `pastor@pillr.dev`, `admin@pillr.dev`, `staff@pillr.dev`,
  password `DemoPillr1!`.
- `flutter analyze` clean and `flutter test` green before reporting work done.
