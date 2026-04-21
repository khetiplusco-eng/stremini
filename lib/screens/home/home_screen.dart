// home_screen.dart — EXACT MATCH TO SCREENSHOT
// Design: Pure black, teal #0AFFE0 accent, system standby card, toggles, feature grid, bottom nav

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_drawer.dart';
import '../../controllers/home_controller.dart';
import '../../providers/scanner_provider.dart';
import '../../providers/app_settings_provider.dart';
import '../../core/localization/app_strings.dart';
import '../../services/keyboard_service.dart';
import '../chat_screen.dart';
import '../stremini_agent_screen.dart';
import '../settings_screen.dart';
import '../contact_us_screen.dart';
import '../smart_scheduler_screen.dart';
import '../../providers/auth_provider.dart';

// ── Design tokens — exact from screenshot ────────────────────────────────────
const _bg        = Color(0xFF000000);
const _surface   = Color(0xFF0D0D0D);
const _card      = Color(0xFF111111);
const _cardBorder= Color(0xFF1C1C1C);

// Teal accent — exactly from screenshot
const _teal      = Color(0xFF0AFFE0);
const _tealDim   = Color(0xFF071A18);
const _tealMid   = Color(0xFF0AC8B4);

const _green     = Color(0xFF00D084);
const _greenDim  = Color(0xFF071A0F);
const _red       = Color(0xFFFF4D4D);
const _amber     = Color(0xFFFFB547);
const _purple    = Color(0xFFA78BFA);
const _purpleDim = Color(0xFF1A1240);
const _orange    = Color(0xFFFF6B2B);
const _orangeDim = Color(0xFF1A0D06);

const _txt       = Color(0xFFFFFFFF);
const _txtSub    = Color(0xFF8C8C8C);
const _txtDim    = Color(0xFF404040);
const _border    = Color(0xFF1C1C1C);
const _borderSub = Color(0xFF141414);

const _logoPath  = 'lib/img/logo.jpg';

final keyboardServiceProvider =
    Provider<KeyboardService>((ref) => KeyboardService());
final keyboardStatusProvider = FutureProvider<KeyboardStatus>((ref) async {
  return await ref.watch(keyboardServiceProvider).checkKeyboardStatus();
});

TextStyle _t(double size, {
  Color color = _txt,
  FontWeight w = FontWeight.w400,
  double spacing = 0,
  double height = 1.4,
}) => GoogleFonts.dmSans(
  fontSize: size, color: color, fontWeight: w,
  letterSpacing: spacing, height: height,
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeControllerProvider.notifier).checkPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(homeControllerProvider.notifier).checkPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state      = ref.watch(homeControllerProvider);
    final controller = ref.read(homeControllerProvider.notifier);
    final kbStatus   = ref.watch(keyboardStatusProvider);
    final settings   = ref.watch(appSettingsProvider);
    final authState  = ref.watch(authProvider);

    String tr(String key) => AppStrings.t(settings.language, key);

    final displayName = authState.user?.userMetadata?['full_name']?.toString() ??
        authState.user?.email?.split('@').first ?? 'User';

    ref.listen(homeControllerProvider, (_, next) {
      if (next.errorMessage != null) {
        _toast(next.errorMessage!, isError: true);
        controller.clearError();
      }
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: _bg,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        drawer: _buildDrawer(context, tr),
        body: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _topBar(context, state, displayName)),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 24),
                        _standbyCard(state, controller),
                        const SizedBox(height: 20),
                        _sectionLabel('SYSTEM ACCESS'),
                        const SizedBox(height: 12),
                        _accessCard(state, controller),
                        const SizedBox(height: 24),
                        _sectionLabel('ACTIVE FEATURES'),
                        const SizedBox(height: 14),
                        _featuresGrid(context, state, controller, kbStatus),
                        const SizedBox(height: 80),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _bottomNav(context),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _topBar(BuildContext context, HomeState state, String displayName) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        left: 18, right: 18, bottom: 14,
      ),
      color: _bg,
      child: Row(children: [
        Builder(builder: (ctx) => GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); Scaffold.of(ctx).openDrawer(); },
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(9), border: Border.all(color: _border)),
            child: const Icon(Icons.menu_rounded, color: _txtSub, size: 17),
          ),
        )),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('STREMINI AI', style: _t(16, w: FontWeight.w800, spacing: 1.5)),
            Text('AI COMPANION', style: _t(10, color: _txtSub, spacing: 2.0)),
          ]),
        ),
        // Avatar circle
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            border: Border.all(color: _teal, width: 2),
          ),
          child: ClipOval(
            child: Image.asset(_logoPath, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text('U', style: _t(14, w: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Standby card — matches screenshot exactly ──────────────────────────────
  Widget _standbyCard(HomeState state, HomeController controller) {
    final isActive = state.bubbleActive;
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        await controller.toggleBubble(!isActive);
      },
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isActive ? _teal.withOpacity(0.3) : _border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SYSTEM STANDBY', style: _t(10, color: _txtSub, spacing: 2.0)),
          const SizedBox(height: 20),
          Row(children: [
            // Power button circle
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? _tealDim : const Color(0xFF1A1A1A),
                border: Border.all(
                  color: isActive ? _teal.withOpacity(0.4) : _border,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.power_settings_new_rounded,
                color: isActive ? _teal : _txtSub,
                size: 28,
              ),
            ),
            const SizedBox(width: 20),
            Text(
              isActive ? 'Active' : 'Inactive',
              style: _t(32, w: FontWeight.w700, spacing: -1.0),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Icon(Icons.auto_awesome_outlined,
                color: isActive ? _teal : _txtDim, size: 15),
            const SizedBox(width: 8),
            Text(
              isActive ? 'Stremini is running.' : 'Tap to activate Stremini.',
              style: _t(13, color: isActive ? _tealMid : _txtSub),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Section label ──────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Row(children: [
    Container(width: 3, height: 14, color: _teal, margin: const EdgeInsets.only(right: 10)),
    Text(text, style: _t(11, color: _txtSub, w: FontWeight.w700, spacing: 2.0)),
  ]);

  // ── System access card — with toggles matching screenshot ─────────────────
  Widget _accessCard(HomeState state, HomeController controller) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        _accessRow(
          iconBg: const Color(0xFF0D1A2E),
          icon: Icons.layers_outlined,
          iconColor: const Color(0xFF4A9EFF),
          title: 'Screen Overlay',
          subtitle: 'Required for floating widget',
          enabled: state.permissionStatus.hasOverlay,
          onToggle: (v) => controller.requestOverlayPermission(),
          isLast: false,
        ),
        _divider(),
        _accessRow(
          iconBg: const Color(0xFF1A0D2E),
          icon: Icons.settings_outlined,
          iconColor: _purple,
          title: 'Accessibility',
          subtitle: 'AI needs to read screen',
          enabled: state.permissionStatus.hasAccessibility,
          onToggle: (v) => _requestAccessibilityPermissionWithPrompt(controller),
          isLast: false,
        ),
        _divider(),
        _accessRow(
          iconBg: const Color(0xFF0D1A2E),
          icon: Icons.keyboard_outlined,
          iconColor: const Color(0xFF4A9EFF),
          title: 'AI Keyboard',
          subtitle: 'Smart typing assistance',
          enabled: state.permissionStatus.hasMicrophone,
          onToggle: (v) => controller.requestMicrophonePermission(),
          isLast: true,
        ),
      ]),
    );
  }

  Widget _accessRow({
    required Color iconBg,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required bool isLast,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _t(14, w: FontWeight.w600)),
          Text(subtitle, style: _t(12, color: _txtSub)),
        ])),
        Switch(
          value: enabled,
          onChanged: onToggle,
          activeColor: _teal,
          activeTrackColor: _tealDim,
          inactiveThumbColor: _txtDim,
          inactiveTrackColor: const Color(0xFF1A1A1A),
        ),
      ]),
    );
  }

  Widget _divider() => Container(
    height: 0.5, color: _borderSub,
    margin: const EdgeInsets.symmetric(horizontal: 18),
  );

  // ── Features grid — 2×2 matching screenshot ───────────────────────────────
  Widget _featuresGrid(BuildContext context, HomeState state, HomeController controller, AsyncValue<KeyboardStatus> kbStatus) {
    return Column(children: [
      Row(children: [
        Expanded(child: _featureCard(
          iconBg: const Color(0xFF1A1200),
          icon: Icons.bolt_rounded,
          iconColor: _amber,
          title: 'Auto Tasker',
          subtitle: 'Device actions',
          onTap: _handleScamDetectionTap,
        )),
        const SizedBox(width: 12),
        Expanded(child: _featureCard(
          iconBg: const Color(0xFF071A18),
          icon: Icons.code_rounded,
          iconColor: _teal,
          title: 'GitHub Agent',
          subtitle: 'Autonomous Ops',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StreminiAgentScreen())),
        )),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _featureCard(
          iconBg: const Color(0xFF1A0A0A),
          icon: Icons.shield_outlined,
          iconColor: _red,
          title: 'Scam Detection',
          subtitle: 'Real-time warning',
          onTap: _handleScamDetectionTap,
        )),
        const SizedBox(width: 12),
        Expanded(child: kbStatus.when(
          data: (s) => _featureCard(
            iconBg: const Color(0xFF0D1A2E),
            icon: Icons.keyboard_outlined,
            iconColor: const Color(0xFF4A9EFF),
            title: 'AI Keyboard',
            subtitle: 'Smart assist',
            onTap: _openKeyboardSetup,
          ),
          loading: () => _featureCard(
            iconBg: const Color(0xFF0D1A2E),
            icon: Icons.keyboard_outlined,
            iconColor: const Color(0xFF4A9EFF),
            title: 'AI Keyboard',
            subtitle: 'Checking...',
            onTap: _openKeyboardSetup,
          ),
          error: (_, __) => _featureCard(
            iconBg: const Color(0xFF0D1A2E),
            icon: Icons.keyboard_outlined,
            iconColor: const Color(0xFF4A9EFF),
            title: 'AI Keyboard',
            subtitle: 'Setup needed',
            onTap: _openKeyboardSetup,
          ),
        )),
      ]),
    ]);
  }

  Widget _featureCard({
    required Color iconBg,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 16),
          Text(title, style: _t(14, w: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle, style: _t(11, color: _txtSub)),
        ]),
      ),
    );
  }

  // ── Bottom nav — matches screenshot exactly ────────────────────────────────
  Widget _bottomNav(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 12, top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(top: BorderSide(color: _border, width: 0.5)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _navItem(icon: Icons.home_outlined, index: 0, onTap: () => setState(() => _selectedTab = 0)),
        _navItem(
          icon: Icons.code_rounded, index: 1,
          onTap: () { setState(() => _selectedTab = 1); Navigator.push(context, MaterialPageRoute(builder: (_) => StreminiAgentScreen())); },
        ),
        _navItem(
          icon: Icons.chat_bubble_outline_rounded, index: 2,
          onTap: () { setState(() => _selectedTab = 2); Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())); },
        ),
        _navItem(
          icon: Icons.settings_outlined, index: 3,
          onTap: () { setState(() => _selectedTab = 3); Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); },
        ),
      ]),
    );
  }

  Widget _navItem({required IconData icon, required int index, required VoidCallback onTap}) {
    final selected = _selectedTab == index;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: selected ? _teal : _txtDim, size: 22),
          if (selected) ...[
            const SizedBox(height: 4),
            Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: _teal)),
          ],
        ]),
      ),
    );
  }

  // ── Toast ──────────────────────────────────────────────────────────────────
  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: _t(13)),
      backgroundColor: _card,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isError ? _red : _border, width: 1),
      ),
    ));
  }

  // ── Drawer ─────────────────────────────────────────────────────────────────
  Widget _buildDrawer(BuildContext context, String Function(String) tr) {
    void close() => Scaffold.maybeOf(context)?.closeDrawer();
    return AppDrawer(items: [
      AppDrawerItem(icon: Icons.home_outlined, title: 'Home', onTap: close),
      AppDrawerItem(icon: Icons.calendar_today_outlined, title: 'Smart Scheduler',
          onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartSchedulerScreen())); }),
      AppDrawerItem(icon: Icons.code_rounded, title: 'GitHub Agent',
          onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => StreminiAgentScreen())); }),
      AppDrawerItem(icon: Icons.chat_bubble_outline, title: 'Quick Chat',
          onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())); }),
      AppDrawerItem(icon: Icons.keyboard_outlined, title: 'AI Keyboard',
          onTap: () async { close(); await _openKeyboardSetup(); }),
      AppDrawerItem(icon: Icons.settings_outlined, title: tr('settings'),
          onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); }),
      AppDrawerItem(icon: Icons.help_outline, title: 'Contact Us',
          onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactUsScreen())); }),
      AppDrawerItem(icon: Icons.logout_outlined, title: 'Sign Out',
          onTap: () { close(); ref.read(authProvider.notifier).signOut(); }),
    ]);
  }

  // ── Handlers (UNCHANGED logic) ─────────────────────────────────────────────
  Future<void> _handleScamDetectionTap() async {
    final scannerNotifier = ref.read(scannerStateProvider.notifier);
    await scannerNotifier.toggleScanning();
    if (!mounted) return;
    final scannerState = ref.read(scannerStateProvider);
    _toast(scannerState.error ?? (scannerState.isActive ? 'Scam detection started' : 'Scam detection stopped'),
        isError: scannerState.error != null);
  }

  Future<void> _openKeyboardSetup() async {
    final service = ref.read(keyboardServiceProvider);
    final status  = await service.checkKeyboardStatus();
    if (!status.isEnabled) { await service.openKeyboardSettings(); return; }
    if (!status.isSelected) { await service.showKeyboardPicker(); return; }
    if (!mounted) return;
    _toast('AI Keyboard is already active');
  }

  Future<void> _requestAccessibilityPermissionWithPrompt(HomeController controller) async {
    final ok = await _showAccessibilityDialog();
    if (ok == true) await controller.requestAccessibilityPermission();
  }

  Future<bool?> _showAccessibilityDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: _tealDim, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _teal.withOpacity(0.25))),
              child: const Icon(Icons.accessibility_new_outlined, color: _teal, size: 20),
            ),
            const SizedBox(height: 16),
            Text('Accessibility Service', style: _t(18, w: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Stremini uses Accessibility Service to protect you from scams in real-time. It reads visible text on screen to detect fraud patterns and trigger alerts while you browse.',
                style: _t(13, color: _txtSub)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(ctx, false),
                child: Container(height: 44,
                  decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                  child: Center(child: Text('Not now', style: _t(14, color: _txtSub, w: FontWeight.w600))),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(height: 44,
                  decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text('Continue', style: _t(14, color: Colors.black, w: FontWeight.w700))),
                ),
              )),
            ]),
          ]),
        ),
      ),
    );
  }
}
