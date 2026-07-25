import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../activity.dart';
import '../models/nutrition.dart';
import '../pedometer_service.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/app_card.dart';
import '../widgets/calorie_ring.dart';
import '../widgets/macro_bar.dart';

const _mealIcons = {
  MealType.breakfast: Icons.wb_sunny_outlined,
  MealType.lunch: Icons.restaurant_outlined,
  MealType.dinner: Icons.nightlight_outlined,
  MealType.snack: Icons.cookie_outlined,
};

class TodayScreen extends StatelessWidget {
  final void Function(MealType meal) onAddFood;
  const TodayScreen({super.key, required this.onAddFood});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final colors = context.colors;
    final date = store.selectedDate;
    final totals = store.totalsForDate(date);
    final goals = store.goals;
    final grouped = store.groupedForDate(date);
    final entries = store.entriesForDate(date);
    final isToday = date == store.today;
    // Steps earn back calories, so they raise the day's budget rather than just
    // being reported in the steps card.
    final burned = caloriesFromSteps(store.stepsForDate(date), store.profile.weightKg);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Date header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => store.shiftDate(-1),
                  icon: Icon(Icons.chevron_left, color: colors.textSecondary),
                ),
                GestureDetector(
                  onTap: () => store.setSelectedDate(store.today),
                  child: Text(formatDateLabel(date),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  onPressed: isToday ? null : () => store.shiftDate(1),
                  icon: Icon(Icons.chevron_right, color: isToday ? colors.track : colors.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              children: [
                // Summary
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: Column(
                    children: [
                      CalorieRing(
                          consumed: totals.calories,
                          goal: goals.calories,
                          burned: burned),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: MacroBar(label: 'Protein', value: totals.protein, goal: goals.protein, color: MacroColors.protein)),
                          const SizedBox(width: 16),
                          Expanded(child: MacroBar(label: 'Carbs', value: totals.carbs, goal: goals.carbs, color: MacroColors.carbs)),
                          const SizedBox(width: 16),
                          Expanded(child: MacroBar(label: 'Fat', value: totals.fat, goal: goals.fat, color: MacroColors.fat)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _StepsCard(date: date),
                const SizedBox(height: 16),
                if (entries.isEmpty) ...[
                  AppCard(
                    child: Column(
                      children: [
                        Icon(Icons.restaurant_outlined, size: 28, color: colors.accent),
                        const SizedBox(height: 8),
                        const Text('Nothing logged yet',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Add what you ate and the ring fills up.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final meal in MealType.values) ...[
                  _MealSection(meal: meal, entries: grouped[meal]!, onAdd: () => onAddFood(meal)),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MealSection extends StatelessWidget {
  final MealType meal;
  final List<Entry> entries;
  final VoidCallback onAdd;
  const _MealSection({required this.meal, required this.entries, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.read<AppStore>();
    final kcal = entries.fold<int>(0, (s, e) => s + e.calories);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(_mealIcons[meal], size: 18, color: colors.textSecondary),
                const SizedBox(width: 8),
                Text(meal.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              Text(kcal > 0 ? '$kcal kcal' : '—',
                  style: TextStyle(fontSize: 14, color: colors.textSecondary)),
            ],
          ),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14)),
                        Text(e.servings == 1 ? e.serving : '${_trim(e.servings)} × ${e.serving}',
                            style: TextStyle(fontSize: 14, color: colors.textSecondary)),
                      ],
                    ),
                  ),
                  Text('${e.calories}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  IconButton(
                    onPressed: () => store.removeEntry(e.id),
                    icon: Icon(Icons.close, size: 18, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: InkWell(
              onTap: onAdd,
              child: Row(
                children: [
                  Icon(Icons.add, size: 18, color: colors.accent),
                  const SizedBox(width: 4),
                  Text('Add food',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.accent)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _trim(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// Steps for the day: hardware pedometer total (while the app is open) plus a
/// manual override, with calories burned and distance.
class _StepsCard extends StatelessWidget {
  final String date;
  const _StepsCard({required this.date});

  Future<void> _editManual(BuildContext context, AppStore store, int current) async {
    final controller = TextEditingController(text: current > 0 ? '$current' : '');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set steps'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Steps', suffixText: 'steps'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final digits = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
              Navigator.pop(ctx, int.tryParse(digits) ?? 0);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) store.setStepsForDate(date, value);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final colors = context.colors;
    final steps = store.stepsForDate(date);
    const goal = kDefaultStepGoal;
    final burned = caloriesFromSteps(steps, store.profile.weightKg);
    final km = distanceFromSteps(steps, store.profile.heightCm);
    final progress = (steps / goal).clamp(0.0, 1.0);

    // Pedometer status only makes sense for today (it counts live).
    final status =
        date == store.today ? context.watch<PedometerService>().status : null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(Icons.directions_walk, size: 18, color: colors.textSecondary),
                const SizedBox(width: 8),
                const Text('Steps', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              if (status != null) _StatusChip(status: status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$steps',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('/ $goal',
                    style: TextStyle(fontSize: 14, color: colors.textSecondary)),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _editManual(context, store, steps),
                icon: Icon(Icons.edit, size: 16, color: colors.accent),
                label: Text('Set', style: TextStyle(color: colors.accent, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colors.track,
              valueColor: AlwaysStoppedAnimation(colors.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text('$burned kcal burned · ${km.toStringAsFixed(2)} km',
              style: TextStyle(fontSize: 13, color: colors.textSecondary)),
          if (status == PedometerStatus.denied)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Enable activity permission to auto-count steps, or set them manually.',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary)),
            ),
          if (status == PedometerStatus.unavailable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('No step sensor detected — enter steps manually.',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary)),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final PedometerStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (label, color) = switch (status) {
      PedometerStatus.active => ('Auto', colors.accent),
      PedometerStatus.checking => ('…', colors.textSecondary),
      PedometerStatus.denied => ('Manual', colors.textSecondary),
      PedometerStatus.unavailable => ('Manual', colors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.accentMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
