// contact_us_screen.dart — THEME MATCH
// Design: Pure black bg, #0AFFE0 teal accent, same card/border style
// ALL LOGIC PRESERVED

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _bg        = Color(0xFF000000);
const _card      = Color(0xFF111111);
const _cardHi    = Color(0xFF161616);
const _border    = Color(0xFF1C1C1C);
const _separator = Color(0xFF1A1A1A);

const _teal      = Color(0xFF0AFFE0);
const _tealDim   = Color(0xFF071A18);
const _tealMid   = Color(0xFF0AC8B4);

const _green     = Color(0xFF30D158);
const _greenDim  = Color(0xFF071A0F);
const _red       = Color(0xFFFF453A);
const _amber     = Color(0xFFFF9F0A);

const _txt       = Color(0xFFFFFFFF);
const _txtSub    = Color(0xFF8C8C8C);
const _txtDim    = Color(0xFF404040);

TextStyle _t(double size, {
  Color color = _txt, FontWeight w = FontWeight.w400,
  double spacing = 0, double h = 1.4,
}) => GoogleFonts.dmSans(fontSize: size, color: color, fontWeight: w, letterSpacing: spacing, height: h);

class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});
  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _isSending = false;
  bool _sent = false;

  static const String _supportEmail = 'streminiai@gmail.com';

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _subjectCtrl.dispose(); _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);

    final subject = Uri.encodeComponent(_subjectCtrl.text.trim());
    final body = Uri.encodeComponent(
        'Name: ${_nameCtrl.text.trim()}\nEmail: ${_emailCtrl.text.trim()}\n\n${_messageCtrl.text.trim()}');
    final mailUri = Uri.parse('mailto:$_supportEmail?subject=$subject&body=$body');

    final launched = await launchUrl(mailUri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    setState(() => _isSending = false);
    if (launched) { setState(() => _sent = true); return; }
    _snack('Could not open email app. Please mail us at $_supportEmail.', err: true);
  }

  void _copyEmail() {
    Clipboard.setData(const ClipboardData(text: _supportEmail));
    _snack('Email copied to clipboard');
  }

  void _snack(String msg, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(err ? Icons.cancel_rounded : Icons.check_circle_rounded, color: err ? _red : _teal, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: _t(13))),
      ]),
      backgroundColor: _card,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _border)),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              physics: const BouncingScrollPhysics(),
              child: _sent ? _successView() : _formView(),
            ),
          ),
          _bottomNav(context),
        ]),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _topBar() {
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
          Text('CONTACT US', style: _t(10, color: _txtSub, spacing: 2.0)),
        ])),
      ]),
    );
  }

  // ── Success view ───────────────────────────────────────────────────────────
  Widget _successView() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.65,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 72, height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: _greenDim,
            border: Border.all(color: _green.withOpacity(0.3), width: 2),
          ),
          child: const Icon(Icons.check_rounded, color: _green, size: 36),
        ),
        const SizedBox(height: 24),
        Text('Email Draft Opened!', style: _t(22, w: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(
          'Your email app was opened with your details.\nTap Send to deliver it to $_supportEmail.',
          style: _t(14, color: _txtSub, h: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: () => setState(() {
            _sent = false;
            _nameCtrl.clear(); _emailCtrl.clear(); _subjectCtrl.clear(); _messageCtrl.clear();
          }),
          child: Container(
            width: double.infinity, height: 52,
            decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text('Send Another Message', style: _t(15, color: Colors.black, w: FontWeight.w700))),
          ),
        ),
      ]),
    );
  }

  // ── Form view ──────────────────────────────────────────────────────────────
  Widget _formView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 20),

      // Support card
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _teal.withOpacity(0.2)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(color: _tealDim, borderRadius: BorderRadius.circular(12), border: Border.all(color: _teal.withOpacity(0.3))),
            child: const Icon(Icons.support_agent_rounded, color: _teal, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("We're here to help", style: _t(16, w: FontWeight.w700)),
            Text('Typically respond within 24–48 hours', style: _t(12, color: _txtSub)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _copyEmail,
              child: Row(children: [
                const Icon(Icons.email_outlined, color: _teal, size: 15),
                const SizedBox(width: 8),
                Text(_supportEmail, style: _t(13, color: _teal)),
                const SizedBox(width: 6),
                const Icon(Icons.copy_rounded, color: _txtSub, size: 13),
              ]),
            ),
          ])),
        ]),
      ),

      const SizedBox(height: 24),

      // Quick actions
      _sectionLabel('QUICK CONTACT'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _quickBtn(icon: Icons.email_outlined, label: 'Email Us', color: _teal, onTap: _copyEmail)),
        const SizedBox(width: 12),
        Expanded(child: _quickBtn(icon: Icons.bug_report_outlined, label: 'Report Bug', color: _amber,
          onTap: () => setState(() => _subjectCtrl.text = 'Bug Report: '))),
      ]),

      const SizedBox(height: 28),

      // Form
      _sectionLabel('SEND A MESSAGE'),
      const SizedBox(height: 14),
      Form(
        key: _formKey,
        child: Column(children: [
          _field(controller: _nameCtrl, label: 'Your Name', icon: Icons.person_outline_rounded,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null),
          const SizedBox(height: 12),
          _field(controller: _emailCtrl, label: 'Your Email', icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Please enter your email';
              if (!v.contains('@') || !v.contains('.')) return 'Please enter a valid email';
              return null;
            }),
          const SizedBox(height: 12),
          _field(controller: _subjectCtrl, label: 'Subject', icon: Icons.subject_outlined,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a subject' : null),
          const SizedBox(height: 12),
          _field(controller: _messageCtrl, label: 'Message', icon: Icons.message_outlined,
            maxLines: 5,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Please enter your message';
              if (v.trim().length < 20) return 'Message must be at least 20 characters';
              return null;
            }),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _isSending ? null : _send,
            child: Container(
              width: double.infinity, height: 54,
              decoration: BoxDecoration(
                color: _isSending ? _teal.withOpacity(0.5) : _teal,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: _isSending
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.send_rounded, size: 18, color: Colors.black),
                      const SizedBox(width: 8),
                      Text('Send Message', style: _t(15, color: Colors.black, w: FontWeight.w700)),
                    ]),
              ),
            ),
          ),
        ]),
      ),

      const SizedBox(height: 32),

      // FAQ
      _sectionLabel('FAQ'),
      const SizedBox(height: 14),
      _faqItem('How do I enable the floating bubble?',
          'Go to Home → tap the power button on the System Standby card → grant Overlay permission when prompted.'),
      const SizedBox(height: 8),
      _faqItem('Why does the keyboard need accessibility?',
          'Accessibility is used only for the scam scanner feature. It reads visible text to detect fraud — nothing else.'),
      const SizedBox(height: 8),
      _faqItem('Is my chat data stored?',
          'Chat history is in-memory only and cleared when you close the app. Nothing is permanently stored on our servers.'),
      const SizedBox(height: 8),
      _faqItem('How do I reset all permissions?',
          'Go to your phone Settings → Apps → Stremini AI → Permissions and revoke any permission you wish to reset.'),

      const SizedBox(height: 40),
    ]);
  }

  Widget _sectionLabel(String text) => Row(children: [
    Container(width: 3, height: 14, color: _teal, margin: const EdgeInsets.only(right: 10)),
    Text(text, style: _t(11, color: _txtSub, w: FontWeight.w700, spacing: 2.0)),
  ]);

  Widget _quickBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(label, style: _t(13, color: color, w: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: _t(14),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: _t(13, color: _txtSub),
        prefixIcon: Icon(icon, color: _txtSub, size: 18),
        filled: true,
        fillColor: _card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _teal, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _red)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _red)),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: maxLines > 1 ? 14 : 0),
      ),
    );
  }

  Widget _faqItem(String question, String answer) {
    return Container(
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          collapsedIconColor: _txtDim,
          iconColor: _teal,
          title: Text(question, style: _t(14, w: FontWeight.w600)),
          children: [
            Text(answer, style: _t(13, color: _txtSub, h: 1.6)),
          ],
        ),
      ),
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
        _navBtn(icon: Icons.settings_outlined, onTap: () => Navigator.pop(context)),
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
}
