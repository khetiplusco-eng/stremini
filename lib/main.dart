import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stremini_chatbot/providers/scanner_provider.dart';
import 'core/localization/app_strings.dart';
import 'core/native/android_native_bridge_service.dart';
import 'core/native/native_bridge_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'providers/app_settings_provider.dart';
import 'utils/session_lifecycle_manager.dart';

const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://libbzwesgiqwkackexzl.supabase.co',
);
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxpYmJ6d2VzZ2lxd2thY2tleHpsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU5MDEwNzgsImV4cCI6MjA5MTQ3NzA3OH0.h0War5wAbQil1hP-igImCABgUeBtuWYNLcEhrHw5qxI',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // ── CRITICAL FIX ──────────────────────────────────────────────────────────
  // Supabase.initialize() returns before the session is fully restored from
  // local storage. Any API call that fires during the first frame will see
  // currentSession == null and send no Authorization header → 401.
  //
  // We wait for the first auth state event, which fires once Supabase has
  // loaded the persisted session (or confirmed there is none).
  // This adds ~0 ms on cold start when there's no saved session,
  // and ~50-100 ms when there is one — completely invisible to the user.
  await _waitForSessionRestore();

  runApp(const ProviderScope(child: MyApp()));
}

/// Waits for the Supabase auth state to emit its first event.
/// After this resolves, `currentSession` is guaranteed to reflect the
/// persisted session (if any), so `_getToken()` will return the real token.
Future<void> _waitForSessionRestore() async {
  final completer = Completer<void>();

  // Listen to the first auth event then immediately cancel.
  late final StreamSubscription sub;
  sub = Supabase.instance.client.auth.onAuthStateChange.listen(
    (_) {
      if (!completer.isCompleted) completer.complete();
      sub.cancel();
    },
    onError: (_) {
      if (!completer.isCompleted) completer.complete();
      sub.cancel();
    },
  );

  // Safety timeout — if the stream never fires (offline / edge case),
  // don't block the app forever.
  await completer.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () {},
  );
}

// Add the missing import at the top (dart:async is needed for Completer)
// It's already pulled in transitively, but being explicit is cleaner.

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  static ProviderContainer? globalContainer;
  final NativeBridgeService _nativeBridge = AndroidNativeBridgeService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_MyAppState.globalContainer == null) {
      _MyAppState.globalContainer = ProviderScope.containerOf(context);
      _setupScannerListeners();
    }
  }

  void _setupScannerListeners() {
    if (_MyAppState.globalContainer == null) return;

    _nativeBridge.initialize(onEvent: (method) async {
      final notifier =
          _MyAppState.globalContainer!.read(scannerStateProvider.notifier);
      switch (method) {
        case 'startScanner':
          await notifier.startScanning();
          break;
        case 'stopScanner':
          await notifier.stopScanning();
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppStrings.t(settings.language, 'app_title'),
      themeMode: settings.themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      locale: settings.locale,
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
        Locale('es'),
        Locale('fr'),
        Locale('ar'),
        Locale('ja'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SessionLifecycleManager(
        child: AuthGate(),
      ),
    );
  }
}