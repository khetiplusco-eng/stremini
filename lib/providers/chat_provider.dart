import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';

// ── Document context ──────────────────────────────────────────────────────────
class DocumentContext {
  final String fileName;
  final String text;

  const DocumentContext({required this.fileName, required this.text});
}

final documentContextProvider =
    StateProvider<DocumentContext?>((ref) => null);

// ── Chat notifier ─────────────────────────────────────────────────────────────
class ChatNotifier extends AsyncNotifier<List<Message>> {
  static const String _initialGreetingId = 'initial_greeting';

  @override
  FutureOr<List<Message>> build() {
    return [
      Message(
        id: _initialGreetingId,
        text: "Hello! I'm Stremini AI. How can I help you today?",
        type: MessageType.bot,
        timestamp: DateTime.now(),
      )
    ];
  }

  List<Map<String, dynamic>> _getHistory() {
    final currentMessages = state.value ?? [];
    final history = <Map<String, dynamic>>[];

    for (var msg in currentMessages) {
      if (msg.id == _initialGreetingId ||
          msg.type == MessageType.typing ||
          msg.type == MessageType.documentBanner ||
          msg.text.startsWith('❌') ||
          msg.text.startsWith('⚠️')) {
        continue;
      }
      history.add({
        "role": msg.type == MessageType.user ? 'user' : 'assistant',
        "content": msg.text,
      });
    }

    return history.length > 100
        ? history.sublist(history.length - 100)
        : history;
  }

  // Send a message. If a document is loaded, routes to the document endpoint.
  Future<void> sendMessage(
    String text, {
    String? attachment,
    String? mimeType,
    String? fileName,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachment == null) return;

    final displayText =
        trimmed.isEmpty ? "Sent an attachment: $fileName" : trimmed;

    final userMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: displayText,
      type: MessageType.user,
      timestamp: DateTime.now(),
    );

    final history = _getHistory();
    final current = state.value ?? <Message>[];
    final filtered = current.where((m) => m.id != _initialGreetingId).toList();
    state = AsyncValue.data([...filtered, userMessage]);

    addTypingIndicator();

    try {
      final api = ref.read(apiServiceProvider);
      final docCtx = ref.read(documentContextProvider);

      String reply;
      if (docCtx != null && trimmed.isNotEmpty) {
        reply = await api.sendDocumentMessage(
          documentText: docCtx.text,
          question: trimmed,
          history: history,
        );
      } else {
        reply = await api.sendMessage(
          trimmed,
          attachment: attachment,
          mimeType: mimeType,
          fileName: fileName,
          history: history,
        );
      }

      removeTypingIndicator();

      state = AsyncValue.data([
        ...(state.value ?? []),
        Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: reply,
          type: MessageType.bot,
          timestamp: DateTime.now(),
        ),
      ]);
    } catch (e) {
      removeTypingIndicator();
      state = AsyncValue.data([
        ...(state.value ?? []),
        Message(
          id: DateTime.now().toString(),
          text: '⚠️ Error: $e',
          type: MessageType.bot,
          timestamp: DateTime.now(),
        ),
      ]);
    }
  }

  // Load a document and pin it into context.
  void loadDocument(DocumentContext doc) {
    ref.read(documentContextProvider.notifier).state = doc;

    final banner = Message(
      id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
      text:
          '📄 Document loaded: ${doc.fileName}\nAsk anything about it. Tap × in the banner to clear.',
      type: MessageType.documentBanner,
      timestamp: DateTime.now(),
    );

    final current = state.value ?? <Message>[];
    state = AsyncValue.data([
      ...current.where((m) => m.id != _initialGreetingId),
      banner,
    ]);
  }

  // Remove document context and return to normal chat.
  void clearDocument() {
    ref.read(documentContextProvider.notifier).state = null;

    state = AsyncValue.data([
      ...(state.value ?? []),
      Message(
        id: 'doc_clear_${DateTime.now().millisecondsSinceEpoch}',
        text: '📄 Document cleared. Back to normal chat.',
        type: MessageType.bot,
        timestamp: DateTime.now(),
      ),
    ]);
  }

  void addTypingIndicator() {
    final current = state.value ?? <Message>[];
    if (current.any((m) => m.type == MessageType.typing)) return;
    state = AsyncValue.data([
      ...current,
      Message(
          id: 'typing',
          text: '...',
          type: MessageType.typing,
          timestamp: DateTime.now()),
    ]);
  }

  void removeTypingIndicator() {
    final current = state.value ?? <Message>[];
    state = AsyncValue.data(
        current.where((m) => m.type != MessageType.typing).toList());
  }

  Future<void> clearChat() async {
    ref.read(documentContextProvider.notifier).state = null;
    state = AsyncValue.data([
      Message(
        id: _initialGreetingId,
        text: "Hello! I'm Stremini AI. How can I help you today?",
        type: MessageType.bot,
        timestamp: DateTime.now(),
      )
    ]);
  }
}

final chatNotifierProvider =
    AsyncNotifierProvider<ChatNotifier, List<Message>>(ChatNotifier.new);