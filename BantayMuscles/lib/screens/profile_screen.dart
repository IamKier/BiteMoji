import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth_controller.dart';
import '../models/nutrition.dart';
import '../store.dart';
import '../sync_service.dart';
import '../theme.dart';
import '../update_prompt.dart';
import '../updater.dart';
import '../widgets/app_card.dart';

const _activityLabels = {
  ActivityLevel.sedentary: ('Sedentary', 'Desk job, little exercise'),
  ActivityLevel.light: ('Light', 'Exercise 1-3 days/week'),
  ActivityLevel.moderate: ('Moderate', 'Exercise 3-5 days/week'),
  ActivityLevel.active: ('Active', 'Exercise 6-7 days/week'),
  ActivityLevel.athlete: ('Athlete', 'Hard training, physical job'),
};

const _goalLabels = {
  Goal.lose: ('Lose weight', '-500 kcal/day'),
  Goal.maintain: ('Maintain', 'Stay at your current weight'),
  Goal.gain: ('Gain muscle', '+300 kcal/day surplus'),
};

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final colors = context.colors;
    final p = store.profile;
    final goals = store.goals;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          const Text('Profile', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          const _AccountCard(),
          // Target
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily target', style: TextStyle(fontSize: 14, color: colors.textSecondary)),
                Text('${goals.calories} kcal',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: colors.accent)),
                const SizedBox(height: 4),
                Row(children: [
                  Text('${goals.protein}g protein', style: const TextStyle(color: MacroColors.protein)),
                  const SizedBox(width: 16),
                  Text('${goals.carbs}g carbs', style: const TextStyle(color: MacroColors.carbs)),
                  const SizedBox(width: 16),
                  Text('${goals.fat}g fat', style: const TextStyle(color: MacroColors.fat)),
                ]),
                const SizedBox(height: 8),
                Text('BMR ${bmr(p).round()} · maintenance ${tdee(p).round()} kcal · BMI ${bmi(p).toStringAsFixed(1)} (${bmiCategory(bmi(p))})',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // About you
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('About you', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(children: [
                  for (final s in Sex.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Chip(
                          label: s.name[0].toUpperCase() + s.name.substring(1),
                          selected: p.sex == s,
                          onTap: () => store.updateProfile(p.copyWith(sex: s)),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _NumberField(label: 'Age', unit: 'yrs', value: p.age, onChanged: (v) => store.updateProfile(p.copyWith(age: v)))),
                  const SizedBox(width: 12),
                  Expanded(child: _NumberField(label: 'Height', unit: 'cm', value: p.heightCm, onChanged: (v) => store.updateProfile(p.copyWith(heightCm: v)))),
                  const SizedBox(width: 12),
                  Expanded(child: _NumberField(label: 'Weight', unit: 'kg', value: p.weightKg.round(), onChanged: (v) => store.updateProfile(p.copyWith(weightKg: v.toDouble())))),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Activity
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Activity level', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                for (final a in ActivityLevel.values)
                  _OptionRow(
                    label: _activityLabels[a]!.$1,
                    hint: _activityLabels[a]!.$2,
                    selected: p.activity == a,
                    onTap: () => store.updateProfile(p.copyWith(activity: a)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Goal
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Goal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                for (final g in Goal.values)
                  _OptionRow(
                    label: _goalLabels[g]!.$1,
                    hint: _goalLabels[g]!.$2,
                    selected: p.goal == g,
                    onTap: () => store.updateProfile(p.copyWith(goal: g)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _CustomTargetCard(),
          const SizedBox(height: 16),
          const _WeightCard(),
          const SizedBox(height: 16),
          // Appearance
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Appearance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(children: [
                  for (final m in ThemeMode.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Chip(
                          label: switch (m) {
                            ThemeMode.system => 'System',
                            ThemeMode.light => 'Light',
                            ThemeMode.dark => 'Dark',
                          },
                          selected: store.themeMode == m,
                          onTap: () => store.setThemeMode(m),
                        ),
                      ),
                    ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _BackupCard(),
          const SizedBox(height: 16),
          const _AboutCard(),
        ],
      ),
    );
  }
}

/// Account card: sign in / create account to sync data across devices, or show
/// the signed-in email + sync status + sign out. Hidden entirely when Supabase
/// isn't configured (the app then stays fully local).
class _AccountCard extends StatefulWidget {
  const _AccountCard();

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  // Login stays hidden until the user chooses to link an account — the app is
  // local-only by default.
  bool _expanded = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final error = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _signIn(AuthController auth) =>
      _run(() => auth.signIn(_email.text, _password.text));

  Future<void> _signUp(AuthController auth) => _run(() async {
        final res = await auth.signUp(_email.text, _password.text);
        if (res.error == null && res.needsConfirmation && mounted) {
          setState(() => _notice = 'Check your email to confirm, then sign in.');
        }
        return res.error;
      });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (!auth.isConfigured) return const SizedBox.shrink();

    final Widget body;
    if (auth.signedIn) {
      body = _signedIn(context, auth);
    } else if (_expanded) {
      body = _signedOut(context, auth);
    } else {
      body = _linkPrompt(context); // opt-in entry point; no login shown yet
    }

    return Column(
      children: [
        AppCard(child: body),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Collapsed, opt-in entry point. Login fields appear only after this is
  /// tapped, so a user who never wants an account never sees a login form.
  Widget _linkPrompt(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => setState(() {
        _expanded = true;
        _error = null;
        _notice = null;
      }),
      child: Row(
        children: [
          Icon(Icons.cloud_outlined, color: colors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sync across devices', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('Optional — link an account to back up your data.',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colors.textSecondary),
        ],
      ),
    );
  }

  Widget _signedIn(BuildContext context, AuthController auth) {
    final colors = context.colors;
    final sync = context.watch<SyncService>();
    final (statusText, statusColor) = switch (sync.status) {
      SyncStatus.syncing => ('Syncing…', colors.textSecondary),
      SyncStatus.synced => ('Synced', colors.accent),
      SyncStatus.offline => ('Offline — will sync when back online', colors.textSecondary),
      SyncStatus.idle => ('Synced to your account', colors.textSecondary),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.cloud_done_outlined, color: colors.accent),
          const SizedBox(width: 8),
          const Expanded(child: Text('Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 4),
        Text(auth.email ?? 'Signed in', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
        const SizedBox(height: 2),
        Row(children: [
          Icon(Icons.sync, size: 14, color: statusColor),
          const SizedBox(width: 4),
          Flexible(child: Text(statusText, style: TextStyle(fontSize: 12, color: statusColor))),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: BorderSide(color: colors.border), padding: const EdgeInsets.symmetric(vertical: 12)),
            icon: Icon(Icons.logout, size: 18, color: colors.text),
            label: Text('Sign out', style: TextStyle(color: colors.text)),
            onPressed: _busy ? null : () => auth.signOut(),
          ),
        ),
      ],
    );
  }

  Widget _signedOut(BuildContext context, AuthController auth) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Save your data', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Not now',
              icon: Icon(Icons.close, size: 20, color: colors.textSecondary),
              onPressed: _busy ? null : () => setState(() => _expanded = false),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Sign in to back up your diary and carry it to a new phone.',
            style: TextStyle(fontSize: 13, color: colors.textSecondary)),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: _authField(colors, hint: 'Email', icon: Icons.mail_outline),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: _authField(colors, hint: 'Password', icon: Icons.lock_outline),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: colors.danger, fontSize: 13)),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 8),
          Text(_notice!, style: TextStyle(color: colors.accent, fontSize: 13)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _busy ? null : () => _signIn(auth),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Sign in', style: TextStyle(color: Color(0xFF04120A), fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(side: BorderSide(color: colors.border), padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: _busy ? null : () => _signUp(auth),
              child: Text('Create account', style: TextStyle(color: colors.text)),
            ),
          ),
        ]),
      ],
    );
  }

  InputDecoration _authField(AppColors colors, {required String hint, required IconData icon}) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        isDense: true,
        filled: true,
        fillColor: colors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.border)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}

/// App version + a manual "Check for updates" (pulls from GitHub Releases).
class _AboutCard extends StatefulWidget {
  const _AboutCard();

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    currentVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    await checkAndPromptUpdate(context, manual: true);
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('About', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('BantayMuscles${_version.isNotEmpty ? '  ·  v$_version' : ''}',
              style: TextStyle(fontSize: 13, color: colors.textSecondary)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: _checking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.system_update, size: 18, color: colors.text),
              label: Text(_checking ? 'Checking…' : 'Check for updates',
                  style: TextStyle(color: colors.text)),
              onPressed: _checking ? null : _check,
            ),
          ),
        ],
      ),
    );
  }
}

/// Log today's body weight and see recent history. The latest entry also becomes
/// the profile weight used for goal math.
class _WeightCard extends StatefulWidget {
  const _WeightCard();

  @override
  State<_WeightCard> createState() => _WeightCardState();
}

class _WeightCardState extends State<_WeightCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _log(AppStore store) {
    final kg = double.tryParse(_controller.text.trim());
    if (kg == null || kg <= 0) return;
    store.setWeightForDate(store.today, kg);
    _controller.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final colors = context.colors;
    // Most recent entries first.
    final recent = (store.weights.entries.toList()
          ..sort((a, b) => b.key.compareTo(a.key)))
        .take(5)
        .toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Weight', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            store.latestWeight != null
                ? 'Latest ${store.latestWeight!.toStringAsFixed(1)} kg'
                : 'No weight logged yet',
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                  hintText: "Today's weight",
                  suffixText: 'kg',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onSubmitted: (_) => _log(store),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _log(store),
                child: const Text('Log', style: TextStyle(color: Color(0xFF04120A), fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final e in recent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatDateLabel(e.key), style: TextStyle(color: colors.textSecondary)),
                    Row(children: [
                      Text('${e.value.toStringAsFixed(1)} kg',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.close, size: 16, color: colors.textSecondary),
                        onPressed: () => store.removeWeightForDate(e.key),
                      ),
                    ]),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Override the calculated daily calorie target with a fixed number.
class _CustomTargetCard extends StatelessWidget {
  const _CustomTargetCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final colors = context.colors;
    final p = store.profile;
    final custom = p.customCalories != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Custom calorie target',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Switch(
                value: custom,
                activeThumbColor: colors.accent,
                onChanged: (on) => store.updateProfile(on
                    ? p.copyWith(customCalories: calorieGoal(p.copyWith(clearCustom: true)))
                    : p.copyWith(clearCustom: true)),
              ),
            ],
          ),
          Text(
            custom
                ? 'Using a fixed target instead of your calculated goal.'
                : 'Off — target is calculated from your profile and goal.',
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          if (custom) ...[
            const SizedBox(height: 12),
            _NumberField(
              label: 'Target',
              unit: 'kcal',
              value: p.customCalories ?? calorieGoal(p),
              onChanged: (v) => store.updateProfile(p.copyWith(customCalories: v)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Export all data to the clipboard as JSON, or restore from a pasted backup.
class _BackupCard extends StatelessWidget {
  const _BackupCard();

  Future<void> _export(BuildContext context, AppStore store) async {
    await Clipboard.setData(ClipboardData(text: store.exportData()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup copied to clipboard')),
    );
  }

  Future<void> _import(BuildContext context, AppStore store) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final raw = data?.text?.trim() ?? '';
    final messenger = ScaffoldMessenger.of(context);
    if (raw.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
      return;
    }
    final ok = store.importData(raw);
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? 'Backup restored' : 'That doesn’t look like a valid backup'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Backup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Copy all your data as JSON, or restore from a pasted backup.',
              style: TextStyle(fontSize: 13, color: colors.textSecondary)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: Icon(Icons.copy, size: 18, color: colors.text),
                label: Text('Export', style: TextStyle(color: colors.text)),
                onPressed: () => _export(context, store),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: Icon(Icons.paste, size: 18, color: colors.text),
                label: Text('Import', style: TextStyle(color: colors.text)),
                onPressed: () => _import(context, store),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final String unit;
  final int value;
  final ValueChanged<int> onChanged;
  const _NumberField({required this.label, required this.unit, required this.value, required this.onChanged});

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _controller = TextEditingController(text: '${widget.value}');

  /// Follow changes made elsewhere — logging a weight rewrites the profile, and
  /// this box has to show it. The parse check keeps the field from being
  /// rewritten (and the caret thrown to the start) while someone is typing in it.
  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value &&
        int.tryParse(_controller.text) != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: TextStyle(fontSize: 14, color: colors.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            suffixText: widget.unit,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.border),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (t) {
            final n = int.tryParse(t);
            if (n != null && n > 0) widget.onChanged(n);
          },
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

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
          color: selected ? colors.accentMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? colors.accent : colors.border),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? colors.accent : colors.textSecondary,
            )),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;
  const _OptionRow({required this.label, required this.hint, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                  Text(hint, style: TextStyle(fontSize: 14, color: colors.textSecondary)),
                ],
              ),
            ),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20, color: selected ? colors.accent : colors.textSecondary),
          ],
        ),
      ),
    );
  }
}
