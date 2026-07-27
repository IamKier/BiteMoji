// Core nutrition domain: profile, macros, and all the calorie/macro math.
// Direct port of the Expo app's nutrition.ts — pure Dart, no Flutter imports,
// so it can be unit-tested and reused on any platform.

enum MealType { breakfast, lunch, dinner, snack }

extension MealTypeLabel on MealType {
  String get label => switch (this) {
        MealType.breakfast => 'Breakfast',
        MealType.lunch => 'Lunch',
        MealType.dinner => 'Dinner',
        MealType.snack => 'Snacks',
      };
}

enum Sex { male, female }

enum ActivityLevel { sedentary, light, moderate, active, athlete }

enum Goal { lose, maintain, gain }

const activityFactors = <ActivityLevel, double>{
  ActivityLevel.sedentary: 1.2,
  ActivityLevel.light: 1.375,
  ActivityLevel.moderate: 1.55,
  ActivityLevel.active: 1.725,
  ActivityLevel.athlete: 1.9,
};

const goalDeltas = <Goal, int>{
  Goal.lose: -500,
  Goal.maintain: 0,
  Goal.gain: 300,
};

class Macros {
  final int calories;
  final int protein;
  final int carbs;
  final int fat;

  const Macros({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
  });

  Macros operator +(Macros other) => Macros(
        calories: calories + other.calories,
        protein: protein + other.protein,
        carbs: carbs + other.carbs,
        fat: fat + other.fat,
      );
}

class Food {
  final String id;
  final String name;
  final String serving;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;

  const Food({
    required this.id,
    required this.name,
    required this.serving,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  Macros scaled(double servings) => Macros(
        calories: (calories * servings).round(),
        protein: (protein * servings).round(),
        carbs: (carbs * servings).round(),
        fat: (fat * servings).round(),
      );

  Food copyWith({String? id, String? name, String? serving, int? calories, int? protein, int? carbs, int? fat}) =>
      Food(
        id: id ?? this.id,
        name: name ?? this.name,
        serving: serving ?? this.serving,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'serving': serving,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
      };

  /// Lenient parse for persisted custom foods: null for anything without a
  /// usable id/name, defaults for the rest — consistent with [Entry.tryFromJson]
  /// so one bad saved food can't take down the whole list on load.
  static Food? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || name is! String || name.isEmpty) return null;
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return Food(
      id: id,
      name: name,
      serving: raw['serving'] is String ? raw['serving'] as String : '1 serving',
      calories: asInt(raw['calories']),
      protein: asInt(raw['protein']),
      carbs: asInt(raw['carbs']),
      fat: asInt(raw['fat']),
    );
  }
}

/// True when a food is one the user saved themselves (see AppStore.customFoods).
bool isCustomFood(Food food) => food.id.startsWith('custom:');

class Entry {
  final String id;
  final String date; // local YYYY-MM-DD
  final MealType meal;
  final String name;
  final String serving;
  final double servings;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;

  const Entry({
    required this.id,
    required this.date,
    required this.meal,
    required this.name,
    required this.serving,
    required this.servings,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  Entry copyWith({
    String? id,
    String? date,
    MealType? meal,
    String? name,
    String? serving,
    double? servings,
    int? calories,
    int? protein,
    int? carbs,
    int? fat,
  }) =>
      Entry(
        id: id ?? this.id,
        date: date ?? this.date,
        meal: meal ?? this.meal,
        name: name ?? this.name,
        serving: serving ?? this.serving,
        servings: servings ?? this.servings,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
      );

  /// Returns this entry rescaled to a new number of servings, keeping the
  /// per-serving values it was logged at.
  Entry withServings(double newServings) {
    final base = servings > 0 ? servings : 1;
    int scale(int total) => (total / base * newServings).round();
    return copyWith(
      servings: newServings,
      calories: scale(calories),
      protein: scale(protein),
      carbs: scale(carbs),
      fat: scale(fat),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'meal': meal.name,
        'name': name,
        'serving': serving,
        'servings': servings,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
      };

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'] as String,
        date: j['date'] as String,
        meal: MealType.values.firstWhere((m) => m.name == j['meal'],
            orElse: () => MealType.snack),
        name: j['name'] as String,
        serving: j['serving'] as String,
        servings: (j['servings'] as num).toDouble(),
        calories: (j['calories'] as num).toInt(),
        protein: (j['protein'] as num).toInt(),
        carbs: (j['carbs'] as num).toInt(),
        fat: (j['fat'] as num).toInt(),
      );

  /// Lenient parse for persisted data. Returns null for anything that isn't a
  /// usable entry — not a map, or missing the id/date that identify it — and
  /// fills sensible defaults for any other field that's absent or the wrong
  /// type. This keeps one malformed row, or a field a future release renames,
  /// from taking down the rest of the diary on load.
  static Entry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final date = raw['date'];
    if (id is! String || date is! String) return null;
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return Entry(
      id: id,
      date: date,
      meal: MealType.values
          .firstWhere((m) => m.name == raw['meal'], orElse: () => MealType.snack),
      name: raw['name'] is String ? raw['name'] as String : '',
      serving: raw['serving'] is String ? raw['serving'] as String : '',
      servings: raw['servings'] is num ? (raw['servings'] as num).toDouble() : 1,
      calories: asInt(raw['calories']),
      protein: asInt(raw['protein']),
      carbs: asInt(raw['carbs']),
      fat: asInt(raw['fat']),
    );
  }
}

class Profile {
  final Sex sex;
  final int age;
  final int heightCm;
  final double weightKg;
  final ActivityLevel activity;
  final Goal goal;
  final int? customCalories;

  const Profile({
    this.sex = Sex.male,
    this.age = 30,
    this.heightCm = 170,
    this.weightKg = 70,
    this.activity = ActivityLevel.light,
    this.goal = Goal.maintain,
    this.customCalories,
  });

  Profile copyWith({
    Sex? sex,
    int? age,
    int? heightCm,
    double? weightKg,
    ActivityLevel? activity,
    Goal? goal,
    int? customCalories,
    bool clearCustom = false,
  }) =>
      Profile(
        sex: sex ?? this.sex,
        age: age ?? this.age,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        activity: activity ?? this.activity,
        goal: goal ?? this.goal,
        customCalories: clearCustom ? null : (customCalories ?? this.customCalories),
      );

  Map<String, dynamic> toJson() => {
        'sex': sex.name,
        'age': age,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'activity': activity.name,
        'goal': goal.name,
        'customCalories': customCalories,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        sex: Sex.values.firstWhere((s) => s.name == j['sex'], orElse: () => Sex.male),
        age: (j['age'] as num?)?.toInt() ?? 30,
        heightCm: (j['heightCm'] as num?)?.toInt() ?? 170,
        weightKg: (j['weightKg'] as num?)?.toDouble() ?? 70,
        activity: ActivityLevel.values
            .firstWhere((a) => a.name == j['activity'], orElse: () => ActivityLevel.light),
        goal: Goal.values.firstWhere((g) => g.name == j['goal'], orElse: () => Goal.maintain),
        customCalories: (j['customCalories'] as num?)?.toInt(),
      );
}

/// Mifflin-St Jeor basal metabolic rate.
double bmr(Profile p) {
  final base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age;
  return p.sex == Sex.male ? base + 5 : base - 161;
}

double tdee(Profile p) => bmr(p) * (activityFactors[p.activity] ?? 1.2);

/// Daily calorie target, floored at 1200. Honours a custom override.
int calorieGoal(Profile p) {
  if (p.customCalories != null) return p.customCalories!;
  final delta = goalDeltas[p.goal] ?? 0;
  final target = ((tdee(p) + delta) / 10).round() * 10;
  return target < 1200 ? 1200 : target;
}

/// Macro targets: protein scales with weight, fat 25% of calories, carbs fill the rest.
Macros macroGoals(Profile p) {
  final calories = calorieGoal(p);
  final proteinPerKg = p.goal == Goal.lose ? 2.2 : (p.goal == Goal.gain ? 2.0 : 1.6);
  final protein = (p.weightKg * proteinPerKg).round();
  final fat = (calories * 0.25 / 9).round();
  final carbs = ((calories - protein * 4 - fat * 9) / 4).round();
  return Macros(
    calories: calories,
    protein: protein,
    carbs: carbs < 0 ? 0 : carbs,
    fat: fat,
  );
}

double bmi(Profile p) {
  final m = p.heightCm / 100;
  return m <= 0 ? 0 : p.weightKg / (m * m);
}

String bmiCategory(double v) {
  if (v < 18.5) return 'Underweight';
  if (v < 25) return 'Normal';
  if (v < 30) return 'Overweight';
  return 'Obese';
}

Macros sumMacros(Iterable<Macros> items) =>
    items.fold(const Macros(), (acc, m) => acc + m);

/// Local YYYY-MM-DD — never use toIso8601 (it shifts the day across timezones).
String toDateKey(DateTime d) {
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

String shiftDateKey(String key, int days) {
  final parts = key.split('-').map(int.parse).toList();
  return toDateKey(DateTime(parts[0], parts[1], parts[2] + days));
}

/// A friendly label for a YYYY-MM-DD key: Today / Yesterday / Tomorrow, else
/// a short "Wed, Jul 21" form.
String formatDateLabel(String key) {
  final today = toDateKey(DateTime.now());
  if (key == today) return 'Today';
  if (key == shiftDateKey(today, -1)) return 'Yesterday';
  if (key == shiftDateKey(today, 1)) return 'Tomorrow';

  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final parts = key.split('-').map(int.parse).toList();
  final d = DateTime(parts[0], parts[1], parts[2]);
  return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
}
