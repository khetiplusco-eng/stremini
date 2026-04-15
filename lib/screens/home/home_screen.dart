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
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeControllerProvider.notifier).checkPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

    // Extract first name from user display name or email
    final displayName = authState.user?.userMetadata?['full_name']?.toString() ??
        authState.user?.email?.split('@').first ??
        'User';
    final firstName = displayName.split(' ').first;

    ref.listen(homeControllerProvider, (previous, next) {
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppColors.danger,
          ),
        );
        controller.clearError();
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: _buildDrawer(context, tr),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _buildAppBar(context),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 28),

                    // --- Greeting Section ---
                    Text(
                      _greeting(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      firstName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Operational status: ${state.bubbleActive ? "Nominal" : "Standby"}',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 15,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // --- AI Agent Status Card ---
                    _buildAgentCard(state, controller),
                    const SizedBox(height: 16),

                    // --- System Access Rows ---
                    _buildSystemAccess(state, controller),
                    const SizedBox(height: 28),

                    // --- Core Modules Grid ---
                    _buildSectionLabel('CORE MODULES'),
                    const SizedBox(height: 14),
                    _buildModulesGrid(context, state, controller, keyboardStatus),
                    const SizedBox(height: 28),

                    // --- Dynamic Permissions Section ---
                    if (!state.permissionStatus.hasAll) ...[
                      _buildSectionLabel('REQUIRED PERMISSIONS'),
                      const SizedBox(height: 14),
                      _buildPermissionsSection(state, controller),
                      const SizedBox(height: 28),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI Component: App Bar ---
  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      color: Colors.black,
      child: Row(
        children: [
          Builder(
            builder: (ctx) => GestureDetector(
              onTap: () => Scaffold.of(ctx).openDrawer(),
              child: const Icon(Icons.menu, color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(width: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              _logoPath,
              width: 26,
              height: 26,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.auto_awesome, color: Color(0xFF23A6E2), size: 20),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'STREMINI AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
          const Spacer(),
          const Icon(Icons.tune, color: Colors.white, size: 22),
          const SizedBox(width: 14),
          GestureDetector(
             onTap: () => Navigator.of(context).pop(), // Functional close button
             child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1C1C1C)),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI Component: Agent Activation Card ---
  Widget _buildAgentCard(HomeState state, HomeController controller) {
    final isActive = state.bubbleActive;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1C1C1C)),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? const Color(0xFF23A6E2) : const Color(0xFF3A4255),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'AI Agent Active' : 'AI Agent Inactive',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive ? 'System-wide assistant running' : 'Tap Start to activate',
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _agentBtn(
            'Pause',
            const Color(0xFF1A1A1A),
            isActive ? const Color(0xFF8B95A6) : const Color(0xFF4A5568),
            isActive
                ? () async {
                    await controller.toggleBubble(false);
                  }
                : null,
          ),
          const SizedBox(width: 8),
          _agentBtn(
            isActive ? 'Running' : 'Start',
            const Color(0xFF1A1A1A),
            Colors.white,
            () async {
              if (isActive) return;
              await controller.toggleBubble(true);
            },
          ),
        ],
      ),
    );
  }

  Widget _agentBtn(String label, Color bg, Color textColor, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Text(
          label,
          style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // --- UI Component: Permission/System Toggles ---
  Widget _buildSystemAccess(HomeState state, HomeController controller) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1C1C1C)),
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF6B7280), size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              if (isEnabled) ...[
                const Text(
                  'ENABLED',
                  style: TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF23A6E2),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 13),
                ),
              ] else
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1117),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFF1C2030)),
                    ),
                    child: const Text(
                      'Enable',
                      style: TextStyle(color: Color(0xFF23A6E2), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(height: 1, color: Color(0xFF191919), indent: 18, endIndent: 18),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF3A4255),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }

  // --- UI Component: Main Module Grid ---
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
                iconColor: const Color(0xFF23A6E2),
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
                iconColor: const Color(0xFF23A6E2),
                title: 'Smart Scheduler',
                subtitle: 'AI task planning',
                statusLabel: 'VIEW',
                statusColor: const Color(0xFF4A5568),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SmartSchedulerScreen()),
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
                iconColor: const Color(0xFF23A6E2),
                title: 'GitHub Agent',
                subtitle: 'Autonomous code ops',
                statusLabel: 'READY',
                statusColor: const Color(0xFF4A5568),
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
                  iconColor: const Color(0xFF23A6E2),
                  title: 'AI Keyboard',
                  subtitle: status.isActive ? 'Ready to type' : 'Needs setup',
                  statusLabel: status.isActive ? 'ACTIVE' : 'SETUP',
                  statusColor: status.isActive ? const Color(0xFF34C47C) : const Color(0xFFE08A23),
                  onTap: _openKeyboardSetup,
                ),
                loading: () => _moduleCard(
                  icon: Icons.keyboard_outlined,
                  iconColor: const Color(0xFF23A6E2),
                  title: 'AI Keyboard',
                  subtitle: 'Checking...',
                  statusLabel: '...',
                  statusColor: const Color(0xFF4A5568),
                  onTap: _openKeyboardSetup,
                ),
                error: (_, __) => _moduleCard(
                  icon: Icons.keyboard_outlined,
                  iconColor: const Color(0xFF23A6E2),
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
      ],
    );
  }

  Widget _moduleCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String statusLabel,
    required Color statusColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF131313), Color(0xFF10131A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1F2430)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF4A5568), fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                ),
                const SizedBox(width: 5),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- UI Component: Required Permissions List ---
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(color: Color(0xFF4A5568), fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Enable', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI Component: App Drawer ---
  Widget _buildDrawer(BuildContext context, String Function(String) tr) {
    void closeDrawer() => Scaffold.maybeOf(context)?.closeDrawer();

    return AppDrawer(
      items: [
        AppDrawerItem(
          icon: Icons.home_outlined,
          title: 'Home',
          onTap: closeDrawer,
        ),
        AppDrawerItem(
          icon: Icons.calendar_today_outlined,
          title: 'Smart Scheduler',
          onTap: () {
            closeDrawer();
            Navigator.push(context, MaterialPageRoute(builder: (_) => SmartSchedulerScreen()));
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
            Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen()));
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
            Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen()));
          },
        ),
        AppDrawerItem(
          icon: Icons.help_outline,
          title: 'Contact Us',
          onTap: () {
            closeDrawer();
            Navigator.push(context, MaterialPageRoute(builder: (_) => ContactUsScreen()));
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

  // --- Logic: Handlers ---
  Future<void> _handleScamDetectionTap() async {
    final scannerNotifier = ref.read(scannerStateProvider.notifier);
    await scannerNotifier.toggleScanning();
    if (!mounted) return;
    final scannerState = ref.read(scannerStateProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(scannerState.error ??
          (scannerState.isActive ? 'Scam detection started' : 'Scam detection stopped')),
      backgroundColor: scannerState.error == null ? AppColors.success : AppColors.warning,
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
      const SnackBar(content: Text('AI Keyboard is already active'), backgroundColor: AppColors.success),
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
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Allow Accessibility Service',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Stremini uses Accessibility Service to protect you from scams in real-time.',
                style: TextStyle(color: Color(0xFF8B95A6), fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 14),
              const Text(
                'Used to:',
                style: TextStyle(color: Color(0xFF23A6E2), fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Detect suspicious links and scam patterns\n'
                '• Analyze visible screen text for fraud warnings\n'
                '• Keep the floating assistant responsive\n'
                '• Trigger alerts while you browse or chat',
                style: TextStyle(color: Color(0xFF8B95A6), fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 10),
              const Text(
                'You can disable this anytime in Accessibility Settings.',
                style: TextStyle(color: Color(0xFF4A5568), fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now', style: TextStyle(color: Color(0xFF4A5568))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(backgroundColor: const Color(0xFF23A6E2).withOpacity(0.12)),
            child: const Text('Continue', style: TextStyle(color: Color(0xFF23A6E2))),
          ),
        ],
      ),
    );
  }
}
