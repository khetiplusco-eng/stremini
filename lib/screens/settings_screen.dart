import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/localization/app_strings.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/app_container.dart';
import '../providers/app_settings_provider.dart';
import '../services/keyboard_service.dart';

final keyboardServiceProvider =
    Provider<KeyboardService>((ref) => KeyboardService());

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // These are the only three theme options that map to ThemeMode properly
  final List<String> _themes = ['Dark', 'Light', 'System Default'];
  final List<String> _languages = [
    'English',
    'Hindi',
    'Spanish',
    'French',
    'Arabic',
    'Japanese'
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    String tr(String key) => AppStrings.t(settings.language, key);

    // Colors that adapt to current theme
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = Theme.of(context).cardColor;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final subColor = Theme.of(context).textTheme.labelSmall?.color ?? const Color(0xFF64748B);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('settings')),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(tr('ai_assistant'), context),
            const SizedBox(height: 12),
            _buildToggleTile(
              icon: Icons.notifications_outlined,
              iconColor: AppColors.primary,
              title: tr('notifications'),
              subtitle: tr('notifications_subtitle'),
              value: settings.notificationsEnabled,
              context: context,
              onChanged: (v) async {
                await ref
                    .read(appSettingsProvider.notifier)
                    .setNotificationsEnabled(v);
                _maybeHaptic(settings.hapticFeedback);
              },
            ),
            const SizedBox(height: 8),
            _buildToggleTile(
              icon: Icons.radar,
              iconColor: AppColors.warning,
              title: tr('auto_scan'),
              subtitle: tr('auto_scan_subtitle'),
              value: settings.autoScan,
              context: context,
              onChanged: (v) async {
                await ref.read(appSettingsProvider.notifier).setAutoScan(v);
                _maybeHaptic(settings.hapticFeedback);
              },
            ),
            const SizedBox(height: 24),

            _buildSectionHeader(tr('keyboard'), context),
            const SizedBox(height: 12),
            _buildActionTile(
              icon: Icons.keyboard,
              iconColor: AppColors.secondary,
              title: tr('ai_keyboard_setup'),
              subtitle: tr('ai_keyboard_setup_subtitle'),
              context: context,
              onTap: _openKeyboardSetup,
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.switch_access_shortcut,
              iconColor: AppColors.scanCyan,
              title: tr('switch_keyboard'),
              subtitle: tr('switch_keyboard_subtitle'),
              context: context,
              onTap: _switchKeyboard,
            ),
            const SizedBox(height: 24),

            _buildSectionHeader(tr('appearance'), context),
            const SizedBox(height: 12),

            // Theme selector — changes the whole app via ThemeMode
            _buildDropdownTile(
              icon: Icons.palette_outlined,
              iconColor: AppColors.emotional,
              title: tr('theme'),
              subtitle: _themeSubtitle(settings.theme),
              value: settings.theme,
              items: _themes,
              context: context,
              onChanged: (v) async {
                if (v == null) return;
                await ref.read(appSettingsProvider.notifier).setTheme(v);
                _maybeHaptic(settings.hapticFeedback);
              },
            ),
            const SizedBox(height: 8),

            // Language selector — changes whole app locale
            _buildDropdownTile(
              icon: Icons.language,
              iconColor: AppColors.info,
              title: tr('languages'),
              subtitle: settings.language,
              value: settings.language,
              items: _languages,
              context: context,
              onChanged: (v) async {
                if (v == null) return;
                await ref.read(appSettingsProvider.notifier).setLanguage(v);
                _maybeHaptic(settings.hapticFeedback);
              },
            ),
            const SizedBox(height: 24),

            _buildSectionHeader(tr('privacy'), context),
            const SizedBox(height: 12),
            _buildToggleTile(
              icon: Icons.vibration,
              iconColor: AppColors.primary,
              title: tr('haptic_feedback'),
              subtitle: tr('haptic_feedback_subtitle'),
              value: settings.hapticFeedback,
              context: context,
              onChanged: (v) async {
                await ref
                    .read(appSettingsProvider.notifier)
                    .setHapticFeedback(v);
                _maybeHaptic(v);
              },
            ),
            const SizedBox(height: 8),
            _buildToggleTile(
              icon: Icons.history,
              iconColor: AppColors.warning,
              title: tr('save_chat_history'),
              subtitle: tr('save_chat_history_subtitle'),
              value: settings.saveChatHistory,
              context: context,
              onChanged: (v) async {
                await ref
                    .read(appSettingsProvider.notifier)
                    .setSaveChatHistory(v);
                _maybeHaptic(settings.hapticFeedback);
              },
            ),
            const SizedBox(height: 24),

            _buildSectionHeader(tr('about'), context),
            const SizedBox(height: 12),
            _buildInfoTile(
                icon: Icons.info_outline,
                iconColor: AppColors.textGray,
                title: tr('version'),
                value: '1.0.0',
                context: context),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.privacy_tip_outlined,
              iconColor: AppColors.textGray,
              title: tr('privacy_policy'),
              subtitle: 'Read our privacy policy',
              context: context,
              onTap: () => _showDialog(
                  'Privacy Policy',
                  'Stremini AI respects your privacy. All screen scanning is done locally on your device. No personal data is transmitted without your consent. Chat messages are processed securely and never stored on our servers permanently.',
                  context),
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.description_outlined,
              iconColor: AppColors.textGray,
              title: tr('terms'),
              subtitle: 'Read our terms of service',
              context: context,
              onTap: () => _showDialog(
                  'Terms of Service',
                  'By using Stremini AI, you agree to use the app responsibly. The AI assistant is provided as-is. Stremini AI is not liable for any damages arising from the use of this application. The accessibility service is used solely for scam detection and automation features.',
                  context),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  String _themeSubtitle(String theme) {
    switch (theme) {
      case 'Light':
        return 'Light mode';
      case 'System Default':
        return 'Follows system setting';
      default:
        return 'Dark mode';
    }
  }

  Widget _buildSectionHeader(String title, BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: Theme.of(context).textTheme.labelSmall?.color ??
            AppColors.textGray,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        fontSize: 11,
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required BuildContext context,
  }) {
    final cardColor = Theme.of(context).cardColor;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final subColor = Theme.of(context).textTheme.labelSmall?.color ??
        const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(color: textColor, fontSize: 14)),
                Text(subtitle,
                    style: TextStyle(color: subColor, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    final cardColor = Theme.of(context).cardColor;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final subColor = Theme.of(context).textTheme.labelSmall?.color ??
        const Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(color: textColor, fontSize: 14)),
                  Text(subtitle,
                      style: TextStyle(color: subColor, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: subColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required BuildContext context,
  }) {
    final cardColor = Theme.of(context).cardColor;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final subColor = Theme.of(context).textTheme.labelSmall?.color ??
        const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(color: textColor, fontSize: 14)),
                Text(subtitle,
                    style: TextStyle(color: subColor, fontSize: 12)),
              ],
            ),
          ),
          DropdownButton<String>(
            value: value,
            items: items
                .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e,
                          style: TextStyle(color: textColor, fontSize: 14)),
                    ))
                .toList(),
            onChanged: onChanged,
            dropdownColor: cardColor,
            underline: const SizedBox(),
            icon: Icon(Icons.expand_more, color: subColor),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required BuildContext context,
  }) {
    final cardColor = Theme.of(context).cardColor;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
              child:
                  Text(title, style: TextStyle(color: textColor, fontSize: 14))),
          Text(value,
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _openKeyboardSetup() async {
    final service = ref.read(keyboardServiceProvider);
    final status = await service.checkKeyboardStatus();
    _maybeHaptic(ref.read(appSettingsProvider).hapticFeedback);
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
      SnackBar(
          content: Text(AppStrings.t(
              ref.read(appSettingsProvider).language, 'already_active'))),
    );
  }

  Future<void> _switchKeyboard() async {
    _maybeHaptic(ref.read(appSettingsProvider).hapticFeedback);
    await ref.read(keyboardServiceProvider).showKeyboardPicker();
  }

  void _maybeHaptic(bool enabled) {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  void _showDialog(String title, String content, BuildContext context) {
    final settings = ref.read(appSettingsProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(content,
              style: const TextStyle(height: 1.6, fontSize: 14)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppStrings.t(settings.language, 'close'),
              style: const TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}