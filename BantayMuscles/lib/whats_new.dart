import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'changelog.dart';
import 'theme.dart';

const _kLastSeenVersion = 'bm.lastSeenVersion.v1';

/// Shows the "What's new" sheet once — the first time the app runs after being
/// updated to a version that has changelog notes. Stays silent on a first-ever
/// install (there's no prior version to have "updated" from) and on every
/// relaunch of a version already seen.
Future<void> maybeShowWhatsNew(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final info = await PackageInfo.fromPlatform();
  final version = info.version; // marketing version, e.g. 1.1.0

  final lastSeen = prefs.getString(_kLastSeenVersion);
  if (lastSeen == version) return; // already shown for this version
  await prefs.setString(_kLastSeenVersion, version);
  if (lastSeen == null) return; // fresh install — nothing was "updated"

  final entry = changelogFor(version);
  if (entry == null || !context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (_) => _WhatsNewDialog(entry: entry),
  );
}

class _WhatsNewDialog extends StatelessWidget {
  final ChangelogEntry entry;
  const _WhatsNewDialog({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: colors.accent, size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text("What's new")),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${entry.version}',
                style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final change in entry.changes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.check_circle,
                                  size: 16, color: colors.accent),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(change,
                                  style: const TextStyle(fontSize: 14, height: 1.3)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.accent),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it',
              style: TextStyle(color: Color(0xFF04120A), fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
