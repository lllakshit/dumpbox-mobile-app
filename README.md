# DumpBox — mobile app (Flutter)

Android and iOS app for DumpBox. It talks to the `/v1` API served by
[`dumpbox-frontend-backend`](https://github.com/lllakshit/dumpbox-frontend-backend) and signs in with Supabase.

## What works

| Area | Status |
|---|---|
| Sign-in | 6-digit email code |
| Capture | Text (a bare URL becomes a link), files (up to 10, 50 MB each), camera photo, current location |
| Feed | Chat-style, newest at the bottom, date separators, pull to sync |
| Item actions | Star, pin, edit, tags, collections, share link (system share sheet), copy, archive, trash, restore, delete forever |
| Browse | Smart views (Notes, Links, Images, Documents, Places, Voice), Pinned, Starred, Archive, Trash, collections, tags |
| Search | Server search with typo tolerance and type/starred filters; on-device search when offline |
| Offline | Everything you capture or change is saved on the phone first and sent in order when back online. Files are copied into app storage so they upload even after a restart. Retries never create duplicates. |
| Sync | Realtime nudge from Supabase + `/v1/changes` pull; on app resume, on reconnect, every minute |

Not yet: Google sign-in on mobile, share-sheet capture from other apps, voice recording, document scanning,
reminders, app lock. AI features are out of scope for now.

## Run locally

Needs Flutter 3.44 (or Docker: `ghcr.io/cirruslabs/flutter:stable`) and the backend running
(see the backend README).

```bash
cp config/dev.example.json config/dev.json   # fill SUPABASE_PUBLISHABLE_KEY; 10.0.2.2 is your computer from the Android emulator
flutter pub get
flutter run --dart-define-from-file=config/dev.json
```

| Command | What it checks |
|---|---|
| `flutter analyze` | Lints and types |
| `flutter test` | Models, capture rules, search highlight, and the sync engine (offline queue, exactly-once sends, refused changes, remote deletes) against a fake server |
| `flutter test test/integration` | Two simulated devices against a **real** running API and Supabase (skipped unless `DUMPBOX_API`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY` are set) |

## CI/CD: APK as a build artifact

`.github/workflows/android-apk.yml` runs on every PR, every push to main and every `v*` tag:

1. `flutter analyze` and `flutter test`
2. builds a release APK with the server settings from repository **variables**
3. checks the APK (package name, permissions, signature)
4. uploads it as the **`dumpbox-android`** artifact (kept 30 days): open the Actions run → *Artifacts*
5. on a `v*` tag, also attaches it to a GitHub release

Set these once in *Settings → Secrets and variables → Actions*:

| Kind | Name | Value |
|---|---|---|
| Variable | `SUPABASE_URL` | `https://<app domain>/sb` (Supabase through our domain; some Indian networks block `*.supabase.co`). A direct `https://<ref>.supabase.co` also works and turns on realtime. |
| Variable | `SUPABASE_PUBLISHABLE_KEY` | Supabase publishable key (safe to ship in the app) |
| Variable | `API_BASE_URL` | The Vercel URL of the web app, e.g. `https://dumpbox.vercel.app` |
| Secret (optional) | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Release signing. Without them the APK is debug-signed: installs fine for testing, not for the Play Store. |

Create a signing key once and keep a backup outside GitHub (losing it means you cannot update the app):

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

```bash
base64 -i upload-keystore.jks | pbcopy
```

Then paste into the `ANDROID_KEYSTORE_BASE64` secret.

Add `dumpbox://login-callback` to Supabase Auth redirect URLs (used when Google sign-in is added to mobile).
