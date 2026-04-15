// chat_screen.dart — IMPROVED: math rendering + markdown cleanup
// Changes vs previous:
//   • _stripMarkdown now properly removes all *, _, #, and ` artifacts
//   • Math expressions (LaTeX \frac, \sum, etc.) rendered as human-readable text
//   • No more stray backslashes, hashtags, or asterisks in bot output
//   • Added _renderContent() which handles inline code blocks nicely

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mime/mime.dart';
import 'package:syncfusion_flutter_pdf/syncfusion_flutter_pdf.dart';

import '../core/widgets/app_drawer.dart';
import '../providers/chat_provider.dart';
import '../models/message_model.dart';
import 'contact_us_screen.dart';
import 'home/home_screen.dart';
import 'settings_screen.dart';

const _bg        = Colors.black;
const _surface   = Color(0xFF0F0F0F);
const _surfaceHi = Color(0xFF1A1A1A);
const _border    = Color(0xFF1C1C1C);
const _accent    = Color(0xFF23A6E2);
const _accentDim = Color(0xFF0A1A28);
const _textPri   = Colors.white;
const _textMuted = Color(0xFF6B7280);
const _textDim   = Color(0xFF4A5568);
const _userBubble= Color(0xFF0C1C2B);
const _botBubble = Color(0xFF0F0F0F);
const _danger    = Color(0xFFEF4444);
const _success   = Color(0xFF34C47C);
const _logoPath  = 'lib/img/logo.jpg';

// ── Text extraction helpers (unchanged) ──────────────────────────────────────

Future<String> _extractPdfText(List<int> bytes) async {
  try {
    final doc = PdfDocument(inputBytes: Uint8List.fromList(bytes));
    final extractor = PdfTextExtractor(doc);
    final buf = StringBuffer();
    for (int i = 0; i < doc.pages.count; i++) {
      final t = extractor.extractText(startPageIndex: i, endPageIndex: i);
      if (t.trim().isNotEmpty) { buf.writeln(t.trim()); buf.writeln(); }
    }
    doc.dispose();
    return buf.toString().trim();
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

// ── IMPROVED: Comprehensive markdown & artifact cleanup ───────────────────────

/// Converts LaTeX-style math to human-readable approximations
String _convertMath(String text) {
  return text
    // fractions: \frac{a}{b} → a/b
    .replaceAllMapped(RegExp(r'\\frac\{([^}]+)\}\{([^}]+)\}'), (m) => '(${m[1]})/(${m[2]})')
    // sqrt: \sqrt{x} → √x
    .replaceAllMapped(RegExp(r'\\sqrt\{([^}]+)\}'), (m) => '√(${m[1]})')
    // subscripts/superscripts: x_{n} or x^{n}
    .replaceAllMapped(RegExp(r'([a-zA-Z])\^\{([^}]+)\}'), (m) => '${m[1]}^${m[2]}')
    .replaceAllMapped(RegExp(r'([a-zA-Z])_\{([^}]+)\}'), (m) => '${m[1]}_${m[2]}')
    .replaceAllMapped(RegExp(r'([a-zA-Z])\^(\w)'), (m) => '${m[1]}^${m[2]}')
    .replaceAllMapped(RegExp(r'([a-zA-Z])_(\w)'), (m) => '${m[1]}_${m[2]}')
    // common symbols
    .replaceAll(r'\times', '×')
    .replaceAll(r'\div', '÷')
    .replaceAll(r'\pm', '±')
    .replaceAll(r'\infty', '∞')
    .replaceAll(r'\pi', 'π')
    .replaceAll(r'\alpha', 'α')
    .replaceAll(r'\beta', 'β')
    .replaceAll(r'\gamma', 'γ')
    .replaceAll(r'\delta', 'δ')
    .replaceAll(r'\theta', 'θ')
    .replaceAll(r'\sigma', 'σ')
    .replaceAll(r'\mu', 'μ')
    .replaceAll(r'\lambda', 'λ')
    .replaceAll(r'\sum', '∑')
    .replaceAll(r'\int', '∫')
    .replaceAll(r'\approx', '≈')
    .replaceAll(r'\neq', '≠')
    .replaceAll(r'\leq', '≤')
    .replaceAll(r'\geq', '≥')
    .replaceAll(r'\cdot', '·')
    .replaceAll(r'\ldots', '…')
    .replaceAll(r'\rightarrow', '→')
    .replaceAll(r'\leftarrow', '←')
    // remove remaining backslash-commands like \text{} \mathbb{} etc.
    .replaceAllMapped(RegExp(r'\\[a-zA-Z]+\{([^}]*)\}'), (m) => m[1] ?? '')
    // remove lone backslash-commands
    .replaceAll(RegExp(r'\\[a-zA-Z]+\s*'), '');
}

/// Full cleanup: math → markdown strip → whitespace normalise
String _cleanBotResponse(String text) {
  String s = _convertMath(text);

  // Remove code fence markers but keep the content
  s = s.replaceAllMapped(
    RegExp(r'```(?:[a-zA-Z0-9_+\-]*)\n?([\s\S]*?)```'),
    (m) => (m[1] ?? '').trim(),
  );

  // Remove headers (# ## ### etc.)
  s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiline: true), '');

  // Remove bold/italic markers (**, *, __, _)
  s = s.replaceAll(RegExp(r'\*\*\*([^*]+)\*\*\*'), r'$1');
  s = s.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
  s = s.replaceAll(RegExp(r'\*([^*\n]+)\*'), r'$1');
  s = s.replaceAll(RegExp(r'___([^_]+)___'), r'$1');
  s = s.replaceAll(RegExp(r'__([^_]+)__'), r'$1');
  s = s.replaceAll(RegExp(r'_([^_\n]+)_'), r'$1');

  // Remove inline backticks but keep content
  s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1] ?? '');

  // Remove horizontal rules
  s = s.replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiline: true), '');

  // Convert markdown links [text](url) → text
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1] ?? '');

  // Remove stray asterisks and underscores that remain
  s = s.replaceAll(RegExp(r'(?<!\w)\*+(?!\w)'), '');
  s = s.replaceAll(RegExp(r'(?<!\w)_+(?!\w)'), '');

  // Normalize multiple blank lines to max 2
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

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 360));
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

  // ── Attach ─────────────────────────────────────────────────────────────────

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
      case 'pdf':
        await _pickDoc(['pdf']);
        break;
      case 'text':
        await _pickDoc(['txt', 'md', 'csv', 'json', 'log', 'docx']);
        break;
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
      if (text.isEmpty) {
        _snack('No text found in image.', err: true);
        return;
      }
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
      if (text.trim().isEmpty) {
        _snack('Could not extract text.', err: true);
        return;
      }
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

  void _send() {
    final text = _controller.text.trim();
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
      content: Text(msg, style: const TextStyle(color: _textPri, fontSize: 13)),
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

    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar(docCtx),
      drawer: _drawer(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            if (docCtx != null) _docBanner(docCtx),
            Expanded(child: _msgList(chatState)),
            if (_processingDoc) _processingBar(),
            _inputArea(docCtx),
          ],
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  PreferredSizeWidget _appBar(DocumentContext? docCtx) {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: Builder(
        builder: (ctx) => GestureDetector(
          onTap: () => Scaffold.of(ctx).openDrawer(),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.menu, color: _textPri, size: 26),
          ),
        ),
      ),
      title: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.asset(_logoPath, width: 26, height: 26,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.auto_awesome, color: _accent, size: 20)),
        ),
        const SizedBox(width: 10),
        const Text('STREMINI AI',
            style: TextStyle(
                color: _textPri,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0)),
        if (docCtx != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: _accent.withOpacity(0.3)),
            ),
            child: const Text('DOC',
                style: TextStyle(color: _accent, fontSize: 9,
                    fontWeight: FontWeight.w800, letterSpacing: 1.0)),
          ),
        ],
      ]),
      actions: [
        GestureDetector(
          onTap: () => ref.read(chatNotifierProvider.notifier).clearChat(),
          child: Container(
            margin: const EdgeInsets.fromLTRB(0, 10, 14, 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: const Text('Clear',
                style: TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  // ── Doc Banner ─────────────────────────────────────────────────────────────
  Widget _docBanner(DocumentContext doc) {
    final isOcr = doc.fileName.startsWith('📷');
    final isDocx = doc.fileName.toLowerCase().endsWith('.docx');
    return Container(
      color: const Color(0xFF080808),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: (isOcr ? _success : isDocx ? _accent : _danger).withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: (isOcr ? _success : isDocx ? _accent : _danger).withOpacity(0.2)),
          ),
          child: Icon(
            isOcr ? Icons.image_search_outlined : isDocx ? Icons.description_outlined : Icons.picture_as_pdf,
            color: isOcr ? _success : isDocx ? _accent : _danger,
            size: 15,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(doc.fileName,
                style: const TextStyle(color: _textPri, fontSize: 12, fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const Text('Ask anything about this document',
                style: TextStyle(color: _textMuted, fontSize: 11)),
          ]),
        ),
        GestureDetector(
          onTap: () => ref.read(chatNotifierProvider.notifier).clearDocument(),
          child: Container(
            width: 26, height: 26,
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(7), border: Border.all(color: _border)),
            child: const Icon(Icons.close, color: _textMuted, size: 13),
          ),
        ),
      ]),
    );
  }

  // ── Message list ───────────────────────────────────────────────────────────
  Widget _msgList(AsyncValue<List<Message>> chatState) {
    return chatState.when(
      data: (msgs) => msgs.isEmpty
          ? _emptyState()
          : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final prev = i > 0 ? msgs[i - 1] : null;
                return _bubble(msgs[i], showAvatar: prev?.type != msgs[i].type);
              },
            ),
      loading: () => const Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_accent))),
      error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: _danger, fontSize: 13))),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Image.asset(_logoPath, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome, color: _accent, size: 26)),
          ),
        ),
        const SizedBox(height: 16),
        const Text('STREMINI AI',
            style: TextStyle(color: _textPri, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
        const SizedBox(height: 6),
        const Text('How can I help you today?',
            style: TextStyle(color: _textMuted, fontSize: 13)),
      ]),
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
        final isUser = message.type == MessageType.user;
        // IMPROVED: use full cleanup for bot, raw text for user
        final displayText = isUser ? message.text : _cleanBotResponse(message.text);
        return Padding(
          padding: EdgeInsets.only(bottom: 4, top: showAvatar ? 14 : 2),
          child: Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser && showAvatar) ...[_botAvatar(), const SizedBox(width: 8)],
              if (!isUser && !showAvatar) const SizedBox(width: 34),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: isUser ? _userBubble : _botBubble,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(14),
                      topRight:    const Radius.circular(14),
                      bottomLeft:  Radius.circular(isUser ? 14 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 14),
                    ),
                    border: Border.all(
                        color: isUser ? _accent.withOpacity(0.18) : _border),
                  ),
                  child: _renderContent(displayText, isUser),
                ),
              ),
              if (isUser && showAvatar) ...[const SizedBox(width: 8), _userAvatar()],
              if (isUser && !showAvatar) const SizedBox(width: 30),
            ],
          ),
        );
    }
  }

  /// Renders text with inline code blocks styled distinctly
  Widget _renderContent(String text, bool isUser) {
    // Split on inline code-like patterns (anything that looks like a formula or code)
    // We render them in a monospace accent style
    final parts = _splitForRendering(text);
    if (parts.length == 1) {
      // Simple text, no special segments
      return SelectableText(
        text,
        style: const TextStyle(color: _textPri, fontSize: 14, height: 1.6),
        cursorColor: _accent,
      );
    }
    return SelectableText.rich(
      TextSpan(
        children: parts.map((part) {
          if (part.isCode) {
            return TextSpan(
              text: part.text,
              style: TextStyle(
                color: _accent,
                fontSize: 13,
                fontFamily: 'monospace',
                background: Paint()..color = _accent.withOpacity(0.08),
                height: 1.6,
              ),
            );
          }
          return TextSpan(
            text: part.text,
            style: const TextStyle(color: _textPri, fontSize: 14, height: 1.6),
          );
        }).toList(),
      ),
      cursorColor: _accent,
    );
  }

  List<_TextPart> _splitForRendering(String text) {
    // Look for math-expression patterns: numbers with operators, or capitalized formula-like text
    final codePattern = RegExp(r'([A-Za-z]\^[A-Za-z0-9]+|[A-Za-z]_[A-Za-z0-9]+|√\([^)]+\)|\([^)]+\)\/\([^)]+\)|∑|∫|≈|≠|≤|≥)');
    final spans = <_TextPart>[];
    int last = 0;
    for (final match in codePattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(_TextPart(text.substring(last, match.start), false));
      }
      spans.add(_TextPart(match[0]!, true));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(_TextPart(text.substring(last), false));
    }
    return spans.isEmpty ? [_TextPart(text, false)] : spans;
  }

  Widget _botAvatar() => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
          child: Image.asset(_logoPath, width: 28, height: 28, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome, color: _accent, size: 13)),
        ),
      );

  Widget _userAvatar() => Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
        child: const Icon(Icons.person_outline, color: _textMuted, size: 14),
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
          Expanded(child: Text(text, style: const TextStyle(color: _textMuted, fontSize: 13, height: 1.5))),
        ]),
      );

  Widget _typingBubble() => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 14),
        child: Row(children: [
          _botAvatar(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: _botBubble,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14), topRight: Radius.circular(14),
                bottomRight: Radius.circular(14), bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: _border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 5, height: 5,
                decoration: BoxDecoration(
                  color: _textMuted.withOpacity(0.45),
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
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_accent))),
          SizedBox(width: 10),
          Text('Extracting text…', style: TextStyle(color: _textMuted, fontSize: 13)),
        ]),
      );

  // ── Input Area ─────────────────────────────────────────────────────────────
  Widget _inputArea(DocumentContext? docCtx) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GestureDetector(
              onTap: _pickAttachment,
              child: Container(
                width: 40, height: 40,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: _surface, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: const Icon(Icons.add_rounded, color: _textMuted, size: 20),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: docCtx != null ? _accent.withOpacity(0.35) : _border),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: const TextStyle(color: _textPri, fontSize: 14, height: 1.45),
                  decoration: InputDecoration(
                    hintText: docCtx != null ? 'Ask about ${docCtx.fileName}…' : 'Message Stremini…',
                    hintStyle: const TextStyle(color: _textDim, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 40, height: 40,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Drawer ─────────────────────────────────────────────────────────────────
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

// Helper class for rich text rendering
class _TextPart {
  final String text;
  final bool isCode;
  const _TextPart(this.text, this.isCode);
}

// ─────────────────────────────────────────────────────────────────────────────
// Attach bottom sheet (unchanged)
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
            decoration: BoxDecoration(color: const Color(0xFF222222), borderRadius: BorderRadius.circular(2)),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Attach',
                style: TextStyle(color: _textPri, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
          ),
          const SizedBox(height: 14),
          _tile(context, Icons.picture_as_pdf_outlined, _danger, 'PDF Document', 'Chat about a PDF file', 'pdf'),
          _tile(context, Icons.description_outlined, _accent, 'Document / Text', 'TXT, MD, CSV, JSON, DOCX', 'text'),
          _tile(context, Icons.image_search_outlined, const Color(0xFF8B5CF6), 'Image', 'Use image as chat context', 'image'),
          _tile(context, Icons.attach_file_rounded, const Color(0xFFF59E0B), 'Other File', 'Any file type', 'file'),
        ],
      ),
    );
  }

  Widget _tile(BuildContext ctx, IconData icon, Color iconColor, String title, String subtitle, String type) {
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
            decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: _textPri, fontSize: 13, fontWeight: FontWeight.w600)),
            Text(subtitle, style: const TextStyle(color: _textMuted, fontSize: 11)),
          ])),
          const Icon(Icons.chevron_right, color: _textDim, size: 16),
        ]),
      ),
    );
  }
}
