import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/app_container.dart';
import '../services/api_service.dart';

class StreminiAgentScreen extends ConsumerStatefulWidget {
  const StreminiAgentScreen({super.key});

  @override
  ConsumerState<StreminiAgentScreen> createState() =>
      _StreminiAgentScreenState();
}

class _StreminiAgentScreenState
    extends ConsumerState<StreminiAgentScreen> {
  final TextEditingController _ownerController =
      TextEditingController();
  final TextEditingController _repoController =
      TextEditingController();
  final TextEditingController _taskController =
      TextEditingController();

  GithubAgentRunResult? _runResult;
  bool _isLoading = false;

  @override
  void dispose() {
    _ownerController.dispose();
    _repoController.dispose();
    _taskController.dispose();
    super.dispose();
  }

  Future<void> _runAgent() async {
    if (_ownerController.text.trim().isEmpty ||
        _repoController.text.trim().isEmpty ||
        _taskController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _runResult = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final result = await api.processGithubAgentTask(
        repoOwner: _ownerController.text.trim(),
        repoName: _repoController.text.trim(),
        task: _taskController.text.trim(),
      );
      setState(() => _runResult = result);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return AppColors.success;
      case 'FIXED':
        return AppColors.info;
      default:
        return AppColors.danger;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'COMPLETED':
        return Icons.check_circle_outline;
      case 'FIXED':
        return Icons.auto_fix_high;
      default:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        title: Text('Stremini Architect', style: AppTextStyles.h2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero banner ───────────────────────────────────────────
            AppContainer(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withOpacity(0.25),
                  AppColors.scanCyan.withOpacity(0.18),
                ],
              ),
              border: BorderSide(
                  color: AppColors.scanCyan.withOpacity(0.35)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          color: AppColors.scanCyan, size: 22),
                      const SizedBox(width: 10),
                      Text('Professional Code Architect',
                          style: AppTextStyles.h3),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Generates corrected, copy-ready code only. '
                    'No repository push is allowed from this workflow.',
                    style: AppTextStyles.body3
                        .copyWith(color: AppColors.hintGray),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            AppContainer(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: AppColors.darkGray,
              border: BorderSide(
                  color: AppColors.info.withOpacity(0.4)),
              child: Row(
                children: [
                  const Icon(Icons.shield_moon,
                      color: AppColors.info, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Safe mode enabled: output is restricted to corrected code snippets and patch content.',
                      style: AppTextStyles.body3
                          .copyWith(color: AppColors.hintGray),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Inputs ────────────────────────────────────────────────
            _buildInputField(
              controller: _ownerController,
              label: 'Repository Owner',
              hint: 'e.g. your-github-username',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 14),
            _buildInputField(
              controller: _repoController,
              label: 'Repository Name',
              hint: 'e.g. your-repo-name',
              icon: Icons.folder_open_outlined,
            ),
            const SizedBox(height: 14),
            _buildInputField(
              controller: _taskController,
              label: 'Task for the Agent',
              hint: 'e.g. Fix failing auth refresh logic and return patch only',
              icon: Icons.code_outlined,
              maxLines: 5,
            ),

            const SizedBox(height: 20),

            // ── Loading state ─────────────────────────────────────────
            if (_isLoading)
              AppContainer(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                color: AppColors.darkGray,
                border: BorderSide(
                    color: AppColors.scanCyan.withOpacity(0.4)),
                child: Column(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: CircularProgressIndicator(
                        color: AppColors.scanCyan,
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Analyzing repository…',
                      style: AppTextStyles.body2
                          .copyWith(color: AppColors.scanCyan),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Preparing corrected code output',
                      style: AppTextStyles.body3
                          .copyWith(color: AppColors.hintGray),
                    ),
                  ],
                ),
              ),

            // ── Results ───────────────────────────────────────────────
            if (_runResult != null && !_isLoading)
              _buildResultPanel(_runResult!),
          ],
        ),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _runAgent,
        backgroundColor:
            _isLoading ? AppColors.hintGray : AppColors.scanCyan,
        icon: Icon(
            _isLoading ? Icons.hourglass_top : Icons.terminal),
        label: Text(
          _isLoading ? 'Running…' : 'Generate Code',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ── Input field ───────────────────────────────────────────────────────────
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.body2
                .copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: AppColors.hintGray),
            prefixIcon:
                Icon(icon, color: AppColors.scanCyan, size: 20),
            filled: true,
            fillColor: AppColors.darkGray,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: AppColors.scanCyan.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: AppColors.scanCyan.withOpacity(0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.scanCyan),
            ),
          ),
        ),
      ],
    );
  }

  // ── Result panel ─────────────────────────────────────────────────────────
  Widget _buildResultPanel(GithubAgentRunResult result) {
    final statusColor = _statusColor(result.status);
    final durationMs = result.duration.inMilliseconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status / metrics header
        AppContainer(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: AppColors.darkGray,
          border: BorderSide(color: statusColor.withOpacity(0.5)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_statusIcon(result.status),
                      color: statusColor, size: 22),
                  const SizedBox(width: 8),
                  Text(result.status,
                      style: AppTextStyles.h3
                          .copyWith(color: statusColor)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildMetricChip(
                      'Iterations: ${result.iterationCount}',
                      AppColors.info),
                  _buildMetricChip(
                      'Files read: ${result.visitedFiles.length}',
                      AppColors.emotional),
                  _buildMetricChip(
                      'Duration: ${durationMs}ms',
                      AppColors.warning),
                ],
              ),
              if (result.visitedFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Files read:',
                    style: AppTextStyles.body3
                        .copyWith(color: AppColors.hintGray)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: result.visitedFiles
                      .map((f) => _buildMetricChip(
                          f, AppColors.scanCyan))
                      .toList(),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Agent output
        _buildSectionHeader('Corrected Code Output',
            'Copy and apply this code manually in your repository'),
        const SizedBox(height: 10),
        _buildCodeBox(result.summary),

        // Raw payload
        if (result.rawPayload.isNotEmpty && result.status == 'ERROR') ...[
          const SizedBox(height: 16),
          _buildSectionHeader(
              'Raw API Payload', 'Full response for debugging'),
          const SizedBox(height: 10),
          _buildCodeBox(result.rawPayload),
        ],
      ],
    );
  }

  Widget _buildMetricChip(String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(value,
          style: AppTextStyles.body3.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.h3),
        const SizedBox(height: 4),
        Text(subtitle,
            style: AppTextStyles.body3
                .copyWith(color: AppColors.hintGray)),
      ],
    );
  }

  Widget _buildCodeBox(String text) {
    return AppContainer(
      width: double.infinity,
      color: AppColors.darkGray,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon:
                const Icon(Icons.copy_all, color: AppColors.scanCyan),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Copied to clipboard.')),
              );
            },
          ),
          SelectableText(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              color: AppColors.white,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
