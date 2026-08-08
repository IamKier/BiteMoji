# BiteMoji — Flutter app

Calorie and macro tracker aimed at Filipino food. Android is the shipping
target; the code also builds for web and Windows, which is handy for fast UI
iteration but neither is distributed.

## Features

- **Log food, however you have it** — a bundled catalog of ~100 foods (heavy on
  Filipino dishes), typo-tolerant / accent-folding search, a barcode scanner and
  online lookup via Open Food Facts, and **Quick Add** for anything with no
  entry. Save one-offs to **My Foods**, or build a dish from parts in the
  **recipe builder**. A **portion guide** helps eyeball amounts.
- **Track what matters** — calories and protein/carbs/fat against goals derived
  from your profile (Mifflin–St Jeor BMR/TDEE), hardware **step counting** that
  credits your daily budget, and **body weight** with a trend chart.
- **Edit freely** — tap a logged meal to change servings or move it; long-press a
  saved food to edit or remove it.
- **Yours, everywhere (optional)** — sign in for per-user **cloud sync**; the app
  is fully usable offline and signed out.
- **Home-screen widget** — today's calories, macros and steps at a glance, with a
  quick-add tap. Resizable.
- **Self-updating** — sideloaded builds check GitHub Releases and update in place.

## Getting started

```bash
cp lib/remote_config.example.dart lib/remote_config.dart
flutter pub get
flutter run                 # or: flutter run -d chrome
```

`remote_config.dart` is gitignored. Left with empty values the app runs fully
offline against the bundled food list — accounts, cloud sync, and the shared
catalog are simply off. That's a supported mode, not a broken one.

Requires the Flutter version pinned in
[`../.github/workflows/ci.yml`](../.github/workflows/ci.yml) (3.44.7) or newer.

## Layout

| Path | What's in it |
| --- | --- |
| `lib/models/nutrition.dart` | The domain: `Food`, `Entry`, `Profile`, and all the calorie/macro math. Pure Dart, no Flutter — so it's directly unit-testable. |
| `lib/store.dart` | `AppStore` — the single source of truth. Holds the diary, profile, steps, weights, and saved foods; persists each to `SharedPreferences`; owns export/import/merge. |
| `lib/screens/` | The four tabs: Today, Add, Progress, Profile — plus the barcode scanner and recipe builder. |
| `lib/search.dart` | Typo-tolerant, accent-folding, word-order-independent food search. |
| `lib/online_search.dart`, `lib/remote.dart` | Open Food Facts lookups, and the shared Supabase food catalog. |
| `lib/auth_controller.dart`, `lib/sync_service.dart` | Optional accounts and per-user cloud sync. |
| `lib/updater.dart`, `lib/update_prompt.dart` | In-app self-update from GitHub Releases. |
| `lib/widget_service.dart`, `android/.../BmWidgetProvider.kt` | The Android home-screen widget. |
| `tool/gen_foods_sql.dart` | Regenerates `supabase_foods_seed.sql` from the bundled catalog. |

## Data, backup, and sync

`AppStore.exportData()` produces the one JSON snapshot that both the manual
backup file and cloud sync use. **Anything the user can lose has to be in it** —
profile, diary entries, steps, weights, saved foods, and the tombstones that
record deletions. It stays at `version: 1` and treats newer fields as optional,
so snapshots stay readable across app versions in both directions.

Two ways in, deliberately different:

- **`importData`** — the explicit "restore this backup file" path. Replaces.
- **`mergeData`** — what cloud sync uses. Unions rows by id and only lets a
  timestamp decide conflicts on the *same* row, because both devices may hold
  edits the other hasn't seen. Deletions travel as tombstones (kept 180 days)
  and are applied last, so a merge can't resurrect something you deleted.

Sync is local-first: the device is always the working copy, so the app is fully
usable offline and signed out. Only real data edits schedule a push —
`AppStore.dataRevision` distinguishes those from browsing days or theme changes.

### Supabase setup (optional)

Run both SQL files once in the Supabase SQL Editor; each is idempotent:

- `supabase_user_sync.sql` — the `user_data` table and its row-level security
  policies. **The policies are the only thing protecting user data**, since the
  app ships a publishable key.
- `supabase_foods_seed.sql` — the shared `foods` catalog.

Then paste your project URL and publishable (anon) key into `remote_config.dart`.
Never put the `service_role` key there.

## Tests and CI

```bash
flutter analyze
flutter test
```

[CI](../.github/workflows/ci.yml) runs analysis, tests, and a release APK build
on every push and PR to `main`. The build step matters: analysis and tests both
run on the host and never touch Gradle, plugin native code, or Android
resources, so an Android-only break would otherwise show up only at release time.

## Releasing

1. Bump `version:` in `pubspec.yaml` (both the marketing version and the `+build`).
2. Add a matching entry at the top of `lib/changelog.dart` — a test fails if the
   shipping version has no notes. It drives the in-app "What's new" sheet.
3. Write `RELEASE_NOTES_vX.Y.Z.md`.
4. `flutter build apk --release`
5. Publish it as a GitHub release on
   [IamKier/BiteMoji](https://github.com/IamKier/BiteMoji/releases).
   Installed apps check that endpoint at startup and offer the update in place.

Release signing reads `android/key.properties` (gitignored). Without it the
release build falls back to debug signing — fine for CI and local checks, but
**a debug-signed APK can't update an installed release build**. Back up the
keystore and its passwords: losing them means never shipping an update to the
same app id again.

## Notes

- Windows/web builds exist but only Android is tested and shipped.
- Building with plugins on Windows needs Developer Mode enabled
  (`start ms-settings:developers`) for symlink support.
