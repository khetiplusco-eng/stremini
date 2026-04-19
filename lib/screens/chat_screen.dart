// chat_screen.dart — REDESIGNED to match new_chatbot_design.png
// Design: Dark editorial chat UI — Stremini AI branding
// - Deep black background
// - Bot greeting displayed as plain text (no bubble)
// - Quick-action suggestion chips with icons
// - User messages in dark rounded bubbles (bottom-right)
// - Timestamps on user messages
// - Sleek input bar with mic + send
// ALL FUNCTIONALITY PRESERVED from original

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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

// ── Design tokens — exact match to the screenshot ─────────────────────────────
const _bg         = Color(0xFF0D0D0D);
const _surface    = Color(0xFF1A1A1A);
const _surfaceHi  = Color(0xFF222222);
const _border     = Color(0xFF2A2A2A);
const _accent     = Color(0xFF23A6E2);
const _accentDim  = Color(0xFF0A1A28);
const _txtPri     = Colors.white;
const _txtMuted   = Color(0xFF8A8A8A);
const _txtDim     = Color(0xFF555555);
const _userBubble = Color(0xFF1E2530);
const _chipBg     = Color(0xFF1C1C1C);
const _chipBorder = Color(0xFF2E2E2E);
const _danger     = Color(0xFFEF4444);
const _success    = Color(0xFF34C47C);
const _logoPath   = 'lib/img/logo.jpg';

// ── Suggestion chips shown on empty state ─────────────────────────────────────
const _suggestions = [
  _SuggestionChip(icon: Icons.description_outlined,   label: 'Draft a strategic brief'),
  _SuggestionChip(icon: Icons.code_outlined,           label: 'Review architecture'),
  _SuggestionChip(icon: Icons.lightbulb_outline,       label: 'Brainstorm concepts'),
];

class _SuggestionChip {
  final IconData icon;
  final String label;
  const _SuggestionChip({required this.icon, required this.label});
}

// ── Text extraction helpers (unchanged) ──────────────────────────────────────

Future<String> _extractPdfText(List<int> bytes) async {
  try {
    final raw = utf8.decode(bytes, allowMalformed: true);
    final matches = RegExp(r'[\x20-\x7E]{8,}').allMatches(raw);
    if (matches.isEmpty) return '';
    final parts = <String>[];
    for (final m in matches) {
      final text = m.group(0)?.trim() ?? '';
      if (text.isNotEmpty) parts.add(text);
    }
    return parts.join('\n').trim();
  } catch (e) {
    debugPrint('[PDF] $e');
    return '';
  }
}

Future<String> _readTextFile(File file) async {
  try {
    return await file.readAsString();
  } catch (_) {
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }
}

Future<String> _extractDocxText(List<int> bytes) async {
  try {
    final raw = utf8.decode(bytes, allowMalformed: true);
    final regex = RegExp(r'<w:t[^>]*>([^<]*)<\/w:t>', dotAll: true);
    final matches = regex.allMatches(raw);
    if (matches.isEmpty) {
      return raw.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return matches.map((m) => m.group(1) ?? '').join(' ').trim();
  } catch (e) {
    debugPrint('[DOCX] $e');
    return '';
  }
}

Future<String> _extractOcrText(File imageFile) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final inputImage = InputImage.fromFile(imageFile);
    final RecognizedText result = await recognizer.processImage(inputImage);
    return result.text.trim();
  } catch (e) {
    debugPrint('[OCR] $e');
    return '';
  } finally {
    recognizer.close();
  }
}

// ── Markdown / LaTeX cleanup (unchanged) ─────────────────────────────────────

String _convertMath(String text) {
  return text
    .replaceAllMapped(RegExp(r'\\frac\{([^}]+)\}\{([^}]+)\}'), (m) => '(${m[1]})/(${m[2]})')
    .replaceAllMapped(RegExp(r'\\sqrt\{([^}]+)\}'), (m) => '√(${m[1]})')
    .replaceAllMapped(RegExp(r'([a-zA-Z])\^\{([^}]+)\}'), (m) => '${m[1]}^${m[2]}')
    .replaceAllMapped(RegExp(r'([a-zA-Z])_\{([^}]+)\}'), (m) => '${m[1]}_${m[2]}')
    .replaceAllMapped(RegExp(r'([a-zA-Z])\^(\w)'), (m) => '${m[1]}^${m[2]}')
    .replaceAllMapped(RegExp(r'([a-zA-Z])_(\w)'), (m) => '${m[1]}_${m[2]}')
    .replaceAll(r'\times', '×').replaceAll(r'\div', '÷')
    .replaceAll(r'\pm', '±').replaceAll(r'\infty', '∞')
    .replaceAll(r'\pi', 'π').replaceAll(r'\alpha', 'α')
    .replaceAll(r'\beta', 'β').replaceAll(r'\gamma', 'γ')
    .replaceAll(r'\delta', 'δ').replaceAll(r'\theta', 'θ')
    .replaceAll(r'\sigma', 'σ').replaceAll(r'\mu', 'μ')
    .replaceAll(r'\lambda', 'λ').replaceAll(r'\sum', '∑')
    .replaceAll(r'\int', '∫').replaceAll(r'\approx', '≈')
    .replaceAll(r'\neq', '≠').replaceAll(r'\leq', '≤')
    .replaceAll(r'\geq', '≥').replaceAll(r'\cdot', '·')
    .replaceAll(r'\ldots', '…').replaceAll(r'\rightarrow', '→')
    .replaceAll(r'\leftarrow', '←')
    .replaceAllMapped(RegExp(r'\\[a-zA-Z]+\{([^}]*)\}'), (m) => m[1] ?? '')
    .replaceAll(RegExp(r'\\[a-zA-Z]+\s*'), '');
}

String _cleanBotResponse(String text) {
  String s = _convertMath(text);
  s = s.replaceAllMapped(
    RegExp(r'```(?:[a-zA-Z0-9_+\-]*)\n?([\s\S]*?)```'),
    (m) => (m[1] ?? '').trim(),
  );
  s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'\*\*\*([^*]+)\*\*\*'), r'$1');
  s = s.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
  s = s.replaceAll(RegExp(r'\*([^*\n]+)\*'), r'$1');
  s = s.replaceAll(RegExp(r'___([^_]+)___'), r'$1');
  s = s.replaceAll(RegExp(r'__([^_]+)__'), r'$1');
  s = s.replaceAll(RegExp(r'_([^_\n]+)_'), r'$1');
  s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1] ?? '');
  s = s.replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '');
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1] ?? '');
  s = s.replaceAll(RegExp(r'(?<!\w)\*+(?!\w)'), '');
  s = s.replaceAll(RegExp(r'(?<!\w)_+(?!\w)'), '');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

// ── Time formatter ────────────────────────────────────────────────────────────
String _fmtTime(DateTime dt) {
  final h  = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m  = dt.minute.toString().padLeft(2, '0');
  final ap = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ap';
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

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _controller.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Attachment helpers (unchanged logic) ───────────────────────────────────

  void _pickAttachment() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
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
      _snack('Image added');
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
      _snack('📄 "$name" added');
    } catch (e) {
      if (mounted) _snack('Error reading file: $e', err: true);
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
      if (_scrollCtrl.hasClients)
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
    });
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _txtPri, fontSize: 13)),
      backgroundColor: err ? const Color(0xFF1A0808) : _accentDim,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider);
    final docCtx    = ref.watch(documentContextProvider);
    ref.listen<AsyncValue<List<Message>>>(
        chatNotifierProvider, (_, next) => next.whenData((_) => _scrollDown()));

    final messages = chatState.value ?? [];
    // Show welcome state when only the initial greeting exists (1 bot msg, no user msgs)
    final showWelcome = messages.length <= 1 &&
        !messages.any((m) => m.type == MessageType.user);

    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar(docCtx),
      drawer: _drawer(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            if (docCtx != null) _docBanner(docCtx),
            Expanded(
              child: showWelcome
                  ? _welcomeView()
                  : _msgList(chatState),
            ),
            if (_processingDoc) _processingBar(),
            _inputArea(docCtx),
          ],
        ),
      ),
    );
  }

  // ── AppBar — matches screenshot: logo + title + 3-dot + avatar ────────────
  PreferredSizeWidget _appBar(DocumentContext? docCtx) {
    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: Builder(
        builder: (ctx) => GestureDetector(
          onTap: () => Scaffold.of(ctx).openDrawer(),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.menu_rounded, color: _txtPri, size: 18),
            ),
          ),
        ),
      ),
      title: Row(children: [
        // Logo — circular avatar like in screenshot
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _accent.withOpacity(0.3), width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(_logoPath, width: 32, height: 32, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: _accent,
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                )),
          ),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Stremini AI',
              style: TextStyle(color: _txtPri, fontSize: 15,
                  fontWeight: FontWeight.w700, letterSpacing: 0.2)),
          if (docCtx != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('DOC MODE',
                  style: TextStyle(color: _accent, fontSize: 9,
                      fontWeight: FontWeight.w700, letterSpacing: 1.0)),
            ),
        ]),
      ]),
      actions: [
        // Clear button
        GestureDetector(
          onTap: () => ref.read(chatNotifierProvider.notifier).clearChat(),
          child: Container(
            margin: const EdgeInsets.fromLTRB(0, 10, 6, 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: const Text('Clear',
                style: TextStyle(color: _txtMuted, fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        // 3-dot menu icon (visual, matches screenshot)
        const Padding(
          padding: EdgeInsets.only(right: 6),
          child: Icon(Icons.more_vert, color: _txtMuted, size: 20),
        ),
        // User avatar circle
        Container(
          margin: const EdgeInsets.only(right: 14),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _surface,
            border: Border.all(color: _border),
          ),
          child: const Icon(Icons.person, color: _txtMuted, size: 16),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  // ── Welcome / empty state — matches screenshot exactly ────────────────────
  Widget _welcomeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bot avatar + name row
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _accent.withOpacity(0.25), width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(_logoPath, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: _accent,
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                    )),
              ),
            ),
            const SizedBox(width: 12),
            const Text('Stremini AI',
                style: TextStyle(color: _txtPri, fontSize: 18,
                    fontWeight: FontWeight.w700, letterSpacing: 0.1)),
          ]),

          const SizedBox(height: 28),

          // Greeting text — plain, like in the screenshot
          const Text(
            'Stremini at your service. How shall we refine\nyour vision today?',
            style: TextStyle(
              color: _txtPri,
              fontSize: 16,
              height: 1.55,
              fontWeight: FontWeight.w400,
            ),
          ),

          const SizedBox(height: 32),

          // Suggestion chips — exact style from screenshot
          ..._suggestions.map((chip) => _buildSuggestionChip(chip)),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(_SuggestionChip chip) {
    return GestureDetector(
      onTap: () => _send(chip.label),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: _chipBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _chipBorder),
        ),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _accent.withOpacity(0.2)),
            ),
            child: Icon(chip.icon, color: _accent, size: 17),
          ),
          const SizedBox(width: 14),
          Text(chip.label,
              style: const TextStyle(color: _txtPri, fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  // ── Doc banner ─────────────────────────────────────────────────────────────
  Widget _docBanner(DocumentContext doc) {
    final isOcr  = doc.fileName.startsWith('📷');
    final isDocx = doc.fileName.toLowerCase().endsWith('.docx');
    final color  = isOcr ? _success : isDocx ? _accent : _danger;
    return Container(
      color: const Color(0xFF0A0A0A),
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
              style: const TextStyle(color: _txtPri, fontSize: 12,
                  fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const Text('Ask anything about this document',
              style: TextStyle(color: _txtMuted, fontSize: 11)),
        ])),
        GestureDetector(
          onTap: () => ref.read(chatNotifierProvider.notifier).clearDocument(),
          child: Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: _surface, borderRadius: BorderRadius.circular(7),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.close, color: _txtMuted, size: 13),
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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
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
          child: Text('Error: $e',
              style: const TextStyle(color: _danger, fontSize: 13))),
    );
  }

  // ── Bubble — key design element ────────────────────────────────────────────
  Widget _bubble(Message message, {bool showAvatar = true}) {
    switch (message.type) {
      case MessageType.typing:
        return _typingBubble();
      case MessageType.documentBanner:
        return _docAnnounce(message.text);
      default:
        final isUser = message.type == MessageType.user;
        final displayText = isUser ? message.text : _cleanBotResponse(message.text);

        if (!isUser) {
          // Bot messages: plain text, no bubble (like screenshot greeting)
          return Padding(
            padding: EdgeInsets.only(
              bottom: 4,
              top: showAvatar ? 18 : 4,
              left: showAvatar ? 0 : 40,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showAvatar) ...[
                  _botAvatar(),
                  const SizedBox(width: 12),
                ] else
                  const SizedBox(width: 44),
                Flexible(
                  child: SelectableText(
                    displayText,
                    style: const TextStyle(
                      color: _txtPri,
                      fontSize: 15,
                      height: 1.6,
                      fontWeight: FontWeight.w400,
                    ),
                    cursorColor: _accent,
                  ),
                ),
              ],
            ),
          );
        }

        // User messages: dark rounded bubble, right-aligned with timestamp
        return Padding(
          padding: EdgeInsets.only(bottom: 4, top: showAvatar ? 18 : 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SizedBox(width: 60),
                  Flexible(
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
                        border: Border.all(
                            color: _accent.withOpacity(0.12)),
                      ),
                      child: SelectableText(
                        displayText,
                        style: const TextStyle(
                          color: _txtPri,
                          fontSize: 15,
                          height: 1.55,
                        ),
                        cursorColor: _accent,
                      ),
                    ),
                  ),
                ],
              ),
              // Timestamp — matches screenshot bottom-right
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 2),
                child: Text(
                  _fmtTime(message.timestamp),
                  style: const TextStyle(
                    color: _txtDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _botAvatar() => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _accent.withOpacity(0.25), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(_logoPath, width: 32, height: 32, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: _accent,
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
              )),
        ),
      );

  Widget _docAnnounce(String text) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent.withOpacity(0.2)),
        ),
        child: Row(children: [
          const Icon(Icons.picture_as_pdf, color: _danger, size: 15),
          const SizedBox(width: 10),
          Expanded(child: Text(text,
              style: const TextStyle(color: _txtMuted, fontSize: 13, height: 1.5))),
        ]),
      );

  Widget _typingBubble() => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _botAvatar(),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: 5, height: 5,
                decoration: BoxDecoration(
                  color: _txtDim.withOpacity(0.6 - i * 0.1),
                  shape: BoxShape.circle,
                ),
              )),
            ),
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
              style: TextStyle(color: _txtMuted, fontSize: 13)),
        ]),
      );

  // ── Input Area — matches screenshot: pill-shaped, mic + send ──────────────
  Widget _inputArea(DocumentContext? docCtx) {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _border.withOpacity(0.5))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Attach button
            GestureDetector(
              onTap: _pickAttachment,
              child: Container(
                width: 42, height: 42,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: const Icon(Icons.add_rounded, color: _txtMuted, size: 20),
              ),
            ),
            const SizedBox(width: 10),

            // Text field — pill shaped like screenshot
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: docCtx != null
                        ? _accent.withOpacity(0.3)
                        : _border,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: const TextStyle(color: _txtPri, fontSize: 14, height: 1.45),
                  decoration: InputDecoration(
                    hintText: docCtx != null
                        ? 'Ask about ${docCtx.fileName}…'
                        : 'Message Stremini',
                    hintStyle: const TextStyle(color: _txtDim, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Mic button — matches screenshot
            Container(
              width: 42, height: 42,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.mic_none_rounded, color: _txtMuted, size: 20),
            ),
            const SizedBox(width: 8),

            // Send button — blue arrow, matches screenshot
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 42, height: 42,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_upward_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Drawer (unchanged) ─────────────────────────────────────────────────────
  Widget _drawer() => AppDrawer(items: [
        AppDrawerItem(
            icon: Icons.home_outlined,
            title: 'Home',
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()));
            }),
        AppDrawerItem(
            icon: Icons.settings_outlined,
            title: 'Settings',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }),
        AppDrawerItem(
            icon: Icons.help_outline,
            title: 'Contact Us',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ContactUsScreen()));
            }),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Attach bottom sheet (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _AttachSheet extends StatelessWidget {
  final Future<void> Function(String type) onPicked;
  const _AttachSheet({required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(2)),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Attach',
                style: TextStyle(color: _txtPri, fontSize: 16,
                    fontWeight: FontWeight.w700, letterSpacing: 0.2)),
          ),
          const SizedBox(height: 14),
          _tile(context, Icons.picture_as_pdf_outlined, _danger,
              'PDF Document', 'Chat about a PDF file', 'pdf'),
          _tile(context, Icons.description_outlined, _accent,
              'Document / Text', 'TXT, MD, CSV, JSON, DOCX', 'text'),
          _tile(context, Icons.image_search_outlined, const Color(0xFF8B5CF6),
              'Image', 'Use image as chat context', 'image'),
          _tile(context, Icons.attach_file_rounded, const Color(0xFFF59E0B),
              'Other File', 'Any file type', 'file'),
        ],
      ),
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
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 13),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(
                color: _txtPri, fontSize: 13, fontWeight: FontWeight.w600)),
            Text(subtitle, style: const TextStyle(color: _txtMuted, fontSize: 11)),
          ])),
          const Icon(Icons.chevron_right, color: _txtDim, size: 16),
        ]),
      ),
    );
  }
}
