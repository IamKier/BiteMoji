import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_controller.dart';
import 'store.dart';

enum SyncStatus { idle, syncing, synced, offline }

/// Keeps the local [AppStore] and the signed-in user's cloud snapshot in sync.
///
/// Design: local-first. The device is always the working copy (so the app works
/// offline and when signed out). When signed in, the full data snapshot
/// (AppStore.exportData) is stored as one row per user in the `user_data`
/// table. On sign-in we reconcile by timestamp (newer wins); on each local
/// change we debounce and push. Row-level security keeps each user's row
/// private — the shipped anon key can only touch its own user's row.
class SyncService extends ChangeNotifier {
  final AppStore store;
  final AuthController auth;

  SyncService(this.store, this.auth);

  static const _table = 'user_data';
  static const _kLocalChangedAt = 'bm.sync.local_changed_at';

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;
  DateTime? _lastSyncedAt;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  bool _applyingRemote = false;
  Timer? _debounce;
  String? _reconciledUserId;

  SupabaseClient get _sb => Supabase.instance.client;

  /// Wires listeners and reconciles now if a session is already restored.
  /// Call once after the store has hydrated.
  void start() {
    if (!auth.isConfigured) return;
    auth.addListener(_onAuthChanged);
    store.addListener(_onStoreChanged);
    _onAuthChanged();
  }

  void _setStatus(SyncStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  void _onAuthChanged() {
    final user = auth.user;
    if (user == null) {
      _reconciledUserId = null;
      _setStatus(SyncStatus.idle);
      return;
    }
    if (user.id == _reconciledUserId) return; // already reconciled this session
    _reconciledUserId = user.id;
    unawaited(_reconcile(user.id));
  }

  Future<void> _reconcile(String userId) async {
    _setStatus(SyncStatus.syncing);
    try {
      final row = await _sb
          .from(_table)
          .select('data, updated_at')
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) {
        await _push(userId); // first sign-in on this account: seed from local
        return;
      }

      final cloudUpdated = DateTime.tryParse('${row['updated_at']}')?.toUtc();
      final localChanged = await _localChangedAt();
      final cloudIsNewer = cloudUpdated != null &&
          (localChanged == null || cloudUpdated.isAfter(localChanged));

      if (cloudIsNewer) {
        _applyingRemote = true;
        final data = row['data'];
        store.importData(data is String ? data : jsonEncode(data));
        _applyingRemote = false;
        _lastSyncedAt = cloudUpdated;
        _setStatus(SyncStatus.synced);
      } else {
        await _push(userId);
      }
    } catch (_) {
      _applyingRemote = false;
      _setStatus(SyncStatus.offline);
    }
  }

  void _onStoreChanged() {
    if (_applyingRemote) return; // don't echo a pull back up
    final user = auth.user;
    if (user == null) return;
    unawaited(_markLocalChanged());
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(_push(user.id)));
  }

  Future<void> _push(String userId) async {
    _setStatus(SyncStatus.syncing);
    final now = DateTime.now().toUtc();
    try {
      await _sb.from(_table).upsert({
        'user_id': userId,
        'data': jsonDecode(store.exportData()),
        'updated_at': now.toIso8601String(),
      });
      _lastSyncedAt = now;
      _setStatus(SyncStatus.synced);
    } catch (_) {
      _setStatus(SyncStatus.offline);
    }
  }

  Future<DateTime?> _localChangedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kLocalChangedAt);
    return v == null ? null : DateTime.tryParse(v)?.toUtc();
  }

  Future<void> _markLocalChanged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocalChangedAt, DateTime.now().toUtc().toIso8601String());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    auth.removeListener(_onAuthChanged);
    store.removeListener(_onStoreChanged);
    super.dispose();
  }
}
