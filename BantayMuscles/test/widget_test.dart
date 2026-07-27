import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bantaymuscles/changelog.dart';
import 'package:bantaymuscles/models/nutrition.dart';
import 'package:bantaymuscles/search.dart';
import 'package:bantaymuscles/store.dart';

// Storage keys are a persistence contract — kept in sync with AppStore.
const _kEntries = 'bm.entries.v1';
const _kProfile = 'bm.profile.v1';
const _kWeights = 'bm.weights.v1';

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
    test('has an entry matching the current pubspec version', () {
      // The What's-new sheet only appears if the shipping version has notes.
      final entry = changelogFor('1.1.0');
      expect(entry, isNotNull);
      expect(entry!.changes, isNotEmpty);
    });

    test('returns null for an unknown version', () {
      expect(changelogFor('0.0.1'), isNull);
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
