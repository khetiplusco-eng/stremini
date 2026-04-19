// chat_screen.dart — PREMIUM REDESIGN v3
// Design: Reference-matched — dark obsidian, cyan accent, DM Sans typography
// Layout: Matches provided screenshots exactly — welcome hero, suggestion cards,
//         bottom input bar with attach/mic/send, bottom nav hint
// Typography: DM Sans throughout, small-to-medium scale (12–22px max)
// ALL FUNCTIONALITY PRESERVED

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mime/mime.dart';

import '../core/widgets/app_drawer.dart';
import '../providers/chat_provider.dart';
import '../models/message_model.dart';
import 'contact_us_screen.dart';
import 'home/home_screen.dart';
import 'settings_screen.dart';

// ── Design Tokens ─────────────────────────────────────────────────────────────
const _bg         = Color(0xFF0A0C10);
const _surface    = Color(0xFF13161C);
const _surfaceHi  = Color(0xFF1A1E26);
const _card       = Color(0xFF161A22);
const _border     = Color(0xFF1E242E);
const _borderHi   = Color(0xFF262E3A);
const _accent     = Color(0xFF22D4F0);   // cyan — matches screenshots
const _accentDim  = Color(0xFF061419);
const _accentSoft = Color(0xFF22D4F030);
const _purple     = Color(0xFF8B6BF5);
const _purpleDim  = Color(0xFF120F28);
const _green      = Color(0xFF22D47A);
const _red        = Color(0xFFEF4444);
const _amber      = Color(0xFFF59E0B);
const _txt        = Color(0xFFE8EDF5);
const _txtSub     = Color(0xFF6B7A8D);
const _txtDim     = Color(0xFF353F4E);
const _userBubble = Color(0xFF0E1520);
const _logoPath   = 'lib/img/logo.jpg';

// ── Suggestion data ───────────────────────────────────────────────────────────
class _SuggestionItem {
  final IconData icon;
  final String   title;
  final String   subtitle;
  const _SuggestionItem(this.icon, this.title, this.subtitle);
}

const _suggestions = [
  _SuggestionItem(Icons.description_outlined,
      'Summarize a document', 'Extract key points and insights quickly.'),
  _SuggestionItem(Icons.code_rounded,
      'Review and fix my code', 'Identify bugs and suggest optimizations.'),
  _SuggestionItem(Icons.lightbulb_outline_rounded,
      'Brainstorm creative ideas', 'Generate concepts for your next big project.'),
  _SuggestionItem(Icons.translate_rounded,
      'Translate this text', 'Convert content to another language.'),
];

// ── Text style helper — DM Sans ───────────────────────────────────────────────
TextStyle _dmSans({
  double size        = 13,
  FontWeight weight  = FontWeight.w400,
  Color color        = _txt,
  double height      = 1.5,
  double letterSpacing = 0,
}) => GoogleFonts.dmSans(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
);

// ── Helpers ───────────────────────────────────────────────────────────────────
String _fmtTime(DateTime dt) {
  final h  = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m  = dt.minute.toString().padLeft(2, '0');
  final ap = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ap';
}

Future<String> _extractPdfText(List<int> bytes) async {
  try {
    final raw     = utf8.decode(bytes, allowMalformed: true);
    final matches = RegExp(r'[\x20-\x7E]{8,}').allMatches(raw);
    if (matches.isEmpty) return '';
    return matches.map((m) => m.group(0)?.trim() ?? '').where((s) => s.isNotEmpty).join('\n').trim();
  } catch (e) { return ''; }
}

Future<String> _readTextFile(File file) async {
  try { return await file.readAsString(); }
  catch (_) { return utf8.decode(await file.readAsBytes(), allowMalformed: true); }
}

Future<String> _extractDocxText(List<int> bytes) async {
  try {
    final raw   = utf8.decode(bytes, allowMalformed: true);
    final regex = RegExp(r'<w:t[^>]*>([^<]*)<\/w:t>', dotAll: true);
    final matches = regex.allMatches(raw);
    if (matches.isEmpty) {
      return raw.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return matches.map((m) => m.group(1) ?? '').join(' ').trim();
  } catch (e) { return ''; }
}

Future<String> _extractOcrText(File imageFile) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFile(imageFile));
    return result.text.trim();
  } catch (e) { return ''; }
  finally { recognizer.close(); }
}

String _convertMath(String text) {
  return text
    .replaceAllMapped(RegExp(r'\\frac\{([^}]+)\}\{([^}]+)\}'), (m) => '(${m[1]})/(${m[2]})')
    .replaceAllMapped(RegExp(r'\\sqrt\{([^}]+)\}'),             (m) => '√(${m[1]})')
    .replaceAllMapped(RegExp(r'([a-zA-Z])\^\{([^}]+)\}'),       (m) => '${m[1]}^${m[2]}')
    .replaceAllMapped(RegExp(r'([a-zA-Z])_\{([^}]+)\}'),        (m) => '${m[1]}_${m[2]}')
    .replaceAll(r'\times','×').replaceAll(r'\div','÷')
    .replaceAll(r'\pm','±').replaceAll(r'\infty','∞')
    .replaceAll(r'\pi','π').replaceAll(r'\alpha','α')
    .replaceAll(r'\beta','β').replaceAll(r'\gamma','γ')
    .replaceAll(r'\sigma','σ').replaceAll(r'\mu','μ')
    .replaceAll(r'\sum','∑').replaceAll(r'\int','∫')
    .replaceAll(r'\approx','≈').replaceAll(r'\neq','≠')
    .replaceAll(r'\leq','≤').replaceAll(r'\geq','≥')
    .replaceAll(r'\cdot','·').replaceAll(r'\rightarrow','→')
    .replaceAllMapped(RegExp(r'\\[a-zA-Z]+\{([^}]*)\}'), (m) => m[1] ?? '')
    .replaceAll(RegExp(r'\\[a-zA-Z]+\s*'), '');
}

String _cleanBotResponse(String text) {
  String s = _convertMath(text);
  s = s.replaceAllMapped(RegExp(r'```(?:[a-zA-Z0-9_+\-]*)\n?([\s\S]*?)```'), (m) => (m[1] ?? '').trim());
  s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'\*\*\*([^*]+)\*\*\*'), r'$1');
  s = s.replaceAll(RegExp(r'\*\*([^*]+)\*\*'),     r'$1');
  s = s.replaceAll(RegExp(r'\*([^*\n]+)\*'),        r'$1');
  s = s.replaceAll(RegExp(r'___([^_]+)___'),        r'$1');
  s = s.replaceAll(RegExp(r'__([^_]+)__'),          r'$1');
  s = s.replaceAll(RegExp(r'_([^_\n]+)_'),          r'$1');
  s = s.replaceAllMapped(RegExp(r'`([^`]+)`'),      (m) => m[1] ?? '');
  s = s.replaceAll(RegExp(r'^[-*_]{3,}\s*$',        multiLine: true), '');
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1] ?? '');
  s = s.replaceAll(RegExp(r'(?<!\w)\*+(?!\w)'), '');
  s = s.replaceAll(RegExp(r'(?<!\w)_+(?!\w)'), '');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatScreen
// ─────────────────────────────────────────────────────────────────────────────
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode  = FocusNode();
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;
  bool _processingDoc = false;
  bool _isTyping      = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _controller.addListener(() {
      setState(() => _isTyping = _controller.text.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _controller.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Attachment helpers ─────────────────────────────────────────────────────
  void _pickAttachment() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      barrierColor: Colors.black.withOpacity(0.75),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AttachSheet(onPicked: _handlePick),
    );
  }

  Future<void> _handlePick(String type) async {
    switch (type) {
      case 'pdf':   await _pickDoc(['pdf']); break;
      case 'text':  await _pickDoc(['txt', 'md', 'csv', 'json', 'log', 'docx']); break;
      case 'image':
        final img = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (img == null) break;
        await _processImageWithOcr(File(img.path));
        break;
      case 'file':
        final r = await FilePicker.platform.pickFiles();
        if (r?.files.single.path == null) break;
        final file = File(r!.files.single.path!);
        final mime = lookupMimeType(file.path) ?? '';
        if (mime.startsWith('image/')) {
          await _processImageWithOcr(file);
        } else {
          final ext = file.path.split('.').last.toLowerCase();
          await _pickDocFromFile(file, ext);
        }
        break;
    }
  }

  Future<void> _processImageWithOcr(File imageFile) async {
    final name = imageFile.path.split('/').last;
    setState(() => _processingDoc = true);
    try {
      final text = await _extractOcrText(imageFile);
      if (!mounted) return;
      if (text.isEmpty) { _snack('No text found in image.', err: true); return; }
      ref.read(chatNotifierProvider.notifier)
          .loadDocument(DocumentContext(fileName: '📷 $name (OCR)', text: text));
      _snack('Image loaded into context');
    } catch (e) {
      if (mounted) _snack('OCR failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _processingDoc = false);
    }
  }

  Future<void> _pickDoc(List<String> exts) async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: exts);
    if (r == null || r.files.single.path == null) return;
    final file = File(r.files.single.path!);
    final name = r.files.single.name;
    final ext  = name.split('.').last.toLowerCase();
    await _pickDocFromFile(file, ext, displayName: name);
  }

  Future<void> _pickDocFromFile(File file, String ext, {String? displayName}) async {
    final name = displayName ?? file.path.split('/').last;
    setState(() => _processingDoc = true);
    try {
      String text;
      if (ext == 'pdf') {
        text = await _extractPdfText(await file.readAsBytes());
      } else if (ext == 'docx') {
        text = await _extractDocxText(await file.readAsBytes());
      } else {
        text = await _readTextFile(file);
      }
      if (!mounted) return;
      if (text.trim().isEmpty) { _snack('Could not extract text.', err: true); return; }
      ref.read(chatNotifierProvider.notifier)
          .loadDocument(DocumentContext(fileName: name, text: text));
      _snack('"$name" loaded');
    } catch (e) {
      if (mounted) _snack('Error: $e', err: true);
    } finally {
      if (mounted) setState(() => _processingDoc = false);
    }
  }

  // ── Send ───────────────────────────────────────────────────────────────────
  void _send([String? override]) {
    final text = (override ?? _controller.text).trim();
    if (text.isEmpty) return;
    ref.read(chatNotifierProvider.notifier).sendMessage(text);
    _controller.clear();
    _focusNode.unfocus();
    _scrollDown();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(err ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: err ? _red : _green, size: 14),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: _dmSans(size: 12, color: _txt))),
      ]),
      backgroundColor: _surfaceHi,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: (err ? _red : _green).withOpacity(0.3)),
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  void _showVoiceSnack() => _snack('Voice input coming soon!');

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider);
    final docCtx    = ref.watch(documentContextProvider);
    ref.listen<AsyncValue<List<Message>>>(
        chatNotifierProvider, (_, next) => next.whenData((_) => _scrollDown()));

    final messages    = chatState.value ?? [];
    final showWelcome = messages.length <= 1 && !messages.any((m) => m.type == MessageType.user);

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(docCtx),
      drawer: _buildDrawer(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          if (docCtx != null) _docBanner(docCtx),
          Expanded(
            child: showWelcome ? _welcomeView() : _msgList(chatState),
          ),
          if (_processingDoc) _processingBar(),
          _inputArea(docCtx),
        ]),
      ),
    );
  }

  // ── AppBar — matches screenshot: logo + name left, copy+clear right ────────
  PreferredSizeWidget _buildAppBar(DocumentContext? docCtx) {
    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leadingWidth: 48,
      leading: Builder(builder: (ctx) => GestureDetector(
        onTap: () => Scaffold.of(ctx).openDrawer(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.menu_rounded, color: _txtSub, size: 16),
          ),
        ),
      )),
      title: Row(children: [
        // Logo — properly sized avatar with cyan ring
        _logoAvatar(32),
        const SizedBox(width: 9),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Stremini AI', style: _dmSans(size: 13, weight: FontWeight.w700)),
          if (docCtx != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _accentDim,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: _accent.withOpacity(0.25)),
              ),
              child: Text('DOC MODE',
                  style: _dmSans(size: 8, weight: FontWeight.w700,
                      color: _accent, letterSpacing: 1.0)),
            )
          else
            Row(children: [
              Container(width: 5, height: 5,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: _green)),
              const SizedBox(width: 4),
              Text('online', style: _dmSans(size: 10, color: _green, weight: FontWeight.w500)),
            ]),
        ]),
      ]),
      actions: [
        // Copy last message
        _appBarBtn(
          onTap: () {
            final msgs = ref.read(chatNotifierProvider).value ?? [];
            final botMsgs = msgs.where((m) => m.type == MessageType.bot).toList();
            if (botMsgs.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: botMsgs.last.text));
              _snack('Copied');
            }
          },
          child: const Icon(Icons.copy_all_rounded, color: _txtSub, size: 13),
        ),
        const SizedBox(width: 6),
        // Clear
        _appBarBtn(
          onTap: () => showDialog(
            context: context,
            builder: (ctx) => _ConfirmDialog(
              title: 'Clear chat',
              message: 'All messages will be removed. Continue?',
              onConfirm: () {
                Navigator.pop(ctx);
                ref.read(chatNotifierProvider.notifier).clearChat();
              },
            ),
          ),
          child: Text('Clear', style: _dmSans(size: 11, weight: FontWeight.w600, color: _txtSub)),
        ),
        const SizedBox(width: 14),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 0.5, color: _border),
      ),
    );
  }

  Widget _appBarBtn({required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _border),
        ),
        child: Center(child: child),
      ),
    );
  }

  // ── Logo avatar ────────────────────────────────────────────────────────────
  Widget _logoAvatar(double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _accent.withOpacity(0.4), width: 1.5),
      ),
      child: ClipOval(
        child: Image.asset(_logoPath, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: _accentDim,
            child: Center(child: Text('S',
                style: _dmSans(size: size * 0.38, weight: FontWeight.w800, color: _accent))),
          ),
        ),
      ),
    );
  }

  // ── Welcome view — matches screenshot exactly ──────────────────────────────
  Widget _welcomeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Hero icon — matches the sparkle icon in screenshot
        Center(
          child: Container(
            width: 62, height: 62,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: const Center(
              child: Icon(Icons.auto_awesome_rounded, color: _accent, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 22),

        // Headline — "How can I help you today?" — matches screenshot
        Center(
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: GoogleFonts.dmSans(
                  fontSize: 22, fontWeight: FontWeight.w800,
                  color: _txt, height: 1.25, letterSpacing: -0.5),
              children: const [
                TextSpan(text: 'How can I help you\n'),
                TextSpan(text: 'today?',
                    style: TextStyle(color: _accent)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Suggestion cards — full width, matches screenshot style
        ..._suggestions.map((s) => _suggestionCard(s)),

        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _suggestionCard(_SuggestionItem item) {
    return GestureDetector(
      onTap: () => _send(item.title),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          // Icon badge
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _accentDim,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _accent.withOpacity(0.15)),
            ),
            child: Icon(item.icon, color: _accent, size: 16),
          ),
          const SizedBox(width: 13),
          // Text
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: _dmSans(size: 13, weight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(item.subtitle,
                style: _dmSans(size: 11, color: _txtSub, height: 1.4)),
          ])),
          // Arrow — matches screenshot
          const Icon(Icons.arrow_forward_rounded, color: _txtSub, size: 14),
        ]),
      ),
    );
  }

  // ── Doc banner ─────────────────────────────────────────────────────────────
  Widget _docBanner(DocumentContext doc) {
    final isOcr  = doc.fileName.startsWith('📷');
    final isDocx = doc.fileName.toLowerCase().endsWith('.docx');
    final color  = isOcr ? _green : isDocx ? _accent : _red;
    return Container(
      color: const Color(0xFF07090C),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Icon(
            isOcr ? Icons.image_search_outlined
                : isDocx ? Icons.description_outlined
                : Icons.picture_as_pdf,
            color: color, size: 14,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(doc.fileName,
              style: _dmSans(size: 12, weight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Doc mode — ask anything about this file',
              style: _dmSans(size: 10, color: _txtSub)),
        ])),
        GestureDetector(
          onTap: () => ref.read(chatNotifierProvider.notifier).clearDocument(),
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: _surface, borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.close_rounded, color: _txtSub, size: 12),
          ),
        ),
      ]),
    );
  }

  // ── Message list ───────────────────────────────────────────────────────────
  Widget _msgList(AsyncValue<List<Message>> chatState) {
    return chatState.when(
      data: (msgs) {
        if (msgs.isEmpty) return _welcomeView();
        return ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final prev = i > 0 ? msgs[i - 1] : null;
            return _bubble(msgs[i],
                showAvatar: prev == null || prev.type != msgs[i].type);
          },
        );
      },
      loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(_accent))),
      error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline_rounded, color: _red, size: 28),
            const SizedBox(height: 10),
            Text('Error: $e',
                style: _dmSans(size: 12, color: _red),
                textAlign: TextAlign.center),
          ])),
    );
  }

  // ── Bubble ─────────────────────────────────────────────────────────────────
  Widget _bubble(Message message, {bool showAvatar = true}) {
    switch (message.type) {
      case MessageType.typing:
        return _typingBubble();
      case MessageType.documentBanner:
        return _docAnnounce(message.text);
      default:
        final isUser      = message.type == MessageType.user;
        final displayText = isUser ? message.text : _cleanBotResponse(message.text);

        if (!isUser) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: 3,
              top:    showAvatar ? 16 : 3,
              left:   showAvatar ? 0  : 40,
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showAvatar) ...[
                _logoAvatar(28),
                const SizedBox(width: 10),
              ] else
                const SizedBox(width: 38),
              Flexible(
                child: GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: displayText));
                    _snack('Copied');
                  },
                  child: SelectableText(
                    displayText,
                    style: _dmSans(size: 14, height: 1.65),
                    cursorColor: _accent,
                  ),
                ),
              ),
            ]),
          );
        }

        // User bubble
        return Padding(
          padding: EdgeInsets.only(bottom: 3, top: showAvatar ? 16 : 3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end, children: [
              const SizedBox(width: 52),
              Flexible(
                child: GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: displayText));
                    _snack('Copied');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: _userBubble,
                      borderRadius: const BorderRadius.only(
                        topLeft:     Radius.circular(16),
                        topRight:    Radius.circular(16),
                        bottomLeft:  Radius.circular(16),
                        bottomRight: Radius.circular(4),
                      ),
                      border: Border.all(color: _accent.withOpacity(0.12)),
                    ),
                    child: SelectableText(
                      displayText,
                      style: _dmSans(size: 14, height: 1.55),
                      cursorColor: _accent,
                    ),
                  ),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 2),
              child: Text(_fmtTime(message.timestamp),
                  style: _dmSans(size: 10, color: _txtDim)),
            ),
          ]),
        );
    }
  }

  Widget _docAnnounce(String text) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _accent.withOpacity(0.15)),
        ),
        child: Row(children: [
          const Icon(Icons.picture_as_pdf, color: _red, size: 13),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: _dmSans(size: 12, color: _txtSub, height: 1.5))),
        ]),
      );

  Widget _typingBubble() => Padding(
        padding: const EdgeInsets.only(bottom: 3, top: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _logoAvatar(28),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(16),
                topRight:    Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft:  Radius.circular(4),
              ),
              border: Border.all(color: _border),
            ),
            child: _TypingDots(),
          ),
        ]),
      );

  Widget _processingBar() => Container(
        color: _surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          const SizedBox(width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(_accent))),
          const SizedBox(width: 9),
          Text('Extracting text…', style: _dmSans(size: 12, color: _txtSub)),
        ]),
      );

  // ── Input area — matches screenshot bottom bar ─────────────────────────────
  Widget _inputArea(DocumentContext? docCtx) {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _border.withOpacity(0.5))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          // Main input row — matches screenshot
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [

            // Attach button
            _barBtn(icon: Icons.attach_file_rounded, onTap: _pickAttachment),
            const SizedBox(width: 7),

            // Text field
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 110),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: docCtx != null ? _accent.withOpacity(0.3) : _borderHi,
                    width: docCtx != null ? 1.5 : 1,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: _dmSans(size: 13, height: 1.5),
                  decoration: InputDecoration(
                    hintText: docCtx != null
                        ? 'Ask about ${docCtx.fileName}…'
                        : 'Message Stremini AI...',
                    hintStyle: _dmSans(size: 13, color: _txtDim),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 10),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 7),

            // Mic button
            _barBtn(icon: Icons.mic_none_rounded, onTap: _showVoiceSnack),
            const SizedBox(width: 7),

            // Send button — cyan when typing, matches screenshot
            AnimatedScale(
              scale: _isTyping ? 1.0 : 0.9,
              duration: const Duration(milliseconds: 180),
              child: GestureDetector(
                onTap: _send,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 40, height: 40,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: _isTyping ? _accent : _surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _isTyping ? _accent : _border),
                  ),
                  child: Icon(Icons.arrow_upward_rounded,
                      color: _isTyping ? const Color(0xFF070809) : _txtDim,
                      size: 18),
                ),
              ),
            ),
          ]),

          // Char count hint
          if (_controller.text.length > 200)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${_controller.text.length} chars',
                  style: _dmSans(size: 10, color: _txtDim)),
            ),
        ]),
      ),
    );
  }

  Widget _barBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Icon(icon, color: _txtSub, size: 17),
      ),
    );
  }

  // ── Drawer ─────────────────────────────────────────────────────────────────
  Widget _buildDrawer() => AppDrawer(items: [
        AppDrawerItem(
            icon: Icons.home_outlined, title: 'Home',
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()));
            }),
        AppDrawerItem(
            icon: Icons.settings_outlined, title: 'Settings',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }),
        AppDrawerItem(
            icon: Icons.help_outline_rounded, title: 'Contact Us',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ContactUsScreen()));
            }),
      ]);
}

// ── Animated Typing Dots ──────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
          final scale = 1.0 + 0.45 * (t < 0.5 ? t / 0.5 : 1 - (t - 0.5) / 0.5);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 5, height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(_txtDim, _accent, scale - 1.0),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Confirm Dialog ────────────────────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onConfirm;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF111418),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _dmSans(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(message, style: _dmSans(size: 12, color: _txtSub, height: 1.5)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: _border),
                  ),
                  child: Center(child: Text('Cancel',
                      style: _dmSans(size: 12, color: _txtSub, weight: FontWeight.w600))),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: GestureDetector(
                onTap: onConfirm,
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: _red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: _red.withOpacity(0.28)),
                  ),
                  child: Center(child: Text('Clear',
                      style: _dmSans(size: 12, color: _red, weight: FontWeight.w700))),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attach bottom sheet
// ─────────────────────────────────────────────────────────────────────────────
class _AttachSheet extends StatelessWidget {
  final Future<void> Function(String type) onPicked;
  const _AttachSheet({required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          width: 32, height: 3,
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
              color: _border, borderRadius: BorderRadius.circular(2)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Attach File',
              style: _dmSans(size: 15, weight: FontWeight.w700)),
        ),
        const SizedBox(height: 3),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Add context to your conversation',
              style: _dmSans(size: 11, color: _txtSub)),
        ),
        const SizedBox(height: 14),
        _tile(context, Icons.picture_as_pdf_outlined, _red,
            'PDF Document', 'Chat about a PDF file', 'pdf'),
        _tile(context, Icons.description_outlined, _accent,
            'Document / Text', 'TXT, MD, CSV, JSON, DOCX', 'text'),
        _tile(context, Icons.image_search_outlined, _purple,
            'Image (OCR)', 'Extract text from an image', 'image'),
        _tile(context, Icons.attach_file_rounded, _amber,
            'Other File', 'Any supported file type', 'file'),
      ]),
    );
  }

  Widget _tile(BuildContext ctx, IconData icon, Color iconColor,
      String title, String subtitle, String type) {
    return GestureDetector(
      onTap: () { Navigator.pop(ctx); onPicked(type); },
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0E12),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: iconColor.withOpacity(0.18)),
            ),
            child: Icon(icon, color: iconColor, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _dmSans(size: 12, weight: FontWeight.w600)),
            Text(subtitle, style: _dmSans(size: 10, color: _txtSub)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: _txtDim, size: 14),
        ]),
      ),
    );
  }
}
