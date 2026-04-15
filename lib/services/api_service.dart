import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/env_config.dart';

// ─── URL sanitizer ────────────────────────────────────────────────────────────
String _sanitizeError(Object e) {
  String raw = e.toString();
  raw = raw.replaceAll(RegExp(r'https?://[^\s,]+'), 'the server');
  raw = raw.replaceAll(RegExp(r'[a-zA-Z0-9._-]+\.workers\.dev[^\s,]*'), 'the server');
  raw = raw.replaceAll(RegExp(r'[a-zA-Z0-9._-]+\.[a-zA-Z]{2,6}(:\d+)?(/[^\s]*)?'), 'the server');
  raw = raw
      .replaceAll('SocketException:', 'Network error:')
      .replaceAll('ClientException:', '')
      .replaceAll('HandshakeException:', 'Secure connection error:')
      .replaceAll('Exception:', '')
      .trim();

  if (raw.toLowerCase().contains('failed host lookup') ||
      raw.toLowerCase().contains('network is unreachable') ||
      raw.toLowerCase().contains('no address associated')) {
    return 'No internet connection. Please check your network and try again.';
  }
  if (raw.toLowerCase().contains('timed out') || raw.toLowerCase().contains('timeout')) {
    return 'Connection timed out. Please try again.';
  }
  if (raw.isEmpty) return 'Something went wrong. Please try again.';
  return raw;
}

class ApiService {
  static const String baseUrl = EnvConfig.baseUrl;
  static const String githubAgentUrl = EnvConfig.githubAgentUrl;

  // ── Auth helpers ──────────────────────────────────────────────────────────

  /// Returns the current access token.
  /// If the session exists but the token is about to expire, Supabase
  /// refreshes it automatically. Returns null if not signed in.
  String? _getToken() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      // This should never happen after the _waitForSessionRestore() fix
      // in main.dart, but log it so we catch regressions immediately.
      debugPrint('⚠️ ApiService._getToken: currentSession is null — '
          'Authorization header will be missing!');
      return null;
    }
    return session.accessToken;
  }

  /// Builds headers including the JWT when the user is signed in.
  Map<String, String> _headers({bool acceptStream = false}) {
    final token = _getToken();
    return <String, String>{
      'Content-Type': 'application/json',
      'Accept': acceptStream ? 'text/event-stream' : 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> initSession() async {}
  Future<void> clearSession() async {}

  // ── Standard chat ─────────────────────────────────────────────────────────
  Future<String> sendMessage(
    String userMessage, {
    String? attachment,
    String? mimeType,
    String? fileName,
    List<Map<String, dynamic>>? history,
  }) async {
    try {
      final Map<String, dynamic> bodyMap = {
        'message': userMessage,
        'history': history ?? [],
      };
      if (attachment != null) {
        bodyMap['attachment'] = <String, dynamic>{
          'data': attachment,
          'mime': mimeType,
          'name': fileName,
        };
      }
      final response = await http.post(
        Uri.parse('$baseUrl/chat/message'),
        headers: _headers(),
        body: jsonEncode(bodyMap),
      );
      if (response.statusCode == 401) return 'Session expired. Please sign in again.';
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          return (data['response'] ?? data['reply'] ?? data['message'] ?? 'Empty reply.').toString();
        }
        return data.toString();
      }
      return 'Unable to get a response. Please try again.';
    } catch (e) {
      return '⚠️ ${_sanitizeError(e)}';
    }
  }

  // ── Document chat ─────────────────────────────────────────────────────────
  Future<String> sendDocumentMessage({
    required String documentText,
    required String question,
    List<Map<String, dynamic>>? history,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/document'),
        headers: _headers(),
        body: jsonEncode({
          'documentText': documentText,
          'question': question,
          'history': history ?? [],
        }),
      );
      if (response.statusCode == 401) return 'Session expired. Please sign in again.';
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['response'] ?? 'Empty reply.').toString();
      }
      return 'Unable to get a response. Please try again.';
    } catch (e) {
      return '⚠️ ${_sanitizeError(e)}';
    }
  }

  // ── Streaming ─────────────────────────────────────────────────────────────
  Stream<String> streamMessage(
    String userMessage, {
    List<Map<String, dynamic>>? history,
  }) async* {
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/chat/stream'));
      request.headers.addAll(_headers(acceptStream: true));
      request.body = jsonEncode({
        'message': userMessage,
        'history': history ?? [],
      });
      final streamedResponse = await request.send();
      if (streamedResponse.statusCode == 401) {
        yield '⚠️ Session expired. Please sign in again.';
        return;
      }
      if (streamedResponse.statusCode == 200) {
        await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
          for (final line in chunk.split('\n')) {
            if (line.startsWith('data: ')) {
              final jsonStr = line.substring(6);
              if (jsonStr.trim().isNotEmpty && jsonStr != '[DONE]') {
                try {
                  final data = jsonDecode(jsonStr);
                  if (data is Map && data.containsKey('token')) {
                    yield data['token'] as String;
                  }
                } catch (_) {}
              }
            }
          }
        }
      } else {
        yield '⚠️ Unable to get a response. Please try again.';
      }
    } catch (e) {
      yield '⚠️ ${_sanitizeError(e)}';
    }
  }

  // ── GitHub Agent — single step ────────────────────────────────────────────
  Future<Map<String, dynamic>> githubAgentStep({
    required String repoOwner,
    required String repoName,
    required String task,
    required List<Map<String, dynamic>> history,
    required List<String> visitedFiles,
    required int iteration,
    List<Map<String, dynamic>> outputFiles = const [],
    String agentMode = 'fix',
    bool allowPush = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(githubAgentUrl),
        headers: _headers(),
        body: jsonEncode({
          'repoOwner': repoOwner,
          'repoName': repoName,
          'task': task,
          'history': history,
          'readFiles': visitedFiles,
          'outputFiles': outputFiles,
          'iteration': iteration,
          'agentMode': agentMode,
          'allowPush': allowPush,
        }),
      );
      if (response.statusCode == 401) {
        return {'status': 'ERROR', 'message': 'Session expired. Please sign in again.'};
      }
      if (response.statusCode != 200) {
        return {'status': 'ERROR', 'message': 'Unable to reach agent. Please check your connection.'};
      }
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
      return {'status': 'ERROR', 'message': 'Unexpected response. Please try again.'};
    } catch (e) {
      return {'status': 'ERROR', 'message': _sanitizeError(e)};
    }
  }

  // ── GitHub Agent — all-in-one loop ────────────────────────────────────────
  Future<GithubAgentRunResult> processGithubAgentTask({
    required String repoOwner,
    required String repoName,
    required String task,
    String agentMode = 'fix',
  }) async {
    final startedAt = DateTime.now();
    final visitedFiles = <String>[];
    final outputFiles = <Map<String, dynamic>>[];
    final history = <Map<String, dynamic>>[];
    const maxClientIterations = 20;
    var iteration = 0;

    try {
      while (true) {
        if (iteration >= maxClientIterations) {
          return GithubAgentRunResult(
            status: 'ERROR',
            summary: 'Stopped after $maxClientIterations iterations.',
            rawPayload: '',
            visitedFiles: visitedFiles,
            iterationCount: iteration,
            duration: DateTime.now().difference(startedAt),
          );
        }

        final response = await githubAgentStep(
          repoOwner: repoOwner,
          repoName: repoName,
          task: task,
          history: history,
          visitedFiles: visitedFiles,
          iteration: iteration,
          outputFiles: outputFiles,
          agentMode: agentMode,
        );

        final status = response['status']?.toString() ?? 'ERROR';

        if (status == 'CONTINUE') {
          final nextFile = response['nextFile']?.toString() ?? '';
          final fileContent = response['fileContent']?.toString() ?? '';
          final action = response['action']?.toString() ?? 'read_file';

          if (response['readFiles'] is List) {
            visitedFiles
              ..clear()
              ..addAll(List<String>.from(response['readFiles'] as List));
          } else if (nextFile.isNotEmpty && !visitedFiles.contains(nextFile)) {
            visitedFiles.add(nextFile);
          }

          if (response['outputFiles'] is List) {
            final workerOutputFiles = List<Map<String, dynamic>>.from(
                (response['outputFiles'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
            outputFiles
              ..clear()
              ..addAll(workerOutputFiles);
          }

          iteration = response['iteration'] is int ? response['iteration'] as int : iteration + 1;

          if (action == 'read_file' && nextFile.isNotEmpty) {
            history.addAll([
              {'role': 'assistant', 'content': '<read_file path="$nextFile" />'},
              {'role': 'user', 'content': 'File content of $nextFile:\n\n$fileContent'},
            ]);
          }
          continue;
        }

        return GithubAgentRunResult(
          status: status,
          summary: _summaryFromResponse(response),
          rawPayload: const JsonEncoder.withIndent('  ').convert(response),
          visitedFiles: visitedFiles,
          iterationCount: iteration,
          duration: DateTime.now().difference(startedAt),
          filePath: response['filePath']?.toString(),
          pushed: response['pushed'] == true,
          outputFiles: outputFiles,
        );
      }
    } catch (e) {
      return GithubAgentRunResult(
        status: 'ERROR',
        summary: _sanitizeError(e),
        rawPayload: '',
        visitedFiles: visitedFiles,
        iterationCount: iteration,
        duration: DateTime.now().difference(startedAt),
      );
    }
  }

  String _summaryFromResponse(Map<String, dynamic> data) {
    final status = data['status'];
    switch (status) {
      case 'COMPLETED':
        final solution = _extractCodeOnly(data['solution']?.toString() ?? '');
        return solution.isNotEmpty ? solution : 'No corrected code returned.';
      case 'FIXED':
        final filePath = data['filePath']?.toString();
        final fixedContent = _extractCodeOnly(data['fixedContent']?.toString() ?? '');
        if (fixedContent.isNotEmpty) {
          if (filePath == null || filePath.isEmpty) return fixedContent;
          return '// File: $filePath\n$fixedContent';
        }
        final fallback = _extractCodeOnly(
          data['solution']?.toString() ??
              data['patch']?.toString() ??
              data['fix']?.toString() ??
              data['pushMessage']?.toString() ?? '',
        );
        return fallback.isNotEmpty ? fallback : 'Corrected code generated.';
      case 'ERROR':
        return _sanitizeError(data['message']?.toString() ?? '');
      default:
        return 'Unexpected response. Please try again.';
    }
  }

  String _extractCodeOnly(String input) {
    final fenceRegex = RegExp(r'```(?:[a-zA-Z0-9_+-]+)?\n([\s\S]*?)```');
    final matches = fenceRegex.allMatches(input).toList();
    if (matches.isEmpty) return input.trim();
    return matches
        .map((m) => (m.group(1) ?? '').trim())
        .where((part) => part.isNotEmpty)
        .join('\n\n');
  }

  // ── Security scan ─────────────────────────────────────────────────────────
  Future<SecurityScanResult> scanContent(String content) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/scan-content'),
        headers: _headers(),
        body: jsonEncode({'content': content}),
      );
      if (response.statusCode == 401) {
        return SecurityScanResult(isSafe: false, riskLevel: 'error', tags: [], analysis: 'Session expired. Please sign in again.');
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<String> extractedTags = [];
        if (data['taggedElements'] != null) {
          extractedTags = (data['taggedElements'] as List)
              .map<String>((e) => e['matchedText']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
        }
        return SecurityScanResult(
          isSafe: data['isSafe'] ?? false,
          riskLevel: data['riskLevel'] ?? 'unknown',
          tags: extractedTags,
          analysis: data['summary'] ?? 'No analysis provided',
        );
      }
      return SecurityScanResult(isSafe: false, riskLevel: 'error', tags: [], analysis: 'Scan failed. Please try again.');
    } catch (e) {
      return SecurityScanResult(isSafe: false, riskLevel: 'error', tags: [], analysis: _sanitizeError(e));
    }
  }

  // Stubs
  Future<VoiceCommandResult> parseVoiceCommand(String command) async => VoiceCommandResult(action: '', parameters: {});
  Future<String> translateScreen(String content, String targetLanguage) async => '';
  Future<String> completeText(String incompleteText) async => '';
  Future<String> rewriteInTone(String text, String tone) async => '';
  Future<String> translateText(String text, String targetLanguage) async => '';
  Future<Map<String, dynamic>> checkHealth() async => {};
}

// ── Models ────────────────────────────────────────────────────────────────────

class SecurityScanResult {
  final bool isSafe;
  final String riskLevel;
  final List<String> tags;
  final String analysis;
  SecurityScanResult({required this.isSafe, required this.riskLevel, required this.tags, required this.analysis});
}

class VoiceCommandResult {
  final String action;
  final Map<String, dynamic> parameters;
  VoiceCommandResult({required this.action, required this.parameters});
}

class GithubAgentRunResult {
  final String status;
  final String summary;
  final String rawPayload;
  final List<String> visitedFiles;
  final int iterationCount;
  final Duration duration;
  final String? filePath;
  final bool pushed;
  final List<Map<String, dynamic>> outputFiles;

  const GithubAgentRunResult({
    required this.status,
    required this.summary,
    required this.rawPayload,
    required this.visitedFiles,
    required this.iterationCount,
    required this.duration,
    this.filePath,
    this.pushed = false,
    this.outputFiles = const [],
  });
}

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());