class EnvConfig {
  // Use String.fromEnvironment to pull values from the build command
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://ai-keyboard-backend.vishwajeetadkine705.workers.dev',
  );

  static const String githubAgentUrl = String.fromEnvironment(
    'GITHUB_AGENT_URL',
    defaultValue: 'https://agentic-github-debugger.vishwajeetadkine705.workers.dev',
  );
}