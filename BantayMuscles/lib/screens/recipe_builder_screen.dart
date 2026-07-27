import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/nutrition.dart';
import '../store.dart';
import '../theme.dart';

/// Builds a dish from catalog/saved ingredients, totals the macros, divides by
/// how many servings it makes, and saves the result as a reusable custom food.
/// The answer for home cooking that has no official database entry.
///
/// Pops with the saved [Food] so the caller can log it right away.
class RecipeBuilderScreen extends StatefulWidget {
  const RecipeBuilderScreen({super.key});

  @override
  State<RecipeBuilderScreen> createState() => _RecipeBuilderScreenState();
}

class _Ingredient {
  final Food food;
  double servings = 1;
  _Ingredient(this.food);
}

class _RecipeBuilderScreenState extends State<RecipeBuilderScreen> {
  final _name = TextEditingController();
  final _ingredients = <_Ingredient>[];
  int _makes = 1; // how many servings the whole recipe yields
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Macros get _total {
    var m = const Macros();
    for (final ing in _ingredients) {
      m = m + ing.food.scaled(ing.servings);
    }
    return m;
  }

  Macros get _perServing {
    final t = _total;
    final n = _makes < 1 ? 1 : _makes;
    return Macros(
      calories: (t.calories / n).round(),
      protein: (t.protein / n).round(),
      carbs: (t.carbs / n).round(),
      fat: (t.fat / n).round(),
    );
  }

  Future<void> _addIngredient() async {
    final food = await Navigator.of(context).push<Food>(
      MaterialPageRoute(builder: (_) => const _IngredientPickerScreen()),
    );
    if (food == null || !mounted) return;
    setState(() {
      _ingredients.add(_Ingredient(food));
      _error = null;
    });
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give your recipe a name.');
      return;
    }
    if (_ingredients.isEmpty) {
      setState(() => _error = 'Add at least one ingredient.');
      return;
    }
    final per = _perServing;
    final food = Food(
      id: 'custom:${createId()}',
      name: _name.text.trim(),
      serving: '1 serving',
      calories: per.calories,
      protein: per.protein,
      carbs: per.carbs,
      fat: per.fat,
    );
    context.read<AppStore>().addCustomFood(food);
    Navigator.of(context).pop(food);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = _total;
    final per = _perServing;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: const Text('Build a recipe', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('Recipe name', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            const SizedBox(height: 4),
            TextField(
              controller: _name,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: _decoration(colors, hint: 'e.g. Lola\'s chicken adobo'),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Ingredients', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                TextButton.icon(
                  onPressed: _addIngredient,
                  icon: Icon(Icons.add, size: 18, color: colors.accent),
                  label: Text('Add', style: TextStyle(color: colors.accent, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (_ingredients.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Add each ingredient and how much of it went in.',
                    style: TextStyle(color: colors.textSecondary)),
              ),
            for (var i = 0; i < _ingredients.length; i++)
              _IngredientRow(
                ingredient: _ingredients[i],
                onChanged: (v) => setState(() => _ingredients[i].servings = v),
                onRemove: () => setState(() => _ingredients.removeAt(i)),
              ),
            const SizedBox(height: 20),
            // Yield
            Row(
              children: [
                const Expanded(
                  child: Text('Makes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                _Stepper(
                  value: _makes.toDouble(),
                  suffix: _makes == 1 ? 'serving' : 'servings',
                  onDown: () => setState(() => _makes = (_makes - 1).clamp(1, 99)),
                  onUp: () => setState(() => _makes = (_makes + 1).clamp(1, 99)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Totals
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  _totalRow(colors, 'Whole recipe', total, emphasize: false),
                  const SizedBox(height: 10),
                  _totalRow(colors, 'Per serving', per, emphasize: true),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.error_outline, size: 16, color: colors.danger),
                const SizedBox(width: 6),
                Text(_error!, style: TextStyle(color: colors.danger, fontSize: 13)),
              ]),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _save,
                child: const Text('Save to My Foods',
                    style: TextStyle(color: Color(0xFF04120A), fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(AppColors colors, String label, Macros m, {required bool emphasize}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: emphasize ? 15 : 14,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                color: emphasize ? colors.text : colors.textSecondary)),
        Text('${m.calories} kcal · P${m.protein} C${m.carbs} F${m.fat}',
            style: TextStyle(
                fontSize: 14,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                color: emphasize ? colors.accent : colors.textSecondary)),
      ],
    );
  }
}

InputDecoration _decoration(AppColors colors, {String? hint}) => InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.border),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );

class _IngredientRow extends StatelessWidget {
  final _Ingredient ingredient;
  final ValueChanged<double> onChanged;
  final VoidCallback onRemove;
  const _IngredientRow({required this.ingredient, required this.onChanged, required this.onRemove});

  String _trim(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scaled = ingredient.food.scaled(ingredient.servings);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ingredient.food.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text('${_trim(ingredient.servings)} × ${ingredient.food.serving} · ${scaled.calories} kcal',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary)),
              ],
            ),
          ),
          _Stepper(
            value: ingredient.servings,
            compact: true,
            onDown: () => onChanged((ingredient.servings - 0.5).clamp(0.5, 99)),
            onUp: () => onChanged((ingredient.servings + 0.5).clamp(0.5, 99)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: colors.textSecondary),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final double value;
  final String? suffix;
  final bool compact;
  final VoidCallback onDown;
  final VoidCallback onUp;
  const _Stepper({
    required this.value,
    required this.onDown,
    required this.onUp,
    this.suffix,
    this.compact = false,
  });

  String _trim(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _round(colors, Icons.remove, onDown),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            suffix == null ? _trim(value) : '${_trim(value)} $suffix',
            style: TextStyle(fontSize: compact ? 14 : 15, fontWeight: FontWeight.w700),
          ),
        ),
        _round(colors, Icons.add, onUp),
      ],
    );
  }

  Widget _round(AppColors colors, IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: colors.border)),
          child: Icon(icon, size: 16, color: colors.text),
        ),
      );
}

/// A search screen that returns the picked [Food] to the recipe builder.
class _IngredientPickerScreen extends StatefulWidget {
  const _IngredientPickerScreen();

  @override
  State<_IngredientPickerScreen> createState() => _IngredientPickerScreenState();
}

class _IngredientPickerScreenState extends State<_IngredientPickerScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final results = context.watch<AppStore>().searchCatalog(_query);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: const Text('Add ingredient', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search foods',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: colors.surface,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: results.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: colors.border),
                itemBuilder: (_, i) {
                  final f = results[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => Navigator.of(context).pop(f),
                    title: Text(f.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${f.serving} · ${f.calories} kcal',
                        style: TextStyle(color: colors.textSecondary)),
                    trailing: Icon(Icons.add_circle, color: colors.accent),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
