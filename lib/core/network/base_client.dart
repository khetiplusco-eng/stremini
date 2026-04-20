import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

String _sanitizeNetworkError(Object e) {
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
      raw.toLowerCase().contains('no address associated') ||
      raw.toLowerCase().contains('nodename nor servname')) {
    return 'No internet connection. Please check your network and try again.';
  }
  if (raw.toLowerCase().contains('timed out') || raw.toLowerCase().contains('timeout')) {
    return 'Connection timed out. Please try again.';
  }
  if (raw.isEmpty) return 'Something went wrong. Please try again.';
  return raw;
}

class BaseClient {
  const BaseClient(this._httpClient);

  final http.Client _httpClient;

  /// Returns the current Supabase JWT or null if not signed in.
  String? _getToken() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      debugPrint('⚠️ BaseClient._getToken: currentSession is null — '
          'Authorization header will be missing!');
      return null;
    }
    return session.accessToken;
  }

  Future<Map<String, dynamic>> postJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    try {
      final token = _getToken();

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );

      final dynamic decoded = response.body.isEmpty ? {} : jsonDecode(response.body);

      if (response.statusCode == 401) {
        throw Exception('Session expired. Please sign in again.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Unable to get a response. Please try again.');
      }

      return decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'data': decoded.toString()};
    } catch (e) {
      throw Exception(_sanitizeNetworkError(e));
    }
  }
}