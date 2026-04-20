class AppConfig {
  static const baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://ai-keyboard-backend.vishwajeetadkine705.workers.dev',
  );

  static const githubAgentUrl = String.fromEnvironment(
    'GITHUB_AGENT_URL',
    defaultValue: 'https://agentic-github-debugger.vishwajeetadkine705.workers.dev',
  );
}
