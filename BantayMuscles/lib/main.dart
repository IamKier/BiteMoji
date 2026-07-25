import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/nutrition.dart';
import 'pedometer_service.dart';
import 'screens/add_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/today_screen.dart';
import 'store.dart';
import 'theme.dart';
import 'update_prompt.dart';
import 'whats_new.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppStore()..hydrate(),
      child: const BantayMusclesApp(),
    ),
  );
}

class BantayMusclesApp extends StatelessWidget {
  const BantayMusclesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return MaterialApp(
      title: 'BantayMuscles',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: store.themeMode,
      home: store.ready ? const HomeShell() : const _LoadingScreen(),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE4E2DD),
      body: Center(
        child: Text('BM',
            style: TextStyle(fontSize: 72, fontWeight: FontWeight.w900, color: Colors.blue.shade800)),
      ),
    );
  }
}

/// Bottom-tab shell with a floating "island" nav bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  MealType _addMeal = MealType.breakfast;
  late final PedometerService _pedometer;

  @override
  void initState() {
    super.initState();
    _pedometer = PedometerService(context.read<AppStore>());
    _pedometer.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupPrompts());
  }

  /// After the first frame: show the "What's new" sheet if we just updated, then
  /// check GitHub for an even newer release (silent unless one exists).
  Future<void> _runStartupPrompts() async {
    if (!mounted) return;
    await maybeShowWhatsNew(context);
    if (!mounted) return;
    await checkAndPromptUpdate(context);
  }

  @override
  void dispose() {
    _pedometer.dispose();
    super.dispose();
  }

  static const _tabs = [
    _TabDef('Today', Icons.today_outlined, Icons.today),
    _TabDef('Add', Icons.add_circle_outline, Icons.add_circle),
    _TabDef('Progress', Icons.bar_chart_outlined, Icons.bar_chart),
    _TabDef('Profile', Icons.person_outline, Icons.person),
  ];

  void _openAdd(MealType meal) => setState(() {
        _addMeal = meal;
        _index = 1;
      });

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayScreen(onAddFood: _openAdd),
      AddScreen(initialMeal: _addMeal, onAdded: () => setState(() => _index = 0)),
      const ProgressScreen(),
      const ProfileScreen(),
    ];

    return ChangeNotifierProvider<PedometerService>.value(
      value: _pedometer,
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: _IslandNav(
          tabs: _tabs,
          index: _index,
          onSelect: (i) => setState(() => _index = i),
        ),
      ),
    );
  }
}

class _TabDef {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _TabDef(this.label, this.icon, this.activeIcon);
}

class _IslandNav extends StatelessWidget {
  final List<_TabDef> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  const _IslandNav({required this.tabs, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, bottomInset > 0 ? bottomInset : 24),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 14, offset: const Offset(0, 6)),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(child: _NavItem(def: tabs[i], selected: i == index, onTap: () => onSelect(i))),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _TabDef def;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.def, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = selected ? colors.accent : colors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? colors.accentMuted : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(selected ? def.activeIcon : def.icon, size: 22, color: fg),
            ),
            const SizedBox(height: 2),
            Text(def.label,
                style: TextStyle(fontSize: 11, height: 1.2, color: fg, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
