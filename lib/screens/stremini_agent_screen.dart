// stremini_agent_screen.dart — EXACT MATCH TO SCREENSHOT
// Design: Black bg, teal accent, GitHub Architect hero card, form fields, Run Agent button, bottom nav
// ALL LOGIC PRESERVED

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';
import '../services/api_service.dart';

// ── Design tokens — teal from screenshot ─────────────────────────────────────
const _bg        = Color(0xFF000000);
const _surface   = Color(0xFF0D0D0D);
const _card      = Color(0xFF111111);
const _cardHi    = Color(0xFF161616);
const _border    = Color(0xFF1C1C1C);
const _borderHi  = Color(0xFF242424);

// Teal — exact from screenshot
const _teal      = Color(0xFF0AFFE0);
const _tealDim   = Color(0xFF071A18);
const _tealMid   = Color(0xFF0AC8B4);

const _green     = Color(0xFF34C47C);
const _red       = Color(0xFFEF4444);
const _amber     = Color(0xFFE08A23);
const _txt       = Color(0xFFFFFFFF);
const _txtMuted  = Color(0xFF8C8C8C);
const _txtDim    = Color(0xFF404040);

const _separator = Color(0xFF1A1A1A);

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
  AgentRunState copyWith({bool? isRunning, bool? isDone, List<AgentLogEntry>? logs,
    GithubAgentRunResult? result, int? iteration, int? filesRead}) => AgentRunState(
    isRunning: isRunning ?? this.isRunning, isDone: isDone ?? this.isDone,
    logs: logs ?? this.logs, result: result ?? this.result,
    iteration: iteration ?? this.iteration, filesRead: filesRead ?? this.filesRead,
  );
}

TextStyle _t(double size, {Color color = _txt, FontWeight w = FontWeight.w400, double spacing = 0, double h = 1.4}) =>
    GoogleFonts.dmSans(fontSize: size, color: color, fontWeight: w, letterSpacing: spacing, height: h);

class StreminiAgentScreen extends ConsumerStatefulWidget {
  const StreminiAgentScreen({super.key});
  @override
  ConsumerState<StreminiAgentScreen> createState() => _StreminiAgentScreenState();
}

class _StreminiAgentScreenState extends ConsumerState<StreminiAgentScreen>
    with TickerProviderStateMixin {

  final _ownerCtrl = TextEditingController();
  final _repoCtrl  = TextEditingController();
  final _taskCtrl  = TextEditingController();
  final _logScroll = ScrollController();

  AgentRunState _state = const AgentRunState();
  final List<AgentLogEntry> _logs = [];

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;
  late AnimationController _entryCtrl;
  late Animation<double>   _entryAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _pulse = Tween(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
    _entryAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _ownerCtrl.dispose(); _repoCtrl.dispose(); _taskCtrl.dispose();
    _logScroll.dispose(); _pulseCtrl.dispose(); _entryCtrl.dispose();
    super.dispose();
  }

  void _addLog(LogType type, String msg) {
    if (!mounted) return;
    setState(() { _logs.add(AgentLogEntry(type, msg)); _state = _state.copyWith(logs: List.unmodifiable(_logs)); });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) _logScroll.animateTo(_logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    });
  }

  Future<void> _runAgent() async {
    final owner = _ownerCtrl.text.trim();
    final repo  = _repoCtrl.text.trim();
    final task  = _taskCtrl.text.trim();

    if (owner.isEmpty || repo.isEmpty || task.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: _amber, size: 15),
          const SizedBox(width: 8),
          Text('Please fill in all fields', style: _t(13)),
        ]),
        backgroundColor: _card,
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

    final api = ref.read(apiServiceProvider);
    final startedAt = DateTime.now();
    final visitedFiles = <String>[];
    final history = <Map<String, dynamic>>[];
    var iteration = 0;

    try {
      while (true) {
        final response = await api.githubAgentStep(
          repoOwner: owner, repoName: repo, task: task,
          history: history, visitedFiles: visitedFiles, iteration: iteration,
        );
        final status = response['status']?.toString() ?? 'ERROR';

        if (status == 'CONTINUE') {
          final action = response['action']?.toString() ?? 'read_file';
          iteration = response['iteration'] is int ? response['iteration'] as int : iteration + 1;

          if (action == 'more_files') {
            final savedFile = response['savedFile']?.toString() ?? 'unknown';
            final nextPrompt = response['nextPrompt']?.toString() ?? '✅ File saved: $savedFile\nNow output the next file.';
            _addLog(LogType.success, 'Saved: $savedFile');
            history.addAll([
              {'role': 'assistant', 'content': '<fix path="$savedFile">...</fix>\n<more_files />'},
              {'role': 'user', 'content': nextPrompt},
            ]);
          } else if (action == 'already_read') {
            _addLog(LogType.info, 'Already read: ${response['nextFile'] ?? 'unknown'} (skipping)');
          } else {
            final nextFile = response['nextFile']?.toString() ?? 'unknown';
            final fileContent = response['fileContent']?.toString() ?? '';
            _addLog(LogType.fileRead, 'Reading: $nextFile');
            history.addAll([
              {'role': 'assistant', 'content': '<read_file path="$nextFile" />'},
              {'role': 'user', 'content': 'File content of $nextFile:\n\n$fileContent'},
            ]);
            if (response['readFiles'] is List) {
              visitedFiles..clear()..addAll(List<String>.from(response['readFiles'] as List));
            } else if (!visitedFiles.contains(nextFile)) { visitedFiles.add(nextFile); }
          }
          if (!mounted) break;
          setState(() => _state = _state.copyWith(iteration: iteration, filesRead: visitedFiles.length));
          continue;
        }

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
          } else { _addLog(LogType.code, summary); }
        } else { _addLog(LogType.error, response['message']?.toString() ?? 'Unknown error'); }

        final outputFilesList = response['outputFiles'];
        final allOutputFiles = outputFilesList is List
            ? List<Map<String, dynamic>>.from(outputFilesList.map((e) => Map<String, dynamic>.from(e as Map)))
            : <Map<String, dynamic>>[];

        final result = GithubAgentRunResult(
          status: status, summary: summary,
          rawPayload: const JsonEncoder.withIndent('  ').convert(response),
          visitedFiles: List.from(visitedFiles), iterationCount: iteration,
          duration: duration, filePath: response['filePath']?.toString(),
          outputFiles: allOutputFiles,
        );

        if (!mounted) break;
        setState(() => _state = _state.copyWith(isRunning: false, isDone: true, result: result));
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
      if (c.isNotEmpty) { final fp = data['filePath']?.toString(); return fp != null ? '// File: $fp\n$c' : c; }
      return _codeOnly(data['solution']?.toString() ?? '');
    }
    return data['message']?.toString() ?? 'Status: $status';
  }

  String _codeOnly(String input) {
    final r = RegExp(r'```(?:[a-zA-Z0-9_+-]+)?\n([\s\S]*?)```');
    final m = r.allMatches(input).toList();
    if (m.isEmpty) return input.trim();
    return m.map((x) => (x.group(1) ?? '').trim()).where((p) => p.isNotEmpty).join('\n\n');
  }

  void _reset() {
    _logs.clear();
    setState(() => _state = const AgentRunState());
    _entryCtrl.reset(); _entryCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          Expanded(child: _state.isDone && _state.result != null
              ? _resultView()
              : _state.isRunning || _logs.isNotEmpty
                  ? _terminalView()
                  : _inputView()),
          _bottomNav(context),
        ]),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(bottom: BorderSide(color: _border, width: 0.5)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () { if (_state.isDone || _logs.isNotEmpty) _reset(); else Navigator.pop(context); },
          child: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
            child: Icon(_state.isRunning || _state.isDone ? Icons.refresh_rounded : Icons.menu_rounded, color: _txtMuted, size: 17),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('STREMINI AI', style: _t(16, w: FontWeight.w800, spacing: 1.0)),
          Text('AGENT', style: _t(10, color: _txtMuted, spacing: 2.0)),
        ])),
        if (_state.isRunning) AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _teal.withOpacity(0.07 * _pulse.value),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _teal.withOpacity(0.3 * _pulse.value)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: Color.lerp(_teal, _green, _pulse.value))),
              const SizedBox(width: 6),
              Text('RUNNING', style: _t(9, color: Color.lerp(_teal, _green, _pulse.value)!, w: FontWeight.w800, spacing: 1.2)),
            ]),
          ),
        ) else if (_state.isDone) Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: (_state.result?.status == 'ERROR' ? _red : _green).withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (_state.result?.status == 'ERROR' ? _red : _green).withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: _state.result?.status == 'ERROR' ? _red : _green)),
            const SizedBox(width: 6),
            Text(_state.result?.status ?? 'DONE', style: _t(9, color: _state.result?.status == 'ERROR' ? _red : _green, w: FontWeight.w800, spacing: 1.2)),
          ]),
        ),
      ]),
    );
  }

  // ── Input view — matches screenshot exactly ────────────────────────────────
  Widget _inputView() {
    return FadeTransition(
      opacity: _entryAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          // GitHub Architect card — exact from screenshot
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _teal.withOpacity(0.2)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: _tealDim, borderRadius: BorderRadius.circular(12), border: Border.all(color: _teal.withOpacity(0.3))),
                child: Icon(Icons.code_rounded, color: _teal, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('GitHub Architect', style: _t(17, w: FontWeight.w700, spacing: -0.3)),
                const SizedBox(height: 6),
                Text('The agent autonomously reads your repo, synthesizes fixes, and pushes code updates.',
                    style: _t(13, color: _txtMuted, h: 1.5)),
              ])),
            ]),
          ),
          const SizedBox(height: 28),

          // Repository Owner
          _fieldLabel('REPOSITORY OWNER'),
          const SizedBox(height: 10),
          _textField(_ownerCtrl, 'e.g. username', Icons.person_outline_rounded),
          const SizedBox(height: 18),

          // Repository Name
          _fieldLabel('REPOSITORY NAME'),
          const SizedBox(height: 10),
          _textField(_repoCtrl, 'e.g. project-repo', Icons.folder_outlined),
          const SizedBox(height: 18),

          // Task Description
          _fieldLabel('TASK DESCRIPTION'),
          const SizedBox(height: 10),
          _textField(_taskCtrl, 'e.g. Fix the API loop in the login module...', Icons.edit_note_rounded, maxLines: 5),
          const SizedBox(height: 32),

          // Run Agent button — exact from screenshot: teal/cyan background
          _runButton(),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(text, style: _t(11, color: _txtDim, w: FontWeight.w700, spacing: 2.0));

  Widget _textField(TextEditingController ctrl, String hint, IconData icon, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: _t(14, h: 1.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: _t(14, color: _txtDim),
          prefixIcon: Padding(
            padding: EdgeInsets.only(left: 14, right: 10, top: maxLines > 1 ? 14 : 0),
            child: Icon(icon, color: _txtMuted, size: 18),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 46),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
    );
  }

  // Run Agent button — teal background exactly matching screenshot
  Widget _runButton() {
    return GestureDetector(
      onTap: _runAgent,
      child: Container(
        width: double.infinity, height: 56,
        decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('>_', style: _t(18, color: Colors.black, w: FontWeight.w800, spacing: -1.0)),
          const SizedBox(width: 10),
          Text('Run Agent', style: _t(16, color: Colors.black, w: FontWeight.w700)),
        ]),
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
      decoration: const BoxDecoration(color: _card, border: Border(bottom: BorderSide(color: _border))),
      child: Row(children: [
        _statChip('ITER', '${_state.iteration}', _teal),
        const SizedBox(width: 10),
        _statChip('FILES', '${_state.filesRead}', _green),
        const Spacer(),
        Text('${_ownerCtrl.text}/${_repoCtrl.text}', style: _t(11, color: _txtDim)),
      ]),
    );
  }

  Widget _statChip(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.18))),
    child: Row(children: [
      Text(label, style: _t(9, color: color.withOpacity(0.6), w: FontWeight.w700, spacing: 1.0)),
      const SizedBox(width: 5),
      Text(value, style: _t(14, color: color, w: FontWeight.w800)),
    ]),
  );

  Widget _logLine(AgentLogEntry entry) {
    if (entry.type == LogType.code) return _codeBlock(entry.message);
    final (color, prefix) = switch (entry.type) {
      LogType.info => (const Color(0xFF4A5568), '›'),
      LogType.fileRead => (_teal, '◆'),
      LogType.thinking => (_amber, '⟳'),
      LogType.success  => (_green, '✓'),
      LogType.error    => (_red, '✗'),
      _ => (Colors.white24, '·'),
    };
    return Padding(padding: const EdgeInsets.only(bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(prefix, style: TextStyle(color: color, fontSize: 13, height: 1.6)),
        const SizedBox(width: 7),
        Expanded(child: Text(entry.message, style: TextStyle(color: color, fontSize: 12.5, height: 1.6,
          fontFamily: entry.type == LogType.fileRead ? 'monospace' : null,
          fontWeight: entry.type == LogType.success ? FontWeight.w600 : null,
        ))),
      ]),
    );
  }

  Widget _codeBlock(String code) => Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10), border: Border.all(color: _green.withOpacity(0.18))),
    child: SelectableText(code, style: const TextStyle(color: Color(0xFF0AFFE0), fontSize: 12, fontFamily: 'monospace', height: 1.6)),
  );

  Widget _cursor() => AnimatedBuilder(
    animation: _pulse,
    builder: (_, __) => Padding(padding: const EdgeInsets.only(top: 3),
      child: Row(children: [
        const Text('›', style: TextStyle(color: Colors.white24, fontSize: 13)),
        const SizedBox(width: 7),
        Container(width: 8, height: 14, decoration: BoxDecoration(color: _teal.withOpacity(_pulse.value), borderRadius: BorderRadius.circular(2))),
      ]),
    ),
  );

  // ── Result view ────────────────────────────────────────────────────────────
  Widget _resultView() {
    final result = _state.result!;
    final isSuccess = result.status != 'ERROR';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _resultHeader(result, isSuccess),
        const SizedBox(height: 20),
        if (result.visitedFiles.isNotEmpty) ...[
          _fieldLabel('FILES ANALYZED (${result.visitedFiles.length})'),
          const SizedBox(height: 10),
          _fileChips(result.visitedFiles),
          const SizedBox(height: 20),
        ],
        if (isSuccess && result.outputFiles.isNotEmpty) ...[
          _fieldLabel('GENERATED / FIXED FILES'),
          const SizedBox(height: 10),
          ...result.outputFiles.map((f) {
            final path = f['path']?.toString() ?? 'unknown';
            final content = f['content']?.toString() ?? '';
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.insert_drive_file_outlined, color: _teal, size: 13),
                  const SizedBox(width: 6),
                  Text(path, style: _t(12, color: _teal)),
                ]),
              ),
              if (content.isNotEmpty) _codeOutput(content),
              const SizedBox(height: 14),
            ]);
          }),
        ] else if (result.summary.isNotEmpty && isSuccess) ...[
          _fieldLabel('GENERATED CODE'),
          const SizedBox(height: 10),
          _codeOutput(result.summary),
        ],
        if (!isSuccess) ...[
          _fieldLabel('ERROR DETAILS'),
          const SizedBox(height: 10),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF0A0404), borderRadius: BorderRadius.circular(12), border: Border.all(color: _red.withOpacity(0.2))),
            child: SelectableText(result.summary, style: const TextStyle(color: Color(0xFFFF7070), fontSize: 13, fontFamily: 'monospace', height: 1.6)),
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
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.2))),
      child: Row(children: [
        Container(width: 42, height: 42,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.1), border: Border.all(color: color.withOpacity(0.2))),
          child: Icon(isSuccess ? Icons.check_rounded : Icons.error_outline_rounded, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isSuccess ? 'Task Completed' : 'Task Failed', style: _t(15, color: color, w: FontWeight.w700)),
          const SizedBox(height: 3),
          Text('${result.iterationCount} iterations · ${result.visitedFiles.length} files · ${result.duration.inSeconds}s', style: _t(12, color: _txtMuted)),
        ])),
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      ]),
    );
  }

  Widget _fileChips(List<String> files) => Wrap(
    spacing: 7, runSpacing: 7,
    children: files.map((path) {
      final name = path.split('/').last;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
        child: Text(name, style: _t(11, color: _teal)),
      );
    }).toList(),
  );

  Widget _codeOutput(String code) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
          child: Row(children: [
            Row(children: [_dot(const Color(0xFFFF5F57)), const SizedBox(width: 5), _dot(const Color(0xFFFFBD2E)), const SizedBox(width: 5), _dot(const Color(0xFF28C840))]),
            const Spacer(),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Row(children: [const Icon(Icons.check, color: _green, size: 13), const SizedBox(width: 6), Text('Copied', style: _t(13))]),
                  backgroundColor: _card, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              },
              child: Row(children: const [Icon(Icons.copy_all_rounded, color: _txtMuted, size: 13), SizedBox(width: 4), Text('Copy', style: TextStyle(color: _txtMuted, fontSize: 11))]),
            ),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(14),
          child: SelectableText(code, style: const TextStyle(color: _txt, fontSize: 12.5, fontFamily: 'monospace', height: 1.65)),
        ),
      ]),
    );
  }

  Widget _dot(Color color) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.8)),
  );

  // ── Bottom nav — matches screenshot exactly ────────────────────────────────
  Widget _bottomNav(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 12, top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(top: BorderSide(color: _border, width: 0.5)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _navBtn(icon: Icons.home_outlined, onTap: () => Navigator.pop(context)),
        _navBtn(icon: Icons.code_rounded, active: true, onTap: () {}),
        _navBtn(icon: Icons.chat_bubble_outline_rounded, onTap: () {}),
        _navBtn(icon: Icons.settings_outlined, onTap: () {}),
      ]),
    );
  }

  Widget _navBtn({required IconData icon, VoidCallback? onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? _teal : _txtDim, size: 22),
          if (active) ...[
            const SizedBox(height: 4),
            Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: _teal)),
          ],
        ]),
      ),
    );
  }
}
