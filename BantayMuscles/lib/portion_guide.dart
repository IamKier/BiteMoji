import 'package:flutter/material.dart';

import 'theme.dart';

/// A read-only cheat sheet for eyeballing amounts when you don't have a scale or
/// a label — hand-size references plus a few common Filipino calorie anchors.
/// Opened from Quick add so you can estimate, then type the number in.
Future<void> showPortionGuide(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PortionGuideSheet(),
  );
}

// (reference, what it's roughly equal to)
const _handGuides = <(String, String)>[
  ('Palm of your hand', '≈ 100 g cooked meat or fish'),
  ('Cupped hand', '≈ 1 cup rice / noodles'),
  ('Closed fist', '≈ 1 cup — rice, veg, or fruit'),
  ('Thumb (whole)', '≈ 1 tbsp — oil, mayo, peanut butter'),
  ('Thumb tip', '≈ 1 tsp — sugar, oil'),
  ('Deck of cards', '≈ 85–100 g meat'),
  ('Golf ball', '≈ ¼ cup — nuts, dried fruit'),
];

// (food, per-amount calories) — quick anchors for local staples.
const _calorieAnchors = <(String, String)>[
  ('White rice (kanin)', '1 cup ≈ 205 kcal'),
  ('Cooking oil', '1 tbsp ≈ 120 kcal'),
  ('Pandesal', '1 pc ≈ 100 kcal'),
  ('Fried egg', '1 pc ≈ 90 kcal'),
  ('Pork belly / liempo', '100 g ≈ 366 kcal'),
  ('Sugar', '1 tsp ≈ 16 kcal'),
];

class _PortionGuideSheet extends StatelessWidget {
  const _PortionGuideSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: colors.border),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.of(context).padding.bottom),
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
            const Text('Portion guide', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('No scale? Estimate with your hand, then type the amount in.',
                style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            const SizedBox(height: 16),
            const _GuideGroup(title: 'EYEBALL A PORTION', icon: Icons.back_hand_outlined, rows: _handGuides),
            const SizedBox(height: 16),
            const _GuideGroup(title: 'QUICK CALORIE ANCHORS', icon: Icons.local_fire_department_outlined, rows: _calorieAnchors),
            const SizedBox(height: 8),
            Text('Estimates for guidance, not exact figures.',
                style: TextStyle(fontSize: 12, color: colors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _GuideGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<(String, String)> rows;
  const _GuideGroup({required this.title, required this.icon, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 16, color: colors.accent),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: colors.textSecondary, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 8),
        for (final (ref, meaning) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Text(ref, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: Text(meaning,
                      style: TextStyle(fontSize: 14, color: colors.textSecondary)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
