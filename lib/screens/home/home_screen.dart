import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_container.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/feature_card.dart';
import '../../core/widgets/permission_card.dart';
import '../../core/widgets/info_step.dart';
import '../../controllers/home_controller.dart';
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
      appBar: _buildAppBar(context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGreetingCard(context),
            const SizedBox(height: 24),

            // ── GitHub Agent hero banner ──────────────────────────────
            _buildAgentHeroBanner(context),
            const SizedBox(height: 28),

            Text('All Features', style: AppTextStyles.h2),
            const SizedBox(height: 16),

            _buildSmartChatbotCard(context, state, controller),
            const SizedBox(height: 16),

            _buildDocumentChatCard(context),
            const SizedBox(height: 16),

            keyboardStatus.when(
              data: (status) => _buildKeyboardCard(context, status),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            _buildInfoCard(),
            const SizedBox(height: 32),

            if (!state.permissionStatus.hasAll) ...[
              Text('Required Permissions', style: AppTextStyles.h3),
              const SizedBox(height: 12),
              if (state.permissionStatus.needsOverlay)
                PermissionCard(
                  title: 'Overlay Permission',
                  description: 'Required for floating bubble over other apps',
                  icon: Icons.bubble_chart,
                  color: AppColors.warning,
                  onTap: () => controller.requestOverlayPermission(),
                ),
              if (state.permissionStatus.needsAccessibility)
                PermissionCard(
                  title: 'Accessibility Permission',
                  description: 'Required for screen scanner to detect scams',
                  icon: Icons.accessibility_new,
                  color: AppColors.emotional,
                  onTap: () => controller.requestAccessibilityPermission(),
                ),
              if (state.permissionStatus.needsMicrophone)
                PermissionCard(
                  title: 'Microphone Permission',
                  description: 'Required for Auto Tasker voice commands',
                  icon: Icons.mic,
                  color: AppColors.info,
                  onTap: () => controller.requestMicrophonePermission(),
                ),
              const SizedBox(height: 16),
              AppContainer(
                padding: const EdgeInsets.all(16),
                color: AppColors.info.withOpacity(0.1),
                border: BorderSide(color: AppColors.info.withOpacity(0.3)),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppColors.info, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Overlay, Accessibility, and Microphone permissions are required for all AI tools to work properly',
                        style: AppTextStyles.body3
                            .copyWith(color: AppColors.info),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.black,
      elevation: 0,
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
          Text(AppConstants.appName, style: AppTextStyles.h2),
        ],
      ),
      centerTitle: true,
      actions: const [SizedBox(width: 48)],
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
              MaterialPageRoute(
                  builder: (context) => const ChatScreen()),
            );
          },
        ),
        AppDrawerItem(
          icon: Icons.keyboard,
          title: 'AI Keyboard',
          onTap: () {
            Navigator.pop(context);
            ref
                .read(keyboardServiceProvider)
                .openKeyboardSettingsActivity();
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

  // ── Greeting card ─────────────────────────────────────────────────────────
  Widget _buildGreetingCard(BuildContext context) {
    return AppContainer(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.primary.withOpacity(0.2),
          AppColors.secondary.withOpacity(0.2),
        ],
      ),
      border: BorderSide(color: AppColors.info.withOpacity(0.3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_getGreeting(), style: AppTextStyles.h1),
              const Spacer(),
              AppContainer(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                color: AppColors.white.withOpacity(0.1),
                borderRadius: 20,
                border: BorderSide(
                    color: AppColors.white.withOpacity(0.2)),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ChatScreen()),
                ),
                child: Row(
                  children: [
                    Icon(Icons.touch_app,
                        color: AppColors.info.withOpacity(0.8),
                        size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Quick Chat',
                      style: AppTextStyles.body3.copyWith(
                        color: AppColors.info.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Autonomous AI reasoning engine at your service.',
            style: AppTextStyles.subtitle1,
          ),
        ],
      ),
    );
  }

  // ── GitHub Agent hero banner ──────────────────────────────────────────────
  // Full-width, eye-catching banner — the main call-to-action on the home screen.
  Widget _buildAgentHeroBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => const StreminiAgentScreen()),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0D2137),
              AppColors.scanCyan.withOpacity(0.18),
              const Color(0xFF0D1B2A),
            ],
          ),
          border: Border.all(
              color: AppColors.scanCyan.withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.scanCyan.withOpacity(0.12),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative glow orb (top-right)
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.scanCyan.withOpacity(0.07),
                ),
              ),
            ),
            // Decorative glow orb (bottom-left)
            Positioned(
              bottom: -30,
              left: -10,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.08),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tag pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.scanCyan.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: AppColors.scanCyan.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.scanCyan,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Engine Ready',
                          style: AppTextStyles.body3.copyWith(
                            color: AppColors.scanCyan,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Title row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stremini',
                              style: AppTextStyles.h1.copyWith(
                                color: AppColors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              'GitHub Architect',
                              style: AppTextStyles.h1.copyWith(
                                color: AppColors.scanCyan,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Icon box
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.scanCyan.withOpacity(0.3),
                              AppColors.primary.withOpacity(0.3),
                            ],
                          ),
                          border: Border.all(
                              color: AppColors.scanCyan.withOpacity(0.5)),
                        ),
                        child: const Icon(Icons.auto_awesome,
                            color: AppColors.scanCyan, size: 28),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Reads your repo, writes the fix, pushes to GitHub — fully autonomous.',
                    style: AppTextStyles.body2
                        .copyWith(color: Colors.white70, height: 1.4),
                  ),

                  const SizedBox(height: 16),

                  // Capability chips row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildCapChip(
                          Icons.account_tree_outlined, 'Repo Reasoning'),
                      _buildCapChip(Icons.bug_report_outlined, 'Debug Loop'),
                      _buildCapChip(Icons.code, 'Code Synthesis'),
                      _buildCapChip(
                          Icons.upload_outlined, 'Auto Push'),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // CTA button
                  Container(
                    width: double.infinity,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [AppColors.scanCyan, AppColors.primary],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.scanCyan.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.terminal,
                            color: AppColors.white, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Launch Agent',
                          style: AppTextStyles.button.copyWith(
                            fontSize: 15,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_ios,
                            color: AppColors.white, size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.scanCyan, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.body3.copyWith(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Smart Chatbot card ────────────────────────────────────────────────────
  Widget _buildSmartChatbotCard(
    BuildContext context,
    HomeState state,
    HomeController controller,
  ) {
    return FeatureCard(
      title: 'Smart Chatbot & Scam Detector',
      description: 'Floating AI assistant with real-time screen analyzer',
      icon: Icons.chat_bubble_outline,
      iconColor: AppColors.primary,
      status: state.bubbleActive ? 'Active' : 'Inactive',
      statusColor:
          state.bubbleActive ? AppColors.success : AppColors.lightGray,
      badges: const ['Floating Chat', 'Screen Scanner', 'Scam Detection'],
      trailing: state.isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation(AppColors.primary),
              ),
            )
          : Switch(
              value: state.bubbleActive,
              onChanged: state.isLoading
                  ? null
                  : (value) async {
                      final success =
                          await controller.toggleBubble(value);
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
                            content: Text(value
                                ? 'Floating bubble activated!'
                                : 'Floating bubble deactivated'),
                            backgroundColor: value
                                ? AppColors.success
                                : AppColors.lightGray,
                          ),
                        );
                      }
                    },
              activeColor: AppColors.primary,
            ),
    );
  }

  // ── Document Chat card ────────────────────────────────────────────────────
  Widget _buildDocumentChatCard(BuildContext context) {
    return FeatureCard(
      title: 'Document Chat',
      description: 'Upload a PDF or text file and ask questions about it',
      icon: Icons.picture_as_pdf_outlined,
      iconColor: AppColors.secondary,
      status: 'Ready',
      statusColor: AppColors.success,
      badges: const ['PDF', 'TXT / MD', 'Q&A', 'Multi-chunk'],
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ChatScreen()),
      ),
      trailing: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.secondary.withOpacity(0.15),
          border: Border.all(
              color: AppColors.secondary.withOpacity(0.4)),
        ),
        child: const Icon(Icons.arrow_forward_ios,
            color: AppColors.secondary, size: 14),
      ),
    );
  }

  // ── AI Keyboard card ──────────────────────────────────────────────────────
  Widget _buildKeyboardCard(BuildContext context, KeyboardStatus status) {
    final keyboardService = ref.read(keyboardServiceProvider);
    return FeatureCard(
      title: 'AI-Powered Keyboard',
      description:
          'Smart typing with translation, completion & enhancement',
      icon: Icons.keyboard,
      iconColor: AppColors.secondary,
      status: status.isActive
          ? 'Active'
          : status.isEnabled
              ? 'Enabled'
              : 'Disabled',
      statusColor: status.isActive
          ? AppColors.success
          : status.isEnabled
              ? AppColors.warning
              : AppColors.lightGray,
      badges: const ['Translate', 'Complete', 'Enhance', 'Emoji'],
      trailing: IconButton(
        icon: const Icon(Icons.settings, color: AppColors.secondary),
        onPressed: () => keyboardService.openKeyboardSettingsActivity(),
      ),
      onTap: () {
        if (!status.isEnabled) {
          keyboardService.openKeyboardSettings();
        } else if (!status.isSelected) {
          keyboardService.showKeyboardPicker();
        } else {
          keyboardService.openKeyboardSettingsActivity();
        }
      },
    );
  }

  // ── Info card ─────────────────────────────────────────────────────────────
  Widget _buildInfoCard() {
    return AppContainer(
      padding: const EdgeInsets.all(16),
      border: BorderSide(color: AppColors.scanCyan.withOpacity(0.3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline,
                  color: AppColors.scanCyan, size: 24),
              const SizedBox(width: 12),
              Text('How to use:',
                  style: AppTextStyles.body2
                      .copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          const InfoStep(
              number: '1', text: 'Grant all required permissions'),
          const InfoStep(
              number: '2',
              text: 'Tap "Launch Agent" to debug & fix a GitHub repo autonomously',
              color: AppColors.scanCyan),
          const InfoStep(
              number: '3', text: 'Toggle Smart Chatbot for floating overlay'),
          const InfoStep(
              number: '4',
              text: 'Use Document Chat to upload a PDF and ask questions'),
          const InfoStep(
              number: '5',
              text: 'Enable AI Keyboard for smart typing',
              color: AppColors.secondary),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning! 👋';
    if (hour < 18) return 'Good afternoon! 👋';
    return 'Good evening! 👋';
  }
}