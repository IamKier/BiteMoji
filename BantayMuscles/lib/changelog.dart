// In-app changelog. Drives the "What's new" sheet shown once after an update,
// so users see what changed even when a GitHub release has no notes written.
//
// Add a new entry at the TOP each release. `version` is the marketing version
// (pubspec's `version:` before the `+`), e.g. 1.1.0.

class ChangelogEntry {
  final String version;
  final List<String> changes;
  const ChangelogEntry({required this.version, required this.changes});
}

const List<ChangelogEntry> kChangelog = [
  ChangelogEntry(
    version: '1.5.0',
    changes: [
      'Your saved foods (My Foods) are now included in backups and in cloud sync. Before this they were left out — restoring a backup, or signing in on a new phone, started you with an empty My Foods.',
      'Signing in on a second phone no longer overwrites what the first one logged. The two are merged instead, so nothing you logged on either device is lost.',
      'Deleting a meal or a saved food now syncs properly — it stays deleted instead of coming back from your other device.',
    ],
  ),
  ChangelogEntry(
    version: '1.4.0',
    changes: [
      'Home-screen widget! Add it from your launcher (long-press home → Widgets → BantayMuscles) to see today\'s calories, macros and steps at a glance.',
      'The widget resizes — shrink it for just calories, expand it for the full picture.',
      'Tap the widget to jump straight into logging a food.',
    ],
  ),
  ChangelogEntry(
    version: '1.3.0',
    changes: [
      'Accounts (optional) — sign in to back up your data and carry it to a new phone. Turn it on under Profile; the app still works fully offline.',
      'Weight trend chart on the Progress tab.',
      'Edit a logged meal (change servings or move it to another meal) — just tap it.',
      'Edit or remove your saved foods with a long-press.',
      'More foods sync from the shared online catalog.',
    ],
  ),
  ChangelogEntry(
    version: '1.2.0',
    changes: [
      'My Foods — save any food you enter and reuse it with one tap; no more retyping.',
      'Recipe builder — combine ingredients into one dish, auto-totalled per serving, saved for reuse.',
      'Portion guide — eyeball amounts by hand size when you have no scale or label.',
      'Added ~45 common Filipino dishes to the food list — adobo, kare-kare, sinigang, bulalo, silog, pancit, street food, kakanin and more.',
      'Rebuilt the barcode scanner on a newer camera engine, with a flashlight toggle for low light.',
    ],
  ),
  ChangelogEntry(
    version: '1.1.0',
    changes: [
      'Smarter search — finds foods even with typos or accents, matches words in any order, and ranks the closest result first.',
      'Your recently logged foods now show at the top of Add, so repeats are one tap.',
      'Steps now add to your daily calorie budget, not just the steps card.',
      'Added samgyupsal and Korean BBQ sides — wings, kimchi, and cheese corn.',
      'Barcode scanner reliably wakes back up after you switch apps.',
      'The day now rolls over at midnight on its own.',
      'Hardened local storage so an update can never lose your history.',
    ],
  ),
];

/// The changelog entry for a marketing [version], or null if none is listed.
ChangelogEntry? changelogFor(String version) {
  for (final entry in kChangelog) {
    if (entry.version == version) return entry;
  }
  return null;
}
