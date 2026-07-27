import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'foods.dart';
import 'models/nutrition.dart';
import 'remote.dart';
import 'search.dart';

String createId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = Random().nextInt(1 << 20).toRadixString(36);
  return '$t-$r';
}

/// Single source of truth. Mirrors the Expo app's store: profile, diary entries,
/// steps, the selected day, and the theme preference — all persisted locally.
class AppStore extends ChangeNotifier with WidgetsBindingObserver {
  Profile _profile = const Profile();
  List<Entry> _entries = [];
  Map<String, int> _steps = {};
  Map<String, double> _weights = {};
  List<Food> _foods = List.of(kFoods);
  List<Food> _customFoods = [];
  String _today = toDateKey(DateTime.now());
  late String _selectedDate = _today;
  ThemeMode _themeMode = ThemeMode.system;
  bool _ready = false;
  Timer? _dayTimer;

  Profile get profile => _profile;
  bool get ready => _ready;
  String get selectedDate => _selectedDate;

  /// The day the app currently considers "today". Everything that needs the
  /// current date reads this rather than calling DateTime.now() itself, so the
  /// whole UI agrees on when the day flipped.
  String get today => _today;

  ThemeMode get themeMode => _themeMode;
  Macros get goals => macroGoals(_profile);
  List<Entry> get allEntries => List.unmodifiable(_entries);

  /// Logged body weights by day (YYYY-MM-DD → kg), oldest first.
  Map<String, double> get weights => Map.unmodifiable(_weights);

  /// The most recently logged weight, or null if none has been recorded.
  double? get latestWeight {
    if (_weights.isEmpty) return null;
    final latestKey = (_weights.keys.toList()..sort()).last;
    return _weights[latestKey];
  }

  /// The food catalog — the remote Supabase list once synced, else the bundled one.
  List<Food> get foods => List.unmodifiable(_foods);

  /// The foods the user saved themselves, newest first. Fully searchable and
  /// persisted locally — the answer for dishes with no official database entry.
  List<Food> get customFoods => List.unmodifiable(_customFoods);

  /// Ranked, typo-tolerant, accent-folding search. Searches the user's saved
  /// foods first, then the catalog, so a "My food" outranks a generic match.
  /// An empty query returns everything. See [searchFoods].
  List<Food> searchCatalog(String query) =>
      searchFoods([..._customFoods, ..._foods], query);

  static const _kCustomFoods = 'bm.customfoods.v1';

  /// Saves (or updates, by id) a food the user entered. Prepended so the newest
  /// is first.
  void addCustomFood(Food food) {
    _customFoods = [food, ..._customFoods.where((f) => f.id != food.id)];
    notifyListeners();
    _persistCustomFoods();
  }

  void removeCustomFood(String id) {
    _customFoods = _customFoods.where((f) => f.id != id).toList();
    notifyListeners();
    _persistCustomFoods();
  }

  void _persistCustomFoods() =>
      _persist(_kCustomFoods, jsonEncode(_customFoods.map((f) => f.toJson()).toList()));

  /// The distinct foods most recently logged, newest first — a shortcut for the
  /// things a user actually eats. Reconstructed from diary entries at their
  /// per-serving values, so re-adding one goes through the normal serving flow.
  List<Food> recentFoods({int limit = 8}) {
    final seen = <String>{};
    final out = <Food>[];
    for (final e in _entries.reversed) {
      if (!seen.add(e.name.toLowerCase())) continue;
      final per = e.servings > 0 ? e.servings : 1;
      out.add(Food(
        id: 'recent:${e.id}',
        name: e.name,
        serving: e.serving,
        calories: (e.calories / per).round(),
        protein: (e.protein / per).round(),
        carbs: (e.carbs / per).round(),
        fat: (e.fat / per).round(),
      ));
      if (out.length >= limit) break;
    }
    return out;
  }

  List<Entry> entriesForDate(String date) =>
      _entries.where((e) => e.date == date).toList();

  Macros totalsForDate(String date) => sumMacros(entriesForDate(date).map(
        (e) => Macros(calories: e.calories, protein: e.protein, carbs: e.carbs, fat: e.fat),
      ));

  Map<MealType, List<Entry>> groupedForDate(String date) {
    final out = {for (final m in MealType.values) m: <Entry>[]};
    for (final e in entriesForDate(date)) {
      out[e.meal]!.add(e);
    }
    return out;
  }

  int stepsForDate(String date) => _steps[date] ?? 0;

  static const _kEntries = 'bm.entries.v1';
  static const _kProfile = 'bm.profile.v1';
  static const _kSteps = 'bm.steps.v1';
  static const _kWeights = 'bm.weights.v1';
  static const _kTheme = 'bm.theme.v1';

  /// Reads one persisted key and hands its raw string to [parse]. Any failure
  /// is swallowed so the key simply keeps its default and the rest of the load
  /// carries on — one unreadable key can't abort the others.
  void _load(SharedPreferences prefs, String key, void Function(String raw) parse) {
    final raw = prefs.getString(key);
    if (raw == null) return;
    try {
      parse(raw);
    } catch (_) {
      // Leave this key at its default value.
    }
  }

  Future<void> hydrate() async {
    WidgetsBinding.instance.addObserver(this);
    _scheduleDayRollover();

    final prefs = await SharedPreferences.getInstance();

    // Each key is loaded on its own: if one value fails to parse — a corrupt
    // write, or a field a future release changes — only that key falls back to
    // its default. The others are untouched, so a single problem can never wipe
    // the whole account the way one shared try/catch used to.
    _load(prefs, _kProfile, (raw) {
      _profile = Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    });

    _load(prefs, _kEntries, (raw) {
      // Parse row by row and drop only the unreadable ones, rather than losing
      // the entire diary to a single bad entry.
      _entries = [
        for (final row in jsonDecode(raw) as List)
          if (Entry.tryFromJson(row) case final Entry e) e,
      ];
    });

    _load(prefs, _kCustomFoods, (raw) {
      _customFoods = [
        for (final row in jsonDecode(raw) as List)
          if (Food.tryFromJson(row) case final Food f) f,
      ];
    });

    _load(prefs, _kSteps, (raw) {
      final out = <String, int>{};
      (jsonDecode(raw) as Map).forEach((k, v) {
        if (k is String && v is num) out[k] = v.toInt();
      });
      _steps = out;
    });

    _load(prefs, _kWeights, (raw) {
      final out = <String, double>{};
      (jsonDecode(raw) as Map).forEach((k, v) {
        if (k is String && v is num) out[k] = v.toDouble();
      });
      _weights = out;
    });

    _load(prefs, _kTheme, (raw) {
      _themeMode = ThemeMode.values
          .firstWhere((m) => m.name == raw, orElse: () => ThemeMode.system);
    });

    _ready = true;
    notifyListeners();

    // Pull the shared catalog in the background; the UI is already usable on the
    // bundled list, so a slow or failed fetch just leaves that in place.
    unawaited(_syncFoods());
  }

  Future<void> _syncFoods() async {
    final remote = await fetchRemoteFoods();
    if (remote == null || remote.isEmpty) return;
    // Merge rather than replace: the bundled list is the baseline (so locally
    // added foods like the Filipino dishes never vanish when the remote table
    // is a subset), and the remote overrides or adds entries by id.
    final byId = {for (final f in kFoods) f.id: f};
    for (final f in remote) {
      byId[f.id] = f;
    }
    _foods = byId.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
  }

  Future<void> _persist(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  String get _entriesJson => jsonEncode(_entries.map((e) => e.toJson()).toList());

  // --- Day rollover ---------------------------------------------------------

  /// Fires a refresh just after the next midnight, then re-arms. Without this a
  /// session left open overnight keeps showing (and logging to) the old day.
  void _scheduleDayRollover() {
    _dayTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _dayTimer = Timer(
      nextMidnight.difference(now) + const Duration(seconds: 1),
      () {
        refreshToday();
        _scheduleDayRollover();
      },
    );
  }

  /// Re-reads the wall clock. If the day has turned over, a view that was
  /// sitting on "today" follows it; a day the user deliberately navigated to is
  /// left where it is.
  void refreshToday() {
    final actual = toDateKey(DateTime.now());
    if (actual == _today) return;
    final wasViewingToday = _selectedDate == _today;
    _today = actual;
    if (wasViewingToday) _selectedDate = actual;
    notifyListeners();
  }

  /// A timer doesn't fire reliably while the app is backgrounded, so the clock
  /// is re-checked whenever the app comes back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshToday();
      _scheduleDayRollover();
    }
  }

  void setSelectedDate(String date) {
    _selectedDate = date;
    notifyListeners();
  }

  void shiftDate(int days) => setSelectedDate(shiftDateKey(_selectedDate, days));

  void addEntry(Entry entry) {
    _entries = [..._entries, entry];
    notifyListeners();
    _persist(_kEntries, _entriesJson);
  }

  void removeEntry(String id) {
    _entries = _entries.where((e) => e.id != id).toList();
    notifyListeners();
    _persist(_kEntries, _entriesJson);
  }

  /// Replaces an entry (matched by id) with an edited version.
  void updateEntry(Entry entry) {
    _entries = [for (final e in _entries) e.id == entry.id ? entry : e];
    notifyListeners();
    _persist(_kEntries, _entriesJson);
  }

  void updateProfile(Profile profile) {
    _profile = profile;
    notifyListeners();
    _persist(_kProfile, jsonEncode(profile.toJson()));
  }

  void setStepsForDate(String date, int steps) {
    _steps = {..._steps, date: steps < 0 ? 0 : steps};
    notifyListeners();
    _persist(_kSteps, jsonEncode(_steps));
  }

  /// Adds a delta to a day's step count — used by the hardware pedometer, which
  /// reports incremental steps taken while the app is open.
  void addStepsForDate(String date, int delta) {
    if (delta <= 0) return;
    _steps = {..._steps, date: (_steps[date] ?? 0) + delta};
    notifyListeners();
    _persist(_kSteps, jsonEncode(_steps));
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    _persist(_kTheme, mode.name);
  }

  /// Records a body weight for a day (kg, one decimal). The profile weight — used
  /// for goal and burned-calorie math — tracks the latest logged weight so the
  /// two never silently disagree.
  void setWeightForDate(String date, double kg) {
    if (kg <= 0) return;
    _weights = {..._weights, date: (kg * 10).round() / 10};
    notifyListeners();
    _persist(_kWeights, jsonEncode(_weights));

    final latestKey = (_weights.keys.toList()..sort()).last;
    if (latestKey == date) updateProfile(_profile.copyWith(weightKg: _weights[date]));
  }

  void removeWeightForDate(String date) {
    if (!_weights.containsKey(date)) return;
    _weights = {..._weights}..remove(date);
    notifyListeners();
    _persist(_kWeights, jsonEncode(_weights));
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // --- Backup ---------------------------------------------------------------

  /// A portable JSON snapshot of everything the user has entered.
  String exportData() => jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'profile': _profile.toJson(),
        'entries': _entries.map((e) => e.toJson()).toList(),
        'steps': _steps,
        'weights': _weights,
      });

  /// Replaces local data with a backup. Returns false if the payload is invalid.
  bool importData(String raw) {
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }
    if (parsed['version'] != 1 || parsed['entries'] is! List) return false;

    try {
      _profile = Profile.fromJson(parsed['profile'] as Map<String, dynamic>);
      _entries = (parsed['entries'] as List)
          .map((j) => Entry.fromJson(j as Map<String, dynamic>))
          .toList();
      _steps = (parsed['steps'] as Map? ?? {})
          .map((k, v) => MapEntry(k as String, (v as num).toInt()));
      _weights = (parsed['weights'] as Map? ?? {})
          .map((k, v) => MapEntry(k as String, (v as num).toDouble()));
    } catch (_) {
      return false;
    }

    notifyListeners();
    _persist(_kProfile, jsonEncode(_profile.toJson()));
    _persist(_kEntries, _entriesJson);
    _persist(_kSteps, jsonEncode(_steps));
    _persist(_kWeights, jsonEncode(_weights));
    return true;
  }
}
