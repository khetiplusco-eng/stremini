import '../../../core/config/app_config.dart';
import '../../../core/network/base_client.dart';
import '../../../core/result/result.dart';

class ChatClient {
  const ChatClient(this._baseClient);

  final BaseClient _baseClient;

  Future<Result<String>> sendMessage({
    required String message,
    List<Map<String, dynamic>> history = const [],
    String? attachment,
    String? mimeType,
    String? fileName,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'history': history,
    };

    if (attachment != null) {
      body['attachment'] = {
        'data': attachment,
        'mime': mimeType,
        'name': fileName,
      };
    }

    try {
      final data = await _baseClient.postJson(
        Uri.parse('${AppConfig.baseUrl}/chat/message'),
        body,
      );
      return Success((data['response'] ?? data['reply'] ?? data['message'] ?? 'Empty reply.').toString());
    } catch (e) {
      return Error(NetworkFailure(e.toString()));
    }
  }

  Future<Result<String>> sendDocumentMessage({
    required String documentText,
    required String question,
    List<Map<String, dynamic>> history = const [],
  }) async {
    try {
      final data = await _baseClient.postJson(
        Uri.parse('${AppConfig.baseUrl}/chat/document'),
        {
          'documentText': documentText,
          'question': question,
          'history': history,
        },
      );
      return Success((data['response'] ?? 'Empty reply.').toString());
    } catch (e) {
      return Error(NetworkFailure(e.toString()));
    }
  }
}
