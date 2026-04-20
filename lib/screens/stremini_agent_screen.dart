import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — exact match to home_screen.dart
//   bg: Colors.black  |  surface: #111111  |  border: #1C1C1C
//   accent: #23A6E2   |  muted: #6B7280    |  dim: #4A5568
//   success: #34C47C  |  danger: #EF4444   |  amber: #E08A23
// ─────────────────────────────────────────────────────────────────────────────
const _bg        = Colors.black;
const _surface   = Color(0xFF111111);
const _surfaceHi = Color(0xFF1A1A1A);
const _border    = Color(0xFF1C1C1C);
const _borderHi  = Color(0xFF2A2A2A);
const _accent    = Color(0xFF23A6E2);
const _accentDim = Color(0xFF0A1A28);
const _green     = Color(0xFF34C47C);
const _red       = Color(0xFFEF4444);
const _amber     = Color(0xFFE08A23);
const _txt       = Colors.white;
const _txtMuted  = Color(0xFF6B7280);
const _txtDim    = Color(0xFF4A5568);

// ── Log types ─────────────────────────────────────────────────────────────────
enum LogType { info, fileRead, thinking, success, error, code }

class AgentLogEntry {
  final LogType type;
  final String message;
  final DateTime time;
  AgentLogEntry(this.type, this.message) : time = DateTime.now();
}

class AgentRunState {
  final bool isRunning, isDone;
  final List<AgentLogEntry> logs;
  final GithubAgentRunResult? result;
  final int iteration, filesRead;

  const AgentRunState({
    this.isRunning = false, this.isDone = false,
    this.logs = const [], this.result,
    this.iteration = 0, this.filesRead = 0,
  });

  AgentRunState copyWith({
    bool? isRunning, bool? isDone, List<AgentLogEntry>? logs,
    GithubAgentRunResult? result, int? iteration, int? filesRead,
  }) => AgentRunState(
    isRunning: isRunning ?? this.isRunning, isDone: isDone ?? this.isDone,
    logs: logs ?? this.logs, result: result ?? this.result,
    iteration: iteration ?? this.iteration, filesRead: filesRead ?? this.filesRead,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class StreminiAgentScreen extends ConsumerStatefulWidget {
  const StreminiAgentScreen({super.key});
  @override
  ConsumerState<StreminiAgentScreen> createState() => _StreminiAgentScreenState();
}

class _StreminiAgentScreenState extends ConsumerState<StreminiAgentScreen>
    with TickerProviderStateMixin {

  final _ownerCtrl   = TextEditingController();
  final _repoCtrl    = TextEditingController();
  final _taskCtrl    = TextEditingController();
  final _logScroll   = ScrollController();

  AgentRunState _state = const AgentRunState();
  final List<AgentLogEntry> _logs = [];

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;
  late AnimationController _entryCtrl;
  late Animation<double>   _entryAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 460));
    _entryAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _ownerCtrl.dispose(); _repoCtrl.dispose(); _taskCtrl.dispose();
    _logScroll.dispose(); _pulseCtrl.dispose(); _entryCtrl.dispose();
    super.dispose();
  }

  // ── Logging ────────────────────────────────────────────────────────────────

  void _addLog(LogType type, String msg) {
    if (!mounted) return;
    setState(() {
      _logs.add(AgentLogEntry(type, msg));
      _state = _state.copyWith(logs: List.unmodifiable(_logs));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients)
        _logScroll.animateTo(_logScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    });
  }

  // ── Agent run ──────────────────────────────────────────────────────────────

  Future<void> _runAgent() async {
    final owner = _ownerCtrl.text.trim();
    final repo  = _repoCtrl.text.trim();
    final task  = _taskCtrl.text.trim();

    if (owner.isEmpty || repo.isEmpty || task.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: _amber, size: 15),
          SizedBox(width: 8),
          Text('Please fill in all fields',
              style: TextStyle(color: _txt, fontSize: 13)),
        ]),
        backgroundColor: _surfaceHi,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    _logs.clear();
    setState(() => _state = const AgentRunState(isRunning: true));
    _pulseCtrl.repeat(reverse: true);

    _addLog(LogType.info, 'Initializing agent for $owner/$repo');
    _addLog(LogType.info, 'Task: $task');
    _addLog(LogType.thinking, 'Fetching repository structure…');

    final api         = ref.read(apiServiceProvider);
    final startedAt   = DateTime.now();
    final visitedFiles = <String>[];
    final history     = <Map<String, dynamic>>[];
    var iteration     = 0;

    try {
      while (true) {
        final response = await api.githubAgentStep(
          repoOwner: owner, repoName: repo, task: task,
          history: history, visitedFiles: visitedFiles, iteration: iteration,
        );
        final status = response['status']?.toString() ?? 'ERROR';

        if (status == 'CONTINUE') {
          final action = response['action']?.toString() ?? 'read_file';
          iteration = response['iteration'] is int
              ? response['iteration'] as int : iteration + 1;

          if (action == 'more_files') {
            final savedFile  = response['savedFile']?.toString() ?? 'unknown';
            final nextPrompt = response['nextPrompt']?.toString() ??
                '✅ File saved: $savedFile\nNow output the next file.';
            _addLog(LogType.success, 'Saved: $savedFile');
            history.addAll([
              {'role': 'assistant', 'content': '<fix path="$savedFile">...</fix>\n<more_files />'},
              {'role': 'user', 'content': nextPrompt},
            ]);
          } else if (action == 'already_read') {
            _addLog(LogType.info,
                'Already read: ${response['nextFile'] ?? 'unknown'} (skipping)');
          } else {
            final nextFile    = response['nextFile']?.toString() ?? 'unknown';
            final fileContent = response['fileContent']?.toString() ?? '';
            _addLog(LogType.fileRead, 'Reading: $nextFile');
            history.addAll([
              {'role': 'assistant', 'content': '<read_file path="$nextFile" />'},
              {'role': 'user', 'content': 'File content of $nextFile:\n\n$fileContent'},
            ]);
            if (response['readFiles'] is List) {
              visitedFiles..clear()
                  ..addAll(List<String>.from(response['readFiles'] as List));
            } else if (!visitedFiles.contains(nextFile)) {
              visitedFiles.add(nextFile);
            }
          }
          if (!mounted) break;
          setState(() =>
              _state = _state.copyWith(iteration: iteration, filesRead: visitedFiles.length));
          continue;
        }

        // ── Terminal ─────────────────────────────────────────────────────────
        final duration = DateTime.now().difference(startedAt);
        final summary  = _extractSummary(response);

        if (status == 'COMPLETED' || status == 'FIXED') {
          _addLog(LogType.success, 'Completed in ${duration.inSeconds}s');
          final out = response['outputFiles'];
          if (out is List && out.isNotEmpty) {
            for (final f in out) {
              if (f is Map) {
                _addLog(LogType.fileRead, '📄 ${f['path']}');
                final c = f['content']?.toString() ?? '';
                if (c.isNotEmpty) _addLog(LogType.code, c);
              }
            }
          } else {
            _addLog(LogType.code, summary);
          }
        } else {
          _addLog(LogType.error, response['message']?.toString() ?? 'Unknown error');
        }

        final outputFilesList = response['outputFiles'];
        final allOutputFiles  = outputFilesList is List
            ? List<Map<String, dynamic>>.from(
                outputFilesList.map((e) => Map<String, dynamic>.from(e as Map)))
            : <Map<String, dynamic>>[];

        final result = GithubAgentRunResult(
          status: status, summary: summary,
          rawPayload: const JsonEncoder.withIndent('  ').convert(response),
          visitedFiles: List.from(visitedFiles),
          iterationCount: iteration, duration: duration,
          filePath: response['filePath']?.toString(),
          outputFiles: allOutputFiles,
        );

        if (!mounted) break;
        setState(() =>
            _state = _state.copyWith(isRunning: false, isDone: true, result: result));
        _pulseCtrl.stop();
        return;
      }
    } catch (e) {
      _addLog(LogType.error, 'Agent error: $e');
      if (mounted) setState(() => _state = _state.copyWith(isRunning: false, isDone: true));
      _pulseCtrl.stop();
    }
  }

  String _extractSummary(Map<String, dynamic> data) {
    final status = data['status'];
    if (status == 'COMPLETED') return _codeOnly(data['solution']?.toString() ?? '');
    if (status == 'FIXED') {
      final c = _codeOnly(data['fixedContent']?.toString() ?? '');
      if (c.isNotEmpty) {
        final fp = data['filePath']?.toString();
        return fp != null ? '// File: $fp\n$c' : c;
      }
      return _codeOnly(data['solution']?.toString() ?? '');
    }
    return data['message']?.toString() ?? 'Status: $status';
  }

  String _codeOnly(String input) {
    final r = RegExp(r'```(?:[a-zA-Z0-9_+-]+)?\n([\s\S]*?)```');
    final m = r.allMatches(input).toList();
    if (m.isEmpty) return input.trim();
    return m.map((x) => (x.group(1) ?? '').trim())
        .where((p) => p.isNotEmpty).join('\n\n');
  }

  void _reset() {
    _logs.clear();
    setState(() => _state = const AgentRunState());
    _entryCtrl.reset(); _entryCtrl.forward();
  }

  // ── Root build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: _state.isDone && _state.result != null
                  ? _resultView()
                  : _state.isRunning || _logs.isNotEmpty
                      ? _terminalView()
                      : _inputView(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar — pure black, home-screen style ────────────────────────────────
  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          // Back / reset button
          GestureDetector(
            onTap: () {
              if (_state.isDone || _logs.isNotEmpty) _reset();
              else Navigator.pop(context);
            },
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: Icon(
                _state.isRunning || _state.isDone
                    ? Icons.refresh_rounded
                    : Icons.arrow_back_ios_new_rounded,
                color: _txtMuted, size: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Code Architect',
                  style: TextStyle(color: _txt, fontSize: 15,
                      fontWeight: FontWeight.w800, letterSpacing: -0.2)),
              Text('Autonomous GitHub Agent',
                  style: TextStyle(color: _txtDim, fontSize: 11,
                      letterSpacing: 0.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          // Status badge
          if (_state.isRunning)
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.07 * _pulse.value),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _green.withOpacity(0.3 * _pulse.value)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(_green, _accent, _pulse.value),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('RUNNING',
                      style: TextStyle(
                        color: Color.lerp(_green, _accent, _pulse.value),
                        fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2,
                      )),
                ]),
              ),
            )
          else if (_state.isDone)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (_state.result?.status == 'ERROR' ? _red : _green)
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: (_state.result?.status == 'ERROR' ? _red : _green)
                        .withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _state.result?.status == 'ERROR' ? _red : _green,
                  ),
                ),
                const SizedBox(width: 6),
                Text(_state.result?.status ?? 'DONE',
                    style: TextStyle(
                      color: _state.result?.status == 'ERROR' ? _red : _green,
                      fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2,
                    )),
              ]),
            ),
        ],
      ),
    );
  }

  // ── Input view ─────────────────────────────────────────────────────────────
  Widget _inputView() {
    return FadeTransition(
      opacity: _entryAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          _heroBanner(),
          const SizedBox(height: 24),
          _formSection(),
          const SizedBox(height: 24),
          _runButton(),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _heroBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accent.withOpacity(0.2)),
            ),
            child: const Icon(Icons.integration_instructions_rounded,
                color: _accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI Code Agent',
                style: TextStyle(color: _txt, fontSize: 16,
                    fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const Text('Reads, reasons & fixes your code',
                style: TextStyle(color: _txtMuted, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 18),
        _capRow(Icons.account_tree_rounded, 'Autonomous repository exploration'),
        const SizedBox(height: 10),
        _capRow(Icons.memory_rounded, 'Multi-file analysis with full context'),
        const SizedBox(height: 10),
        _capRow(Icons.auto_fix_high_rounded, 'Production-ready code output'),
      ]),
    );
  }

  Widget _capRow(IconData icon, String text) => Row(children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, color: _accent, size: 13),
        ),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(color: _txtMuted, fontSize: 13)),
      ]);

  Widget _formSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('REPOSITORY'),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _textField(_ownerCtrl, 'Owner', Icons.person_outline_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _textField(_repoCtrl, 'Repository', Icons.folder_outlined)),
      ]),
      const SizedBox(height: 14),
      _sectionLabel('TASK'),
      const SizedBox(height: 10),
      _textField(_taskCtrl, 'Describe what to fix, refactor, or analyze…',
          Icons.edit_note_rounded, maxLines: 5),
    ]);
  }

  // Section label — exactly as home_screen.dart's _buildSectionLabel
  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: _txtDim, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 1.5));

  Widget _textField(TextEditingController ctrl, String hint, IconData icon,
      {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(
            color: _txt, fontSize: 14, height: 1.5, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _txtDim, fontSize: 13),
          prefixIcon: Padding(
            padding: EdgeInsets.only(
                left: 13, right: 10, top: maxLines > 1 ? 14 : 0),
            child: Icon(icon, color: _txtMuted, size: 17),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
    );
  }

  // Run button — matches the home-screen module card's accent style
  Widget _runButton() {
    return GestureDetector(
      onTap: _runAgent,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Run Agent',
                style: TextStyle(color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w700, letterSpacing: 0.1)),
          ],
        ),
      ),
    );
  }

  // ── Terminal view ──────────────────────────────────────────────────────────
  Widget _terminalView() {
    return Column(children: [
      if (_state.isRunning) _statsBar(),
      Expanded(
        child: Container(
          color: const Color(0xFF050505),
          padding: const EdgeInsets.all(14),
          child: ListView.builder(
            controller: _logScroll,
            itemCount: _logs.length + (_state.isRunning ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == _logs.length && _state.isRunning) return _cursor();
              return _logLine(_logs[i]);
            },
          ),
        ),
      ),
    ]);
  }

  Widget _statsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(children: [
        _statChip('ITER', '${_state.iteration}', _accent),
        const SizedBox(width: 10),
        _statChip('FILES', '${_state.filesRead}', _green),
        const Spacer(),
        Text('${_ownerCtrl.text}/${_repoCtrl.text}',
            style: const TextStyle(color: _txtDim, fontSize: 11,
                fontFamily: 'monospace')),
      ]),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(children: [
        Text(label, style: TextStyle(color: color.withOpacity(0.6),
            fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
        const SizedBox(width: 5),
        Text(value, style: TextStyle(color: color, fontSize: 14,
            fontWeight: FontWeight.w800, fontFamily: 'monospace')),
      ]),
    );
  }

  Widget _logLine(AgentLogEntry entry) {
    if (entry.type == LogType.code) return _codeBlock(entry.message);
    final (color, prefix) = switch (entry.type) {
      LogType.info     => (const Color(0xFF4A5568), '›'),
      LogType.fileRead => (_accent, '◆'),
      LogType.thinking => (_amber, '⟳'),
      LogType.success  => (_green, '✓'),
      LogType.error    => (_red,   '✗'),
      _                => (Colors.white24, '·'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(prefix, style: TextStyle(color: color, fontSize: 13, height: 1.6)),
        const SizedBox(width: 7),
        Expanded(child: Text(entry.message,
            style: TextStyle(
              color: color, fontSize: 12.5, height: 1.6,
              fontFamily: entry.type == LogType.fileRead ? 'monospace' : null,
              fontWeight: entry.type == LogType.success ? FontWeight.w600 : null,
            ))),
      ]),
    );
  }

  Widget _codeBlock(String code) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _green.withOpacity(0.18)),
        ),
        child: SelectableText(code,
            style: const TextStyle(color: Color(0xFF23A6E2),
                fontSize: 12, fontFamily: 'monospace', height: 1.6)),
      );

  Widget _cursor() => AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(children: [
            const Text('›', style: TextStyle(color: Colors.white24, fontSize: 13)),
            const SizedBox(width: 7),
            Container(
              width: 8, height: 14,
              decoration: BoxDecoration(
                color: _accent.withOpacity(_pulse.value),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ]),
        ),
      );

  // ── Result view ────────────────────────────────────────────────────────────
  Widget _resultView() {
    final result    = _state.result!;
    final isSuccess = result.status != 'ERROR';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _resultHeader(result, isSuccess),
        const SizedBox(height: 20),
        if (result.visitedFiles.isNotEmpty) ...[
          _sectionLabel('FILES ANALYZED (${result.visitedFiles.length})'),
          const SizedBox(height: 10),
          _fileChips(result.visitedFiles),
          const SizedBox(height: 20),
        ],
        if (isSuccess && result.outputFiles.isNotEmpty) ...[
          _sectionLabel('GENERATED / FIXED FILES'),
          const SizedBox(height: 10),
          ...result.outputFiles.map((f) {
            final path    = f['path']?.toString() ?? 'unknown';
            final content = f['content']?.toString() ?? '';
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.insert_drive_file_outlined,
                      color: _accent, size: 13),
                  const SizedBox(width: 6),
                  Text(path,
                      style: const TextStyle(color: _accent, fontSize: 12,
                          fontFamily: 'monospace')),
                ]),
              ),
              if (content.isNotEmpty) _codeOutput(content),
              const SizedBox(height: 14),
            ]);
          }),
        ] else if (result.summary.isNotEmpty && isSuccess) ...[
          _sectionLabel('GENERATED CODE'),
          const SizedBox(height: 10),
          _codeOutput(result.summary),
        ],
        if (!isSuccess) ...[
          _sectionLabel('ERROR DETAILS'),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0404),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _red.withOpacity(0.2)),
            ),
            child: SelectableText(result.summary,
                style: const TextStyle(color: Color(0xFFFF7070),
                    fontSize: 13, fontFamily: 'monospace', height: 1.6)),
          ),
        ],
        const SizedBox(height: 24),
        _runButton(),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _resultHeader(GithubAgentRunResult result, bool isSuccess) {
    final color = isSuccess ? _green : _red;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.1),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Icon(
            isSuccess ? Icons.check_rounded : Icons.error_outline_rounded,
            color: color, size: 20,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isSuccess ? 'Task Completed' : 'Task Failed',
              style: TextStyle(color: color, fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text('${result.iterationCount} iterations · '
              '${result.visitedFiles.length} files · '
              '${result.duration.inSeconds}s',
              style: const TextStyle(color: _txtMuted, fontSize: 12)),
        ])),
        // Status dot — mirrors home-screen module card style
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ]),
    );
  }

  Widget _fileChips(List<String> files) => Wrap(
        spacing: 7, runSpacing: 7,
        children: files.map((path) {
          final name = path.split('/').last;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Text(name,
                style: const TextStyle(color: _accent, fontSize: 11,
                    fontFamily: 'monospace')),
          );
        }).toList(),
      );

  Widget _codeOutput(String code) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Toolbar row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border))),
          child: Row(children: [
            Row(children: [
              _dot(const Color(0xFFFF5F57)),
              const SizedBox(width: 5),
              _dot(const Color(0xFFFFBD2E)),
              const SizedBox(width: 5),
              _dot(const Color(0xFF28C840)),
            ]),
            const Spacer(),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Row(children: [
                    Icon(Icons.check, color: _green, size: 13),
                    SizedBox(width: 6),
                    Text('Copied', style: TextStyle(color: _txt, fontSize: 13)),
                  ]),
                  backgroundColor: _surfaceHi,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ));
              },
              child: Row(children: const [
                Icon(Icons.copy_all_rounded, color: _txtMuted, size: 13),
                SizedBox(width: 4),
                Text('Copy', style: TextStyle(color: _txtMuted, fontSize: 11)),
              ]),
            ),
          ]),
        ),
        // Code
        Padding(
          padding: const EdgeInsets.all(14),
          child: SelectableText(code,
              style: const TextStyle(color: _txt, fontSize: 12.5,
                  fontFamily: 'monospace', height: 1.65)),
        ),
      ]),
    );
  }

  Widget _dot(Color color) => Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: color.withOpacity(0.8)));
}