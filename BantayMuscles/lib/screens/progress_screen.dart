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
          const _WeightTrendCard(),
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

/// Weight over time — a line chart drawn from the logged body weights. Uses the
/// same hand-painted approach as the rest of the app's charts.
class _WeightTrendCard extends StatelessWidget {
  const _WeightTrendCard();

  String _fmtDate(String key) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final p = key.split('-').map(int.parse).toList();
    return '${months[p[1] - 1]} ${p[2]}';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final colors = context.colors;

    // Oldest → newest, so the line reads left to right.
    final entries = store.weights.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Weight trend', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              if (entries.length >= 2)
                Builder(builder: (_) {
                  final delta = entries.last.value - entries.first.value;
                  final up = delta > 0;
                  final flat = delta.abs() < 0.05;
                  return Text(
                    flat ? 'no change' : '${up ? '+' : '−'}${delta.abs().toStringAsFixed(1)} kg',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: flat ? colors.textSecondary : (up ? colors.danger : colors.accent),
                    ),
                  );
                }),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                entries.isEmpty
                    ? 'Log your weight on the Profile tab to see your trend.'
                    : 'Log at least one more day to see a trend line.',
                style: TextStyle(color: colors.textSecondary),
              ),
            )
          else ...[
            SizedBox(
              height: 140,
              width: double.infinity,
              child: CustomPaint(
                painter: _WeightLinePainter(
                  weights: [for (final e in entries) e.value],
                  line: colors.accent,
                  grid: colors.track,
                  dot: colors.accent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmtDate(entries.first.key),
                    style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                Text('${entries.last.value.toStringAsFixed(1)} kg',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.text)),
                Text(_fmtDate(entries.last.key),
                    style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WeightLinePainter extends CustomPainter {
  final List<double> weights;
  final Color line;
  final Color grid;
  final Color dot;

  _WeightLinePainter({required this.weights, required this.line, required this.grid, required this.dot});

  @override
  void paint(Canvas canvas, Size size) {
    if (weights.length < 2) return;

    var minW = weights.reduce((a, b) => a < b ? a : b);
    var maxW = weights.reduce((a, b) => a > b ? a : b);
    // Pad the range so a flat-ish line isn't glued to an edge.
    if ((maxW - minW).abs() < 1) {
      minW -= 1;
      maxW += 1;
    }
    final range = maxW - minW;

    const pad = 8.0;
    final w = size.width;
    final h = size.height - pad * 2;

    double xAt(int i) => weights.length == 1 ? w / 2 : w * i / (weights.length - 1);
    double yAt(double v) => pad + h * (1 - (v - minW) / range);

    // Horizontal guide lines (top / middle / bottom of the range).
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final frac in [0.0, 0.5, 1.0]) {
      final y = pad + h * frac;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // The weight line.
    final path = Path()..moveTo(xAt(0), yAt(weights[0]));
    for (var i = 1; i < weights.length; i++) {
      path.lineTo(xAt(i), yAt(weights[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots at each logged point.
    final dotPaint = Paint()..color = dot;
    for (var i = 0; i < weights.length; i++) {
      canvas.drawCircle(Offset(xAt(i), yAt(weights[i])), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_WeightLinePainter old) =>
      old.weights != weights || old.line != line || old.grid != grid;
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
