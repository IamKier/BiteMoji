// ignore_for_file: avoid_print
// Generates an idempotent SQL upsert of the bundled food catalog, for seeding
// or syncing the Supabase `foods` table. Pure Dart — no Flutter needed.
//
//   dart run tool/gen_foods_sql.dart > supabase_foods_seed.sql
//
// Paste the output into the Supabase SQL Editor. Safe to re-run: rows are
// matched by id and updated in place.

import 'package:bantaymuscles/foods.dart';

String q(String s) => "'${s.replaceAll("'", "''")}'";

void main() {
  final b = StringBuffer();
  b.writeln('-- BiteMoji food catalog seed / sync (${kFoods.length} foods).');
  b.writeln('-- Idempotent: safe to run repeatedly.');
  b.writeln('insert into public.foods (id, name, serving, calories, protein, carbs, fat) values');
  b.writeln([
    for (final f in kFoods)
      '  (${q(f.id)}, ${q(f.name)}, ${q(f.serving)}, ${f.calories}, ${f.protein}, ${f.carbs}, ${f.fat})',
  ].join(',\n'));
  b.writeln('on conflict (id) do update set');
  b.writeln('  name = excluded.name,');
  b.writeln('  serving = excluded.serving,');
  b.writeln('  calories = excluded.calories,');
  b.writeln('  protein = excluded.protein,');
  b.writeln('  carbs = excluded.carbs,');
  b.writeln('  fat = excluded.fat;');
  print(b.toString());
}
