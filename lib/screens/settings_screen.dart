// settings_screen.dart — THEME MATCH
// Design: Pure black bg, #0AFFE0 teal accent, same card/border style
// ALL LOGIC PRESERVED

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/localization/app_strings.dart';
import '../core/theme/app_colors.dart';
import '../providers/app_settings_provider.dart';
import '../services/keyboard_service.dart';

final keyboardServiceProvider = Provider<KeyboardService>((ref) => KeyboardService());

// ── Design tokens ─────────────────────────────────────────────────────────────
const _bg        = Color(0xFF000000);
const _card      = Color(0xFF111111);
const _border    = Color(0xFF1C1C1C);
const _separator = Color(0xFF1A1A1A);

const _teal      = Color(0xFF0AFFE0);
const _tealDim   = Color(0xFF071A18);

const _green     = Color(0xFF30D158);
const _red       = Color(0xFFFF453A);
const _amber     = Color(0xFFFF9F0A);
const _purple    = Color(0xFFBF5AF2);
const _blue      = Color(0xFF4A9EFF);

const _txt       = Color(0xFFFFFFFF);
const _txtSub    = Color(0xFF8C8C8C);
const _txtDim    = Color(0xFF404040);

TextStyle _t(double size, {
  Color color = _txt, FontWeight w = FontWeight.w400,
  double spacing = 0, double h = 1.4,
}) => GoogleFonts.dmSans(fontSize: size, color: color, fontWeight: w, letterSpacing: spacing, height: h);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final List<String> _themes = ['Dark', 'Light', 'System Default'];
  final List<String> _languages = ['English', 'Hindi', 'Spanish', 'French', 'Arabic', 'Japanese'];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    String tr(String key) => AppStrings.t(settings.language, key);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _topBar(tr),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              physics: const BouncingScrollPhysics(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 16),
                _sectionLabel('AI ASSISTANT'),
                const SizedBox(height: 12),
                _settingsCard([
                  _toggleRow(
                    iconBg: const Color(0xFF0D1A2E), icon: Icons.notifications_outlined, iconColor: _blue,
                    title: tr('notifications'), subtitle: tr('notifications_subtitle'),
                    value: settings.notificationsEnabled,
                    onChanged: (v) async { await ref.read(appSettingsProvider.notifier).setNotificationsEnabled(v); _haptic(settings.hapticFeedback); },
                    isLast: false,
                  ),
                  _divider(),
                  _toggleRow(
                    iconBg: const Color(0xFF1A1000), icon: Icons.radar_rounded, iconColor: _amber,
                    title: tr('auto_scan'), subtitle: tr('auto_scan_subtitle'),
                    value: settings.autoScan,
                    onChanged: (v) async { await ref.read(appSettingsProvider.notifier).setAutoScan(v); _haptic(settings.hapticFeedback); },
                    isLast: true,
                  ),
                ]),

                const SizedBox(height: 28),
                _sectionLabel('KEYBOARD'),
                const SizedBox(height: 12),
                _settingsCard([
                  _actionRow(
                    iconBg: const Color(0xFF071A18), icon: Icons.keyboard_outlined, iconColor: _teal,
                    title: tr('ai_keyboard_setup'), subtitle: tr('ai_keyboard_setup_subtitle'),
                    onTap: _openKeyboardSetup, isLast: false,
                  ),
                  _divider(),
                  _actionRow(
                    iconBg: const Color(0xFF071A18), icon: Icons.switch_access_shortcut_rounded, iconColor: _tealDim == _teal ? _teal : const Color(0xFF5AC8FA),
                    title: tr('switch_keyboard'), subtitle: tr('switch_keyboard_subtitle'),
                    onTap: _switchKeyboard, isLast: true,
                  ),
                ]),

                const SizedBox(height: 28),
                _sectionLabel('APPEARANCE'),
                const SizedBox(height: 12),
                _settingsCard([
                  _dropdownRow(
                    iconBg: const Color(0xFF1A0D28), icon: Icons.palette_outlined, iconColor: _purple,
                    title: tr('theme'), subtitle: _themeSubtitle(settings.theme),
                    value: settings.theme, items: _themes,
                    onChanged: (v) async { if (v == null) return; await ref.read(appSettingsProvider.notifier).setTheme(v); _haptic(settings.hapticFeedback); },
                    isLast: false,
                  ),
                  _divider(),
                  _dropdownRow(
                    iconBg: const Color(0xFF0D1A2E), icon: Icons.language_rounded, iconColor: _blue,
                    title: tr('languages'), subtitle: settings.language,
                    value: settings.language, items: _languages,
                    onChanged: (v) async { if (v == null) return; await ref.read(appSettingsProvider.notifier).setLanguage(v); _haptic(settings.hapticFeedback); },
                    isLast: true,
                  ),
                ]),

                const SizedBox(height: 28),
                _sectionLabel('PRIVACY'),
                const SizedBox(height: 12),
                _settingsCard([
                  _toggleRow(
                    iconBg: const Color(0xFF071A18), icon: Icons.vibration_rounded, iconColor: _teal,
                    title: tr('haptic_feedback'), subtitle: tr('haptic_feedback_subtitle'),
                    value: settings.hapticFeedback,
                    onChanged: (v) async { await ref.read(appSettingsProvider.notifier).setHapticFeedback(v); _haptic(v); },
                    isLast: false,
                  ),
                  _divider(),
                  _toggleRow(
                    iconBg: const Color(0xFF1A1000), icon: Icons.history_rounded, iconColor: _amber,
                    title: tr('save_chat_history'), subtitle: tr('save_chat_history_subtitle'),
                    value: settings.saveChatHistory,
                    onChanged: (v) async { await ref.read(appSettingsProvider.notifier).setSaveChatHistory(v); _haptic(settings.hapticFeedback); },
                    isLast: true,
                  ),
                ]),

                const SizedBox(height: 28),
                _sectionLabel('ABOUT'),
                const SizedBox(height: 12),
                _settingsCard([
                  _infoRow(
                    iconBg: const Color(0xFF141414), icon: Icons.info_outline_rounded, iconColor: _txtSub,
                    title: tr('version'), value: '1.0.0', isLast: false,
                  ),
                  _divider(),
                  _actionRow(
                    iconBg: const Color(0xFF141414), icon: Icons.privacy_tip_outlined, iconColor: _txtSub,
                    title: tr('privacy_policy'), subtitle: 'Read our privacy policy',
                    onTap: () => _showInfoDialog('Privacy Policy',
                        'Stremini AI respects your privacy. All screen scanning is done locally on your device. No personal data is transmitted without your consent. Chat messages are processed securely and never stored on our servers permanently.'),
                    isLast: false,
                  ),
                  _divider(),
                  _actionRow(
                    iconBg: const Color(0xFF141414), icon: Icons.description_outlined, iconColor: _txtSub,
                    title: tr('terms'), subtitle: 'Read our terms of service',
                    onTap: () => _showInfoDialog('Terms of Service',
                        'By using Stremini AI, you agree to use the app responsibly. The AI assistant is provided as-is. Stremini AI is not liable for any damages arising from the use of this application. The accessibility service is used solely for scam detection and automation features.'),
                    isLast: true,
                  ),
                ]),

                const SizedBox(height: 40),
              ]),
            ),
          ),
          _bottomNav(context),
        ]),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _topBar(String Function(String) tr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(color: _bg, border: Border(bottom: BorderSide(color: _border, width: 0.5))),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _txtSub, size: 14),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('STREMINI AI', style: _t(16, w: FontWeight.w800, spacing: 1.0)),
          Text('SETTINGS', style: _t(10, color: _txtSub, spacing: 2.0)),
        ])),
      ]),
    );
  }

  // ── Section label ──────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Row(children: [
    Container(width: 3, height: 14, color: _teal, margin: const EdgeInsets.only(right: 10)),
    Text(text, style: _t(11, color: _txtSub, w: FontWeight.w700, spacing: 2.0)),
  ]);

  Widget _settingsCard(List<Widget> children) => Container(
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
    child: Column(children: children),
  );

  Widget _divider() => Container(height: 0.5, color: _separator, margin: const EdgeInsets.symmetric(horizontal: 16));

  // ── Toggle row ─────────────────────────────────────────────────────────────
  Widget _toggleRow({
    required Color iconBg, required IconData icon, required Color iconColor,
    required String title, required String subtitle,
    required bool value, required ValueChanged<bool> onChanged, required bool isLast,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: iconColor, size: 19),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _t(14, w: FontWeight.w600)),
          Text(subtitle, style: _t(12, color: _txtSub)),
        ])),
        Switch(
          value: value, onChanged: onChanged,
          activeColor: _teal,
          activeTrackColor: _tealDim,
          inactiveThumbColor: _txtDim,
          inactiveTrackColor: const Color(0xFF1A1A1A),
        ),
      ]),
    );
  }

  // ── Action row ─────────────────────────────────────────────────────────────
  Widget _actionRow({
    required Color iconBg, required IconData icon, required Color iconColor,
    required String title, required String subtitle,
    required VoidCallback onTap, required bool isLast,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _t(14, w: FontWeight.w600)),
            Text(subtitle, style: _t(12, color: _txtSub)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: _txtDim, size: 18),
        ]),
      ),
    );
  }

  // ── Dropdown row ───────────────────────────────────────────────────────────
  Widget _dropdownRow({
    required Color iconBg, required IconData icon, required Color iconColor,
    required String title, required String subtitle,
    required String value, required List<String> items,
    required ValueChanged<String?> onChanged, required bool isLast,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: iconColor, size: 19),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _t(14, w: FontWeight.w600)),
          Text(subtitle, style: _t(12, color: _txtSub)),
        ])),
        Theme(
          data: ThemeData.dark().copyWith(canvasColor: _card),
          child: DropdownButton<String>(
            value: value,
            items: items.map((e) => DropdownMenuItem(value: e,
              child: Text(e, style: _t(13, color: _txt)))).toList(),
            onChanged: onChanged,
            dropdownColor: _card,
            underline: const SizedBox(),
            icon: const Icon(Icons.expand_more_rounded, color: _txtDim, size: 18),
            style: _t(13),
          ),
        ),
      ]),
    );
  }

  // ── Info row ───────────────────────────────────────────────────────────────
  Widget _infoRow({
    required Color iconBg, required IconData icon, required Color iconColor,
    required String title, required String value, required bool isLast,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: iconColor, size: 19),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(title, style: _t(14, w: FontWeight.w600))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: _tealDim, borderRadius: BorderRadius.circular(8), border: Border.all(color: _teal.withOpacity(0.2))),
          child: Text(value, style: _t(13, color: _teal, w: FontWeight.w600)),
        ),
      ]),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────
  Widget _bottomNav(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 12, top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(top: BorderSide(color: _border, width: 0.5)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _navBtn(icon: Icons.home_outlined, onTap: () => Navigator.pop(context)),
        _navBtn(icon: Icons.code_rounded, onTap: () => Navigator.pop(context)),
        _navBtn(icon: Icons.chat_bubble_outline_rounded, onTap: () => Navigator.pop(context)),
        _navBtn(icon: Icons.settings_outlined, active: true, onTap: () {}),
      ]),
    );
  }

  Widget _navBtn({required IconData icon, VoidCallback? onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? _teal : _txtDim, size: 22),
          if (active) ...[
            const SizedBox(height: 4),
            Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: _teal)),
          ],
        ]),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _themeSubtitle(String theme) {
    switch (theme) { case 'Light': return 'Light mode'; case 'System Default': return 'Follows system setting'; default: return 'Dark mode'; }
  }

  void _haptic(bool enabled) { if (enabled) HapticFeedback.selectionClick(); }

  Future<void> _openKeyboardSetup() async {
    final service = ref.read(keyboardServiceProvider);
    final status = await service.checkKeyboardStatus();
    _haptic(ref.read(appSettingsProvider).hapticFeedback);
    if (!status.isEnabled) { await service.openKeyboardSettings(); return; }
    if (!status.isSelected) { await service.showKeyboardPicker(); return; }
    if (!mounted) return;
    _showSnack('AI Keyboard is already active');
  }

  Future<void> _switchKeyboard() async {
    _haptic(ref.read(appSettingsProvider).hapticFeedback);
    await ref.read(keyboardServiceProvider).showKeyboardPicker();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: _t(13)),
      backgroundColor: _card,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _border)),
    ));
  }

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: _border)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _t(18, w: FontWeight.w700)),
            const SizedBox(height: 14),
            Text(content, style: _t(14, color: _txtSub, h: 1.6)),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: 48,
                decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text('Close', style: _t(15, color: Colors.black, w: FontWeight.w700))),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
