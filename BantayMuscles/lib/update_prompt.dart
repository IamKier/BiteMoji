import 'package:flutter/material.dart';

import 'theme.dart';
import 'updater.dart';

/// Checks for an update and, if one exists, shows the update dialog.
/// When [manual] is true (user tapped "Check for updates"), also reports when
/// already up to date; on launch it stays silent unless there's an update.
Future<void> checkAndPromptUpdate(BuildContext context, {bool manual = false}) async {
  final update = await checkForUpdate();
  if (!context.mounted) return;
  if (update == null) {
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You’re on the latest version')),
      );
    }
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(update: update),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo update;
  const _UpdateDialog({required this.update});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    final ok = await downloadAndInstall(
      widget.update,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (ok) {
      // The system installer is now in front; close the dialog.
      Navigator.of(context).pop();
    } else {
      setState(() {
        _downloading = false;
        _error = 'Download failed. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sizeMb = widget.update.sizeBytes > 0
        ? (widget.update.sizeBytes / (1024 * 1024)).toStringAsFixed(1)
        : null;

    return AlertDialog(
      title: Text('Update available — ${widget.update.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_downloading) ...[
            Text(
              widget.update.notes.isNotEmpty
                  ? widget.update.notes
                  : 'A new version of BiteMoji is ready to install.',
              style: TextStyle(color: colors.textSecondary),
            ),
            if (sizeMb != null) ...[
              const SizedBox(height: 8),
              Text('Download size: $sizeMb MB', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
            ],
          ] else ...[
            Text('Downloading… ${(_progress * 100).round()}%'),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 8,
                backgroundColor: colors.track,
                valueColor: AlwaysStoppedAnimation(colors.accent),
              ),
            ),
            const SizedBox(height: 8),
            Text('Android will ask you to confirm the install when it finishes.',
                style: TextStyle(fontSize: 12, color: colors.textSecondary)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: colors.danger, fontSize: 13)),
          ],
        ],
      ),
      actions: _downloading
          ? const [Padding(padding: EdgeInsets.all(8), child: Text('Please wait…'))]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Later', style: TextStyle(color: colors.textSecondary)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: colors.accent),
                onPressed: _update,
                child: Text(_error == null ? 'Update' : 'Retry',
                    style: const TextStyle(color: Color(0xFF04120A), fontWeight: FontWeight.w700)),
              ),
            ],
    );
  }
}
