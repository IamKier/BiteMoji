# BantayMuscles

Calorie and macro tracker for Filipino food — Android-first, built with Flutter.

The app lives in [`BantayMuscles/`](BantayMuscles). Everything else in this repo
is CI and tooling.

```bash
cd BantayMuscles
cp lib/remote_config.example.dart lib/remote_config.dart   # first time only
flutter pub get
flutter run
```

The app's own [README](BantayMuscles/README.md) has the full setup — Supabase,
release signing, and how updates ship.

## What it does

- **Diary** — log foods by meal, edit or remove what you logged, browse any day.
- **Food sources** — a bundled catalog (including ~45 Filipino dishes), a shared
  Supabase catalog, Open Food Facts search, and barcode scanning.
- **My Foods** — save anything you enter and reuse it; build recipes from
  ingredients and save the result as one dish.
- **Goals** — calorie and macro targets from your profile (Mifflin-St Jeor), or
  a custom target. Steps from the hardware pedometer add to the daily budget.
- **Progress** — calorie history and a weight trend chart.
- **Home-screen widget** — today's calories, macros and steps, with a quick-add tap.
- **Accounts are optional.** Everything works offline and signed out; signing in
  adds cloud backup and carries your data to a new phone.

Updates are distributed as APKs on
[GitHub Releases](https://github.com/IamKier/BantayMuscles/releases) — the app
checks for a newer one at startup and can install it in place.
