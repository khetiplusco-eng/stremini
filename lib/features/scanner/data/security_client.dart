import '../../../core/config/app_config.dart';
import '../../../core/network/base_client.dart';

class SecurityClient {
  const SecurityClient(this._baseClient);

  final BaseClient _baseClient;

  Future<Map<String, dynamic>> scanContent(String content) {
    return _baseClient.postJson(
      Uri.parse('${AppConfig.baseUrl}/scan-content'),
      {'content': content},
    );
  }
}
