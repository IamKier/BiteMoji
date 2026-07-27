import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'activity.dart';
import 'store.dart';

/// Kotlin AppWidgetProvider class name (see android/.../BmWidgetProvider.kt).
const String _androidWidgetName = 'BmWidgetProvider';

/// Home-screen widgets only exist on Android here; everything is a no-op
/// elsewhere (web/Windows) and wrapped in try/catch so a missing widget or
/// plugin never surfaces an error.
bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Pushes today's calorie / macro / step summary to the widget and refreshes
/// it. Values are pre-formatted here so the native side stays dumb.
Future<void> updateHomeWidget(AppStore store) async {
  if (!_supported) return;
  try {
    final date = store.today;
    final totals = store.totalsForDate(date);
    final goals = store.goals;
    final steps = store.stepsForDate(date);
    final burned = caloriesFromSteps(steps, store.profile.weightKg);
    final effectiveGoal = goals.calories + burned;
    final remaining = effectiveGoal - totals.calories;
    final over = remaining < 0;

    int pct(int v, int g) => g <= 0 ? 0 : (v / g * 100).clamp(0, 100).round();

    await Future.wait([
      HomeWidget.saveWidgetData<String>('cal_left', remaining.abs().toString()),
      HomeWidget.saveWidgetData<String>('cal_label', over ? 'kcal over' : 'kcal left'),
      HomeWidget.saveWidgetData<String>('cal_sub', '${totals.calories} / $effectiveGoal kcal'),
      HomeWidget.saveWidgetData<int>('cal_progress', pct(totals.calories, effectiveGoal)),
      HomeWidget.saveWidgetData<String>('p_text', 'P ${totals.protein}/${goals.protein}g'),
      HomeWidget.saveWidgetData<int>('p_progress', pct(totals.protein, goals.protein)),
      HomeWidget.saveWidgetData<String>('c_text', 'C ${totals.carbs}/${goals.carbs}g'),
      HomeWidget.saveWidgetData<int>('c_progress', pct(totals.carbs, goals.carbs)),
      HomeWidget.saveWidgetData<String>('f_text', 'F ${totals.fat}/${goals.fat}g'),
      HomeWidget.saveWidgetData<int>('f_progress', pct(totals.fat, goals.fat)),
      HomeWidget.saveWidgetData<String>('steps_text', '${_grouped(steps)} steps · $burned kcal'),
    ]);
    await HomeWidget.updateWidget(androidName: _androidWidgetName);
  } catch (_) {
    // No widget placed, or a platform without home widgets — ignore.
  }
}

/// 8200 -> "8,200"
String _grouped(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// Keeps the widget in sync with the store: an initial push plus a debounced
/// update on every change.
class HomeWidgetUpdater {
  final AppStore store;
  Timer? _debounce;

  HomeWidgetUpdater(this.store) {
    if (!_supported) return;
    store.addListener(_onChange);
    unawaited(updateHomeWidget(store));
  }

  void _onChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () => unawaited(updateHomeWidget(store)));
  }

  void dispose() {
    _debounce?.cancel();
    if (_supported) store.removeListener(_onChange);
  }
}
