import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/nutrition.dart';
import '../online_search.dart';
import '../portion_guide.dart';
import '../store.dart';
import '../theme.dart';
import 'barcode_scanner_screen.dart';
import 'recipe_builder_screen.dart';

class AddScreen extends StatefulWidget {
  final MealType initialMeal;
  final VoidCallback onAdded;
  const AddScreen({super.key, required this.initialMeal, required this.onAdded});

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  late MealType _meal = widget.initialMeal;
  final _searchController = TextEditingController();
  String _query = '';

  // Online (Open Food Facts) search state. A short debounce keeps us from
  // firing a request on every keystroke; a token guards against a slow early
  // response landing after a newer query.
  Timer? _debounce;
  int _searchToken = 0;
  bool _searching = false;
  String? _onlineError;
  List<Food> _online = const [];

  @override
  void didUpdateWidget(AddScreen old) {
    super.didUpdateWidget(old);
    if (old.initialMeal != widget.initialMeal) _meal = widget.initialMeal;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _clearQuery() {
    _searchController.clear();
    _onQueryChanged('');
    FocusScope.of(context).unfocus();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _searching = false;
        _onlineError = null;
        _online = const [];
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _runOnline(q));
  }

  Future<void> _runOnline(String q) async {
    final token = ++_searchToken;
    final result = await searchOnline(q);
    if (!mounted || token != _searchToken) return; // a newer query superseded us
    setState(() {
      _searching = false;
      _onlineError = result.ok ? null : result.error;
      _online = result.foods;
    });
  }

  Future<void> _scanBarcode() async {
    final food = await Navigator.of(context).push<Food>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (food == null || !mounted) return;
    _pick(food);
  }

  /// Log a food by typing the numbers in — no catalog entry needed.
  Future<void> _quickAdd() async {
    final values = await showModalBottomSheet<_QuickAddValues>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _QuickAddSheet(),
    );
    if (values == null || !mounted) return;
    final store = context.read<AppStore>();
    final name = values.name.isEmpty ? 'Quick add' : values.name;
    // Keep it for reuse first, so it's in My Foods even if logging is undone.
    if (values.save) {
      store.addCustomFood(Food(
        id: 'custom:${createId()}',
        name: name,
        serving: '1 serving',
        calories: values.calories,
        protein: values.protein,
        carbs: values.carbs,
        fat: values.fat,
      ));
    }
    store.addEntry(Entry(
      id: createId(),
      date: store.selectedDate,
      meal: _meal,
      name: name,
      serving: '1 serving',
      servings: 1,
      calories: values.calories,
      protein: values.protein,
      carbs: values.carbs,
      fat: values.fat,
    ));
    widget.onAdded();
  }

  /// Opens the recipe builder. It saves the result to My Foods and returns it,
  /// so we go straight into logging it via the serving sheet.
  Future<void> _buildRecipe() async {
    final food = await Navigator.of(context).push<Food>(
      MaterialPageRoute(builder: (_) => const RecipeBuilderScreen()),
    );
    if (food == null || !mounted) return;
    _pick(food);
  }

  /// Long-press on a saved food: edit its numbers or remove it.
  Future<void> _customFoodMenu(Food food) async {
    final colors = context.colors;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(food.name,
                  style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            ),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: colors.text),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: colors.danger),
              title: Text('Remove from My Foods', style: TextStyle(color: colors.danger)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      _editCustomFood(food);
    } else if (action == 'remove') {
      _confirmRemoveCustom(food);
    }
  }

  /// Opens a prefilled editor for a saved food; saving upserts it (same id).
  Future<void> _editCustomFood(Food food) async {
    final updated = await showModalBottomSheet<Food>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditCustomFoodSheet(food: food),
    );
    if (updated == null || !mounted) return;
    context.read<AppStore>().addCustomFood(updated);
  }

  /// Removes a saved food from My Foods. Past diary entries are untouched —
  /// they carry their own copied values.
  Future<void> _confirmRemoveCustom(Food food) async {
    final store = context.read<AppStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from My Foods?'),
        content: Text('"${food.name}" will no longer appear in your saved foods. '
            'Meals you already logged with it stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) store.removeCustomFood(food.id);
  }

  void _pick(Food food) async {
    final servings = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServingSheet(food: food, meal: _meal),
    );
    if (servings == null || !mounted) return;
    final store = context.read<AppStore>();
    final scaled = food.scaled(servings);
    store.addEntry(Entry(
      id: createId(),
      date: store.selectedDate,
      meal: _meal,
      name: food.name,
      serving: food.serving,
      servings: servings,
      calories: scaled.calories,
      protein: scaled.protein,
      carbs: scaled.carbs,
      fat: scaled.fat,
    ));
    widget.onAdded();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<AppStore>();
    final hasQuery = _query.trim().isNotEmpty;
    final results = store.searchCatalog(_query);
    final myFoods = hasQuery ? const <Food>[] : store.customFoods;
    final recents = hasQuery ? const <Food>[] : store.recentFoods();

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('Add food', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onQueryChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search foods',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  tooltip: 'Clear',
                                  onPressed: _clearQuery,
                                )
                              : null,
                          filled: true,
                          fillColor: colors.surface,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colors.accent, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Scan a product barcode → Open Food Facts lookup.
                    Material(
                      color: colors.accentMuted,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: _scanBarcode,
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: Icon(Icons.qr_code_scanner, color: colors.accent),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final m in MealType.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _MealChip(
                            meal: m,
                            selected: m == _meal,
                            onTap: () => setState(() => _meal = m),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              children: [
                // Ways to add a food that isn't (or can't be) in a database.
                _ActionRow(
                  icon: Icons.edit_note,
                  title: 'Quick add',
                  subtitle: 'Enter a food manually',
                  onTap: _quickAdd,
                ),
                const SizedBox(height: 8),
                _ActionRow(
                  icon: Icons.blender_outlined,
                  title: 'Build a recipe',
                  subtitle: 'Combine ingredients into one saved food',
                  onTap: _buildRecipe,
                ),
                // Your saved foods — long-press to remove one.
                if (myFoods.isNotEmpty) ...[
                  const _SectionLabel('MY FOODS'),
                  for (final f in myFoods) ...[
                    _FoodRow(
                      food: f,
                      onTap: () => _pick(f),
                      onLongPress: () => _customFoodMenu(f),
                    ),
                    Divider(height: 1, color: colors.border),
                  ],
                ],
                // Recently logged — the fast path back to what you actually eat.
                if (recents.isNotEmpty) ...[
                  const _SectionLabel('RECENT'),
                  for (final f in recents) ...[
                    _FoodRow(food: f, leading: Icons.history, onTap: () => _pick(f)),
                    Divider(height: 1, color: colors.border),
                  ],
                ],
                // Catalog matches, ranked. Header carries a live count so it's
                // clear how much matched.
                _SectionLabel(hasQuery
                    ? (results.isEmpty
                        ? 'CATALOG'
                        : '${results.length} ${results.length == 1 ? 'MATCH' : 'MATCHES'}')
                    : 'ALL FOODS'),
                if (hasQuery && results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('No catalog matches. Try Quick add, or the online results below.',
                        style: TextStyle(color: colors.textSecondary)),
                  ),
                for (final f in results) ...[
                  _FoodRow(
                    food: f,
                    onTap: () => _pick(f),
                    onLongPress: isCustomFood(f) ? () => _customFoodMenu(f) : null,
                  ),
                  Divider(height: 1, color: colors.border),
                ],
                _OnlineSection(
                  query: _query,
                  searching: _searching,
                  error: _onlineError,
                  foods: _online,
                  localCount: results.length,
                  onPick: _pick,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable card row — Quick add / Build a recipe entry points.
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: colors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small uppercase section header used to separate Recent / matches / online.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.colors.textSecondary,
              letterSpacing: 0.5)),
    );
  }
}

/// A single food row — shared by the local catalog and online results.
class _FoodRow extends StatelessWidget {
  final Food food;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool online;
  final IconData? leading;
  const _FoodRow({
    required this.food,
    required this.onTap,
    this.onLongPress,
    this.online = false,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = online ? 'online' : (isCustomFood(food) ? 'saved' : null);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: leading == null
          ? null
          : Icon(leading, size: 20, color: colors.textSecondary),
      title: Row(children: [
        Flexible(child: Text(food.name, overflow: TextOverflow.ellipsis)),
        if (label != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.accentMuted,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: colors.accent)),
          ),
        ],
      ]),
      subtitle: Text('${food.serving} · P${food.protein} C${food.carbs} F${food.fat}',
          style: TextStyle(color: colors.textSecondary)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${food.calories}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Icon(Icons.add_circle, color: colors.accent),
      ]),
    );
  }
}

/// The "Online results" block: a header, plus a spinner, error, empty note, or
/// the Open Food Facts matches.
class _OnlineSection extends StatelessWidget {
  final String query;
  final bool searching;
  final String? error;
  final List<Food> foods;
  final int localCount;
  final void Function(Food) onPick;
  const _OnlineSection({
    required this.query,
    required this.searching,
    required this.error,
    required this.foods,
    required this.localCount,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (query.trim().length < 2) return const SizedBox.shrink();

    Widget body;
    if (searching) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(children: [
          const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text('Searching Open Food Facts…', style: TextStyle(color: colors.textSecondary)),
        ]),
      );
    } else if (error != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(error!, style: TextStyle(color: colors.textSecondary)),
      );
    } else if (foods.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('No online matches. Try Quick add.',
            style: TextStyle(color: colors.textSecondary)),
      );
    } else {
      body = Column(
        children: [
          for (final f in foods) ...[
            _FoodRow(food: f, online: true, onTap: () => onPick(f)),
            Divider(height: 1, color: colors.border),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: localCount > 0 ? 20 : 8, bottom: 4),
          child: Text('ONLINE (OPEN FOOD FACTS)',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: colors.textSecondary, letterSpacing: 0.5)),
        ),
        body,
      ],
    );
  }
}

class _MealChip extends StatelessWidget {
  final MealType meal;
  final bool selected;
  final VoidCallback onTap;
  const _MealChip({required this.meal, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.accentMuted : colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? colors.accent : colors.border),
        ),
        child: Text(
          meal.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? colors.accent : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ServingSheet extends StatefulWidget {
  final Food food;
  final MealType meal;
  const _ServingSheet({required this.food, required this.meal});

  @override
  State<_ServingSheet> createState() => _ServingSheetState();
}

class _ServingSheetState extends State<_ServingSheet> {
  double _servings = 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scaled = widget.food.scaled(_servings);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: colors.border),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: colors.track, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(widget.food.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Text('${widget.food.serving} · ${widget.meal.label}',
              style: TextStyle(color: colors.textSecondary)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepButton(icon: Icons.remove, onTap: () => setState(() => _servings = (_servings - 0.5).clamp(0.5, 99))),
              const SizedBox(width: 24),
              Column(children: [
                Text(_trim(_servings), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                Text(_servings == 1 ? 'serving' : 'servings', style: TextStyle(color: colors.textSecondary)),
              ]),
              const SizedBox(width: 24),
              _StepButton(icon: Icons.add, onTap: () => setState(() => _servings = (_servings + 0.5).clamp(0.5, 99))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Pill(label: 'kcal', value: '${scaled.calories}', color: colors.accent),
              _Pill(label: 'protein', value: '${scaled.protein}g', color: MacroColors.protein),
              _Pill(label: 'carbs', value: '${scaled.carbs}g', color: MacroColors.carbs),
              _Pill(label: 'fat', value: '${scaled.fat}g', color: MacroColors.fat),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.of(context).pop(_servings),
              child: const Text('Add to diary', style: TextStyle(color: Color(0xFF04120A), fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  String _trim(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.border),
        ),
        child: Icon(icon, color: colors.text),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Pill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
      Text(label, style: TextStyle(fontSize: 13, color: context.colors.textSecondary)),
    ]);
  }
}

/// What the Quick Add sheet returns: a name, typed-in macros, and whether to
/// keep it in My Foods for reuse.
class _QuickAddValues {
  final String name;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final bool save;
  const _QuickAddValues({
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.save,
  });
}

/// Logs a food that isn't in the catalog by typing the numbers straight in.
/// Only calories are required — macros default to 0 so a rough entry stays quick.
class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet();

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _name = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  bool _save = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  /// Parses a typed number, treating blank/garbage as 0 rather than NaN.
  int _toNumber(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    final parsed = double.tryParse(cleaned);
    return parsed == null || !parsed.isFinite ? 0 : parsed.round();
  }

  void _confirm() {
    final kcal = _toNumber(_calories.text);
    if (kcal <= 0) {
      setState(() => _error = 'Enter how many calories this was.');
      return;
    }
    // Saving to My Foods needs a name to find it by later.
    if (_save && _name.text.trim().isEmpty) {
      setState(() => _error = 'Give it a name to save it to My Foods.');
      return;
    }
    Navigator.of(context).pop(_QuickAddValues(
      name: _name.text.trim(),
      calories: kcal,
      protein: _toNumber(_protein.text),
      carbs: _toNumber(_carbs.text),
      fat: _toNumber(_fat.text),
      save: _save,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: colors.border),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: colors.track, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text('Quick add', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                // Portion helper — for when you're eyeballing the amount.
                TextButton.icon(
                  onPressed: () => showPortionGuide(context),
                  icon: Icon(Icons.straighten, size: 16, color: colors.accent),
                  label: Text('Portion guide',
                      style: TextStyle(color: colors.accent, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('Type the numbers off a label or receipt. Only calories are required.',
                style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            const SizedBox(height: 16),
            Text('Name (optional)', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            const SizedBox(height: 4),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(colors, hint: 'e.g. Lunch at the canteen'),
            ),
            const SizedBox(height: 16),
            _NumberField(
              controller: _calories,
              label: 'Calories (kcal)',
              color: colors.accent,
              autofocus: true,
              onChanged: () {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _NumberField(controller: _protein, label: 'Protein (g)', color: MacroColors.protein)),
              const SizedBox(width: 8),
              Expanded(child: _NumberField(controller: _carbs, label: 'Carbs (g)', color: MacroColors.carbs)),
              const SizedBox(width: 8),
              Expanded(child: _NumberField(controller: _fat, label: 'Fat (g)', color: MacroColors.fat)),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.error_outline, size: 16, color: colors.danger),
                const SizedBox(width: 6),
                Text(_error!, style: TextStyle(color: colors.danger, fontSize: 13)),
              ]),
            ],
            const SizedBox(height: 8),
            // Keep it for reuse — the fix for foods with no official database.
            InkWell(
              onTap: () => setState(() => _save = !_save),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Checkbox(
                      value: _save,
                      onChanged: (v) => setState(() => _save = v ?? false),
                      activeColor: colors.accent,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Save to My Foods',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          Text('Reuse it later without retyping.',
                              style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _confirm,
                child: Text(_save ? 'Save & add to diary' : 'Add to diary',
                    style: const TextStyle(color: Color(0xFF04120A), fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _fieldDecoration(AppColors colors, {String? hint}) => InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: colors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.border),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );

/// A labelled numeric field for Quick Add.
class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final Color color;
  final bool autofocus;
  final VoidCallback? onChanged;
  const _NumberField({
    required this.controller,
    required this.label,
    required this.color,
    this.autofocus = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: color)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => onChanged?.call(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          decoration: _fieldDecoration(colors, hint: '0'),
        ),
      ],
    );
  }
}

/// Edits a saved food in place. Pops with the updated [Food] (same id) or null.
class _EditCustomFoodSheet extends StatefulWidget {
  final Food food;
  const _EditCustomFoodSheet({required this.food});

  @override
  State<_EditCustomFoodSheet> createState() => _EditCustomFoodSheetState();
}

class _EditCustomFoodSheetState extends State<_EditCustomFoodSheet> {
  late final _name = TextEditingController(text: widget.food.name);
  late final _serving = TextEditingController(text: widget.food.serving);
  late final _calories = TextEditingController(text: '${widget.food.calories}');
  late final _protein = TextEditingController(text: '${widget.food.protein}');
  late final _carbs = TextEditingController(text: '${widget.food.carbs}');
  late final _fat = TextEditingController(text: '${widget.food.fat}');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _serving.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  int _toNumber(String text) {
    final parsed = double.tryParse(text.replaceAll(RegExp(r'[^0-9.]'), ''));
    return parsed == null || !parsed.isFinite ? 0 : parsed.round();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'A saved food needs a name.');
      return;
    }
    Navigator.of(context).pop(widget.food.copyWith(
      name: _name.text.trim(),
      serving: _serving.text.trim().isEmpty ? '1 serving' : _serving.text.trim(),
      calories: _toNumber(_calories.text),
      protein: _toNumber(_protein.text),
      carbs: _toNumber(_carbs.text),
      fat: _toNumber(_fat.text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: colors.border),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: colors.track, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Edit food', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Text('Name', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            const SizedBox(height: 4),
            TextField(controller: _name, decoration: _fieldDecoration(colors), textInputAction: TextInputAction.next),
            const SizedBox(height: 12),
            Text('Serving', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            const SizedBox(height: 4),
            TextField(controller: _serving, decoration: _fieldDecoration(colors, hint: 'e.g. 1 cup, 100g')),
            const SizedBox(height: 16),
            _NumberField(controller: _calories, label: 'Calories (kcal)', color: colors.accent),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _NumberField(controller: _protein, label: 'Protein (g)', color: MacroColors.protein)),
              const SizedBox(width: 8),
              Expanded(child: _NumberField(controller: _carbs, label: 'Carbs (g)', color: MacroColors.carbs)),
              const SizedBox(width: 8),
              Expanded(child: _NumberField(controller: _fat, label: 'Fat (g)', color: MacroColors.fat)),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: colors.danger, fontSize: 13)),
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
                child: const Text('Save changes',
                    style: TextStyle(color: Color(0xFF04120A), fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
