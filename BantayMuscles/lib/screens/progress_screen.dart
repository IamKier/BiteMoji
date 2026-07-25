import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/nutrition.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/app_card.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final colors = context.colors;
    final goal = store.goals.calories;
    final today = store.today;

    const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final days = List.generate(7, (i) {
      final date = shiftDateKey(today, i - 6);
      final p = date.split('-').map(int.parse).toList();
      final weekday = DateTime(p[0], p[1], p[2]).weekday; // 1..7
      return (
        date: date,
        label: dayLetters[weekday - 1],
        calories: store.totalsForDate(date).calories,
      );
    });

    final logged = days.where((d) => d.calories > 0).toList();
    final avg = logged.isEmpty
        ? 0
        : (logged.fold<int>(0, (s, d) => s + d.calories) / logged.length).round();
    final onTarget = logged.where((d) => (d.calories - goal).abs() <= goal * 0.1).length;
    final peak = [goal, ...days.map((d) => d.calories)].reduce((a, b) => a > b ? a : b).toDouble();
    const chartHeight = 140.0;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          const Text('Progress', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Last 7 days', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('Goal $goal kcal', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: chartHeight,
                  child: Stack(
                    children: [
                      // goal line
                      Positioned(
                        top: chartHeight * (1 - goal / peak),
                        left: 0,
                        right: 0,
                        child: Container(height: 1, color: colors.textSecondary.withValues(alpha: 0.4)),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final d in days)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Container(
                                  height: peak > 0
                                      ? (d.calories / peak * chartHeight).clamp(d.calories > 0 ? 4.0 : 0.0, chartHeight)
                                      : 0,
                                  decoration: BoxDecoration(
                                    color: d.calories > goal ? colors.danger : colors.accent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final d in days)
                      Expanded(
                        child: Text(d.label, textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This week', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(children: [
                  _Stat(label: 'Avg calories', value: avg > 0 ? '$avg' : '—', hint: 'per logged day'),
                  _Stat(label: 'On target', value: '$onTarget/${logged.length}', hint: 'within 10%'),
                  _Stat(label: 'Logged', value: '${logged.length}/7', hint: 'days'),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  const _Stat({required this.label, required this.value, required this.hint});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: colors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          Text(hint, style: TextStyle(fontSize: 13, color: colors.textSecondary)),
        ],
      ),
    );
  }
}
