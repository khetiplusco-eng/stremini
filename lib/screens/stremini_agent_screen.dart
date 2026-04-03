import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/app_container.dart';
import '../services/api_service.dart';

// ── Agent Log Entry ──────────────────────────────────────────────────────────
enum LogType { info, fileRead, thinking, success, error, code }

class AgentLogEntry {
  final LogType type;
  final String message;
  final DateTime time;
  AgentLogEntry(this.type, this.message) : time = DateTime.now();
}

// ── Agent Run State ──────────────────────────────────────────────────────────
class AgentRunState {
  final bool isRunning;
  final bool isDone;
  final List<AgentLogEntry> logs;
  final GithubAgentRunResult? result;
  final int iteration;
  final int filesRead;

  const AgentRunState({
    this.isRunning = false,
    this.isDone = false,
    this.logs = const [],
    this.result,
    this.iteration = 0,
    this.filesRead = 0,
  });

  AgentRunState copyWith({
    bool? isRunning,
    bool? isDone,
    List<AgentLogEntry>? logs,
    GithubAgentRunResult? result,
    int? iteration,
    int? filesRead,
  }) =>
      AgentRunState(
        isRunning: isRunning ?? this.isRunning,
        isDone: isDone ?? this.isDone,
        logs: logs ?? this.logs,
        result: result ?? this.result,
        iteration: iteration ?? this.iteration,
        filesRead: filesRead ?? this.filesRead,
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class StreminiAgentScreen extends ConsumerStatefulWidget {
  const StreminiAgentScreen({super.key});

  @override
  ConsumerState<StreminiAgentScreen> createState() =>
      _StreminiAgentScreenState();
}

class _StreminiAgentScreenState extends ConsumerState<StreminiAgentScreen>
    with TickerProviderStateMixin {
  final _ownerCtrl = TextEditingController();
  final _repoCtrl = TextEditingController();
  final _taskCtrl = TextEditingController();
  final _logScrollCtrl = ScrollController();

  AgentRunState _state = const AgentRunState();

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  // Streaming log buffer
  final List<AgentLogEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    _taskCtrl.dispose();
    _logScrollCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _addLog(LogType type, String msg) {
    final entry = AgentLogEntry(type, msg);
    if (!mounted) return;
    setState(() {
      _logs.add(entry);
      _state = _state.copyWith(logs: List.unmodifiable(_logs));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(
          _logScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _runAgent() async {
    final owner = _ownerCtrl.text.trim();
    final repo = _repoCtrl.text.trim();
    final task = _taskCtrl.text.trim();

    if (owner.isEmpty || repo.isEmpty || task.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please fill in all fields'),
          backgroundColor: const Color(0xFFFF6B35),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    _logs.clear();
    setState(() {
      _state = const AgentRunState(isRunning: true);
    });
    _pulseCtrl.repeat(reverse: true);

    _addLog(LogType.info, 'Initializing agent for $owner/$repo');
    _addLog(LogType.info, 'Task: $task');
    _addLog(LogType.thinking, 'Fetching repository structure...');

    final api = ref.read(apiServiceProvider);
    final startedAt = DateTime.now();
    final visitedFiles = <String>[];
    final history = <Map<String, dynamic>>[];
    var iteration = 0;

    try {
      while (true) {
        final response = await api.githubAgentStep(
          repoOwner: owner,
          repoName: repo,
          task: task,
          history: history,
          visitedFiles: visitedFiles,
          iteration: iteration,
        );

        final status = response['status']?.toString() ?? 'ERROR';

        if (status == 'CONTINUE') {
          final action = response['action']?.toString() ?? 'read_file';
          iteration = response['iteration'] is int
              ? response['iteration'] as int
              : iteration + 1;

          if (action == 'more_files') {
            // AI saved a file and signalled more_files — continue prompting for next file
            final savedFile = response['savedFile']?.toString() ?? 'unknown';
            final nextPrompt = response['nextPrompt']?.toString() ??
                '✅ File saved: $savedFile\nNow output the next file that needs to be fixed or created.';

            _addLog(LogType.success, 'Saved: $savedFile');

            history.addAll([
              {
                'role': 'assistant',
                'content': response['savedContent'] != null
                    ? '<fix path="$savedFile">${response['savedContent']}</fix>\n<more_files />'
                    : '<fix path="$savedFile">...</fix>\n<more_files />',
              },
              {'role': 'user', 'content': nextPrompt},
            ]);
          } else if (action == 'already_read') {
            final path = response['nextFile']?.toString() ?? 'unknown';
            _addLog(LogType.info, 'Already read: $path (skipping)');
            // Don't add to history — worker already handled it
          } else {
            // Standard read_file
            final nextFile = response['nextFile']?.toString() ?? 'unknown';
            final fileContent = response['fileContent']?.toString() ?? '';

            _addLog(LogType.fileRead, 'Reading: $nextFile');

            history.addAll([
              {'role': 'assistant', 'content': '<read_file path="$nextFile" />'},
              {
                'role': 'user',
                'content': 'File content of $nextFile:\n\n$fileContent'
              },
            ]);

            if (response['readFiles'] is List) {
              visitedFiles
                ..clear()
                ..addAll(List<String>.from(response['readFiles'] as List));
            } else if (!visitedFiles.contains(nextFile)) {
              visitedFiles.add(nextFile);
            }
          }

          if (!mounted) break;
          setState(() {
            _state = _state.copyWith(
              iteration: iteration,
              filesRead: visitedFiles.length,
            );
          });

          continue;
        }

        // Terminal
        final duration = DateTime.now().difference(startedAt);
        final summary = _extractSummary(response);

        if (status == 'COMPLETED' || status == 'FIXED') {
          _addLog(
              LogType.success, 'Agent completed in ${duration.inSeconds}s');

          // Show each output file separately in the terminal log
          final outputFilesList = response['outputFiles'];
          if (outputFilesList is List && outputFilesList.isNotEmpty) {
            for (final f in outputFilesList) {
              if (f is Map) {
                final path = f['path']?.toString() ?? '';
                final content = f['content']?.toString() ?? '';
                _addLog(LogType.fileRead, '📄 $path');
                if (content.isNotEmpty) _addLog(LogType.code, content);
              }
            }
          } else {
            _addLog(LogType.code, summary);
          }
        } else {
          _addLog(LogType.error,
              response['message']?.toString() ?? 'Unknown error');
        }

        final outputFilesList = response['outputFiles'];
        final allOutputFiles = outputFilesList is List
            ? List<Map<String, dynamic>>.from(outputFilesList
                .map((e) => Map<String, dynamic>.from(e as Map)))
            : <Map<String, dynamic>>[];

        final result = GithubAgentRunResult(
          status: status,
          summary: summary,
          rawPayload: const JsonEncoder.withIndent('  ').convert(response),
          visitedFiles: List.from(visitedFiles),
          iterationCount: iteration,
          duration: duration,
          filePath: response['filePath']?.toString(),
          outputFiles: allOutputFiles,
        );

        if (!mounted) break;
        setState(() {
          _state = _state.copyWith(
            isRunning: false,
            isDone: true,
            result: result,
          );
        });
        _pulseCtrl.stop();
        return;
      }
    } catch (e) {
      _addLog(LogType.error, 'Agent error: $e');
      if (mounted) {
        setState(() {
          _state = _state.copyWith(isRunning: false, isDone: true);
        });
      }
      _pulseCtrl.stop();
    }
  }

  String _extractSummary(Map<String, dynamic> data) {
    final status = data['status'];
    if (status == 'COMPLETED') {
      return _codeOnly(data['solution']?.toString() ?? '');
    }
    if (status == 'FIXED') {
      final content = _codeOnly(data['fixedContent']?.toString() ?? '');
      if (content.isNotEmpty) {
        final fp = data['filePath']?.toString();
        return fp != null ? '// File: $fp\n$content' : content;
      }
      return _codeOnly(data['solution']?.toString() ??
          data['patch']?.toString() ??
          data['fix']?.toString() ??
          '');
    }
    return data['message']?.toString() ?? 'Unexpected status: $status';
  }

  String _codeOnly(String input) {
    final r = RegExp(r'```(?:[a-zA-Z0-9_+-]+)?\n([\s\S]*?)```');
    final m = r.allMatches(input).toList();
    if (m.isEmpty) return input.trim();
    return m
        .map((x) => (x.group(1) ?? '').trim())
        .where((p) => p.isNotEmpty)
        .join('\n\n');
  }

  void _reset() {
    _logs.clear();
    setState(() => _state = const AgentRunState());
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0E),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _state.isDone && _state.result != null
                  ? _buildResultView()
                  : _state.isRunning || _logs.isNotEmpty
                      ? _buildTerminalView()
                      : _buildInputView(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Color(0xFF1A1F2E), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_state.isDone || _logs.isNotEmpty) {
                _reset();
              } else {
                Navigator.pop(context);
              }
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF111318),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E2535)),
              ),
              child: Icon(
                _state.isRunning || _state.isDone
                    ? Icons.refresh_rounded
                    : Icons.arrow_back_ios_new_rounded,
                color: Colors.white54,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Code Architect',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Autonomous GitHub Agent',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 11,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (_state.isRunning)
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D084).withOpacity(0.1 * _pulse.value),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF00D084)
                          .withOpacity(0.4 * _pulse.value)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.lerp(
                            const Color(0xFF00D084),
                            const Color(0xFF00AAFF),
                            _pulse.value),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'RUNNING',
                      style: TextStyle(
                        color: Color.lerp(const Color(0xFF00D084),
                            const Color(0xFF00AAFF), _pulse.value),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_state.isDone)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _state.result?.status == 'ERROR'
                    ? const Color(0xFFFF4545).withOpacity(0.1)
                    : const Color(0xFF00D084).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _state.result?.status == 'ERROR'
                        ? const Color(0xFFFF4545).withOpacity(0.4)
                        : const Color(0xFF00D084).withOpacity(0.4)),
              ),
              child: Text(
                _state.result?.status ?? 'DONE',
                style: TextStyle(
                  color: _state.result?.status == 'ERROR'
                      ? const Color(0xFFFF4545)
                      : const Color(0xFF00D084),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Input View ────────────────────────────────────────────────────────────
  Widget _buildInputView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // Hero
          _buildHero(),
          const SizedBox(height: 32),

          // Form fields
          _buildFieldLabel('REPOSITORY OWNER'),
          const SizedBox(height: 8),
          _buildTextField(
            _ownerCtrl,
            'e.g. torvalds',
            Icons.person_outline_rounded,
          ),
          const SizedBox(height: 20),

          _buildFieldLabel('REPOSITORY NAME'),
          const SizedBox(height: 8),
          _buildTextField(
            _repoCtrl,
            'e.g. linux',
            Icons.folder_outlined,
          ),
          const SizedBox(height: 20),

          _buildFieldLabel('TASK DESCRIPTION'),
          const SizedBox(height: 8),
          _buildTextField(
            _taskCtrl,
            'Describe what the agent should fix, refactor, or analyze...',
            Icons.edit_outlined,
            maxLines: 5,
          ),
          const SizedBox(height: 32),

          _buildRunButton(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0D1117),
            const Color(0xFF0A1628),
          ],
        ),
        border: Border.all(color: const Color(0xFF1E2D45), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0070F3), Color(0xFF00D9FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.integration_instructions_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Code Agent',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Reads, reasons, and fixes your code',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildCapabilityRow(
              Icons.search_rounded, 'Explores the repo tree autonomously'),
          const SizedBox(height: 10),
          _buildCapabilityRow(
              Icons.memory_rounded, 'Reads as many files as needed'),
          const SizedBox(height: 10),
          _buildCapabilityRow(
              Icons.auto_fix_high_rounded, 'Outputs corrected, copy-ready code'),
        ],
      ),
    );
  }

  Widget _buildCapabilityRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00D9FF), size: 16),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withOpacity(0.35),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2535)),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.5,
          fontFamily: 'monospace',
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.2),
            fontSize: 14,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10, top: 14),
            child: Icon(icon, color: Colors.white24, size: 18),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
    );
  }

  Widget _buildRunButton() {
    return GestureDetector(
      onTap: _runAgent,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF0070F3), Color(0xFF00AAFF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0070F3).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'Run Agent',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Terminal View ─────────────────────────────────────────────────────────
  Widget _buildTerminalView() {
    return Column(
      children: [
        // Stats bar
        if (_state.isRunning)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Color(0xFF111520), width: 1)),
            ),
            child: Row(
              children: [
                _buildStatChip(
                    'ITER', '${_state.iteration}', const Color(0xFF00AAFF)),
                const SizedBox(width: 12),
                _buildStatChip('FILES', '${_state.filesRead}',
                    const Color(0xFF00D9FF)),
                const Spacer(),
                Text(
                  '${_ownerCtrl.text}/${_repoCtrl.text}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

        // Terminal log
        Expanded(
          child: Container(
            color: const Color(0xFF060810),
            padding: const EdgeInsets.all(16),
            child: ListView.builder(
              controller: _logScrollCtrl,
              itemCount: _logs.length + (_state.isRunning ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _logs.length && _state.isRunning) {
                  return _buildCursor();
                }
                return _buildLogLine(_logs[i]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.6),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogLine(AgentLogEntry entry) {
    Color color;
    String prefix;
    TextStyle style;

    switch (entry.type) {
      case LogType.info:
        color = Colors.white38;
        prefix = '›';
        style = TextStyle(color: color, fontSize: 13, height: 1.6);
        break;
      case LogType.fileRead:
        color = const Color(0xFF00AAFF);
        prefix = '◆';
        style = TextStyle(
          color: color,
          fontSize: 13,
          height: 1.6,
          fontFamily: 'monospace',
        );
        break;
      case LogType.thinking:
        color = const Color(0xFFFFB800);
        prefix = '⟳';
        style = TextStyle(color: color, fontSize: 13, height: 1.6);
        break;
      case LogType.success:
        color = const Color(0xFF00D084);
        prefix = '✓';
        style = TextStyle(
          color: color,
          fontSize: 13,
          height: 1.6,
          fontWeight: FontWeight.w600,
        );
        break;
      case LogType.error:
        color = const Color(0xFFFF4545);
        prefix = '✗';
        style = TextStyle(color: color, fontSize: 13, height: 1.6);
        break;
      case LogType.code:
        return _buildCodeBlock(entry.message);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prefix,
            style: TextStyle(
              color: color,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(entry.message, style: style)),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(String code) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00D084).withOpacity(0.2)),
      ),
      child: SelectableText(
        code,
        style: const TextStyle(
          color: Color(0xFF79C0FF),
          fontSize: 12,
          fontFamily: 'monospace',
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildCursor() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            const Text('›', style: TextStyle(color: Colors.white24, fontSize: 13)),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF00AAFF).withOpacity(_pulse.value),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Result View ───────────────────────────────────────────────────────────
  Widget _buildResultView() {
    final result = _state.result!;
    final isSuccess = result.status != 'ERROR';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isSuccess
                  ? const Color(0xFF00D084).withOpacity(0.06)
                  : const Color(0xFFFF4545).withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSuccess
                    ? const Color(0xFF00D084).withOpacity(0.25)
                    : const Color(0xFFFF4545).withOpacity(0.25),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSuccess
                        ? const Color(0xFF00D084).withOpacity(0.15)
                        : const Color(0xFFFF4545).withOpacity(0.15),
                  ),
                  child: Icon(
                    isSuccess
                        ? Icons.check_rounded
                        : Icons.error_outline_rounded,
                    color: isSuccess
                        ? const Color(0xFF00D084)
                        : const Color(0xFFFF4545),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSuccess ? 'Task Completed' : 'Task Failed',
                        style: TextStyle(
                          color: isSuccess
                              ? const Color(0xFF00D084)
                              : const Color(0xFFFF4545),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${result.iterationCount} iterations · '
                        '${result.visitedFiles.length} files read · '
                        '${result.duration.inSeconds}s',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Files read
          if (result.visitedFiles.isNotEmpty) ...[
            _buildSectionHeader('Files Analyzed'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: result.visitedFiles
                  .map((f) => _buildFileChip(f))
                  .toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Code output
          if (isSuccess && result.outputFiles.isNotEmpty) ...[
            _buildSectionHeader(
                'Generated / Fixed Files (${result.outputFiles.length})'),
            const SizedBox(height: 10),
            ...result.outputFiles.map((f) {
              final path = f['path']?.toString() ?? 'unknown';
              final content = f['content']?.toString() ?? '';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      path,
                      style: const TextStyle(
                        color: Color(0xFF79C0FF),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  _buildCodeOutput(content),
                  const SizedBox(height: 16),
                ],
              );
            }).toList(),
          ] else if (result.summary.isNotEmpty && isSuccess) ...[
            _buildSectionHeader('Generated Code'),
            const SizedBox(height: 10),
            _buildCodeOutput(result.summary),
          ],

          // Error output
          if (!isSuccess) ...[
            _buildSectionHeader('Error Details'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF120808),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFFF4545).withOpacity(0.2)),
              ),
              child: SelectableText(
                result.summary,
                style: const TextStyle(
                  color: Color(0xFFFF7070),
                  fontSize: 13,
                  fontFamily: 'monospace',
                  height: 1.6,
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
          _buildRunButton(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withOpacity(0.3),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _buildFileChip(String path) {
    final parts = path.split('/');
    final name = parts.last;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E2535)),
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: Color(0xFF79C0FF),
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildCodeOutput(String code) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2535)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Code header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: Color(0xFF1E2535))),
            ),
            child: Row(
              children: [
                const Row(children: [
                  _TrafficDot(color: Color(0xFFFF5F57)),
                  SizedBox(width: 6),
                  _TrafficDot(color: Color(0xFFFFBD2E)),
                  SizedBox(width: 6),
                  _TrafficDot(color: Color(0xFF28C840)),
                ]),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Copied to clipboard'),
                        backgroundColor: const Color(0xFF00D084),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.copy_all_rounded,
                          color: Colors.white38, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        'Copy',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Code body
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              code,
              style: const TextStyle(
                color: Color(0xFFE6EDF3),
                fontSize: 12.5,
                fontFamily: 'monospace',
                height: 1.65,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Traffic light dot ────────────────────────────────────────────────────────
class _TrafficDot extends StatelessWidget {
  final Color color;
  const _TrafficDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.7),
        ),
      );
}
