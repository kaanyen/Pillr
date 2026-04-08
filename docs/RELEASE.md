# Release and App Distribution

## Firebase App Distribution (Android)

The workflow [`.github/workflows/app-distribution.yml`](../.github/workflows/app-distribution.yml) uploads a release APK to Firebase App Distribution.

### Required GitHub secrets

| Secret | Description |
|--------|-------------|
| `FIREBASE_TOKEN` | CI token from `firebase login:ci` (not your personal Google password). |
| `FIREBASE_ANDROID_APP_ID` | Firebase Console → Project settings → Your apps → Android → App ID (e.g. `1:xxx:android:yyy`). |

The tester **group** in the workflow is `testers` — create a group with this name in Firebase App Distribution (or change the `--groups` flag to match your group).

### Release notes

The workflow passes `--release-notes "Build from $GITHUB_REF_NAME"` (or `manual run` for workflow_dispatch). Adjust the shell line in the workflow if you want a fixed template or changelog extraction.

### Optional: iOS IPA on CI

A second job can run on `macos-latest` with `flutter build ipa` and `firebase appdistribution:distribute` when these secrets exist:

- `FIREBASE_IOS_APP_ID`
- `FIREBASE_TOKEN` (same as Android)
- Apple signing secrets as required by your team (`APPLE_*`, certificates, provisioning profiles), or use manual signing with exported credentials.

If iOS signing secrets are **not** configured, skip the CI job and distribute via **TestFlight** locally:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Set signing team, bundle ID, and provisioning.
3. Archive → Distribute App → App Store Connect / TestFlight.
4. Upload build in App Store Connect and add testers.

This keeps Android CI unblocked when Apple credentials are not in GitHub.

### Optional GitHub Actions job (copy when ready)

```yaml
  distribute-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: '3.27.0'
      - run: flutter pub get
      - run: flutter build ipa --release
      - run: npm install -g firebase-tools
      - env:
          FIREBASE_TOKEN: ${{ secrets.FIREBASE_TOKEN }}
          FIREBASE_IOS_APP_ID: ${{ secrets.FIREBASE_IOS_APP_ID }}
        run: |
          firebase appdistribution:distribute build/ios/ipa/*.ipa \
            --app "$FIREBASE_IOS_APP_ID" \
            --token "$FIREBASE_TOKEN" \
            --groups "testers" \
            --release-notes "Build from ${GITHUB_REF_NAME:-manual run}"
```

Requires valid code signing in the Flutter iOS project (certificates/profiles in CI or manual export).
