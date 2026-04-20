// home_screen.dart — iOS PREMIUM REDESIGN
// Fixes: 1) Sidebar AI Keyboard crash — now safely routed
//         2) Logo uses lib/img/logo.png (not X icon)
// Design: Apple-grade dark UI — clean groups, generous spacing, refined hierarchy
// ALL LOGIC PRESERVED

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// ── Design tokens — iOS Dark ──────────────────────────────────────────────────
const _bg           = Color(0xFF000000);
const _bgSecondary  = Color(0xFF1C1C1E);
const _bgTertiary   = Color(0xFF2C2C2E);
const _separator    = Color(0xFF38383A);
const _accent       = Color(0xFF0A84FF);
const _accentSoft   = Color(0xFF0A84FF15);
const _green        = Color(0xFF30D158);
const _greenSoft    = Color(0xFF30D15810);
const _red          = Color(0xFFFF453A);
const _amber        = Color(0xFFFF9F0A);
const _amberSoft    = Color(0xFFFF9F0A12);
const _purple       = Color(0xFFBF5AF2);
const _purpleSoft   = Color(0xFFBF5AF212);
const _txt          = Color(0xFFFFFFFF);
const _txtSecondary = Color(0xFF8E8E93);
const _txtTertiary  = Color(0xFF48484A);
const _logoPath     = 'lib/img/logo.png';

// ── Typography ────────────────────────────────────────────────────────────────
TextStyle _sf({
  double size       = 14,
  FontWeight weight = FontWeight.w400,
  Color color       = _txt,
  double height     = 1.5,
  double spacing    = -0.3,
}) => TextStyle(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

// ─────────────────────────────────────────────────────────────────────────────

final keyboardServiceProvider = Provider<KeyboardService>((ref) => KeyboardService());
final keyboardStatusProvider  = FutureProvider<KeyboardStatus>((ref) async {
  return await ref.watch(keyboardServiceProvider).checkKeyboardStatus();
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeControllerProvider.notifier).checkPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(homeControllerProvider.notifier).checkPermissions();
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 18) return 'Good Afternoon';
    return 'Good Evening';
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
          content: Text(next.errorMessage!, style: _sf(size: 13)),
          backgroundColor: _bgSecondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        controller.clearError();
      }
    });

    return Scaffold(
      backgroundColor: _bg,
      drawer: _buildDrawer(context, tr),
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildTopBar(context, state)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 32),
                  _buildGreetingBlock(firstName, state),
                  const SizedBox(height: 28),
                  _buildAgentCard(state, controller),
                  const SizedBox(height: 28),
                  _buildSectionHeader('Modules'),
                  const SizedBox(height: 14),
                  _buildModulesGrid(context, state, controller, keyboardStatus),
                  const SizedBox(height: 28),
                  _buildPermissionsCard(state, controller),
                  if (!state.permissionStatus.hasAll) ...[
                    const SizedBox(height: 28),
                    _buildSectionHeader('Action Required'),
                    const SizedBox(height: 14),
                    _buildPermAlerts(state, controller),
                  ],
                  const SizedBox(height: 80),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context, HomeState state) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 20, right: 20, bottom: 14,
      ),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(bottom: BorderSide(color: _separator, width: 0.5)),
      ),
      child: Row(children: [
        Builder(builder: (ctx) => GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); Scaffold.of(ctx).openDrawer(); },
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _bgSecondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.menu_rounded, color: _txtSecondary, size: 18),
          ),
        )),
        const SizedBox(width: 12),
        // LOGO — uses logo.png
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(
              colors: [Color(0xFF0A84FF), Color(0xFF5AC8FA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(_logoPath, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome_rounded, color: _txt, size: 16),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('STREMINI', style: _sf(size: 15, weight: FontWeight.w800, spacing: 1.5)),
        const Spacer(),
        _statusPill(state),
      ]),
    );
  }

  Widget _statusPill(HomeState state) {
    final isLive = state.bubbleActive;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isLive ? _greenSoft : _bgSecondary,
        borderRadius: BorderRadius.circular(20),
        border: isLive ? Border.all(color: _green.withOpacity(0.3)) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isLive ? _green : _txtTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Text(isLive ? 'Live' : 'Idle',
            style: _sf(size: 12, color: isLive ? _green : _txtTertiary, weight: FontWeight.w600)),
      ]),
    );
  }

  // ── Greeting ───────────────────────────────────────────────────────────────
  Widget _buildGreetingBlock(String firstName, HomeState state) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_greeting(), style: _sf(size: 17, color: _txtSecondary, weight: FontWeight.w400)),
      const SizedBox(height: 4),
      Text(firstName,
          style: _sf(size: 38, weight: FontWeight.w800, spacing: -1.5, height: 1.1)),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _bgSecondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.bubbleActive ? _green : _txtTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            state.bubbleActive ? 'AI agent is operational' : 'AI agent is on standby',
            style: _sf(size: 13, color: state.bubbleActive ? _txtSecondary : _txtTertiary),
          ),
        ]),
      ),
    ]);
  }

  // ── Agent Card ─────────────────────────────────────────────────────────────
  Widget _buildAgentCard(HomeState state, HomeController controller) {
    final isActive = state.bubbleActive;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: isActive ? Border.all(color: _accent.withOpacity(0.25)) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: isActive ? _accentSoft : _bgTertiary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isActive ? Icons.bolt_rounded : Icons.power_settings_new_rounded,
              color: isActive ? _accent : _txtSecondary, size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isActive ? 'Agent Active' : 'Agent Inactive',
                style: _sf(size: 17, weight: FontWeight.w600)),
            Text(
              isActive ? 'System-wide intelligence running' : 'Tap to activate AI overlay',
              style: _sf(size: 13, color: _txtSecondary),
            ),
          ])),
          if (isActive)
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: _green,
                boxShadow: [BoxShadow(color: _green.withOpacity(0.5), blurRadius: 8)],
              ),
            ),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          if (isActive) ...[
            Expanded(
              child: GestureDetector(
                onTap: () async { HapticFeedback.lightImpact(); await controller.toggleBubble(false); },
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: _bgTertiary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text('Pause', style: _sf(size: 15, color: _txtSecondary, weight: FontWeight.w500))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _accent.withOpacity(0.3)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 7, height: 7,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: _accent)),
                  const SizedBox(width: 8),
                  Text('Running', style: _sf(size: 15, color: _accent, weight: FontWeight.w600)),
                ]),
              ),
            ),
          ] else
            Expanded(
              child: GestureDetector(
                onTap: () async { HapticFeedback.mediumImpact(); await controller.toggleBubble(true); },
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text('Start Agent', style: _sf(size: 15, weight: FontWeight.w600))),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  // ── Permissions Card ───────────────────────────────────────────────────────
  Widget _buildPermissionsCard(HomeState state, HomeController controller) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildSectionHeader('Permissions'),
      const SizedBox(height: 14),
      Container(
        decoration: BoxDecoration(
          color: _bgSecondary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          _permRow('Screen Overlay', 'Floating bubble', Icons.layers_rounded,
              state.permissionStatus.hasOverlay,
              () => controller.requestOverlayPermission(), false),
          _divider(),
          _permRow('Accessibility', 'Scam scanner', Icons.accessibility_new_rounded,
              state.permissionStatus.hasAccessibility,
              () => _requestAccessibilityPermissionWithPrompt(controller), false),
          _divider(),
          _permRow('Microphone', 'Voice commands', Icons.mic_rounded,
              state.permissionStatus.hasMicrophone,
              () => controller.requestMicrophonePermission(), true),
        ]),
      ),
    ]);
  }

  Widget _divider() => Container(
        height: 0.5, color: _separator,
        margin: const EdgeInsets.only(left: 56),
      );

  Widget _permRow(String label, String sublabel, IconData icon,
      bool isEnabled, VoidCallback onTap, bool isLast) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: isEnabled ? _accentSoft : _bgTertiary,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: isEnabled ? _accent : _txtSecondary, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _sf(size: 15, weight: FontWeight.w500)),
          Text(sublabel, style: _sf(size: 12, color: _txtSecondary)),
        ])),
        if (isEnabled)
          const Icon(Icons.checkmark_circle_fill, color: _green, size: 22)
        else
          GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); onTap(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Enable', style: _sf(size: 13, color: _accent, weight: FontWeight.w500)),
            ),
          ),
      ]),
    );
  }

  // ── Section header ─────────────────────────────────────────────────────────
  Widget _buildSectionHeader(String text) =>
      Text(text.toUpperCase(),
          style: _sf(size: 11, color: _txtSecondary, weight: FontWeight.w600, spacing: 0.8));

  // ── Modules Grid ───────────────────────────────────────────────────────────
  Widget _buildModulesGrid(
    BuildContext context,
    HomeState state,
    HomeController controller,
    AsyncValue<KeyboardStatus> keyboardStatus,
  ) {
    return Column(children: [
      Row(children: [
        Expanded(child: _moduleCard(
          icon: Icons.shield_fill, iconBg: _greenSoft, iconColor: _green,
          label: 'Scam Shield', sublabel: 'Real-time protection',
          statusLabel: 'Active', statusColor: _green,
          onTap: _handleScamDetectionTap,
        )),
        const SizedBox(width: 12),
        Expanded(child: _moduleCard(
          icon: Icons.calendar_fill, iconBg: _purpleSoft, iconColor: _purple,
          label: 'Scheduler', sublabel: 'AI task planning',
          statusLabel: 'Open', statusColor: _purple,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartSchedulerScreen())),
        )),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _moduleCard(
          icon: Icons.chevron_left_right, iconBg: _amberSoft, iconColor: _amber,
          label: 'GitHub Agent', sublabel: 'Autonomous code ops',
          statusLabel: 'Ready', statusColor: _amber,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StreminiAgentScreen())),
        )),
        const SizedBox(width: 12),
        Expanded(child: keyboardStatus.when(
          data: (status) => _moduleCard(
            icon: Icons.keyboard_rounded,
            iconBg: status.isActive ? _greenSoft : _amberSoft,
            iconColor: status.isActive ? _green : _amber,
            label: 'AI Keyboard', sublabel: status.isActive ? 'Active' : 'Setup needed',
            statusLabel: status.isActive ? 'Active' : 'Setup',
            statusColor: status.isActive ? _green : _amber,
            onTap: () => _openKeyboardSetup(),   // ← fixed: no crash
          ),
          loading: () => _moduleCard(
            icon: Icons.keyboard_rounded, iconBg: _bgTertiary, iconColor: _txtSecondary,
            label: 'AI Keyboard', sublabel: 'Checking…',
            statusLabel: '…', statusColor: _txtSecondary,
            onTap: () => _openKeyboardSetup(),
          ),
          error: (_, __) => _moduleCard(
            icon: Icons.keyboard_rounded, iconBg: _amberSoft, iconColor: _amber,
            label: 'AI Keyboard', sublabel: 'Tap to setup',
            statusLabel: 'Setup', statusColor: _amber,
            onTap: () => _openKeyboardSetup(),
          ),
        )),
      ]),
      const SizedBox(height: 12),
      // Quick Chat — full width
      GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())); },
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _bgSecondary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.chat_bubble_fill, color: _accent, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Quick Chat', style: _sf(size: 16, weight: FontWeight.w600)),
              Text('Ask anything, attach documents', style: _sf(size: 13, color: _txtSecondary)),
            ])),
            const Icon(Icons.chevron_right, color: _txtTertiary, size: 20),
          ]),
        ),
      ),
    ]);
  }

  Widget _moduleCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required String sublabel,
    required String statusLabel,
    required Color statusColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bgSecondary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 19),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(statusLabel, style: _sf(size: 10, color: statusColor, weight: FontWeight.w600, spacing: 0)),
            ),
          ]),
          const SizedBox(height: 14),
          Text(label, style: _sf(size: 15, weight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(sublabel, style: _sf(size: 12, color: _txtSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  // ── Permission Alerts ──────────────────────────────────────────────────────
  Widget _buildPermAlerts(HomeState state, HomeController controller) {
    return Container(
      decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        if (state.permissionStatus.needsOverlay) ...[
          _permAlert('Screen Overlay', 'Required for floating bubble',
              Icons.layers_rounded, _amber, () => controller.requestOverlayPermission()),
          if (state.permissionStatus.needsAccessibility || state.permissionStatus.needsMicrophone)
            Container(height: 0.5, color: _separator, margin: const EdgeInsets.only(left: 56)),
        ],
        if (state.permissionStatus.needsAccessibility) ...[
          _permAlert('Accessibility', 'Required for scam scanner',
              Icons.accessibility_new_rounded, _accent, () => _requestAccessibilityPermissionWithPrompt(controller)),
          if (state.permissionStatus.needsMicrophone)
            Container(height: 0.5, color: _separator, margin: const EdgeInsets.only(left: 56)),
        ],
        if (state.permissionStatus.needsMicrophone)
          _permAlert('Microphone', 'Required for voice commands',
              Icons.mic_rounded, _accent, () => controller.requestMicrophonePermission()),
      ]),
    );
  }

  Widget _permAlert(String title, String desc, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _sf(size: 15, weight: FontWeight.w500)),
          Text(desc, style: _sf(size: 12, color: _txtSecondary)),
        ])),
        GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); onTap(); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Enable', style: _sf(size: 13, color: color, weight: FontWeight.w500)),
          ),
        ),
      ]),
    );
  }

  // ── Drawer ─────────────────────────────────────────────────────────────────
  Widget _buildDrawer(BuildContext context, String Function(String) tr) {
    void close() => Scaffold.maybeOf(context)?.closeDrawer();
    return AppDrawer(items: [
      AppDrawerItem(icon: Icons.house_fill, title: 'Home', onTap: close),
      AppDrawerItem(
        icon: Icons.calendar_fill, title: 'Smart Scheduler',
        onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartSchedulerScreen())); },
      ),
      AppDrawerItem(
        icon: Icons.chevron_left_right, title: 'Stremini Agent',
        onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => StreminiAgentScreen())); },
      ),
      AppDrawerItem(
        icon: Icons.chat_bubble_fill, title: 'Quick Chat',
        onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())); },
      ),
      AppDrawerItem(
        icon: Icons.keyboard_rounded, title: 'AI Keyboard',
        // ↓ FIX: wrapped in async closure, safe error handling
        onTap: () async {
          close();
          await Future.delayed(const Duration(milliseconds: 250)); // let drawer close
          await _openKeyboardSetup();
        },
      ),
      AppDrawerItem(
        icon: Icons.gear_6_teeth_fill, title: tr('settings'),
        onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); },
      ),
      AppDrawerItem(
        icon: Icons.envelope_fill, title: 'Contact Us',
        onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactUsScreen())); },
      ),
      AppDrawerItem(
        icon: Icons.arrow_right_on_rectangle, title: 'Sign Out',
        onTap: () { close(); ref.read(authProvider.notifier).signOut(); },
      ),
    ]);
  }

  // ── Handlers ───────────────────────────────────────────────────────────────
  Future<void> _handleScamDetectionTap() async {
    final scannerNotifier = ref.read(scannerStateProvider.notifier);
    await scannerNotifier.toggleScanning();
    if (!mounted) return;
    final scannerState = ref.read(scannerStateProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        scannerState.error ?? (scannerState.isActive ? 'Scam detection started' : 'Scam detection stopped'),
        style: _sf(size: 13),
      ),
      backgroundColor: _bgSecondary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  /// FIX: safe keyboard setup — wrapped in try/catch, no crash
  Future<void> _openKeyboardSetup() async {
    try {
      final service = ref.read(keyboardServiceProvider);
      final status  = await service.checkKeyboardStatus();
      if (!status.isEnabled) { await service.openKeyboardSettings(); return; }
      if (!status.isSelected) { await service.showKeyboardPicker(); return; }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('AI Keyboard is already active', style: _sf(size: 13)),
        backgroundColor: _bgSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open keyboard settings. Please enable it manually in Settings.', style: _sf(size: 13)),
        backgroundColor: _bgSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _requestAccessibilityPermissionWithPrompt(HomeController controller) async {
    final ok = await _showAccessibilityDialog();
    if (ok == true) await controller.requestAccessibilityPermission();
  }

  Future<bool?> _showAccessibilityDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Accessibility Service', style: _sf(size: 17, weight: FontWeight.w600), textAlign: TextAlign.center),
        content: Text(
          'Stremini uses Accessibility Service to protect you from scams in real-time by reading visible on-screen text to detect fraud patterns.',
          style: _sf(size: 13, color: _txtSecondary),
          textAlign: TextAlign.center,
        ),
        actionsPadding: EdgeInsets.zero,
        actions: [
          Container(height: 0.5, color: _separator),
          IntrinsicHeight(
            child: Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    foregroundColor: _txtSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  child: Text('Not Now', style: _sf(size: 17, color: _txtSecondary)),
                ),
              ),
              Container(width: 0.5, color: _separator),
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                    foregroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  child: Text('Continue', style: _sf(size: 17, color: _accent, weight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
