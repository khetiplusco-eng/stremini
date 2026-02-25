import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_container.dart';
import '../../core/widgets/app_drawer.dart';
import '../../controllers/home_controller.dart';
import '../../providers/scanner_provider.dart';
import '../../services/keyboard_service.dart';
import '../chat_screen.dart';
import '../stremini_agent_screen.dart';

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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeControllerProvider.notifier).checkPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeControllerProvider);
    final controller = ref.read(homeControllerProvider.notifier);
    final keyboardStatus = ref.watch(keyboardStatusProvider);

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
      backgroundColor: AppColors.black,
      drawer: _buildDrawer(context),
      body: CustomScrollView(
        slivers: [
          // Custom App Bar with logo
          SliverAppBar(
            backgroundColor: AppColors.black,
            elevation: 0,
            floating: true,
            pinned: true,
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, color: AppColors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(AppAssets.logo,
                    width: 32, height: 32, fit: BoxFit.contain),
                const SizedBox(width: 12),
                Text('Stremini', style: AppTextStyles.h2),
              ],
            ),
            centerTitle: true,
            actions: const [SizedBox(width: 48)],
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  
                  // Main title section
                  _buildMainTitle(),
                  const SizedBox(height: 32),

                  // Floating AI Agent Banner (Matching screenshot)
                  _buildFloatingAgentBanner(state, controller),
                  const SizedBox(height: 32),

                  // System Access Section
                  _buildSectionTitle('SYSTEM ACCESS'),
                  const SizedBox(height: 16),
                  _buildSystemAccessCards(state, controller),
                  const SizedBox(height: 32),

                  // Active Modules Section
                  _buildSectionTitle('ACTIVE MODULES'),
                  const SizedBox(height: 16),
                  _buildModulesGrid(context, state, controller, keyboardStatus),
                  const SizedBox(height: 32),

                  // Permissions if needed
                  if (!state.permissionStatus.hasAll) ...[
                    _buildSectionTitle('REQUIRED PERMISSIONS'),
                    const SizedBox(height: 16),
                    _buildPermissionsSection(state, controller),
                    const SizedBox(height: 32),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Main Title ────────────────────────────────────────────────────────────
  Widget _buildMainTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stremini',
          style: AppTextStyles.h1.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Autonomous AI',
          style: AppTextStyles.body2.copyWith(
            color: AppColors.primary,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ── Section Title ─────────────────────────────────────────────────────────
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTextStyles.body3.copyWith(
        color: AppColors.textGray,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  // ── Floating AI Agent Banner (Main CTA - Matching Screenshot) ────────────
  Widget _buildFloatingAgentBanner(HomeState state, HomeController controller) {
    return AppContainer(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF0D2137),
          AppColors.primary.withOpacity(0.15),
        ],
      ),
      border: BorderSide(color: AppColors.primary.withOpacity(0.4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.3),
                      AppColors.scanCyan.withOpacity(0.2),
                    ],
                  ),
                  border: Border.all(color: AppColors.primary.withOpacity(0.5)),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Floating AI Agent',
                      style: AppTextStyles.h3.copyWith(fontSize: 18),
                    ),
                    Text(
                      'Tap to activate system-wide assistant',
                      style: AppTextStyles.subtitle1.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.bubbleActive
                      ? AppColors.primary
                      : AppColors.mediumGray,
                  boxShadow: state.bubbleActive
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
                child: state.isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppColors.white),
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          state.bubbleActive ? Icons.power_settings_new : Icons.power_settings_new_outlined,
                          color: AppColors.white,
                          size: 24,
                        ),
                        onPressed: state.isLoading
                            ? null
                            : () async {
                                final success = await controller
                                    .toggleBubble(!state.bubbleActive);
                                if (!success && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Please grant permissions first'),
                                      backgroundColor: AppColors.warning,
                                    ),
                                  );
                                } else if (success && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(state.bubbleActive
                                          ? 'Floating AI activated!'
                                          : 'Floating AI deactivated'),
                                      backgroundColor: state.bubbleActive
                                          ? AppColors.success
                                          : AppColors.lightGray,
                                    ),
                                  );
                                }
                              },
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── System Access Cards ───────────────────────────────────────────────────
  Widget _buildSystemAccessCards(HomeState state, HomeController controller) {
    return Column(
      children: [
        _buildSystemAccessCard(
          'Screen Overlay',
          'Required for floating widget',
          Icons.layers,
          state.permissionStatus.hasOverlay,
          () => controller.requestOverlayPermission(),
        ),
        const SizedBox(height: 12),
        _buildSystemAccessCard(
          'Accessibility',
          'Allows AI to read screen context',
          Icons.accessibility_new,
          state.permissionStatus.hasAccessibility,
          () => _requestAccessibilityPermissionWithPrompt(controller),
        ),
        const SizedBox(height: 12),
        _buildSystemAccessCard(
          'Notifications',
          'Receive background agent updates',
          Icons.notifications,
          true, // Notifications are usually granted by default
          () {},
        ),
      ],
    );
  }

  Widget _buildSystemAccessCard(
    String title,
    String description,
    IconData icon,
    bool isEnabled,
    VoidCallback onTap,
  ) {
    return AppContainer(
      padding: const EdgeInsets.all(16),
      color: AppColors.darkGray,
      border: BorderSide(
        color: isEnabled
            ? AppColors.primary.withOpacity(0.4)
            : AppColors.lightGray.withOpacity(0.2),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isEnabled
                  ? AppColors.primary.withOpacity(0.2)
                  : AppColors.lightGray.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: isEnabled ? AppColors.primary : AppColors.lightGray,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.body2),
                Text(description, style: AppTextStyles.subtitle2),
              ],
            ),
          ),
          if (!isEnabled)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary.withOpacity(0.2),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(
                'Enable',
                style: AppTextStyles.button.copyWith(color: AppColors.primary),
              ),
            )
          else
            Icon(Icons.check_circle, color: AppColors.success, size: 24),
        ],
      ),
    );
  }

  // ── Active Modules Grid ───────────────────────────────────────────────────
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
              child: _buildModuleCard(
                'Scam Detection',
                'Live screen risk scan',
                Icons.shield,
                AppColors.warning,
                () => _handleScamDetectionTap(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModuleCard(
                'Automation',
                'Hands-free phone tasks',
                Icons.bolt,
                AppColors.scanCyan,
                () => _handleAutomationTap(controller),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildModuleCard(
                'GitHub Agent',
                'Autonomous code ops',
                Icons.integration_instructions,
                AppColors.scanCyan,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const StreminiAgentScreen()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: keyboardStatus.when(
                data: (status) => _buildModuleCard(
                  'AI Keyboard',
                  status.isActive
                      ? 'Ready to type with AI'
                      : 'Tap to complete setup',
                  Icons.keyboard,
                  AppColors.secondary,
                  _openKeyboardSetup,
                ),
                loading: () => _buildModuleCard(
                  'AI Keyboard',
                  'Checking keyboard status...',
                  Icons.keyboard,
                  AppColors.secondary,
                  () {},
                ),
                error: (_, __) => _buildModuleCard(
                  'AI Keyboard',
                  'Open keyboard settings',
                  Icons.keyboard,
                  AppColors.secondary,
                  _openKeyboardSetup,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleScamDetectionTap() async {
    final scannerNotifier = ref.read(scannerStateProvider.notifier);
    await scannerNotifier.toggleScanning();
    if (!mounted) return;
    final scannerState = ref.read(scannerStateProvider);
    final message = scannerState.error ??
        (scannerState.isActive
            ? 'Scam detection started'
            : 'Scam detection stopped');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            scannerState.error == null ? AppColors.success : AppColors.warning,
      ),
    );
  }

  Future<void> _handleAutomationTap(HomeController controller) async {
    final success = await controller.toggleBubble(true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Automation ready. Use the floating menu to start tasks.'
            : 'Enable required permissions to use automation'),
        backgroundColor: success ? AppColors.success : AppColors.warning,
      ),
    );
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
      ),
    );
  }

  Widget _buildModuleCard(
    String title,
    String description,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return AppContainer(
      padding: const EdgeInsets.all(16),
      color: AppColors.darkGray,
      border: BorderSide(color: color.withOpacity(0.3)),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: AppTextStyles.subtitle2,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Permissions Section ───────────────────────────────────────────────────
  Widget _buildPermissionsSection(HomeState state, HomeController controller) {
    return Column(
      children: [
        if (state.permissionStatus.needsOverlay)
          _buildPermissionCard(
            'Overlay Permission',
            'Required for floating bubble over other apps',
            Icons.bubble_chart,
            AppColors.warning,
            () => controller.requestOverlayPermission(),
          ),
        if (state.permissionStatus.needsAccessibility) ...[
          if (state.permissionStatus.needsOverlay) const SizedBox(height: 12),
          _buildPermissionCard(
            'Accessibility Permission',
            'Required for screen scanner to detect scams',
            Icons.accessibility_new,
            AppColors.emotional,
            () => _requestAccessibilityPermissionWithPrompt(controller),
          ),
        ],
        if (state.permissionStatus.needsMicrophone) ...[
          if (state.permissionStatus.needsOverlay ||
              state.permissionStatus.needsAccessibility)
            const SizedBox(height: 12),
          _buildPermissionCard(
            'Microphone Permission',
            'Required for Auto Tasker voice commands',
            Icons.mic,
            AppColors.info,
            () => controller.requestMicrophonePermission(),
          ),
        ],
      ],
    );
  }


  Future<void> _requestAccessibilityPermissionWithPrompt(
    HomeController controller,
  ) async {
    final shouldContinue = await _showAccessibilityPermissionPrompt();
    if (shouldContinue == true) {
      await controller.requestAccessibilityPermission();
    }
  }

  Future<bool?> _showAccessibilityPermissionPrompt() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.darkGray,
          title: Text(
            'Allow Accessibility Service',
            style: AppTextStyles.body1.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stremini uses Accessibility Service to help protect you from scams in real-time.',
                  style: AppTextStyles.subtitle2.copyWith(color: AppColors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  'Why this is required:',
                  style: AppTextStyles.body3.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '• Detect suspicious links, popups, and scam patterns\n'
                  '• Analyze visible screen text for fraud warnings\n'
                  '• Trigger instant alerts while you browse or chat\n'
                  '• Keep the floating AI assistant responsive across apps',
                  style: AppTextStyles.subtitle2.copyWith(color: AppColors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  'You can disable this anytime from Accessibility Settings.',
                  style: AppTextStyles.subtitle2.copyWith(
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Not now',
                style: AppTextStyles.button.copyWith(color: AppColors.textGray),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary.withOpacity(0.2),
              ),
              child: Text(
                'Continue',
                style: AppTextStyles.button.copyWith(color: AppColors.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionCard(
    String title,
    String description,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return AppContainer(
      padding: const EdgeInsets.all(16),
      color: color.withOpacity(0.1),
      border: BorderSide(color: color.withOpacity(0.3)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body2.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(description, style: AppTextStyles.subtitle2),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              backgroundColor: color.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              'Enable',
              style: AppTextStyles.button.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  // ── Drawer ────────────────────────────────────────────────────────────────
  Widget _buildDrawer(BuildContext context) {
    return AppDrawer(
      items: [
        AppDrawerItem(
          icon: Icons.home,
          title: 'Home',
          onTap: () => Navigator.pop(context),
        ),
        AppDrawerItem(
          icon: Icons.auto_awesome,
          title: 'Stremini Agent',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const StreminiAgentScreen()),
            );
          },
        ),
        AppDrawerItem(
          icon: Icons.chat_bubble_outline,
          title: 'Quick Chat',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ChatScreen()),
            );
          },
        ),
        AppDrawerItem(
          icon: Icons.keyboard,
          title: 'AI Keyboard',
          onTap: () {
            Navigator.pop(context);
            ref.read(keyboardServiceProvider).openKeyboardSettingsActivity();
          },
        ),
        AppDrawerItem(
          icon: Icons.settings,
          title: 'Settings',
          onTap: () => Navigator.pop(context),
        ),
        AppDrawerItem(
          icon: Icons.help_outline,
          title: 'Contact Us',
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
