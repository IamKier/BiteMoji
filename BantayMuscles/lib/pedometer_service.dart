import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import 'store.dart';

enum PedometerStatus { checking, active, denied, unavailable }

/// Counts steps from the phone's hardware pedometer and folds them into the store.
///
/// Android limitation (per the platform): step updates are NOT delivered while
/// the app is backgrounded, and there's no historical query — so this only counts
/// steps taken with the app open, which is why the steps card also accepts a
/// manual figure.
///
/// The sensor reports a running total since device boot, not a delta. We keep a
/// baseline and only add the increase. On resume the counter has advanced by the
/// steps taken while backgrounded (which we can't attribute to a day), so the
/// baseline is reset to discard that jump. Port of the Expo app's use-pedometer.
class PedometerService extends ChangeNotifier with WidgetsBindingObserver {
  final AppStore store;
  PedometerService(this.store);

  PedometerStatus _status = PedometerStatus.checking;
  PedometerStatus get status => _status;

  StreamSubscription<StepCount>? _sub;
  int? _lastTotal;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);

    // Android 10+ needs runtime activity-recognition permission; older versions
    // grant it at install time. iOS uses motion (sensors).
    final granted = await _ensurePermission();
    if (granted != true) {
      _set(PedometerStatus.denied);
      return;
    }

    try {
      _sub = Pedometer.stepCountStream.listen(
        _onStep,
        onError: (_) => _set(PedometerStatus.unavailable),
        cancelOnError: false,
      );
      _set(PedometerStatus.active);
    } catch (_) {
      _set(PedometerStatus.unavailable);
    }
  }

  Future<bool> _ensurePermission() async {
    try {
      final status = await Permission.activityRecognition.request();
      if (status.isGranted || status.isLimited) return true;
      // activityRecognition is Android-only; on iOS fall back to sensors.
      final sensors = await Permission.sensors.request();
      return sensors.isGranted || sensors.isLimited;
    } catch (_) {
      return false;
    }
  }

  void _onStep(StepCount event) {
    final total = event.steps;
    if (_lastTotal == null) {
      _lastTotal = total; // establish baseline; don't count history
      return;
    }
    final delta = total - _lastTotal!;
    _lastTotal = total;
    // Credit the store's current day so steps can't land on a stale date if the
    // app has been open across midnight.
    if (delta > 0) store.addStepsForDate(store.today, delta);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Discard the background jump: re-baseline on the next event after resume.
    if (state == AppLifecycleState.resumed) _lastTotal = null;
  }

  void _set(PedometerStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }
}
