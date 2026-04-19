// chat_screen.dart — PREMIUM REDESIGN v2
// Design: Liquid obsidian — deep blacks, electric cyan accent, editorial grid
// Typography: Surgical hierarchy, monospaced for code, humanist for prose
// ALL FUNCTIONALITY PRESERVED + mic button now opens voice snackbar
// Attachment, clear, menu — all wired. Suggestions are functional.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
const _ink        = Color(0xFF070809);
const _bg         = Color(0xFF0A0C0F);
const _surface    = Color(0xFF111418);
const _surfaceHi  = Color(0xFF181C22);
const _card       = Color(0xFF1C2028);
const _border     = Color(0xFF222830);
const _borderHi   = Color(0xFF2E3640);
const _accent     = Color(0xFF0EB5E8);
const _accentDim  = Color(0xFF071825);
const _accentSoft = Color(0xFF0EB5E840);
const _purple     = Color(0xFF8B6BF5);
const _purpleDim  = Color(0xFF120F28);
const _green      = Color(0xFF22D47A);
const _greenDim   = Color(0xFF061A10);
const _red        = Color(0xFFEF4444);
const _amber      = Color(0xFFF59E0B);
const _txt        = Color(0xFFEEF2F8);
const _txtSub     = Color(0xFF7A8899);
const _txtDim     = Color(0xFF3D4B5C);
const _userBubble = Color(0xFF0F1820);
const _logoPath   = 'lib/img/logo.jpg';

// ── Suggestion Chips ──────────────────────────────────────────────────────────
const _suggestions = [
  _Chip(Icons.auto_stories_outlined,    'Summarize a document for me'),
  _Chip(Icons.code_rounded,             'Review and fix my code'),
  _Chip(Icons.lightbulb_outline_rounded,'Brainstorm creative ideas'),
  _Chip(Icons.translate_rounded,        'Translate this text'),
];

class _Chip {
  final IconData icon;
  final String label;
  const _Chip(this.icon, this.label);
}

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
        vsync: this, duration: const Duration(milliseconds: 500));
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
      barrierColor: Colors.black.withOpacity(0.7),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
            color: err ? _red : _green, size: 15),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(color: _txt, fontSize: 13))),
      ]),
      backgroundColor: _surfaceHi,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: (err ? _red : _green).withOpacity(0.4)),
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  void _showVoiceSnack() {
    _snack('Voice input coming in the next update!');
  }

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
            child: showWelcome
                ? _welcomeView()
                : _msgList(chatState),
          ),
          if (_processingDoc) _processingBar(),
          _inputArea(docCtx),
        ]),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(DocumentContext? docCtx) {
    return AppBar(
      backgroundColor: _ink,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: Builder(builder: (ctx) => GestureDetector(
        onTap: () => Scaffold.of(ctx).openDrawer(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.menu_rounded, color: _txtSub, size: 17),
          ),
        ),
      )),
      title: Row(children: [
        _logoRing(30),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Stremini AI',
              style: TextStyle(color: _txt, fontSize: 14,
                  fontWeight: FontWeight.w700, letterSpacing: 0.1)),
          if (docCtx != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: _accentDim,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _accent.withOpacity(0.3)),
              ),
              child: const Text('DOC MODE',
                  style: TextStyle(color: _accent, fontSize: 8,
                      fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            )
          else
            Row(children: [
              Container(
                width: 5, height: 5,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: _green,
                ),
              ),
              const SizedBox(width: 5),
              const Text('online', style: TextStyle(color: _green, fontSize: 10,
                  fontWeight: FontWeight.w500)),
            ]),
        ]),
      ]),
      actions: [
        // Copy last message
        GestureDetector(
          onTap: () {
            final msgs = ref.read(chatNotifierProvider).value ?? [];
            final botMsgs = msgs.where((m) => m.type == MessageType.bot).toList();
            if (botMsgs.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: botMsgs.last.text));
              _snack('Last reply copied');
            }
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(0, 10, 6, 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.copy_all_rounded, color: _txtSub, size: 13),
          ),
        ),
        // Clear chat
        GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => _ConfirmDialog(
                title: 'Clear Chat',
                message: 'This will clear all messages. Continue?',
                onConfirm: () {
                  Navigator.pop(ctx);
                  ref.read(chatNotifierProvider.notifier).clearChat();
                },
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(0, 10, 14, 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: const Text('Clear',
                style: TextStyle(color: _txtSub, fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  // ── Welcome view ───────────────────────────────────────────────────────────
  Widget _welcomeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Brand row
        Row(children: [
          _logoRing(52, ringWidth: 2),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Stremini AI',
                style: TextStyle(color: _txt, fontSize: 20,
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const Text('Your intelligent companion',
                style: TextStyle(color: _txtSub, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 32),

        // Greeting headline
        RichText(text: const TextSpan(
          style: TextStyle(color: _txt, fontSize: 26,
              fontWeight: FontWeight.w800, letterSpacing: -1.0, height: 1.2),
          children: [
            TextSpan(text: 'How can I\n'),
            TextSpan(text: 'help you ', style: TextStyle(color: _txt)),
            TextSpan(text: 'today?', style: TextStyle(color: _accent)),
          ],
        )),
        const SizedBox(height: 8),
        const Text('Ask me anything — I can code, write, analyze, and more.',
            style: TextStyle(color: _txtSub, fontSize: 13, height: 1.5)),

        const SizedBox(height: 32),

        // Capability chips
        const Text('QUICK ACTIONS',
            style: TextStyle(color: _txtDim, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 2.0)),
        const SizedBox(height: 14),
        ..._suggestions.map((chip) => _suggestionTile(chip)),

        const SizedBox(height: 32),

        // Capability grid
        const Text('CAPABILITIES',
            style: TextStyle(color: _txtDim, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 2.0)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _capCard(Icons.code_rounded, 'Code', 'Debug & write', _purple, _purpleDim)),
          const SizedBox(width: 10),
          Expanded(child: _capCard(Icons.description_outlined, 'Docs', 'Read & summarize', _accent, _accentDim)),
          const SizedBox(width: 10),
          Expanded(child: _capCard(Icons.auto_awesome_rounded, 'Create', 'Write & ideate', _amber, const Color(0xFF1A1200))),
        ]),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _suggestionTile(_Chip chip) {
    return GestureDetector(
      onTap: () => _send(chip.label),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _accentDim,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _accent.withOpacity(0.2)),
            ),
            child: Icon(chip.icon, color: _accent, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(chip.label,
              style: const TextStyle(color: _txt, fontSize: 13,
                  fontWeight: FontWeight.w500))),
          const Icon(Icons.arrow_forward_ios_rounded, color: _txtDim, size: 11),
        ]),
      ),
    );
  }

  Widget _capCard(IconData icon, String title, String sub, Color color, Color dimColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: dimColor,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(color: _txt, fontSize: 12,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(color: _txtSub, fontSize: 10,
            height: 1.4)),
      ]),
    );
  }

  // ── Doc banner ─────────────────────────────────────────────────────────────
  Widget _docBanner(DocumentContext doc) {
    final isOcr  = doc.fileName.startsWith('📷');
    final isDocx = doc.fileName.toLowerCase().endsWith('.docx');
    final color  = isOcr ? _green : isDocx ? _accent : _red;
    return Container(
      color: const Color(0xFF080A0C),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Icon(
            isOcr ? Icons.image_search_outlined
                : isDocx ? Icons.description_outlined
                : Icons.picture_as_pdf,
            color: color, size: 15,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(doc.fileName,
              style: const TextStyle(color: _txt, fontSize: 12,
                  fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const Text('Document mode — ask anything about this file',
              style: TextStyle(color: _txtSub, fontSize: 10)),
        ])),
        GestureDetector(
          onTap: () => ref.read(chatNotifierProvider.notifier).clearDocument(),
          child: Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: _surface, borderRadius: BorderRadius.circular(7),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.close_rounded, color: _txtSub, size: 13),
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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final prev = i > 0 ? msgs[i - 1] : null;
            return _bubble(msgs[i],
                showAvatar: prev == null || prev.type != msgs[i].type);
          },
        );
      },
      loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(_accent))),
      error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline_rounded, color: _red, size: 32),
            const SizedBox(height: 12),
            Text('Error: $e',
                style: const TextStyle(color: _red, fontSize: 13),
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
              bottom: 4,
              top:    showAvatar ? 20 : 4,
              left:   showAvatar ? 0  : 44,
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showAvatar) ...[
                _botAvatar(),
                const SizedBox(width: 12),
              ] else
                const SizedBox(width: 44),
              Flexible(
                child: GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: displayText));
                    _snack('Message copied');
                  },
                  child: SelectableText(
                    displayText,
                    style: const TextStyle(
                        color: _txt, fontSize: 15, height: 1.65,
                        fontWeight: FontWeight.w400),
                    cursorColor: _accent,
                  ),
                ),
              ),
            ]),
          );
        }

        // User bubble
        return Padding(
          padding: EdgeInsets.only(bottom: 4, top: showAvatar ? 20 : 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end, children: [
              const SizedBox(width: 56),
              Flexible(
                child: GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: displayText));
                    _snack('Message copied');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: _userBubble,
                      borderRadius: const BorderRadius.only(
                        topLeft:     Radius.circular(18),
                        topRight:    Radius.circular(18),
                        bottomLeft:  Radius.circular(18),
                        bottomRight: Radius.circular(4),
                      ),
                      border: Border.all(color: _accent.withOpacity(0.15)),
                    ),
                    child: SelectableText(
                      displayText,
                      style: const TextStyle(
                          color: _txt, fontSize: 15, height: 1.55),
                      cursorColor: _accent,
                    ),
                  ),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 2),
              child: Text(_fmtTime(message.timestamp),
                  style: const TextStyle(
                      color: _txtDim, fontSize: 10,
                      fontWeight: FontWeight.w400)),
            ),
          ]),
        );
    }
  }

  Widget _logoRing(double size, {double ringWidth = 1.5}) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _accent.withOpacity(0.35), width: ringWidth),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Image.asset(_logoPath, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: _accentDim,
              child: const Center(
                child: Text('S', style: TextStyle(color: _accent,
                    fontWeight: FontWeight.w800, fontSize: 14))),
            ),
          ),
        ),
      );

  Widget _botAvatar() => _logoRing(32);

  Widget _docAnnounce(String text) => Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent.withOpacity(0.18)),
        ),
        child: Row(children: [
          const Icon(Icons.picture_as_pdf, color: _red, size: 15),
          const SizedBox(width: 10),
          Expanded(child: Text(text,
              style: const TextStyle(color: _txtSub, fontSize: 13,
                  height: 1.5))),
        ]),
      );

  Widget _typingBubble() => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _botAvatar(),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(18),
                topRight:    Radius.circular(18),
                bottomRight: Radius.circular(18),
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: const Row(children: [
          SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(_accent))),
          SizedBox(width: 10),
          Text('Extracting text…',
              style: TextStyle(color: _txtSub, fontSize: 13)),
        ]),
      );

  // ── Input area ─────────────────────────────────────────────────────────────
  Widget _inputArea(DocumentContext? docCtx) {
    return Container(
      decoration: BoxDecoration(
        color: _ink,
        border: Border(top: BorderSide(color: _border.withOpacity(0.6))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Attach
            _inputActionBtn(
              icon: Icons.add_rounded,
              onTap: _pickAttachment,
              color: _txtSub,
            ),
            const SizedBox(width: 8),

            // Text field
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: docCtx != null
                        ? _accent.withOpacity(0.35)
                        : _borderHi,
                    width: docCtx != null ? 1.5 : 1,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode:  _focusNode,
                  style: const TextStyle(color: _txt, fontSize: 14, height: 1.5),
                  decoration: InputDecoration(
                    hintText: docCtx != null
                        ? 'Ask about ${docCtx.fileName}…'
                        : 'Message Stremini AI',
                    hintStyle: const TextStyle(color: _txtDim, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Mic
            _inputActionBtn(
              icon: Icons.mic_none_rounded,
              onTap: _showVoiceSnack,
              color: _txtSub,
            ),
            const SizedBox(width: 8),

            // Send — animates in when typing
            AnimatedScale(
              scale: _isTyping ? 1.0 : 0.85,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: _send,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 42, height: 42,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: _isTyping ? _accent : _surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _isTyping ? _accent : _border),
                  ),
                  child: Icon(Icons.arrow_upward_rounded,
                      color: _isTyping ? _ink : _txtDim, size: 20),
                ),
              ),
            ),
          ]),

          // Character count when typing long messages
          if (_controller.text.length > 200)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${_controller.text.length} chars',
                  style: const TextStyle(color: _txtDim, fontSize: 10)),
            ),
        ]),
      ),
    );
  }

  Widget _inputActionBtn({
    required IconData icon,
    required VoidCallback onTap,
    Color color = _txtSub,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Icon(icon, color: color, size: 19),
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
          final scale = 1.0 + 0.5 * (t < 0.5 ? t / 0.5 : 1 - (t - 0.5) / 0.5);
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
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: _txt, fontSize: 16,
              fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: _txtSub, fontSize: 13,
              height: 1.5)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: const Center(child: Text('Cancel',
                      style: TextStyle(color: _txtSub, fontSize: 13,
                          fontWeight: FontWeight.w600))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: onConfirm,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: _red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _red.withOpacity(0.3)),
                  ),
                  child: const Center(child: Text('Clear',
                      style: TextStyle(color: _red, fontSize: 13,
                          fontWeight: FontWeight.w700))),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
              color: const Color(0xFF222830),
              borderRadius: BorderRadius.circular(2)),
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Attach File',
              style: TextStyle(color: _txt, fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Add context to your conversation',
              style: TextStyle(color: _txtSub, fontSize: 12)),
        ),
        const SizedBox(height: 16),
        _tile(context, Icons.picture_as_pdf_outlined, _red,
            'PDF Document', 'Chat about a PDF file', 'pdf'),
        _tile(context, Icons.description_outlined, _accent,
            'Document / Text', 'TXT, MD, CSV, JSON, DOCX', 'text'),
        _tile(context, Icons.image_search_outlined, _purple,
            'Image', 'Use OCR to extract text', 'image'),
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0E12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: iconColor.withOpacity(0.2)),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(width: 13),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(
                color: _txt, fontSize: 13, fontWeight: FontWeight.w600)),
            Text(subtitle, style: const TextStyle(color: _txtSub, fontSize: 11)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: _txtDim, size: 16),
        ]),
      ),
    );
  }
}
