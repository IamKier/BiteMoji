// In-app updater for the sideloaded (non-Play-Store) build.
//
// Checks the GitHub Releases API for a newer version, then downloads the release
// APK and hands it to the system installer. Android always shows its own install
// confirmation — an app can't silently self-install — so this is a one-tap update.
//
// Requires the release APK to be signed with the SAME key as the installed app
// (the upload keystore) or Android refuses the update.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// owner/repo whose Releases feed the updater. Must be public.
const String kGithubRepo = 'IamKier/BiteMoji';

class UpdateInfo {
  final String version; // tag without a leading "v", e.g. "1.0.1+3"
  final String tagName;
  final String apkUrl;
  final String notes;
  final int sizeBytes;
  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.apkUrl,
    required this.notes,
    required this.sizeBytes,
  });
}

/// Parse "1.0.0+2" (or "v1.0.0+2") into [major, minor, patch, build].
List<int> _parseVersion(String raw) {
  var s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  final plus = s.split('+');
  final core = plus[0]
      .split('.')
      .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  while (core.length < 3) {
    core.add(0);
  }
  final build = plus.length > 1
      ? (int.tryParse(plus[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      : 0;
  return [core[0], core[1], core[2], build];
}

/// True if [latest] is strictly newer than [current].
bool _isNewer(String latest, String current) {
  final a = _parseVersion(latest), b = _parseVersion(current);
  for (var i = 0; i < 4; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// The running app's version, e.g. "1.0.0+2".
Future<String> currentVersion() async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
}

/// Checks GitHub's latest release; returns info only when it's newer than the
/// running app and carries an .apk asset. Returns null on any failure (offline,
/// no release, already up to date) so callers can stay quiet.
Future<UpdateInfo?> checkForUpdate() async {
  if (!Platform.isAndroid) return null; // APK self-update is Android-only
  try {
    final current = await currentVersion();
    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$kGithubRepo/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String?) ?? '';
    if (tag.isEmpty || !_isNewer(tag, current)) return null;

    Map<String, dynamic>? apk;
    for (final a in (data['assets'] as List? ?? const [])) {
      if (a is Map && ((a['name'] as String?)?.toLowerCase().endsWith('.apk') ?? false)) {
        apk = a.cast<String, dynamic>();
        break;
      }
    }
    if (apk == null) return null;

    return UpdateInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      tagName: tag,
      apkUrl: apk['browser_download_url'] as String,
      notes: (data['body'] as String?)?.trim() ?? '',
      sizeBytes: (apk['size'] as num?)?.toInt() ?? 0,
    );
  } catch (_) {
    return null;
  }
}

/// Downloads the release APK (reporting 0..1 progress) and launches the system
/// installer. Returns false on any failure.
Future<bool> downloadAndInstall(UpdateInfo update, {void Function(double)? onProgress}) async {
  try {
    final dir = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    final file = File('${dir.path}/BiteMoji-${update.tagName}.apk');

    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(update.apkUrl)));
      if (resp.statusCode != 200) return false;

      final total = resp.contentLength ?? update.sizeBytes;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
    } finally {
      client.close();
    }

    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done;
  } catch (_) {
    return false;
  }
}
