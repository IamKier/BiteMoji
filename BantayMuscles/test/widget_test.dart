import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bitemoji/changelog.dart';
import 'package:bitemoji/models/nutrition.dart';
import 'package:bitemoji/search.dart';
import 'package:bitemoji/store.dart';

// Storage keys are a persistence contract — kept in sync with AppStore.
const _kEntries = 'bm.entries.v1';
const _kProfile = 'bm.profile.v1';
const _kWeights = 'bm.weights.v1';

/// The marketing version from pubspec (`1.4.0` out of `version: 1.4.0+7`).
/// Tests run with the package root as the working directory.
String _pubspecVersion() {
  final line = File('pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'));
  return line.split(':')[1].trim().split('+').first;
}

/// A store hydrated from the given persisted values.
Future<AppStore> _storeWith([Map<String, Object> prefs = const {}]) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(prefs);
  final store = AppStore();
  await store.hydrate();
  return store;
}

const _kFood = Food(
  id: 'custom:1',
  name: 'Lola adobo',
  serving: '1 serving',
  calories: 350,
  protein: 28,
  carbs: 8,
  fat: 22,
);

Map<String, dynamic> _entryJson(String id, {int calories = 200}) => {
      'id': id,
      'date': '2026-07-25',
      'meal': 'lunch',
      'name': 'Rice',
      'serving': '1 cup',
      'servings': 1,
      'calories': calories,
      'protein': 4,
      'carbs': 45,
      'fat': 0,
    };

void main() {
  test('macro goals derive from the profile and stay sane', () {
    const p = Profile();
    final g = macroGoals(p);
    expect(g.calories, greaterThanOrEqualTo(1200));
    expect(g.protein, greaterThan(0));
    expect(g.carbs, greaterThanOrEqualTo(0));
    expect(g.fat, greaterThan(0));
  });

  test('a custom target overrides the calculated one', () {
    final p = const Profile().copyWith(customCalories: 2500);
    expect(calorieGoal(p), 2500);
  });

  test('bmi categories', () {
    expect(bmiCategory(17), 'Underweight');
    expect(bmiCategory(22), 'Normal');
    expect(bmiCategory(27), 'Overweight');
    expect(bmiCategory(32), 'Obese');
  });

  test('date keys shift correctly', () {
    expect(shiftDateKey('2026-01-01', -1), '2025-12-31');
    expect(shiftDateKey('2026-02-28', 1), '2026-03-01');
  });

  group('Entry.tryFromJson (lenient load parse)', () {
    test('rejects non-maps and rows missing id/date', () {
      expect(Entry.tryFromJson(null), isNull);
      expect(Entry.tryFromJson('nope'), isNull);
      expect(Entry.tryFromJson(42), isNull);
      expect(Entry.tryFromJson({'date': '2026-07-25'}), isNull); // no id
      expect(Entry.tryFromJson({'id': 'x'}), isNull); // no date
    });

    test('defaults missing/garbage fields instead of throwing', () {
      final e = Entry.tryFromJson({'id': 'a', 'date': '2026-07-25'});
      expect(e, isNotNull);
      expect(e!.calories, 0);
      expect(e.protein, 0);
      expect(e.servings, 1);
      expect(e.name, '');
      expect(e.meal, MealType.snack);
    });

    test('reads a well-formed row', () {
      final e = Entry.tryFromJson(_entryJson('a', calories: 400));
      expect(e!.meal, MealType.lunch);
      expect(e.calories, 400);
    });
  });

  group('normalizeForSearch', () {
    test('folds case and accents, collapses punctuation/space', () {
      expect(normalizeForSearch('Piñakbet!!'), 'pinakbet');
      expect(normalizeForSearch('Café  au   lait'), 'cafe au lait');
      expect(normalizeForSearch('   '), '');
    });
  });

  group('searchFoods', () {
    const foods = [
      Food(id: 'a', name: 'Chicken breast, grilled', serving: '100g', calories: 165, protein: 31, carbs: 0, fat: 4),
      Food(id: 'b', name: 'Chicken thigh, roasted', serving: '100g', calories: 209, protein: 26, carbs: 0, fat: 11),
      Food(id: 'c', name: 'Piñakbet', serving: '1 cup', calories: 150, protein: 5, carbs: 20, fat: 6),
      Food(id: 'd', name: 'Beef sirloin, grilled', serving: '100g', calories: 206, protein: 30, carbs: 0, fat: 9),
      Food(id: 'e', name: 'Samgyupsal (grilled pork belly)', serving: '100g', calories: 370, protein: 20, carbs: 2, fat: 31),
    ];

    test('empty query returns everything', () {
      expect(searchFoods(foods, '   ').length, foods.length);
    });

    test('multi-word query matches regardless of word order', () {
      expect(searchFoods(foods, 'grilled chicken').first.id, 'a');
    });

    test('is accent-insensitive both ways', () {
      expect(searchFoods(foods, 'pinakbet').map((f) => f.id), contains('c'));
      expect(searchFoods(foods, 'piñakbet').map((f) => f.id), contains('c'));
    });

    test('tolerates a single typo', () {
      expect(searchFoods(foods, 'chiken').map((f) => f.id), containsAll(['a', 'b']));
    });

    test('every token must match (AND, not OR)', () {
      expect(searchFoods(foods, 'chicken beef'), isEmpty);
    });

    test('ranks a name-prefix match first', () {
      expect(searchFoods(foods, 'samgyupsal').first.id, 'e');
      expect(searchFoods(foods, 'chicken').first.id, 'a');
    });
  });

  group('changelog', () {
    test('has an entry for the version actually being shipped', () {
      // The What's-new sheet only appears if the shipping version has notes, so
      // read the real version out of pubspec rather than a hardcoded one — a
      // literal here goes stale the moment a release is cut and stops catching
      // the thing it exists to catch.
      final version = _pubspecVersion();
      final entry = changelogFor(version);
      expect(entry, isNotNull,
          reason: 'pubspec is at $version but lib/changelog.dart has no entry '
              'for it — the "What\'s new" sheet would not appear.');
      expect(entry!.changes, isNotEmpty);
    });

    test('returns null for an unknown version', () {
      expect(changelogFor('0.0.1'), isNull);
    });
  });

  group('editing a diary entry', () {
    Entry sample() => const Entry(
          id: 'e1', date: '2026-07-27', meal: MealType.lunch, name: 'Rice',
          serving: '1 cup', servings: 1, calories: 200, protein: 4, carbs: 45, fat: 0,
        );

    test('withServings rescales macros proportionally', () {
      final e = sample().withServings(2);
      expect(e.servings, 2);
      expect(e.calories, 400);
      expect(e.carbs, 90);
      final half = sample().withServings(0.5);
      expect(half.calories, 100);
    });

    test('copyWith can move an entry to another meal without touching macros', () {
      final e = sample().copyWith(meal: MealType.dinner);
      expect(e.meal, MealType.dinner);
      expect(e.calories, 200);
    });

    test('updateEntry replaces by id and persists', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        _kEntries: jsonEncode([_entryJson('e1', calories: 200)]),
      });
      final store = AppStore();
      await store.hydrate();
      final original = store.allEntries.single;
      store.updateEntry(original.withServings(3));
      expect(store.allEntries.single.calories, 600);
      expect(store.allEntries.length, 1);
      store.dispose();
    });
  });

  group('custom foods (My Foods)', () {
    test('Food round-trips through JSON', () {
      const f = Food(id: 'custom:x', name: 'Lola adobo', serving: '1 serving', calories: 350, protein: 28, carbs: 8, fat: 22);
      final back = Food.tryFromJson(f.toJson());
      expect(back, isNotNull);
      expect(back!.name, 'Lola adobo');
      expect(back.calories, 350);
      expect(isCustomFood(back), isTrue);
    });

    test('tryFromJson rejects rows without id/name, defaults the rest', () {
      expect(Food.tryFromJson('nope'), isNull);
      expect(Food.tryFromJson({'id': 'custom:1'}), isNull); // no name
      final f = Food.tryFromJson({'id': 'custom:1', 'name': 'X'});
      expect(f!.calories, 0);
      expect(f.serving, '1 serving');
    });

    test('saved foods persist and lead search results', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.hydrate();

      store.addCustomFood(const Food(
          id: 'custom:1', name: 'WingBab unli plate', serving: '1 serving',
          calories: 900, protein: 45, carbs: 20, fat: 65));
      expect(store.customFoods.length, 1);
      // Searchable, and a saved food outranks catalog matches.
      final hits = store.searchCatalog('wingbab');
      expect(hits.first.id, 'custom:1');
      store.dispose();

      // A fresh store reads it back from storage.
      final store2 = AppStore();
      await store2.hydrate();
      expect(store2.customFoods.map((f) => f.name), contains('WingBab unli plate'));
      store2.removeCustomFood('custom:1');
      expect(store2.customFoods, isEmpty);
      store2.dispose();
    });
  });

  group('the backup snapshot covers everything the user owns', () {
    // Regression: saved foods were persisted under their own key but left out
    // of exportData, so they were in neither the backup file nor the cloud
    // snapshot. Restoring a backup, or signing in on a new phone, silently
    // dropped every food the user had entered by hand.
    test('a saved food survives export → import', () async {
      final store = await _storeWith();
      store.addCustomFood(_kFood);
      final backup = store.exportData();
      store.dispose();

      expect(jsonDecode(backup)['customFoods'], isNotEmpty);

      final restored = await _storeWith();
      expect(restored.importData(backup), isTrue);
      expect(restored.customFoods.single.name, 'Lola adobo');
      restored.dispose();
    });

    test('a snapshot written before saved foods were tracked still imports',
        () async {
      // Forward/backward compatibility is why the snapshot stays at version 1
      // with optional fields — an old backup must not be rejected.
      final legacy = jsonEncode({
        'version': 1,
        'profile': const Profile().toJson(),
        'entries': [_entryJson('a')],
        'steps': {'2026-07-25': 500},
        'weights': {'2026-07-25': 70.0},
      });
      final store = await _storeWith();
      expect(store.importData(legacy), isTrue);
      expect(store.allEntries.single.id, 'a');
      expect(store.customFoods, isEmpty);
      store.dispose();
    });

    test('a corrupt payload leaves local data alone', () async {
      final store = await _storeWith();
      store.addEntry(Entry.tryFromJson(_entryJson('mine'))!);
      expect(store.importData('{ not json'), isFalse);
      expect(store.mergeData('{ not json', remoteIsNewer: true), isFalse);
      expect(store.allEntries.single.id, 'mine');
      store.dispose();
    });
  });

  group('AppStore.mergeData (cloud sync reconciliation)', () {
    /// A remote snapshot as the cloud would hold it.
    String remote({
      List<Map<String, dynamic>> entries = const [],
      List<Map<String, dynamic>> customFoods = const [],
      Map<String, int> steps = const {},
      Map<String, double> weights = const {},
      Map<String, String> deleted = const {},
      Profile profile = const Profile(),
    }) =>
        jsonEncode({
          'version': 1,
          'profile': profile.toJson(),
          'entries': entries,
          'customFoods': customFoods,
          'steps': steps,
          'weights': weights,
          'deleted': deleted,
        });

    // Regression: reconcile used to pick one whole snapshot by timestamp, so
    // whichever device was "older" lost everything it had logged since its
    // last sync — even though the two sets didn't overlap at all.
    test('keeps rows only one side has, in both directions', () async {
      final store = await _storeWith();
      store.addEntry(Entry.tryFromJson(_entryJson('local'))!);

      expect(
        store.mergeData(remote(entries: [_entryJson('cloud')]), remoteIsNewer: true),
        isTrue,
      );

      expect(store.allEntries.map((e) => e.id), containsAll(['local', 'cloud']));
      store.dispose();
    });

    test('on the same row, the newer side wins', () async {
      final store = await _storeWith();
      store.addEntry(Entry.tryFromJson(_entryJson('e1', calories: 200))!);

      store.mergeData(remote(entries: [_entryJson('e1', calories: 900)]),
          remoteIsNewer: true);
      expect(store.allEntries.single.calories, 900);

      store.mergeData(remote(entries: [_entryJson('e1', calories: 111)]),
          remoteIsNewer: false);
      expect(store.allEntries.single.calories, 900, reason: 'stale remote must not win');
      store.dispose();
    });

    test('saved foods merge too, and are not lost to the cloud copy', () async {
      final store = await _storeWith();
      store.addCustomFood(_kFood);

      store.mergeData(
        remote(customFoods: [
          const Food(
            id: 'custom:2', name: 'Tita sinigang', serving: '1 bowl',
            calories: 180, protein: 12, carbs: 14, fat: 8,
          ).toJson()
        ]),
        remoteIsNewer: true,
      );

      expect(store.customFoods.map((f) => f.id), containsAll(['custom:1', 'custom:2']));
      store.dispose();
    });

    test('a deleted row is not resurrected by the other device', () async {
      final store = await _storeWith();
      final entry = Entry.tryFromJson(_entryJson('gone'))!;
      store.addEntry(entry);
      store.removeEntry('gone');
      expect(store.deleted.containsKey('gone'), isTrue);

      // The cloud still has it — it hasn't heard about the delete yet.
      store.mergeData(remote(entries: [_entryJson('gone')]), remoteIsNewer: true);
      expect(store.allEntries, isEmpty, reason: 'local delete must win');

      // ...and the other way round: the cloud recorded the delete, we still hold it.
      final other = await _storeWith();
      other.addEntry(entry);
      other.mergeData(
        remote(deleted: {'gone': DateTime.now().toUtc().toIso8601String()}),
        remoteIsNewer: false,
      );
      expect(other.allEntries, isEmpty, reason: 'remote delete must win too');
      other.dispose();
      store.dispose();
    });

    test('re-adding a deleted saved food beats the old tombstone', () async {
      final store = await _storeWith();
      store.addCustomFood(_kFood);
      store.removeCustomFood('custom:1');
      store.addCustomFood(_kFood);

      store.mergeData(remote(), remoteIsNewer: true);
      expect(store.customFoods.single.id, 'custom:1');
      store.dispose();
    });

    test('steps take the higher count rather than overwriting', () async {
      final store = await _storeWith();
      store.setStepsForDate('2026-07-25', 8000);

      store.mergeData(remote(steps: {'2026-07-25': 3000, '2026-07-26': 500}),
          remoteIsNewer: true);

      expect(store.stepsForDate('2026-07-25'), 8000);
      expect(store.stepsForDate('2026-07-26'), 500);
      store.dispose();
    });
  });

  group('AppStore.dataRevision', () {
    // Sync used to push (and stamp a "local changed" time) on every notify,
    // so a device that had merely been opened and scrolled looked newer than
    // one that had actually logged food — and then won the timestamp compare.
    test('moves only for changes that belong in the snapshot', () async {
      final store = await _storeWith();
      final start = store.dataRevision;

      store.setSelectedDate('2026-07-01');
      store.shiftDate(-1);
      store.setThemeMode(ThemeMode.dark);
      expect(store.dataRevision, start, reason: 'UI state is not user data');

      store.addEntry(Entry.tryFromJson(_entryJson('a'))!);
      expect(store.dataRevision, greaterThan(start));
      store.dispose();
    });
  });

  group('AppStore.hydrate resilience', () {
    test('a corrupt entry is skipped; good ones survive', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        _kEntries: jsonEncode([
          _entryJson('ok'),
          'not-an-entry',
          {'no-id': true},
        ]),
      });

      final store = AppStore();
      await store.hydrate();

      expect(store.allEntries.length, 1);
      expect(store.allEntries.first.id, 'ok');
      store.dispose();
    });

    test('one unreadable key cannot wipe the others', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        _kEntries: jsonEncode([_entryJson('ok')]),
        _kWeights: '{ not valid json at all',
        _kProfile: jsonEncode(const Profile().copyWith(age: 41).toJson()),
      });

      final store = AppStore();
      await store.hydrate();

      expect(store.allEntries.length, 1); // entries intact
      expect(store.profile.age, 41); // profile intact
      expect(store.weights, isEmpty); // only the bad key fell back
      store.dispose();
    });
  });
}
