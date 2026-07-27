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
