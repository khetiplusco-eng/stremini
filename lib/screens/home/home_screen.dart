// home_screen.dart — PREMIUM REDESIGN
// Design direction: Editorial luxury — Bloomberg meets Vercel dashboard.
// Ultra-tight typographic hierarchy. Surgical whitespace. Every element
// serves a purpose. The accent color is the only pop of life.
// ALL LOGIC IS UNCHANGED — only presentation layer is redesigned.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

// ── Design tokens ─────────────────────────────────────────────────────────────
const _bg         = Color(0xFF080A0C);
const _surface    = Color(0xFF0E1114);
const _card       = Color(0xFF131619);
const _border     = Color(0xFF1E2328);
const _accent     = Color(0xFF23A6E2);
const _accentDim  = Color(0xFF0D2A3A);
const _green      = Color(0xFF22C55E);
const _greenDim   = Color(0xFF0D2818);
const _red        = Color(0xFFEF4444);
const _amber      = Color(0xFFF59E0B);
const _purple     = Color(0xFF8B5CF6);
const _txt        = Color(0xFFF0F2F5);
const _txtSub     = Color(0xFF8A95A3);
const _txtDim     = Color(0xFF454E5A);
const _logoPath   = 'lib/img/logo.jpg';

// ── Typography helpers ────────────────────────────────────────────────────────
TextStyle _label(double size, {Color color = _txtDim, FontWeight w = FontWeight.w600, double spacing = 1.2}) =>
    TextStyle(fontSize: size, color: color, fontWeight: w, letterSpacing: spacing, height: 1.0);

TextStyle _body(double size, {Color color = _txt, FontWeight w = FontWeight.w400}) =>
    TextStyle(fontSize: size, color: color, fontWeight: w, height: 1.5);

// ─────────────────────────────────────────────────────────────────────────────

final keyboardServiceProvider =
    Provider<KeyboardService>((ref) => KeyboardService());
final keyboardStatusProvider = FutureProvider<KeyboardStatus>((ref) async {
  return await ref.watch(keyboardServiceProvider).checkKeyboardStatus();
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shimmerCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeControllerProvider.notifier).checkPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(homeControllerProvider.notifier).checkPermissions();
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final state          = ref.watch(homeControllerProvider);
    final controller     = ref.read(homeControllerProvider.notifier);
    final keyboardStatus = ref.watch(keyboardStatusProvider);
    final settings       = ref.watch(appSettingsProvider);
    final authState      = ref.watch(authProvider);

    String tr(String key) => AppStrings.t(settings.language, key);

    final displayName = authState.user?.userMetadata?['full_name']?.toString() ??
        authState.user?.email?.split('@').first ?? 'User';
    final firstName = displayName.split(' ').first;

    ref.listen(homeControllerProvider, (_, next) {
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.errorMessage!, style: _body(13)),
          backgroundColor: _surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: _red, width: 1),
          ),
        ));
        controller.clearError();
      }
    });

    return Scaffold(
      backgroundColor: _bg,
      drawer: _buildDrawer(context, tr),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildTopBar(context, state)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 32),
                _buildGreetingBlock(firstName, state),
                const SizedBox(height: 32),
                _buildAgentControl(state, controller),
                const SizedBox(height: 24),
                _buildPermissionsBlock(state, controller),
                const SizedBox(height: 32),
                _buildSectionLabel('MODULES'),
                const SizedBox(height: 16),
                _buildModulesGrid(context, state, controller, keyboardStatus),
                const SizedBox(height: 32),
                if (!state.permissionStatus.hasAll) ...[
                  _buildSectionLabel('PERMISSIONS REQUIRED'),
                  const SizedBox(height: 16),
                  _buildPermAlerts(state, controller),
                  const SizedBox(height: 32),
                ],
                const SizedBox(height: 60),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context, HomeState state) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        left: 22, right: 22, bottom: 16,
      ),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(children: [
        Builder(builder: (ctx) => GestureDetector(
          onTap: () => Scaffold.of(ctx).openDrawer(),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _surface, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.menu_rounded, color: _txtSub, size: 18),
          ),
        )),
        const SizedBox(width: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(_logoPath, width: 28, height: 28, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: _accent, borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('STREMINI AI', style: _label(13, color: _txt, spacing: 2.5, w: FontWeight.w800)),
        const Spacer(),
        _buildLivePill(state),
      ]),
    );
  }

  Widget _buildLivePill(HomeState state) {
    final isLive = state.bubbleActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isLive ? _greenDim : _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLive ? _green.withOpacity(0.35) : _border,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 5, height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isLive ? _green : _txtDim,
            boxShadow: isLive ? [BoxShadow(color: _green.withOpacity(0.6), blurRadius: 4, spreadRadius: 1)] : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          isLive ? 'LIVE' : 'IDLE',
          style: _label(9, color: isLive ? _green : _txtDim, spacing: 1.5),
        ),
      ]),
    );
  }

  // ── Greeting block ─────────────────────────────────────────────────────────
  Widget _buildGreetingBlock(String firstName, HomeState state) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_greeting(), style: _body(15, color: _txtSub)),
      const SizedBox(height: 4),
      Text(firstName, style: const TextStyle(
        color: _txt, fontSize: 40, fontWeight: FontWeight.w800,
        letterSpacing: -2.0, height: 1.0,
      )),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.bubbleActive ? _green : _txtDim,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            state.bubbleActive
                ? 'AI agent operational'
                : 'AI agent on standby',
            style: _label(11, color: state.bubbleActive ? _txtSub : _txtDim, spacing: 0),
          ),
        ]),
      ),
    ]);
  }

  // ── Agent control card ─────────────────────────────────────────────────────
  Widget _buildAgentControl(HomeState state, HomeController controller) {
    final isActive = state.bubbleActive;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? _accent.withOpacity(0.2) : _border,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isActive ? _accentDim : _card,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: isActive ? _accent.withOpacity(0.3) : _border,
              ),
            ),
            child: Icon(
              isActive ? Icons.memory_rounded : Icons.power_settings_new_rounded,
              color: isActive ? _accent : _txtDim, size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              isActive ? 'Agent Active' : 'Agent Inactive',
              style: _body(14, w: FontWeight.w700),
            ),
            Text(
              isActive ? 'System-wide intelligence running' : 'Activate to enable AI overlay',
              style: _body(12, color: _txtSub),
            ),
          ])),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: _actionBtn(
              label: 'Pause',
              onTap: isActive ? () async => await controller.toggleBubble(false) : null,
              color: _txtSub,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: isActive
                ? _runningBtn()
                : _primaryBtn(
                    label: 'Start Agent',
                    onTap: () async => await controller.toggleBubble(true),
                  ),
          ),
        ]),
      ]),
    );
  }

  Widget _actionBtn({required String label, VoidCallback? onTap, Color color = _accent}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Center(child: Text(label, style: _body(13, color: onTap != null ? color : _txtDim, w: FontWeight.w600))),
      ),
    );
  }

  Widget _primaryBtn({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: Text(label, style: _body(13, w: FontWeight.w700))),
      ),
    );
  }

  Widget _runningBtn() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: _accentDim,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accent.withOpacity(0.25)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 6, height: 6,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: _accent),
        ),
        const SizedBox(width: 8),
        Text('Running', style: _body(13, color: _accent, w: FontWeight.w700)),
      ]),
    );
  }

  // ── Permissions block ──────────────────────────────────────────────────────
  Widget _buildPermissionsBlock(HomeState state, HomeController controller) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        _permRow(
          label: 'Screen Overlay',
          sublabel: 'Floating bubble',
          icon: Icons.layers_outlined,
          isEnabled: state.permissionStatus.hasOverlay,
          onTap: () => controller.requestOverlayPermission(),
          isLast: false,
        ),
        _permRow(
          label: 'Accessibility',
          sublabel: 'Scam scanner',
          icon: Icons.accessibility_new_outlined,
          isEnabled: state.permissionStatus.hasAccessibility,
          onTap: () => _requestAccessibilityPermissionWithPrompt(controller),
          isLast: false,
        ),
        _permRow(
          label: 'Microphone',
          sublabel: 'Voice commands',
          icon: Icons.mic_none_outlined,
          isEnabled: state.permissionStatus.hasMicrophone,
          onTap: () => controller.requestMicrophonePermission(),
          isLast: true,
        ),
      ]),
    );
  }

  Widget _permRow({
    required String label,
    required String sublabel,
    required IconData icon,
    required bool isEnabled,
    required VoidCallback onTap,
    required bool isLast,
  }) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(children: [
          Icon(icon, color: isEnabled ? _accent : _txtDim, size: 17),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: _body(13, color: isEnabled ? _txt : _txtSub, w: FontWeight.w500)),
            Text(sublabel, style: _label(10, spacing: 0)),
          ])),
          isEnabled
              ? Row(children: [
                  Text('ENABLED', style: _label(9, color: _accent.withOpacity(0.6), spacing: 1.0)),
                  const SizedBox(width: 8),
                  Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: _accentDim,
                      border: Border.all(color: _accent.withOpacity(0.4)),
                    ),
                    child: const Icon(Icons.check, color: _accent, size: 10),
                  ),
                ])
              : GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _accentDim,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: _accent.withOpacity(0.2)),
                    ),
                    child: Text('Enable', style: _label(11, color: _accent, spacing: 0)),
                  ),
                ),
        ]),
      ),
      if (!isLast) Container(height: 1, color: _border),
    ]);
  }

  // ── Section label ──────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String text) =>
      Text(text, style: _label(10, spacing: 2.5));

  // ── Modules grid ───────────────────────────────────────────────────────────
  Widget _buildModulesGrid(
    BuildContext context,
    HomeState state,
    HomeController controller,
    AsyncValue<KeyboardStatus> keyboardStatus,
  ) {
    return Column(children: [
      Row(children: [
        Expanded(
          child: _moduleCard(
            icon: Icons.shield_outlined,
            label: 'Scam Detection',
            sublabel: 'Real-time protection',
            statusLabel: 'ACTIVE',
            statusColor: _green,
            accentColor: _green,
            onTap: _handleScamDetectionTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _moduleCard(
            icon: Icons.calendar_today_outlined,
            label: 'Smart Scheduler',
            sublabel: 'AI task planning',
            statusLabel: 'OPEN',
            statusColor: _purple,
            accentColor: _purple,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SmartSchedulerScreen())),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: _moduleCard(
            icon: Icons.integration_instructions_outlined,
            label: 'GitHub Agent',
            sublabel: 'Autonomous code ops',
            statusLabel: 'READY',
            statusColor: _amber,
            accentColor: _amber,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => StreminiAgentScreen())),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: keyboardStatus.when(
            data: (status) => _moduleCard(
              icon: Icons.keyboard_outlined,
              label: 'AI Keyboard',
              sublabel: status.isActive ? 'Ready to type' : 'Needs setup',
              statusLabel: status.isActive ? 'ACTIVE' : 'SETUP',
              statusColor: status.isActive ? _green : _amber,
              accentColor: status.isActive ? _green : _amber,
              onTap: _openKeyboardSetup,
            ),
            loading: () => _moduleCard(
              icon: Icons.keyboard_outlined,
              label: 'AI Keyboard',
              sublabel: 'Checking...',
              statusLabel: '...',
              statusColor: _txtDim,
              accentColor: _txtDim,
              onTap: _openKeyboardSetup,
            ),
            error: (_, __) => _moduleCard(
              icon: Icons.keyboard_outlined,
              label: 'AI Keyboard',
              sublabel: 'Open settings',
              statusLabel: 'SETUP',
              statusColor: _amber,
              accentColor: _amber,
              onTap: _openKeyboardSetup,
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      _quickChatRow(context),
    ]);
  }

  Widget _moduleCard({
    required IconData icon,
    required String label,
    required String sublabel,
    required String statusLabel,
    required Color statusColor,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accentColor.withOpacity(0.15)),
              ),
              child: Icon(icon, color: accentColor, size: 17),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.07),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: statusColor.withOpacity(0.18)),
              ),
              child: Text(statusLabel, style: _label(8, color: statusColor, spacing: 0.8)),
            ),
          ]),
          const SizedBox(height: 16),
          Text(label, style: _body(13, w: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(sublabel, style: _label(11, spacing: 0), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _quickChatRow(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const ChatScreen())),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _accentDim, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _accent.withOpacity(0.2)),
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded, color: _accent, size: 17),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Quick Chat', style: _body(13, w: FontWeight.w700)),
            Text('Ask anything, attach documents', style: _label(11, spacing: 0)),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, color: _txtDim, size: 12),
        ]),
      ),
    );
  }

  // ── Permission alerts ──────────────────────────────────────────────────────
  Widget _buildPermAlerts(HomeState state, HomeController controller) {
    return Column(children: [
      if (state.permissionStatus.needsOverlay)
        _permAlert('Overlay Permission', 'Required for floating bubble',
            Icons.layers_outlined, _amber,
            () => controller.requestOverlayPermission()),
      if (state.permissionStatus.needsAccessibility) ...[
        if (state.permissionStatus.needsOverlay) const SizedBox(height: 8),
        _permAlert('Accessibility', 'Required for scam scanner',
            Icons.accessibility_new_outlined, _accent,
            () => _requestAccessibilityPermissionWithPrompt(controller)),
      ],
      if (state.permissionStatus.needsMicrophone) ...[
        const SizedBox(height: 8),
        _permAlert('Microphone', 'Required for voice commands',
            Icons.mic_none_outlined, _accent,
            () => controller.requestMicrophonePermission()),
      ],
    ]);
  }

  Widget _permAlert(String title, String desc, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _body(13, color: color, w: FontWeight.w600)),
          Text(desc, style: _label(10, spacing: 0)),
        ])),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Text('Enable', style: _label(11, color: color, spacing: 0)),
          ),
        ),
      ]),
    );
  }

  // ── Drawer ─────────────────────────────────────────────────────────────────
  Widget _buildDrawer(BuildContext context, String Function(String) tr) {
    void close() => Scaffold.maybeOf(context)?.closeDrawer();
    return AppDrawer(items: [
      AppDrawerItem(icon: Icons.home_outlined, title: 'Home', onTap: close),
      AppDrawerItem(
        icon: Icons.calendar_today_outlined, title: 'Smart Scheduler',
        onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartSchedulerScreen())); },
      ),
      AppDrawerItem(
        icon: Icons.auto_awesome_outlined, title: 'Stremini Agent',
        onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => StreminiAgentScreen())); },
      ),
      AppDrawerItem(
        icon: Icons.chat_bubble_outline, title: 'Quick Chat',
        onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())); },
      ),
      AppDrawerItem(
        icon: Icons.keyboard_outlined, title: 'AI Keyboard',
        onTap: () async { close(); await _openKeyboardSetup(); },
      ),
      AppDrawerItem(
        icon: Icons.settings_outlined, title: tr('settings'),
        onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); },
      ),
      AppDrawerItem(
        icon: Icons.help_outline, title: 'Contact Us',
        onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactUsScreen())); },
      ),
      AppDrawerItem(
        icon: Icons.logout_outlined, title: 'Sign Out',
        onTap: () { close(); ref.read(authProvider.notifier).signOut(); },
      ),
    ]);
  }

  // ── Handlers (UNCHANGED logic) ─────────────────────────────────────────────
  Future<void> _handleScamDetectionTap() async {
    final scannerNotifier = ref.read(scannerStateProvider.notifier);
    await scannerNotifier.toggleScanning();
    if (!mounted) return;
    final scannerState = ref.read(scannerStateProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        scannerState.error ?? (scannerState.isActive ? 'Scam detection started' : 'Scam detection stopped'),
        style: _body(13),
      ),
      backgroundColor: _surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scannerState.error == null ? _green : _amber, width: 1),
      ),
    ));
  }

  Future<void> _openKeyboardSetup() async {
    final service = ref.read(keyboardServiceProvider);
    final status  = await service.checkKeyboardStatus();
    if (!status.isEnabled) { await service.openKeyboardSettings(); return; }
    if (!status.isSelected) { await service.showKeyboardPicker(); return; }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('AI Keyboard is already active', style: _body(13)),
      backgroundColor: _surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _green, width: 1),
      ),
    ));
  }

  Future<void> _requestAccessibilityPermissionWithPrompt(HomeController controller) async {
    final ok = await _showAccessibilityDialog();
    if (ok == true) await controller.requestAccessibilityPermission();
  }

  Future<bool?> _showAccessibilityDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ACCESSIBILITY', style: _label(10, spacing: 2.5)),
            const SizedBox(height: 10),
            Text('Allow Accessibility Service', style: _body(17, w: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Stremini uses Accessibility Service to protect you from scams in real-time. It reads visible text on screen to detect fraud patterns and trigger alerts while you browse.',
              style: _body(13, color: _txtSub),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, false),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _surface, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border),
                    ),
                    child: Center(child: Text('Not now', style: _body(13, color: _txtSub, w: FontWeight.w600))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, true),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _accent, borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: Text('Continue', style: _body(13, w: FontWeight.w700))),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
