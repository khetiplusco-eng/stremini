// chat_screen.dart — FIXED v3
// Fixes:
//   1. SINGLE input box — this screen is fully self-contained.
//      lib/widgets/message_input.dart is NOT used here.
//   2. Document text properly reaches the AI:
//      _send() passes ONLY the plain user question to the provider.
//      chat_provider.dart already reads DocumentContext and routes to
//      sendDocumentChatMessageUseCase(documentText, question) — the
//      correct path. The previous code was prepending the entire file
//      into the question string, sending the document twice and
//      corrupting the backend request.
//   3. Logo shown in app bar and bot bubbles.

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
import 'stremini_agent_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _bg           = Color(0xFF000000);
const _bgSecondary  = Color(0xFF1C1C1E);
const _surface      = Color(0xFF2C2C2E);
const _separator    = Color(0xFF1C1C1C);
const _accent       = Color(0xFF0A84FF);
const _green        = Color(0xFF30D158);
const _red          = Color(0xFFFF453A);
const _amber        = Color(0xFFFF9F0A);
const _purple       = Color(0xFFBF5AF2);
const _txt          = Color(0xFFFFFFFF);
const _txtSecondary = Color(0xFF8E8E93);
const _txtTertiary  = Color(0xFF48484A);
const _logoPath     = 'lib/img/logo.jpg';

// ── Typography ────────────────────────────────────────────────────────────────
TextStyle _sf({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color color = _txt,
  double height = 1.5,
  double spacing = -0.3,
}) =>
    GoogleFonts.dmSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: spacing,
    );

// ── Helpers ───────────────────────────────────────────────────────────────────
String _fmtTime(DateTime dt) {
  final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
}

// ── PDF text extraction ───────────────────────────────────────────────────────
Future<String> _extractPdfText(List<int> bytes) async {
  try {
    final raw = utf8.decode(bytes, allowMalformed: true);
    final btEtPattern = RegExp(r'BT\s*([\s\S]*?)\s*ET', dotAll: true);
    final tjPattern = RegExp(r'\(((?:[^()\\]|\\.)*)\)\s*T[Jj]', caseSensitive: false);
    final buffer = StringBuffer();
    for (final btMatch in btEtPattern.allMatches(raw)) {
      final block = btMatch.group(1) ?? '';
      for (final tjMatch in tjPattern.allMatches(block)) {
        final decoded = _decodePdfString(tjMatch.group(1) ?? '');
        if (decoded.trim().isNotEmpty) { buffer.write(decoded); buffer.write(' '); }
      }
    }
    var result = buffer.toString().trim();
    if (result.length < 100) {
      final sb = StringBuffer();
      for (final m in RegExp(r'[\x20-\x7E]{8,}').allMatches(raw)) {
        final s = m.group(0)?.trim() ?? '';
        if (s.isEmpty) continue;
        if (s.startsWith('/') || s.startsWith('<<') || s.startsWith('>>')) continue;
        if (RegExp(r'^[0-9. ]+$').hasMatch(s)) continue;
        sb.writeln(s);
      }
      result = sb.toString().trim();
    }
    return result;
  } catch (_) { return ''; }
}

String _decodePdfString(String s) {
  s = s.replaceAllMapped(RegExp(r'\\([0-7]{1,3})'), (m) =>
      String.fromCharCode(int.parse(m.group(1)!, radix: 8)));
  return s.replaceAll(r'\n', '\n').replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t').replaceAll(r'\\', '\\')
      .replaceAll(r'\(', '(').replaceAll(r'\)', ')');
}

// ── DOCX text extraction ──────────────────────────────────────────────────────
Future<String> _extractDocxText(List<int> bytes) async {
  try {
    final raw = utf8.decode(bytes, allowMalformed: true);
    final matches = RegExp(r'<w:t(?:\s[^>]*)?>([^<]*)<\/w:t>', dotAll: true).allMatches(raw);
    if (matches.isNotEmpty) {
      return matches.map((m) => m.group(1)?.trim() ?? '').where((t) => t.isNotEmpty).join(' ').trim();
    }
    return raw.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  } catch (_) { return ''; }
}

Future<String> _readTextFile(File file) async {
  try { return await file.readAsString(); }
  catch (_) { return utf8.decode(await file.readAsBytes(), allowMalformed: true); }
}

Future<String> _extractOcrText(File imageFile) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    return (await recognizer.processImage(InputImage.fromFile(imageFile))).text.trim();
  } catch (_) { return ''; }
  finally { recognizer.close(); }
}

// ── Markdown / LaTeX cleaner for bot responses ────────────────────────────────
String _cleanBotResponse(String text) {
  String s = text
      .replaceAllMapped(RegExp(r'\\frac\{([^}]+)\}\{([^}]+)\}'), (m) => '(${m[1]})/(${m[2]})')
      .replaceAllMapped(RegExp(r'\\sqrt\{([^}]+)\}'), (m) => '√(${m[1]})')
      .replaceAll(r'\times', '×').replaceAll(r'\div', '÷').replaceAll(r'\pm', '±')
      .replaceAll(r'\infty', '∞').replaceAll(r'\pi', 'π').replaceAll(r'\sum', '∑')
      .replaceAll(r'\int', '∫').replaceAll(r'\approx', '≈').replaceAll(r'\neq', '≠')
      .replaceAll(r'\leq', '≤').replaceAll(r'\geq', '≥').replaceAll(r'\rightarrow', '→')
      .replaceAllMapped(RegExp(r'\\[a-zA-Z]+\{([^}]*)\}'), (m) => m[1] ?? '')
      .replaceAll(RegExp(r'\\[a-zA-Z]+\s*'), '');
  s = s.replaceAllMapped(RegExp(r'```(?:[a-zA-Z0-9_+\-]*)\n?([\s\S]*?)```'), (m) => (m[1] ?? '').trim());
  s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'\*\*\*([^*]+)\*\*\*'), r'$1')
       .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
       .replaceAll(RegExp(r'\*([^*\n]+)\*'), r'$1')
       .replaceAll(RegExp(r'___([^_]+)___'), r'$1')
       .replaceAll(RegExp(r'__([^_]+)__'), r'$1')
       .replaceAll(RegExp(r'_([^_\n]+)_'), r'$1');
  s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1] ?? '');
  s = s.replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '');
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1] ?? '');
  s = s.replaceAll(RegExp(r'(?<!\w)\*+(?!\w)'), '').replaceAll(RegExp(r'(?<!\w)_+(?!\w)'), '');
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
  // Single controller / focusNode — there is NO other input widget on this screen
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
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _controller.addListener(() => setState(() => _isTyping = _controller.text.isNotEmpty));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _controller.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────────────
  void _navTo(Widget screen, {bool replace = false}) {
    HapticFeedback.selectionClick();
    if (replace) {
      Navigator.pushReplacement(context, _smoothRoute(screen));
    } else {
      Navigator.push(context, _smoothRoute(screen));
    }
  }

  PageRoute _smoothRoute(Widget screen) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => screen,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
      child: child,
    ),
  );

  // ── Attachment picker ───────────────────────────────────────────────────────
  void _pickAttachment() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.6),
      isScrollControlled: true,
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
          await _pickDocFromFile(file, file.path.split('.').last.toLowerCase());
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
      _snack('Image loaded — ask me about it');
    } catch (e) {
      if (mounted) _snack('OCR failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _processingDoc = false);
    }
  }

  Future<void> _pickDoc(List<String> exts) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: exts);
    if (r == null || r.files.single.path == null) return;
    final file = File(r.files.single.path!);
    final name = r.files.single.name;
    await _pickDocFromFile(file, name.split('.').last.toLowerCase(), displayName: name);
  }

  Future<void> _pickDocFromFile(File file, String ext, {String? displayName}) async {
    final name = displayName ?? file.path.split('/').last;
    setState(() => _processingDoc = true);
    try {
      String text;
      final bytes = await file.readAsBytes();
      if (ext == 'pdf') {
        text = await _extractPdfText(bytes);
      } else if (ext == 'docx') {
        text = await _extractDocxText(bytes);
      } else {
        text = await _readTextFile(file);
      }

      if (!mounted) return;

      if (text.trim().isEmpty) {
        _snack('Could not extract text from "$name". The file may be scanned/image-based.', err: true);
        return;
      }

      // Truncate very large documents to avoid token limits (~80 k chars)
      const maxChars = 80000;
      final truncated = text.length > maxChars;
      if (truncated) text = text.substring(0, maxChars);

      // Store extracted text in DocumentContext.
      // chat_provider.sendMessage() reads this and calls
      // sendDocumentChatMessageUseCase(documentText: docCtx.text, question: userQuestion)
      // — that is the correct and complete flow. Nothing else is needed here.
      ref.read(chatNotifierProvider.notifier)
          .loadDocument(DocumentContext(fileName: name, text: text));

      _snack(truncated
          ? '"$name" loaded (truncated to 80 k chars)'
          : '"$name" loaded — ask me anything about it');
    } catch (e) {
      if (mounted) _snack('Error reading "$name": $e', err: true);
    } finally {
      if (mounted) setState(() => _processingDoc = false);
    }
  }

  // ── FIX: Send — pass ONLY the plain user question ──────────────────────────
  // Do NOT prepend document text here.
  // chat_provider.dart's sendMessage() already does:
  //   if (docCtx != null)  →  sendDocumentChatMessageUseCase(docCtx.text, trimmed)
  //   else                 →  sendChatMessageUseCase(trimmed)
  // Prepending the doc here caused it to be sent twice and broke the backend.
  void _send([String? override]) {
    final text = (override ?? _controller.text).trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
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
        Icon(err ? Icons.cancel : Icons.check_circle,
            color: err ? _red : _green, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: _sf(size: 13))),
      ]),
      backgroundColor: _bgSecondary,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
      elevation: 0,
    ));
  }

  void _showVoiceSnack() => _snack('Voice input coming soon!');

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider);
    final docCtx    = ref.watch(documentContextProvider);
    ref.listen<AsyncValue<List<Message>>>(chatNotifierProvider,
        (_, next) => next.whenData((_) => _scrollDown()));

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _buildAppBar(docCtx),
          if (docCtx != null) _docBanner(docCtx),
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _msgList(chatState),
            ),
          ),
          if (_processingDoc) _processingBar(),
          // ── The ONE and ONLY input box ──────────────────────────────────
          _inputArea(docCtx),
          _bottomNav(),
        ]),
      ),
    );
  }

  // ── App bar ─────────────────────────────────────────────────────────────────
  Widget _buildAppBar(DocumentContext? docCtx) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(bottom: BorderSide(color: _separator, width: 0.5)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); Navigator.pop(context); },
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.menu_rounded, color: _txtSecondary, size: 18),
          ),
        ),
        const SizedBox(width: 12),
        _logoAvatar(32),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('STREMINI AI', style: _sf(size: 15, weight: FontWeight.w800, spacing: 1.0)),
          Text('CHAT', style: _sf(size: 10, color: _txtSecondary, spacing: 2.0)),
        ])),
        GestureDetector(
          onTap: () {
            final botMsgs = (ref.read(chatNotifierProvider).value ?? [])
                .where((m) => m.type == MessageType.bot).toList();
            if (botMsgs.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: botMsgs.last.text));
              _snack('Copied');
            }
          },
          child: _headerBtn('Copy'),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (ctx) => _ConfirmDialog(
              title: 'Clear Chat',
              message: 'All messages will be permanently removed.',
              onConfirm: () {
                Navigator.pop(ctx);
                ref.read(chatNotifierProvider.notifier).clearChat();
              },
            ),
          ),
          child: _headerBtn('Clear'),
        ),
      ]),
    );
  }

  Widget _headerBtn(String label) => Container(
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(8)),
    child: Center(child: Text(label, style: _sf(size: 12, color: _txtSecondary, weight: FontWeight.w500))),
  );

  Widget _logoAvatar(double size) => ClipOval(
    child: Image.asset(_logoPath, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _sparkleAvatar(size)),
  );

  Widget _sparkleAvatar(double size) => Container(
    width: size, height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(colors: [Color(0xFF0A84FF), Color(0xFF5AC8FA)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    child: Center(child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.5)),
  );

  Widget _botAvatar(double size) => ClipOval(
    child: Image.asset(_logoPath, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _sparkleAvatar(size)),
  );

  // ── Document banner ─────────────────────────────────────────────────────────
  Widget _docBanner(DocumentContext doc) {
    final isOcr  = doc.fileName.startsWith('📷');
    final isDocx = doc.fileName.toLowerCase().endsWith('.docx');
    final color  = isOcr ? _green : isDocx ? _accent : _red;
    return Container(
      color: color.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(isOcr ? Icons.image_rounded : isDocx
            ? Icons.description_rounded : Icons.picture_as_pdf_rounded,
            color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(doc.fileName, style: _sf(size: 13, weight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Ask me anything about this file',
              style: _sf(size: 11, color: _txtSecondary)),
        ])),
        GestureDetector(
          onTap: () => ref.read(chatNotifierProvider.notifier).clearDocument(),
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.close_rounded, color: _txtSecondary, size: 14),
          ),
        ),
      ]),
    );
  }

  // ── Message list ────────────────────────────────────────────────────────────
  Widget _msgList(AsyncValue<List<Message>> chatState) {
    return chatState.when(
      data: (msgs) {
        if (msgs.isEmpty || (msgs.length == 1 && msgs.first.type == MessageType.bot && msgs.first.text.isEmpty)) {
          return const SizedBox.expand();
        }
        return ListView.builder(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final prev = i > 0 ? msgs[i - 1] : null;
            return _bubble(msgs[i], showAvatar: prev == null || prev.type != msgs[i].type);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(
          strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_accent))),
      error: (e, _) => Center(child: Text('Error: $e', style: _sf(size: 14, color: _red))),
    );
  }

  // ── Message bubble ──────────────────────────────────────────────────────────
  Widget _bubble(Message message, {bool showAvatar = true}) {
    switch (message.type) {
      case MessageType.typing:         return _typingBubble();
      case MessageType.documentBanner: return _docAnnounce(message.text);
      default:
        final isUser      = message.type == MessageType.user;
        final displayText = isUser ? message.text : _cleanBotResponse(message.text);

        if (!isUser) {
          return Padding(
            padding: EdgeInsets.only(bottom: 2, top: showAvatar ? 20 : 2, left: showAvatar ? 0 : 42),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (showAvatar) ...[_botAvatar(28), const SizedBox(width: 8)]
              else const SizedBox(width: 36),
              Flexible(
                child: GestureDetector(
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    Clipboard.setData(ClipboardData(text: displayText));
                    _snack('Copied');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: const BoxDecoration(
                      color: _bgSecondary,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(18), topRight: Radius.circular(18),
                        bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4),
                      ),
                    ),
                    child: SelectableText(displayText, style: _sf(size: 15, height: 1.6),
                        cursorColor: _accent),
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ]),
          );
        }

        return Padding(
          padding: EdgeInsets.only(bottom: 2, top: showAvatar ? 20 : 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              const SizedBox(width: 60),
              Flexible(
                child: GestureDetector(
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    Clipboard.setData(ClipboardData(text: displayText));
                    _snack('Copied');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: const BoxDecoration(
                      color: _bgSecondary,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20), topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(20), bottomRight: Radius.circular(5),
                      ),
                    ),
                    child: SelectableText(displayText, style: _sf(size: 15, height: 1.5, color: _txt),
                        cursorColor: _txt),
                  ),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Text(_fmtTime(message.timestamp), style: _sf(size: 10, color: _txtTertiary)),
            ),
          ]),
        );
    }
  }

  Widget _docAnnounce(String text) => Container(
    margin: const EdgeInsets.symmetric(vertical: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: _accent.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _accent.withOpacity(0.2)),
    ),
    child: Row(children: [
      Icon(Icons.description, color: _accent, size: 14),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: _sf(size: 12, color: _txtSecondary))),
    ]),
  );

  Widget _typingBubble() => Padding(
    padding: const EdgeInsets.only(bottom: 2, top: 20),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      _botAvatar(28),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          color: _bgSecondary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18), topRight: Radius.circular(18),
            bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4),
          ),
        ),
        child: _TypingDots(),
      ),
    ]),
  );

  Widget _processingBar() => Container(
    color: _bgSecondary,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: Row(children: [
      const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_accent))),
      const SizedBox(width: 12),
      Text('Extracting text…', style: _sf(size: 13, color: _txtSecondary)),
    ]),
  );

  // ── THE SINGLE input area ───────────────────────────────────────────────────
  Widget _inputArea(DocumentContext? docCtx) {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _separator, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attach button
          GestureDetector(
            onTap: _pickAttachment,
            child: Container(
              width: 38, height: 38,
              margin: const EdgeInsets.only(bottom: 1),
              decoration: BoxDecoration(
                color: _bgSecondary, shape: BoxShape.circle,
                border: Border.all(color: _surface, width: 1),
              ),
              child: const Icon(Icons.add_rounded, color: _txtSecondary, size: 20),
            ),
          ),
          const SizedBox(width: 8),

          // Text input pill — the ONLY text field on this screen
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minHeight: 42, maxHeight: 130),
              decoration: BoxDecoration(
                color: _bgSecondary,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: docCtx != null ? _accent.withOpacity(0.55) : _surface,
                  width: 1.2,
                ),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: _sf(size: 15, height: 1.45, color: _txt),
                decoration: InputDecoration(
                  hintText: docCtx != null
                      ? 'Ask about ${docCtx.fileName}…'
                      : 'Message Stremini…',
                  hintStyle: _sf(size: 15, color: _txtTertiary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                cursorColor: _accent,
                cursorWidth: 1.8,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send / mic button
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: _isTyping
                ? GestureDetector(
                    key: const ValueKey('send'),
                    onTap: _send,
                    child: Container(
                      width: 38, height: 38,
                      margin: const EdgeInsets.only(bottom: 1),
                      decoration: BoxDecoration(
                        color: _accent, shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: _accent.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 18),
                    ),
                  )
                : GestureDetector(
                    key: const ValueKey('mic'),
                    onTap: _showVoiceSnack,
                    child: Container(
                      width: 38, height: 38,
                      margin: const EdgeInsets.only(bottom: 1),
                      decoration: BoxDecoration(
                        color: _accent, shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: _accent.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 18),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Bottom nav ──────────────────────────────────────────────────────────────
  Widget _bottomNav() {
    return Container(
      padding: EdgeInsets.only(left: 12, right: 12, top: 8, bottom: MediaQuery.of(context).padding.bottom + 4),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: _separator, width: 0.5)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _navBtn(icon: Icons.home_outlined,      active: false, onTap: () => _navTo(const HomeScreen(), replace: true)),
        _navBtn(icon: Icons.code_rounded,       active: false, onTap: () => _navTo(StreminiAgentScreen())),
        _navBtn(icon: Icons.chat_bubble_rounded,active: true,  onTap: () {}),
        _navBtn(icon: Icons.settings_outlined,  active: false, onTap: () => _navTo(const SettingsScreen())),
      ]),
    );
  }

  Widget _navBtn({required IconData icon, required VoidCallback onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? _txt : _txtTertiary, size: 22),
          if (active) ...[
            const SizedBox(height: 4),
            Container(width: 4, height: 4, decoration: const BoxDecoration(shape: BoxShape.circle, color: _txt)),
          ],
        ]),
      ),
    );
  }
}

// ── Typing dots ───────────────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
          final opacity = t < 0.5 ? t / 0.5 : 1 - (t - 0.5) / 0.5;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: 7, height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(_txtTertiary, _txtSecondary, opacity),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Confirm dialog ────────────────────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final String title, message;
  final VoidCallback onConfirm;
  const _ConfirmDialog({required this.title, required this.message, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(title, style: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w600, color: _txt),
          textAlign: TextAlign.center),
      content: Text(message, style: GoogleFonts.dmSans(fontSize: 13, color: _txtSecondary),
          textAlign: TextAlign.center),
      actionsPadding: EdgeInsets.zero,
      actions: [
        Container(height: 0.5, color: _separator),
        IntrinsicHeight(child: Row(children: [
          Expanded(child: TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: _accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
            child: Text('Cancel', style: GoogleFonts.dmSans(fontSize: 17, color: _accent)),
          )),
          Container(width: 0.5, color: _separator),
          Expanded(child: TextButton(
            onPressed: onConfirm,
            style: TextButton.styleFrom(foregroundColor: _red,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
            child: Text('Clear', style: GoogleFonts.dmSans(fontSize: 17, color: _red, fontWeight: FontWeight.w600)),
          )),
        ])),
      ],
    );
  }
}

// ── Attach sheet ──────────────────────────────────────────────────────────────
class _AttachSheet extends StatelessWidget {
  final Future<void> Function(String type) onPicked;
  const _AttachSheet({required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 20),
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            Text('Attach File', style: _sf(size: 20, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Add context to your conversation', style: _sf(size: 14, color: _txtSecondary)),
            const SizedBox(height: 20),
            _tile(context, Icons.picture_as_pdf_rounded, _red,    'PDF Document',    'Chat about a PDF file',        'pdf'),
            _tile(context, Icons.description_rounded,    _accent, 'Document / Text', 'TXT, MD, CSV, JSON, DOCX',     'text'),
            _tile(context, Icons.photo_rounded,          _purple, 'Image (OCR)',     'Extract text from an image',   'image'),
            _tile(context, Icons.folder_rounded,         _amber,  'Other File',      'Any supported file type',      'file'),
          ]),
        ),
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          width: double.infinity, height: 54,
          decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(14)),
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: _sf(size: 17, weight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _tile(BuildContext ctx, IconData icon, Color color, String title, String subtitle, String type) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); Navigator.pop(ctx); onPicked(type); },
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _sf(size: 15, weight: FontWeight.w500)),
            Text(subtitle, style: _sf(size: 12, color: _txtSecondary)),
          ])),
          Icon(Icons.chevron_right, color: _txtTertiary, size: 16),
        ]),
      ),
    );
  }
}
