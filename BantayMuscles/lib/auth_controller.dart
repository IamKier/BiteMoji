import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'remote_config.dart';

/// Thin wrapper over Supabase email/password auth. Exposes the current user and
/// notifies listeners on sign-in/out. No-ops cleanly when Supabase isn't
/// configured, so the app still runs fully local/offline.
class AuthController extends ChangeNotifier {
  User? _user;
  StreamSubscription<AuthState>? _sub;

  AuthController() {
    if (!isConfigured) return;
    final auth = Supabase.instance.client.auth;
    _user = auth.currentUser;
    _sub = auth.onAuthStateChange.listen((state) {
      _user = state.session?.user;
      notifyListeners();
    });
  }

  /// True only when a Supabase URL + key are set (see remote_config.dart).
  bool get isConfigured => kSupabaseUrl.isNotEmpty && kSupabaseAnonKey.isNotEmpty;

  User? get user => _user;
  bool get signedIn => _user != null;
  String? get email => _user?.email;

  /// Signs in. Returns null on success, or a user-facing error message.
  Future<String?> signIn(String email, String password) async {
    if (!isConfigured) return 'Accounts aren’t available in this build.';
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email.trim(), password: password);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'Couldn’t sign in. Check your connection and try again.';
    }
  }

  /// Result of a sign-up attempt: [error] set means it failed; otherwise
  /// [needsConfirmation] tells the UI whether to prompt the user to confirm
  /// their email before they're logged in.
  Future<({String? error, bool needsConfirmation})> signUp(
      String email, String password) async {
    if (!isConfigured) return (error: 'Accounts aren’t available in this build.', needsConfirmation: false);
    try {
      final res = await Supabase.instance.client.auth
          .signUp(email: email.trim(), password: password);
      return (error: null, needsConfirmation: res.session == null);
    } on AuthException catch (e) {
      return (error: e.message, needsConfirmation: false);
    } catch (_) {
      return (error: 'Couldn’t sign up. Check your connection and try again.', needsConfirmation: false);
    }
  }

  Future<void> signOut() async {
    if (!isConfigured) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
