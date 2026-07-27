import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/nutrition.dart';
import '../online_search.dart';
import '../theme.dart';

/// Scans a product barcode and resolves it to a food via Open Food Facts.
/// Pushed as a full-screen route; pops with the resolved [Food] on success.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

enum _Status { scanning, looking, error }

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? _controller;

  // Camera permission is resolved before the camera is created, so the OS
  // prompt always fires and a denial gets a clear, actionable screen.
  PermissionStatus? _camPermission;

  _Status _status = _Status.scanning;
  String? _message;
  // Guards against the camera firing the same barcode dozens of times a second.
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _requestCamera();
  }

  // Camera lifecycle (stop on background, restart on resume) is handled by the
  // MobileScanner widget itself in v7 via useAppLifecycleState — no manual
  // observer needed here.

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _camPermission = status;
      if (status.isGranted) {
        _controller = MobileScannerController(
          formats: const [
            BarcodeFormat.ean13,
            BarcodeFormat.ean8,
            BarcodeFormat.upcA,
            BarcodeFormat.upcE,
          ],
        );
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final code = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    _handled = true;
    setState(() {
      _status = _Status.looking;
      _message = null;
    });

    final result = await lookupBarcode(code);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(result.food);
      return;
    }
    setState(() {
      _status = _Status.error;
      _message = result.error;
    });
  }

  void _scanAgain() {
    setState(() {
      _handled = false;
      _status = _Status.scanning;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Scan barcode',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  Row(
                    children: [
                      // Torch — only meaningful once the camera is live.
                      if (_controller != null && (_camPermission?.isGranted ?? false))
                        ValueListenableBuilder<MobileScannerState>(
                          valueListenable: _controller!,
                          builder: (context, state, _) {
                            final on = state.torchState == TorchState.on;
                            final available = state.torchState != TorchState.unavailable;
                            if (!available) return const SizedBox.shrink();
                            return IconButton(
                              tooltip: on ? 'Turn off flashlight' : 'Turn on flashlight',
                              onPressed: () => _controller?.toggleTorch(),
                              icon: Icon(on ? Icons.flash_on : Icons.flash_off,
                                  color: on ? colors.accent : colors.text),
                            );
                          },
                        ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: colors.text),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _buildCameraArea(colors),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Point the camera at a product barcode. Packaged groceries only — '
                'values come per 100 g from Open Food Facts.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraArea(AppColors colors) {
    // Still resolving the permission prompt.
    if (_camPermission == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Denied — offer a retry, or a jump to Settings if permanently denied.
    if (!_camPermission!.isGranted || _controller == null) {
      final permanentlyDenied = _camPermission!.isPermanentlyDenied;
      return _CameraMessage(
        icon: Icons.camera_alt_outlined,
        message: 'Camera access is needed to scan barcodes.',
        actionLabel: permanentlyDenied ? 'Open settings' : 'Allow camera',
        onAction: permanentlyDenied ? openAppSettings : _requestCamera,
        accent: colors.accent,
      );
    }

    // Granted — show the live camera with the reticle + status overlays.
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller!,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _CameraMessage(
            icon: Icons.videocam_off_outlined,
            message: switch (error.errorCode) {
              MobileScannerErrorCode.permissionDenied =>
                'Camera access was denied.',
              MobileScannerErrorCode.unsupported =>
                'This device can’t run the barcode scanner.',
              _ => 'The camera couldn’t start. Close this and try again.',
            },
          ),
        ),
        IgnorePointer(
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.78,
              heightFactor: 0.38,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.accent, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
        if (_status != _Status.scanning)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: const Color(0xB0000000),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_status == _Status.looking) ...[
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    const SizedBox(width: 12),
                    const Flexible(
                      child: Text('Looking it up…', style: TextStyle(color: Colors.white)),
                    ),
                  ] else ...[
                    Flexible(
                      child: Text(_message ?? 'Not found', style: const TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _scanAgain,
                      child: Text('Scan again',
                          style: TextStyle(color: colors.accent, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Full-bleed black panel explaining why there's no camera preview, with an
/// optional recovery action. Used for both a denied permission and a camera
/// that failed to start.
class _CameraMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? accent;

  const _CameraMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: Colors.white70),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent ?? context.colors.accent,
                  ),
                  onPressed: onAction,
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                        color: Color(0xFF04120A), fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
