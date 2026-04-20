// home_screen.dart — PREMIUM REDESIGN v2
// Design: Refined dark luxury — matte black, tight DM Sans typography,
// ultra-clean hierarchy, every element breathes exactly right.
// ALL LOGIC IS UNCHANGED — only presentation layer is redesigned.

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

// ── Design tokens ─────────────────────────────────────────────────────────────
// Background layers
const _bg         = Color(0xFF0A0A0A); // True near-black
const _surface    = Color(0xFF111111); // Elevated surface
const _card       = Color(0xFF161616); // Card layer
const _cardHover  = Color(0xFF1C1C1C); // Interactive card
const _overlay    = Color(0xFF1A1A1A); // Overlay / modal

// Borders — hair-thin, intentional
const _border     = Color(0xFF242424);
const _borderSub  = Color(0xFF1C1C1C);

// Accent — electric teal, the only color in the room
const _accent     = Color(0xFF0AFFE0); // Teal accent
const _accentMid  = Color(0xFF0AC8B4); // Slightly muted
const _accentDim  = Color(0xFF0A1F1C); // Accent background
const _accentGlow = Color(0x1A0AFFE0); // Glow wash

// Semantic colors
const _green      = Color(0xFF00D084);
const _greenDim   = Color(0xFF091C14);
const _red        = Color(0xFFFF4D4D);
const _amber      = Color(0xFFFFB547);
const _amberDim   = Color(0xFF1C1400);
const _purple     = Color(0xFFA78BFA);
const _purpleDim  = Color(0xFF120D1F);

// Text scale
const _txt        = Color(0xFFF5F5F5); // Primary
const _txtSub     = Color(0xFF8C8C8C); // Secondary
const _txtDim     = Color(0xFF404040); // Tertiary / decorative

// Logo
const _logoPath   = 'lib/img/logo.jpg';

// ── Typography — DM Sans ──────────────────────────────────────────────────────
// NOTE: Add 'dm_sans' to your pubspec.yaml fonts section:
//   - family: DMSans
//     fonts:
//       - asset: fonts/DMSans-Regular.ttf
//       - asset: fonts/DMSans-Medium.ttf  weight: 500
//       - asset: fonts/DMSans-SemiBold.ttf weight: 600
//       - asset: fonts/DMSans-Bold.ttf    weight: 700
//       - asset: fonts/DMSans-ExtraBold.ttf weight: 800
// Or use google_fonts package: GoogleFonts.dmSans(...)
TextStyle _display(double size, {
  Color color = _txt,
  FontWeight w = FontWeight.w800,
  double spacing = -1.5,
}) => GoogleFonts.dmSans(
  fontSize: size,
  color: color,
  fontWeight: w,
  letterSpacing: spacing,
  height: 1.0,
);

TextStyle _heading(double size, {
  Color color = _txt,
  FontWeight w = FontWeight.w700,
}) => GoogleFonts.dmSans(
  fontSize: size,
  color: color,
  fontWeight: w,
  letterSpacing: -0.3,
  height: 1.2,
);

TextStyle _body(double size, {
  Color color = _txt,
  FontWeight w = FontWeight.w400,
  double spacing = 0,
}) => GoogleFonts.dmSans(
  fontSize: size,
  color: color,
  fontWeight: w,
  letterSpacing: spacing,
  height: 1.55,
);

TextStyle _caption(double size, {
  Color color = _txtDim,
  FontWeight w = FontWeight.w500,
  double spacing = 1.0,
}) => GoogleFonts.dmSans(
  fontSize: size,
  color: color,
  fontWeight: w,
  letterSpacing: spacing,
  height: 1.0,
);

// ── Shared decoration helpers ─────────────────────────────────────────────────
BoxDecoration _cardDecoration({Color border = _border, Color bg = _surface}) =>
    BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: border, width: 1),
    );

BoxDecoration _pillDecoration({required Color color}) => BoxDecoration(
  color: color.withOpacity(0.08),
  borderRadius: BorderRadius.circular(100),
  border: Border.all(color: color.withOpacity(0.2)),
);

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
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
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

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
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
        _showToast(next.errorMessage!, isError: true);
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
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildTopBar(context, state)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 36),
                  _buildGreeting(firstName, state),
                  const SizedBox(height: 28),
                  _buildAgentCard(state, controller),
                  const SizedBox(height: 20),
                  _buildPermissionsCard(state, controller),
                  const SizedBox(height: 36),
                  _buildLabel('MODULES'),
                  const SizedBox(height: 14),
                  _buildModulesGrid(context, state, controller, keyboardStatus),
                  const SizedBox(height: 36),
                  if (!state.permissionStatus.hasAll) ...[
                    _buildLabel('ACTION REQUIRED'),
                    const SizedBox(height: 14),
                    _buildPermAlerts(state, controller),
                    const SizedBox(height: 36),
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
        left: 20,
        right: 20,
        bottom: 14,
      ),
      decoration: BoxDecoration(
        color: _bg,
        border: Border(
          bottom: BorderSide(color: _border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Menu button
          Builder(
            builder: (ctx) => _iconButton(
              icon: Icons.menu_rounded,
              onTap: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          const SizedBox(width: 12),
          // Logo placeholder + wordmark
          Row(
            children: [
              _buildLogo(),
              const SizedBox(width: 10),
              Text(
                'STREMINI',
                style: _caption(12, color: _txt, w: FontWeight.w800, spacing: 3.5),
              ),
              Text(
                ' AI',
                style: _caption(12, color: _accent, w: FontWeight.w800, spacing: 3.5),
              ),
            ],
          ),
          const Spacer(),
          _buildStatusPill(state),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.asset(
        _logoPath,
        width: 30,
        height: 30,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _accentDim,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _accent.withOpacity(0.3)),
          ),
          child: Center(
            child: Text(
              'S',
              style: _heading(14, color: _accent),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _border),
        ),
        child: Icon(icon, color: _txtSub, size: 18),
      ),
    );
  }

  Widget _buildStatusPill(HomeState state) {
    final live = state.bubbleActive;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: _pillDecoration(color: live ? _green : _txtDim),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pulseDot(color: live ? _green : _txtDim, pulse: live),
          const SizedBox(width: 7),
          Text(
            live ? 'LIVE' : 'IDLE',
            style: _caption(9, color: live ? _green : _txtDim, spacing: 1.8),
          ),
        ],
      ),
    );
  }

  Widget _pulseDot({required Color color, bool pulse = false}) {
    if (!pulse) {
      return Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
    }
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) => Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5 + _pulseCtrl.value * 0.3),
              blurRadius: 4 + _pulseCtrl.value * 4,
              spreadRadius: _pulseCtrl.value * 1.5,
            ),
          ],
        ),
      ),
    );
  }

  // ── Greeting ───────────────────────────────────────────────────────────────
  Widget _buildGreeting(String firstName, HomeState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_greeting(), style: _body(15, color: _txtSub)),
        const SizedBox(height: 4),
        Text(firstName, style: _display(44, spacing: -2.5)),
        const SizedBox(height: 16),
        // Status badge
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: state.bubbleActive ? _accentDim : _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: state.bubbleActive ? _accent.withOpacity(0.25) : _border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pulseDot(
                color: state.bubbleActive ? _accent : _txtDim,
                pulse: state.bubbleActive,
              ),
              const SizedBox(width: 9),
              Text(
                state.bubbleActive ? 'AI agent operational' : 'AI agent on standby',
                style: _body(
                  12,
                  color: state.bubbleActive ? _accentMid : _txtSub,
                  w: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Agent Card ─────────────────────────────────────────────────────────────
  Widget _buildAgentCard(HomeState state, HomeController controller) {
    final isActive = state.bubbleActive;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? _accent.withOpacity(0.18) : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isActive ? _accentDim : _card,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: isActive ? _accent.withOpacity(0.25) : _border,
                  ),
                ),
                child: Icon(
                  isActive ? Icons.memory_rounded : Icons.power_settings_new_rounded,
                  color: isActive ? _accent : _txtDim,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? 'Agent Active' : 'Agent Inactive',
                      style: _heading(15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive
                          ? 'System-wide intelligence running'
                          : 'Activate to enable AI overlay',
                      style: _body(12, color: _txtSub),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Divider
          Container(height: 1, color: _borderSub),
          const SizedBox(height: 20),
          // Action row
          Row(
            children: [
              _textBtn(
                label: 'Pause',
                onTap: isActive ? () async => await controller.toggleBubble(false) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: isActive ? _runningBadge() : _accentBtn(
                  label: 'Start Agent',
                  onTap: () async => await controller.toggleBubble(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _textBtn({required String label, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _border),
        ),
        child: Center(
          child: Text(
            label,
            style: _body(13, color: enabled ? _txt : _txtDim, w: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _accentBtn({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Center(
          child: Text(label, style: _body(13, color: const Color(0xFF0A0A0A), w: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _runningBadge() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) => Container(
        height: 44,
        decoration: BoxDecoration(
          color: _accentDim,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: _accent.withOpacity(0.15 + _pulseCtrl.value * 0.1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent,
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.4 + _pulseCtrl.value * 0.3),
                    blurRadius: 6 + _pulseCtrl.value * 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text('Running', style: _body(13, color: _accent, w: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  // ── Permissions Card ───────────────────────────────────────────────────────
  Widget _buildPermissionsCard(HomeState state, HomeController controller) {
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: [
          _permRow(
            icon: Icons.layers_outlined,
            label: 'Screen Overlay',
            sublabel: 'Floating bubble',
            isEnabled: state.permissionStatus.hasOverlay,
            onTap: () => controller.requestOverlayPermission(),
            isLast: false,
          ),
          _permRow(
            icon: Icons.accessibility_new_outlined,
            label: 'Accessibility',
            sublabel: 'Scam scanner',
            isEnabled: state.permissionStatus.hasAccessibility,
            onTap: () => _requestAccessibilityPermissionWithPrompt(controller),
            isLast: false,
          ),
          _permRow(
            icon: Icons.mic_none_outlined,
            label: 'Microphone',
            sublabel: 'Voice commands',
            isEnabled: state.permissionStatus.hasMicrophone,
            onTap: () => controller.requestMicrophonePermission(),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _permRow({
    required IconData icon,
    required String label,
    required String sublabel,
    required bool isEnabled,
    required VoidCallback onTap,
    required bool isLast,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: isEnabled ? _accent : _txtDim,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: _body(13, color: isEnabled ? _txt : _txtSub, w: FontWeight.w500),
                    ),
                    Text(sublabel, style: _caption(10, spacing: 0)),
                  ],
                ),
              ),
              if (isEnabled)
                Row(
                  children: [
                    Text(
                      'ENABLED',
                      style: _caption(9, color: _accent.withOpacity(0.5), spacing: 1.2),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _accentDim,
                        border: Border.all(color: _accent.withOpacity(0.35)),
                      ),
                      child: const Icon(Icons.check, color: _accent, size: 11),
                    ),
                  ],
                )
              else
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: _accentDim,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _accent.withOpacity(0.18)),
                    ),
                    child: Text('Enable', style: _caption(11, color: _accent, spacing: 0.3)),
                  ),
                ),
            ],
          ),
        ),
        if (!isLast)
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            color: _borderSub,
          ),
      ],
    );
  }

  // ── Section label ──────────────────────────────────────────────────────────
  Widget _buildLabel(String text) => Text(
    text,
    style: _caption(10, color: _txtDim, spacing: 3.0),
  );

  // ── Modules Grid ───────────────────────────────────────────────────────────
  Widget _buildModulesGrid(
    BuildContext context,
    HomeState state,
    HomeController controller,
    AsyncValue<KeyboardStatus> keyboardStatus,
  ) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _moduleCard(
                  icon: Icons.shield_outlined,
                  label: 'Scam Detection',
                  sublabel: 'Real-time protection',
                  status: 'ACTIVE',
                  statusColor: _green,
                  onTap: _handleScamDetectionTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _moduleCard(
                  icon: Icons.calendar_today_outlined,
                  label: 'Smart Scheduler',
                  sublabel: 'AI task planning',
                  status: 'OPEN',
                  statusColor: _purple,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SmartSchedulerScreen())),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _moduleCard(
                  icon: Icons.integration_instructions_outlined,
                  label: 'GitHub Agent',
                  sublabel: 'Autonomous code ops',
                  status: 'READY',
                  statusColor: _amber,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => StreminiAgentScreen())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: keyboardStatus.when(
                  data: (s) => _moduleCard(
                    icon: Icons.keyboard_outlined,
                    label: 'AI Keyboard',
                    sublabel: s.isActive ? 'Ready to type' : 'Needs setup',
                    status: s.isActive ? 'ACTIVE' : 'SETUP',
                    statusColor: s.isActive ? _green : _amber,
                    onTap: _openKeyboardSetup,
                  ),
                  loading: () => _moduleCard(
                    icon: Icons.keyboard_outlined,
                    label: 'AI Keyboard',
                    sublabel: 'Checking status...',
                    status: '···',
                    statusColor: _txtDim,
                    onTap: _openKeyboardSetup,
                  ),
                  error: (_, __) => _moduleCard(
                    icon: Icons.keyboard_outlined,
                    label: 'AI Keyboard',
                    sublabel: 'Open settings',
                    status: 'SETUP',
                    statusColor: _amber,
                    onTap: _openKeyboardSetup,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _quickChatTile(context),
      ],
    );
  }

  Widget _moduleCard({
    required IconData icon,
    required String label,
    required String sublabel,
    required String status,
    required Color statusColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: statusColor.withOpacity(0.14)),
                  ),
                  child: Icon(icon, color: statusColor, size: 17),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withOpacity(0.15)),
                  ),
                  child: Text(
                    status,
                    style: _caption(8, color: statusColor, spacing: 1.0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(label, style: _heading(13)),
            const SizedBox(height: 4),
            Text(
              sublabel,
              style: _caption(10, spacing: 0),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickChatTile(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _accentDim,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _accent.withOpacity(0.18)),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded, color: _accent, size: 18),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quick Chat', style: _heading(14)),
                  const SizedBox(height: 3),
                  Text(
                    'Ask anything, attach documents',
                    style: _caption(11, spacing: 0),
                  ),
                ],
              ),
            ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.arrow_forward_ios_rounded, color: _txtDim, size: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ── Permission Alerts ──────────────────────────────────────────────────────
  Widget _buildPermAlerts(HomeState state, HomeController controller) {
    return Column(
      children: [
        if (state.permissionStatus.needsOverlay)
          _permAlert(
            title: 'Overlay Permission',
            desc: 'Required for floating bubble',
            icon: Icons.layers_outlined,
            color: _amber,
            onTap: () => controller.requestOverlayPermission(),
          ),
        if (state.permissionStatus.needsAccessibility) ...[
          if (state.permissionStatus.needsOverlay) const SizedBox(height: 8),
          _permAlert(
            title: 'Accessibility Service',
            desc: 'Required for scam scanner',
            icon: Icons.accessibility_new_outlined,
            color: _accent,
            onTap: () => _requestAccessibilityPermissionWithPrompt(controller),
          ),
        ],
        if (state.permissionStatus.needsMicrophone) ...[
          const SizedBox(height: 8),
          _permAlert(
            title: 'Microphone Access',
            desc: 'Required for voice commands',
            icon: Icons.mic_none_outlined,
            color: _accent,
            onTap: () => controller.requestMicrophonePermission(),
          ),
        ],
      ],
    );
  }

  Widget _permAlert({
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _body(13, color: _txt, w: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(desc, style: _caption(10, color: _txtDim, spacing: 0)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Text('Enable', style: _caption(11, color: color, spacing: 0.3)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Toast ──────────────────────────────────────────────────────────────────
  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: _body(13)),
        backgroundColor: _surface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isError ? _red : _border, width: 1),
        ),
      ),
    );
  }

  // ── Drawer ─────────────────────────────────────────────────────────────────
  Widget _buildDrawer(BuildContext context, String Function(String) tr) {
    void close() => Scaffold.maybeOf(context)?.closeDrawer();
    return AppDrawer(items: [
      AppDrawerItem(icon: Icons.home_outlined, title: 'Home', onTap: close),
      AppDrawerItem(
        icon: Icons.calendar_today_outlined,
        title: 'Smart Scheduler',
        onTap: () {
          close();
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SmartSchedulerScreen()));
        },
      ),
      AppDrawerItem(
        icon: Icons.auto_awesome_outlined,
        title: 'Stremini Agent',
        onTap: () {
          close();
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => StreminiAgentScreen()));
        },
      ),
      AppDrawerItem(
        icon: Icons.chat_bubble_outline,
        title: 'Quick Chat',
        onTap: () {
          close();
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ChatScreen()));
        },
      ),
      AppDrawerItem(
        icon: Icons.keyboard_outlined,
        title: 'AI Keyboard',
        onTap: () async {
          close();
          await _openKeyboardSetup();
        },
      ),
      AppDrawerItem(
        icon: Icons.settings_outlined,
        title: tr('settings'),
        onTap: () {
          close();
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
      ),
      AppDrawerItem(
        icon: Icons.help_outline,
        title: 'Contact Us',
        onTap: () {
          close();
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ContactUsScreen()));
        },
      ),
      AppDrawerItem(
        icon: Icons.logout_outlined,
        title: 'Sign Out',
        onTap: () {
          close();
          ref.read(authProvider.notifier).signOut();
        },
      ),
    ]);
  }

  // ── Handlers (UNCHANGED logic) ─────────────────────────────────────────────
  Future<void> _handleScamDetectionTap() async {
    final scannerNotifier = ref.read(scannerStateProvider.notifier);
    await scannerNotifier.toggleScanning();
    if (!mounted) return;
    final scannerState = ref.read(scannerStateProvider);
    _showToast(
      scannerState.error ??
          (scannerState.isActive
              ? 'Scam detection started'
              : 'Scam detection stopped'),
      isError: scannerState.error != null,
    );
  }

  Future<void> _openKeyboardSetup() async {
    final service = ref.read(keyboardServiceProvider);
    final status  = await service.checkKeyboardStatus();
    if (!status.isEnabled) {
      await service.openKeyboardSettings();
      return;
    }
    if (!status.isSelected) {
      await service.showKeyboardPicker();
      return;
    }
    if (!mounted) return;
    _showToast('AI Keyboard is already active');
  }

  Future<void> _requestAccessibilityPermissionWithPrompt(HomeController controller) async {
    final ok = await _showAccessibilityDialog();
    if (ok == true) await controller.requestAccessibilityPermission();
  }

  Future<bool?> _showAccessibilityDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _accentDim,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: _accent.withOpacity(0.25)),
                ),
                child: const Icon(Icons.accessibility_new_outlined, color: _accent, size: 20),
              ),
              const SizedBox(height: 18),
              Text(
                'Accessibility Service',
                style: _heading(19),
              ),
              const SizedBox(height: 10),
              Text(
                'Stremini uses Accessibility Service to protect you from scams in real-time. It reads visible text on screen to detect fraud patterns and trigger alerts while you browse.',
                style: _body(13, color: _txtSub),
              ),
              const SizedBox(height: 26),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                        ),
                        child: Center(
                          child: Text('Not now', style: _body(14, color: _txtSub, w: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'Continue',
                            style: _body(14, color: const Color(0xFF0A0A0A), w: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
