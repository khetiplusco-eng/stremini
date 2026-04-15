import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_settings_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/scanner_provider.dart';

class SessionLifecycleManager extends ConsumerStatefulWidget {
  final Widget child;

  const SessionLifecycleManager({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<SessionLifecycleManager> createState() => _SessionLifecycleManagerState();
}

class _SessionLifecycleManagerState extends ConsumerState<SessionLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleAutoScan());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _handleAutoScan() async {
    final settings = ref.read(appSettingsProvider);
    if (!settings.autoScan) return;

    final scanner = ref.read(scannerStateProvider.notifier);
    final hasPermission = await ref.read(screenScannerControllerProvider).hasAccessibilityPermission();
    if (!hasPermission) return;

    await scanner.startScanning();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      _handleAutoScan();
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(chatNotifierProvider.notifier).clearChat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}