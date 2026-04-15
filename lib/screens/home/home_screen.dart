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

const _logoPath = 'lib/img/logo.jpg';

final keyboardServiceProvider =
    Provider<KeyboardService>((ref) => KeyboardService());
final keyboardStatusProvider = FutureProvider<KeyboardStatus>((ref) async {
  final service = ref.watch(keyboardServiceProvider);
  return await service.checkKeyboardStatus();
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
      vsync: this,
      duration: const Duration(milliseconds: 2400),
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
    if (hour < 12) return 'Good morning,';
    if (hour < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeControllerProvider);
    final controller = ref.read(homeControllerProvider.notifier);
    final keyboardStatus = ref.watch(keyboardStatusProvider);
    final settings = ref.watch(appSettingsProvider);
    final authState = ref.watch(authProvider);
    String tr(String key) => AppStrings.t(settings.language, key);

    final displayName = authState.user?.userMetadata?['full_name']?.toString() ??
        authState.user?.email?.split('@').first ??
        'User';
    final firstName = displayName.split(' ').first;

    ref.listen(homeControllerProvider, (previous, next) {
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        controller.clearError();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF030507),
      drawer: _buildDrawer(context, tr),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildAppBar(context)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  _buildGreeting(firstName, state),
                  const SizedBox(height: 28),
                  _buildAgentCard(state, controller),
                  const SizedBox(height: 16),
                  _buildSystemAccess(state, controller),
                  const SizedBox(height: 32),
                  _buildSectionLabel('CORE MODULES'),
                  const SizedBox(height: 14),
                  _buildModulesGrid(context, state, controller, keyboardStatus),
                  const SizedBox(height: 32),
                  if (!state.permissionStatus.hasAll) ...[
                    _buildSectionLabel('REQUIRED PERMISSIONS'),
                    const SizedBox(height: 14),
                    _buildPermissionsSection(state, controller),
                    const SizedBox(height: 32),
                  ],
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 20,
        right: 20,
        bottom: 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF030507),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
        ),
      ),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => GestureDetector(
              onTap: () => Scaffold.of(ctx).openDrawer(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Icon(Icons.menu, color: Colors.white, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Logo
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF23A6E2).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                _logoPath,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF23A6E2), Color(0xFF0A5F8F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF23A6E2), Color(0xFF8DDCFF)],
            ).createShader(bounds),
            child: const Text(
              'STREMINI AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
              ),
            ),
          ),
          const Spacer(),
          _buildStatusDot(),
        ],
      ),
    );
  }

  Widget _buildStatusDot() {
    final state = ref.watch(homeControllerProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: state.bubbleActive
            ? const Color(0xFF0A2518)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: state.bubbleActive
              ? const Color(0xFF34C47C).withOpacity(0.4)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.bubbleActive
                  ? const Color(0xFF34C47C)
                  : const Color(0xFF3A4255),
              boxShadow: state.bubbleActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFF34C47C).withOpacity(0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            state.bubbleActive ? 'LIVE' : 'IDLE',
            style: TextStyle(
              color: state.bubbleActive
                  ? const Color(0xFF34C47C)
                  : const Color(0xFF4A5568),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting(String firstName, HomeState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _greeting(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 18,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          firstName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 42,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: state.bubbleActive
                    ? const Color(0xFF34C47C)
                    : const Color(0xFF3A4255),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              state.bubbleActive
                  ? 'System operational — AI agent running'
                  : 'System standby — tap Start to activate',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAgentCard(HomeState state, HomeController controller) {
    final isActive = state.bubbleActive;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? const Color(0xFF23A6E2).withOpacity(0.2)
              : Colors.white.withOpacity(0.07),
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFF23A6E2).withOpacity(0.08),
                  blurRadius: 40,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF23A6E2).withOpacity(0.12)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFF23A6E2).withOpacity(0.25)
                        : Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Icon(
                  isActive ? Icons.memory_rounded : Icons.power_settings_new_rounded,
                  color: isActive ? const Color(0xFF23A6E2) : const Color(0xFF4A5568),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? 'AI Agent Active' : 'AI Agent Inactive',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive
                          ? 'System-wide intelligence running'
                          : 'Activate to enable AI overlay',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _agentBtn(
                  label: 'Pause',
                  onTap: isActive
                      ? () async => await controller.toggleBubble(false)
                      : null,
                  active: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _agentBtnPrimary(
                  label: isActive ? 'Running' : 'Start Agent',
                  onTap: isActive ? null : () async => await controller.toggleBubble(true),
                  isActive: isActive,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _agentBtn({required String label, required VoidCallback? onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: onTap != null ? Colors.white : const Color(0xFF3A4255),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _agentBtnPrimary({required String label, required VoidCallback? onTap, bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: isActive
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF23A6E2), Color(0xFF0A5F8F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: isActive ? Colors.white.withOpacity(0.04) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? const Color(0xFF23A6E2).withOpacity(0.2)
                : Colors.transparent,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF23A6E2),
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isActive ? const Color(0xFF23A6E2) : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSystemAccess(HomeState state, HomeController controller) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          _permissionRow(
            icon: Icons.layers_outlined,
            label: 'Screen Overlay',
            isEnabled: state.permissionStatus.hasOverlay,
            onTap: () => controller.requestOverlayPermission(),
            isLast: false,
          ),
          _permissionRow(
            icon: Icons.accessibility_new_outlined,
            label: 'Accessibility',
            isEnabled: state.permissionStatus.hasAccessibility,
            onTap: () => _requestAccessibilityPermissionWithPrompt(controller),
            isLast: false,
          ),
          _permissionRow(
            icon: Icons.mic_none_outlined,
            label: 'Microphone',
            isEnabled: state.permissionStatus.hasMicrophone,
            onTap: () => controller.requestMicrophonePermission(),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _permissionRow({
    required IconData icon,
    required String label,
    required bool isEnabled,
    required VoidCallback onTap,
    required bool isLast,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isEnabled
                      ? const Color(0xFF23A6E2).withOpacity(0.08)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isEnabled ? const Color(0xFF23A6E2) : const Color(0xFF4A5568),
                  size: 17,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isEnabled ? Colors.white : Colors.white.withOpacity(0.5),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (isEnabled) ...[
                Text(
                  'ENABLED',
                  style: TextStyle(
                    color: const Color(0xFF23A6E2).withOpacity(0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF23A6E2).withOpacity(0.15),
                    border: Border.all(color: const Color(0xFF23A6E2).withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.check, color: Color(0xFF23A6E2), size: 12),
                ),
              ] else
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF23A6E2).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0xFF23A6E2).withOpacity(0.2)),
                    ),
                    child: const Text(
                      'Enable',
                      style: TextStyle(
                        color: Color(0xFF23A6E2),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: Colors.white.withOpacity(0.05),
            indent: 18,
            endIndent: 18,
          ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withOpacity(0.2),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.8,
      ),
    );
  }

  Widget _buildModulesGrid(
    BuildContext context,
    HomeState state,
    HomeController controller,
    AsyncValue<KeyboardStatus> keyboardStatus,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _moduleCard(
                icon: Icons.shield_outlined,
                gradient: const [Color(0xFF23A6E2), Color(0xFF0A5F8F)],
                title: 'Scam Detection',
                subtitle: 'Real-time protection',
                statusLabel: 'ACTIVE',
                statusColor: const Color(0xFF34C47C),
                onTap: () => _handleScamDetectionTap(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _moduleCard(
                icon: Icons.calendar_today_outlined,
                gradient: const [Color(0xFF8B5CF6), Color(0xFF5B21B6)],
                title: 'Smart Scheduler',
                subtitle: 'AI task planning',
                statusLabel: 'VIEW',
                statusColor: const Color(0xFF8B5CF6),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SmartSchedulerScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _moduleCard(
                icon: Icons.integration_instructions_outlined,
                gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                title: 'GitHub Agent',
                subtitle: 'Autonomous code ops',
                statusLabel: 'READY',
                statusColor: const Color(0xFFF59E0B),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => StreminiAgentScreen()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: keyboardStatus.when(
                data: (status) => _moduleCard(
                  icon: Icons.keyboard_outlined,
                  gradient: const [Color(0xFF34C47C), Color(0xFF16A34A)],
                  title: 'AI Keyboard',
                  subtitle: status.isActive ? 'Ready to type' : 'Needs setup',
                  statusLabel: status.isActive ? 'ACTIVE' : 'SETUP',
                  statusColor: status.isActive ? const Color(0xFF34C47C) : const Color(0xFFE08A23),
                  onTap: _openKeyboardSetup,
                ),
                loading: () => _moduleCard(
                  icon: Icons.keyboard_outlined,
                  gradient: const [Color(0xFF34C47C), Color(0xFF16A34A)],
                  title: 'AI Keyboard',
                  subtitle: 'Checking...',
                  statusLabel: '...',
                  statusColor: const Color(0xFF4A5568),
                  onTap: _openKeyboardSetup,
                ),
                error: (_, __) => _moduleCard(
                  icon: Icons.keyboard_outlined,
                  gradient: const [Color(0xFF34C47C), Color(0xFF16A34A)],
                  title: 'AI Keyboard',
                  subtitle: 'Open settings',
                  statusLabel: 'SETUP',
                  statusColor: const Color(0xFFE08A23),
                  onTap: _openKeyboardSetup,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildQuickChatBanner(context),
      ],
    );
  }

  Widget _buildQuickChatBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0F14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF23A6E2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF23A6E2).withOpacity(0.2)),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF23A6E2), size: 19),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Chat',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Ask anything, attach documents',
                    style: TextStyle(color: Color(0xFF4A5568), fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF23A6E2).withOpacity(0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF23A6E2), size: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moduleCard({
    required IconData icon,
    required List<Color> gradient,
    required String title,
    required String subtitle,
    required String statusLabel,
    required Color statusColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0F14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [gradient[0].withOpacity(0.15), gradient[1].withOpacity(0.08)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: gradient[0].withOpacity(0.2)),
              ),
              child: Icon(icon, color: gradient[0], size: 20),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: statusColor.withOpacity(0.2)),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsSection(HomeState state, HomeController controller) {
    return Column(
      children: [
        if (state.permissionStatus.needsOverlay)
          _permCard(
            'Overlay Permission',
            'Required for floating bubble',
            Icons.bubble_chart_outlined,
            const Color(0xFFE08A23),
            () => controller.requestOverlayPermission(),
          ),
        if (state.permissionStatus.needsAccessibility) ...[
          if (state.permissionStatus.needsOverlay) const SizedBox(height: 10),
          _permCard(
            'Accessibility',
            'Required for scam scanner',
            Icons.accessibility_new_outlined,
            const Color(0xFF23A6E2),
            () => _requestAccessibilityPermissionWithPrompt(controller),
          ),
        ],
        if (state.permissionStatus.needsMicrophone) ...[
          if (state.permissionStatus.needsOverlay || state.permissionStatus.needsAccessibility)
            const SizedBox(height: 10),
          _permCard(
            'Microphone',
            'Required for voice commands',
            Icons.mic_none_outlined,
            const Color(0xFF23A6E2),
            () => controller.requestMicrophonePermission(),
          ),
        ],
      ],
    );
  }

  Widget _permCard(String title, String description, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(description, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Text('Enable', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, String Function(String) tr) {
    void closeDrawer() => Scaffold.maybeOf(context)?.closeDrawer();
    return AppDrawer(
      items: [
        AppDrawerItem(icon: Icons.home_outlined, title: 'Home', onTap: closeDrawer),
        AppDrawerItem(
          icon: Icons.calendar_today_outlined,
          title: 'Smart Scheduler',
          onTap: () {
            closeDrawer();
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartSchedulerScreen()));
          },
        ),
        AppDrawerItem(
          icon: Icons.auto_awesome_outlined,
          title: 'Stremini Agent',
          onTap: () {
            closeDrawer();
            Navigator.push(context, MaterialPageRoute(builder: (_) => StreminiAgentScreen()));
          },
        ),
        AppDrawerItem(
          icon: Icons.chat_bubble_outline,
          title: 'Quick Chat',
          onTap: () {
            closeDrawer();
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen()));
          },
        ),
        AppDrawerItem(
          icon: Icons.keyboard_outlined,
          title: 'AI Keyboard',
          onTap: () async {
            closeDrawer();
            await _openKeyboardSetup();
          },
        ),
        AppDrawerItem(
          icon: Icons.settings_outlined,
          title: tr('settings'),
          onTap: () {
            closeDrawer();
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
          },
        ),
        AppDrawerItem(
          icon: Icons.help_outline,
          title: 'Contact Us',
          onTap: () {
            closeDrawer();
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactUsScreen()));
          },
        ),
        AppDrawerItem(
          icon: Icons.logout_outlined,
          title: 'Sign Out',
          onTap: () {
            closeDrawer();
            ref.read(authProvider.notifier).signOut();
          },
        ),
      ],
    );
  }

  Future<void> _handleScamDetectionTap() async {
    final scannerNotifier = ref.read(scannerStateProvider.notifier);
    await scannerNotifier.toggleScanning();
    if (!mounted) return;
    final scannerState = ref.read(scannerStateProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(scannerState.error ??
          (scannerState.isActive ? 'Scam detection started' : 'Scam detection stopped')),
      backgroundColor: scannerState.error == null ? AppColors.success : AppColors.warning,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _openKeyboardSetup() async {
    final service = ref.read(keyboardServiceProvider);
    final status = await service.checkKeyboardStatus();
    if (!status.isEnabled) {
      await service.openKeyboardSettings();
      return;
    }
    if (!status.isSelected) {
      await service.showKeyboardPicker();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('AI Keyboard is already active'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _requestAccessibilityPermissionWithPrompt(HomeController controller) async {
    final shouldContinue = await _showAccessibilityDialog();
    if (shouldContinue == true) {
      await controller.requestAccessibilityPermission();
    }
  }

  Future<bool?> _showAccessibilityDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D0F14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Allow Accessibility Service',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stremini uses Accessibility Service to protect you from scams in real-time.',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 14),
              const Text(
                'Used to:',
                style: TextStyle(color: Color(0xFF23A6E2), fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                '• Detect suspicious links and scam patterns\n'
                '• Analyze visible screen text for fraud warnings\n'
                '• Keep the floating assistant responsive\n'
                '• Trigger alerts while you browse or chat',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Not now', style: TextStyle(color: Colors.white.withOpacity(0.3))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(backgroundColor: const Color(0xFF23A6E2).withOpacity(0.1)),
            child: const Text('Continue', style: TextStyle(color: Color(0xFF23A6E2))),
          ),
        ],
      ),
    );
  }
}
