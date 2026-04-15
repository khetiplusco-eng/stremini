import '../../../core/config/app_config.dart';
import '../../../core/network/base_client.dart';

class GithubAgentClient {
  const GithubAgentClient(this._baseClient);

  final BaseClient _baseClient;

  Future<Map<String, dynamic>> run(Map<String, dynamic> payload) {
    return _baseClient.postJson(Uri.parse(AppConfig.githubAgentUrl), payload);
  }
}
