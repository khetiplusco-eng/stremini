import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../providers/chat_provider.dart';
import '../models/message_model.dart';

// ── PDF text extraction using syncfusion_flutter_pdf ─────────────────────────
// Handles real-world PDFs: compressed streams, encoded text, multi-page docs.
// Add to pubspec.yaml:  syncfusion_flutter_pdf: ^27.1.48
Future<String> _extractTextFromPdfBytes(List<int> bytes) async {
  try {
    final document = PdfDocument(inputBytes: Uint8List.fromList(bytes));
    final extractor = PdfTextExtractor(document);
    final buffer = StringBuffer();

    for (int i = 0; i < document.pages.count; i++) {
      final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
      if (pageText.trim().isNotEmpty) {
        buffer.writeln(pageText.trim());
        buffer.writeln(); // blank line between pages
      }
    }

    document.dispose();

    final result = buffer.toString().trim();
    if (result.isEmpty) {
      return ''; // caller will show "could not extract" snackbar
    }
    return result;
  } catch (e) {
    debugPrint('[PDF extraction error] $e');
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

// ─────────────────────────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Standard image / file attachment
  File? _selectedFile;
  String? _base64File;
  String? _mimeType;
  String? _fileName;

  // Document processing spinner
  bool _processingDocument = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Attachment picker ─────────────────────────────────────────────────────
  Future<void> _pickAttachment() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Document options ────────────────────────────────────────
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
              title: const Text('PDF Document',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Load & chat about a PDF',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () async {
                Navigator.pop(context);
                await _pickDocument(['pdf']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.lightBlueAccent),
              title: const Text('Text / TXT / MD',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Load & chat about a text file',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () async {
                Navigator.pop(context);
                await _pickDocument(['txt', 'md', 'csv', 'json', 'log']);
              },
            ),
            const Divider(color: Colors.white12, height: 20),
            // ── Regular attachment options ──────────────────────────────
            ListTile(
              leading: const Icon(Icons.image, color: Colors.blue),
              title: const Text('Image', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final XFile? image =
                    await picker.pickImage(source: ImageSource.gallery);
                if (image != null) _processAttachment(File(image.path));
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.orange),
              title: const Text('Other File', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final result = await FilePicker.platform.pickFiles();
                if (result != null && result.files.single.path != null) {
                  _processAttachment(File(result.files.single.path!));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Pick + extract document ───────────────────────────────────────────────
  Future<void> _pickDocument(List<String> extensions) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final name = result.files.single.name;
    final ext = name.split('.').last.toLowerCase();

    setState(() => _processingDocument = true);
    try {
      String text;
      if (ext == 'pdf') {
        final bytes = await file.readAsBytes();
        text = await _extractTextFromPdfBytes(bytes);
      } else {
        text = await _readTextFile(file);
      }

      if (!mounted) return;

      if (text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
            'Could not extract text from this PDF. It may be scanned/image-based.',
          ),
          backgroundColor: Colors.orange[800],
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ));
        return;
      }

      // Debug: log how much text was extracted so you can verify
      debugPrint('[Document loaded] "$name" — ${text.length} chars, '
          '~${(text.length / 4).round()} tokens');

      ref
          .read(chatNotifierProvider.notifier)
          .loadDocument(DocumentContext(fileName: name, text: text));

      // Show success confirmation with char count
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '📄 Loaded "$name" — ${(text.length / 1000).toStringAsFixed(1)}k characters extracted',
        ),
        backgroundColor: const Color(0xFF1A3A5C),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      debugPrint('[Document error] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error reading document: $e'),
          backgroundColor: Colors.red[800],
        ));
      }
    } finally {
      if (mounted) setState(() => _processingDocument = false);
    }
  }

  // ── Process image / generic attachment ───────────────────────────────────
  Future<void> _processAttachment(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final base64 = base64Encode(bytes);
      final mime = lookupMimeType(file.path) ?? 'application/octet-stream';
      final name = file.path.split('/').last;

      setState(() {
        _selectedFile = file;
        _base64File = base64;
        _mimeType = mime;
        _fileName = name;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error processing file: $e')));
      }
    }
  }

  void _clearAttachment() {
    setState(() {
      _selectedFile = null;
      _base64File = null;
      _mimeType = null;
      _fileName = null;
    });
  }

  // ── Send ──────────────────────────────────────────────────────────────────
  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedFile == null) return;

    ref.read(chatNotifierProvider.notifier).sendMessage(
          text,
          attachment: _base64File,
          mimeType: _mimeType,
          fileName: _fileName,
        );

    _controller.clear();
    _clearAttachment();
    _focusNode.unfocus();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider);
    final docCtx = ref.watch(documentContextProvider);

    ref.listen<AsyncValue<List<Message>>>(chatNotifierProvider,
        (previous, next) {
      next.whenData((messages) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      });
    });

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('Stremini AI',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          // ── Active document banner ────────────────────────────────────
          if (docCtx != null) _buildDocumentBanner(docCtx),

          // ── Message list ──────────────────────────────────────────────
          Expanded(
            child: chatState.when(
              data: (messages) => ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 20),
                itemCount: messages.length,
                itemBuilder: (context, index) =>
                    _buildMessageBubble(messages[index]),
              ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                  child: Text('Error: $error',
                      style: const TextStyle(color: Colors.red))),
            ),
          ),

          // ── Document processing indicator ─────────────────────────────
          if (_processingDocument)
            Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(Colors.blue)),
                  ),
                  SizedBox(width: 12),
                  Text('Extracting document text…',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),

          // ── Image / file preview ──────────────────────────────────────
          if (_selectedFile != null)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              color: Colors.grey[900],
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _mimeType?.startsWith('image/') == true
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(_selectedFile!,
                                fit: BoxFit.cover),
                          )
                        : const Icon(Icons.insert_drive_file,
                            color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _fileName ?? 'Attached File',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.red, size: 20),
                    onPressed: _clearAttachment,
                  ),
                ],
              ),
            ),

          // ── Input area ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border(
                  top: BorderSide(
                      color: Colors.grey[800]!, width: 1)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Attachment button
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: Colors.grey[900],
                        shape: BoxShape.circle),
                    child: IconButton(
                      icon: const Icon(Icons.add,
                          color: Colors.white, size: 24),
                      onPressed: _pickAttachment,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Text field — hint changes when document is loaded
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(24),
                        border: docCtx != null
                            ? Border.all(
                                color: Colors.blue.withOpacity(0.5),
                                width: 1.5)
                            : null,
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: docCtx != null
                              ? 'Ask about ${docCtx.fileName}…'
                              : 'Ask anything...',
                          hintStyle: const TextStyle(
                              color: Colors.grey, fontSize: 15),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Send button
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [
                            Color(0xFF23A6E2),
                            Color(0xFF0066FF)
                          ]),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send,
                          color: Colors.white, size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Active document banner ────────────────────────────────────────────────
  Widget _buildDocumentBanner(DocumentContext doc) {
    return Container(
      color: const Color(0xFF0D2137),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf,
              color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.fileName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Document mode — ask anything about this file',
                  style: TextStyle(color: Colors.blue[200], fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                color: Colors.white54, size: 20),
            onPressed: () =>
                ref.read(chatNotifierProvider.notifier).clearDocument(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ── Message bubbles ───────────────────────────────────────────────────────
  Widget _buildMessageBubble(Message message) {
    switch (message.type) {
      case MessageType.typing:
        return _buildTypingIndicatorBubble();
      case MessageType.documentBanner:
        return _buildDocumentAnnouncementBubble(message.text);
      default:
        final isUser = message.type == MessageType.user;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Colors.grey[800]
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: SelectableText(
                    message.text,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4),
                    cursorColor: const Color(0xFF23A6E2),
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildDocumentAnnouncementBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D2137),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Colors.blue.withOpacity(0.35), width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.picture_as_pdf,
                color: Colors.redAccent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicatorBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Typing...',
                style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1A),
      child: Container(),
    );
  }
}
