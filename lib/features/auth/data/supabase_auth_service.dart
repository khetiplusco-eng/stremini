import 'package:supabase_flutter/supabase_flutter.dart';

class AuthResult {
  final bool success;
  final String? error;
  final User? user;

  const AuthResult({required this.success, this.error, this.user});
}

class SupabaseAuthService {
  static final SupabaseClient _client = Supabase.instance.client;
  static const String _googleProviderDashboardUrl =
      'https://supabase.com/dashboard/project/libbzwesgiqwkackexzl/auth/providers?provider=Google';
  static const String _expectedGoogleWebClientId =
      '1062300556206-h1hd5cvr3v1mabg0hftcmsvvci615sp9.apps.googleusercontent.com';

  // ── Current user ───────────────────────────────────────────────────────────
  User? get currentUser => _client.auth.currentUser;
  bool get isAuthenticated => currentUser != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ── Email sign up ──────────────────────────────────────────────────────────
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );
      if (response.user != null) {
        return AuthResult(success: true, user: response.user);
      }
      return const AuthResult(
        success: false,
        error: 'Sign up failed. Please check your email for confirmation.',
      );
    } on AuthException catch (e) {
      return AuthResult(success: false, error: _friendlyError(e.message));
    } catch (e) {
      return const AuthResult(
        success: false,
        error: 'Something went wrong. Please try again.',
      );
    }
  }

  // ── Email sign in ──────────────────────────────────────────────────────────
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user != null) {
        return AuthResult(success: true, user: response.user);
      }
      return const AuthResult(success: false, error: 'Sign in failed.');
    } on AuthException catch (e) {
      return AuthResult(success: false, error: _friendlyError(e.message));
    } catch (e) {
      return const AuthResult(
        success: false,
        error: 'Something went wrong. Please try again.',
      );
    }
  }

  // ── Google sign in (Supabase OAuth only) ─────────────────────────────────
  Future<AuthResult> signInWithGoogle() async {
    try {
      const redirectUrl = String.fromEnvironment(
        'SUPABASE_REDIRECT_URL',
        defaultValue: 'stremini://login-callback',
      );
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );
      return const AuthResult(success: true);
    } on AuthException catch (e) {
      return AuthResult(success: false, error: _friendlyError(e.message));
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('auth session missing')) {
        return const AuthResult(
          success: false,
          error:
              'Google sign in did not complete. Verify redirect URL: '
              'stremini://login-callback in Supabase Authentication settings.',
        );
      }
      if (message.contains('provider') ||
          message.contains('configuration') ||
          message.contains('invalid_request')) {
        return AuthResult(
          success: false,
          error:
              'Google provider configuration is invalid. In Supabase Google provider, '
              'set Client ID to:\n$_expectedGoogleWebClientId\nDashboard:\n'
              '$_googleProviderDashboardUrl',
        );
      }
      if (message.contains('network') || message.contains('socket')) {
        return const AuthResult(
          success: false,
          error: 'Network error. Please check your connection and try again.',
        );
      }
      return AuthResult(
        success: false,
        error:
            'Google sign in failed. Verify Supabase Google provider configuration:\n'
            '$_googleProviderDashboardUrl',
      );
    }
  }

  // ── Forgot password ────────────────────────────────────────────────────────
  Future<AuthResult> sendPasswordResetEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      return const AuthResult(success: true);
    } on AuthException catch (e) {
      return AuthResult(success: false, error: _friendlyError(e.message));
    } catch (e) {
      return const AuthResult(
        success: false,
        error: 'Failed to send reset email.',
      );
    }
  }

  // ── Sign out ───────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ── Error mapping ──────────────────────────────────────────────────────────
  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login')) return 'Incorrect email or password.';
    if (lower.contains('email not confirmed'))
      return 'Please confirm your email first.';
    if (lower.contains('already registered'))
      return 'This email is already registered. Try signing in.';
    if (lower.contains('password'))
      return 'Password must be at least 6 characters.';
    if (lower.contains('rate limit'))
      return 'Too many attempts. Please wait a moment.';
    return raw;
  }
}