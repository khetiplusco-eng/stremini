// smart_scheduler_screen.dart — FIXED & REDESIGNED
// FIXES:
//   1. API calls now have proper error handling with fallback offline mode
//   2. Task parsing uses correct endpoint and handles all response shapes
//   3. Notifications use zonedSchedule with correct API (no deprecated params)
//   4. SharedPreferences persistence fixed (key collision resolved)
//   5. UI completely redesigned to be clean, premium, and functional
//   6. World clock uses correct UTC offsets
//   7. Empty states properly shown

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ── Design tokens ────────────────────────────────────────────────────────────
const _bg       = Color(0xFF030507);
const _surface  = Color(0xFF0D0F14);
const _card     = Color(0xFF141720);
const _border   = Color(0xFF1C2030);
const _accent   = Color(0xFF23A6E2);
const _purple   = Color(0xFF8B5CF6);
const _green    = Color(0xFF34C47C);
const _red      = Color(0xFFEF4444);
const _amber    = Color(0xFFE08A23);
const _txt      = Colors.white;
const _muted    = Color(0xFF6B7280);
const _dim      = Color(0xFF4A5568);
const _logoPath = 'lib/img/logo.jpg';

// ── Models ───────────────────────────────────────────────────────────────────

enum TaskPriority { high, medium, low }
enum TaskCategory { work, personal, health, finance, learning, other }
enum TaskStatus   { pending, completed }

class ScheduledTask {
  final String id;
  final String title;
  final String description;
  final DateTime scheduledTime;
  final TaskCategory category;
  final TaskPriority priority;
  final int estimatedDuration;
  final String emoji;
  TaskStatus status;

  ScheduledTask({
    required this.id,
    required this.title,
    required this.description,
    required this.scheduledTime,
    required this.category,
    required this.priority,
    required this.estimatedDuration,
    required this.emoji,
    this.status = TaskStatus.pending,
  });

  factory ScheduledTask.fromJson(Map<String, dynamic> j) {
    TaskPriority parsePriority(String? s) {
      if (s == null) return TaskPriority.medium;
      if (s.toLowerCase() == 'high') return TaskPriority.high;
      if (s.toLowerCase() == 'low') return TaskPriority.low;
      return TaskPriority.medium;
    }

    TaskCategory parseCategory(String? s) {
      if (s == null) return TaskCategory.other;
      switch (s.toLowerCase()) {
        case 'work': return TaskCategory.work;
        case 'personal': return TaskCategory.personal;
        case 'health': return TaskCategory.health;
        case 'finance': return TaskCategory.finance;
        case 'learning': return TaskCategory.learning;
        default: return TaskCategory.other;
      }
    }

    DateTime parseTime(dynamic raw) {
      try {
        if (raw is String && raw.isNotEmpty) return DateTime.parse(raw).toLocal();
      } catch (_) {}
      return DateTime.now().add(const Duration(days: 1));
    }

    return ScheduledTask(
      id:                j['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title:             j['title']?.toString() ?? 'Untitled Task',
      description:       j['description']?.toString() ?? '',
      scheduledTime:     parseTime(j['scheduledTime'] ?? j['scheduled_time'] ?? j['time']),
      category:          parseCategory(j['category']?.toString()),
      priority:          parsePriority(j['priority']?.toString()),
      estimatedDuration: (j['estimatedDuration'] as num?)?.toInt() ?? 30,
      emoji:             j['emoji']?.toString() ?? '📋',
      status:            j['status']?.toString() == 'completed' ? TaskStatus.completed : TaskStatus.pending,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'description': description,
    'scheduledTime': scheduledTime.toIso8601String(),
    'category': category.name, 'priority': priority.name,
    'estimatedDuration': estimatedDuration, 'emoji': emoji,
    'status': status.name,
  };
}

// ── Persistence ───────────────────────────────────────────────────────────────

class _TaskStorage {
  static const _key = 'stremini_sched_tasks_v2';

  static Future<List<ScheduledTask>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list  = jsonDecode(raw) as List;
      return list.map((e) => ScheduledTask.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[TaskStorage] load error: $e');
      return [];
    }
  }

  static Future<void> save(List<ScheduledTask> tasks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(tasks.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('[TaskStorage] save error: $e');
    }
  }
}

// ── Notification Service ──────────────────────────────────────────────────────

class _NotifService {
  static final _NotifService _i = _NotifService._();
  factory _NotifService() => _i;
  _NotifService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: androidSettings, iOS: iosSettings),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _initialized = true;
    } catch (e) {
      debugPrint('[Notif] init error: $e');
    }
  }

  Future<void> schedule(ScheduledTask task) async {
    if (!_initialized) await init();
    try {
      final id = task.id.hashCode.abs() % 100000;
      final scheduledTz = tz.TZDateTime.from(task.scheduledTime, tz.local);
      if (scheduledTz.isBefore(tz.TZDateTime.now(tz.local))) return;
      await _plugin.zonedSchedule(
        id,
        '${task.emoji} ${task.title}',
        task.description.isNotEmpty ? task.description : 'Scheduled task reminder',
        scheduledTz,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'stremini_tasks', 'Smart Scheduler',
            channelDescription: 'Stremini task reminders',
            importance: Importance.high, priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[Notif] schedule error: $e');
    }
  }

  Future<void> cancel(ScheduledTask task) async {
    try {
      await _plugin.cancel(task.id.hashCode.abs() % 100000);
    } catch (_) {}
  }
}

// ── API Service ───────────────────────────────────────────────────────────────

class _SchedulerApi {
  static const _baseUrl = 'https://ai-keyboard-backend.vishwajeetadkine705.workers.dev';

  String? get _token => Supabase.instance.client.auth.currentSession?.accessToken;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// Parse a natural-language task description into a ScheduledTask.
  /// Returns null if the API fails — caller should handle gracefully.
  Future<ScheduledTask?> parseTask(String input) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/scheduler/parse'),
            headers: _headers,
            body: jsonEncode({'input': input}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        debugPrint('[SchedulerAPI] parse ${res.statusCode}: ${res.body}');
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      // Handle both {'task': {...}} and direct {...} shapes
      final taskJson = (data['task'] as Map<String, dynamic>?) ?? data;
      if (taskJson.isEmpty || taskJson['title'] == null) return null;

      taskJson['id'] = DateTime.now().millisecondsSinceEpoch.toString();
      return ScheduledTask.fromJson(taskJson);
    } catch (e) {
      debugPrint('[SchedulerAPI] parseTask error: $e');
      return null;
    }
  }

  Future<List<ScheduledTask>> getSuggestions(List<ScheduledTask> existing) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/scheduler/suggest'),
            headers: _headers,
            body: jsonEncode({
              'context': 'Smart task suggestions for today',
              'existingTasks': existing.map((t) => t.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return _fallback();
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['suggestions'] as List? ?? [];
      if (list.isEmpty) return _fallback();

      return list.asMap().entries.map((entry) {
        final m = Map<String, dynamic>.from(entry.value as Map);
        m['id'] = '${DateTime.now().millisecondsSinceEpoch}${entry.key}';
        return ScheduledTask.fromJson(m);
      }).toList();
    } catch (e) {
      debugPrint('[SchedulerAPI] getSuggestions error: $e');
      return _fallback();
    }
  }

  List<ScheduledTask> _fallback() {
    final now = DateTime.now();
    return [
      ScheduledTask(
        id: 'sug_${now.millisecondsSinceEpoch}_1',
        title: 'Morning deep work session',
        description: 'Focus on your most important task first',
        scheduledTime: DateTime(now.year, now.month, now.day, 9),
        category: TaskCategory.work,
        priority: TaskPriority.high,
        estimatedDuration: 90,
        emoji: '🧠',
      ),
      ScheduledTask(
        id: 'sug_${now.millisecondsSinceEpoch}_2',
        title: 'Review pending emails',
        description: 'Process inbox and respond to urgent items',
        scheduledTime: DateTime(now.year, now.month, now.day, 14),
        category: TaskCategory.work,
        priority: TaskPriority.medium,
        estimatedDuration: 30,
        emoji: '📧',
      ),
      ScheduledTask(
        id: 'sug_${now.millisecondsSinceEpoch}_3',
        title: 'Evening walk',
        description: '30-min walk for mental clarity',
        scheduledTime: DateTime(now.year, now.month, now.day, 18, 30),
        category: TaskCategory.health,
        priority: TaskPriority.low,
        estimatedDuration: 30,
        emoji: '🚶',
      ),
    ];
  }
}

// ── World clock ───────────────────────────────────────────────────────────────

String _worldTime(int utcOffset) {
  final utc   = DateTime.now().toUtc();
  final local = utc.add(Duration(hours: utcOffset));
  final h     = local.hour.toString().padLeft(2, '0');
  final m     = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// ─────────────────────────────────────────────────────────────────────────────
// SmartSchedulerScreen
// ─────────────────────────────────────────────────────────────────────────────

class SmartSchedulerScreen extends StatefulWidget {
  const SmartSchedulerScreen({super.key});

  @override
  State<SmartSchedulerScreen> createState() => _SmartSchedulerScreenState();
}

class _SmartSchedulerScreenState extends State<SmartSchedulerScreen>
    with SingleTickerProviderStateMixin {
  final _api        = _SchedulerApi();
  final _notif      = _NotifService();
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<ScheduledTask> _tasks       = [];
  List<ScheduledTask> _suggestions = [];
  bool _parsing            = false;
  bool _loadingSuggestions = false;
  bool _tasksLoaded        = false;

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _notif.init();
    _loadTasks();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadTasks() async {
    final saved = await _TaskStorage.load();
    if (mounted) setState(() { _tasks = saved; _tasksLoaded = true; });
    // Reschedule notifications for future tasks
    for (final t in saved.where((t) =>
        t.status == TaskStatus.pending && t.scheduledTime.isAfter(DateTime.now()))) {
      _notif.schedule(t);
    }
  }

  Future<void> _save() => _TaskStorage.save(_tasks);

  Future<void> _loadSuggestions() async {
    setState(() => _loadingSuggestions = true);
    final s = await _api.getSuggestions(_tasks);
    if (mounted) setState(() { _suggestions = s; _loadingSuggestions = false; });
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _parseAndAdd() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty) {
      _snack('Please describe a task first', err: true);
      return;
    }
    setState(() => _parsing = true);
    HapticFeedback.lightImpact();
    final task = await _api.parseTask(input);
    if (!mounted) return;
    setState(() => _parsing = false);
    if (task != null) {
      _inputCtrl.clear();
      _showPreview(task);
    } else {
      // Offline fallback: create a basic task manually
      _showManualCreate(input);
    }
  }

  void _confirmAdd(ScheduledTask task) {
    setState(() => _tasks.add(task));
    _save();
    _notif.schedule(task);
    _snack('Task scheduled ✓');
  }

  void _addSuggestion(ScheduledTask sug) {
    final copy = ScheduledTask(
      id:                DateTime.now().millisecondsSinceEpoch.toString(),
      title:             sug.title, description: sug.description,
      scheduledTime:     sug.scheduledTime, category: sug.category,
      priority:          sug.priority, estimatedDuration: sug.estimatedDuration,
      emoji:             sug.emoji,
    );
    setState(() { _tasks.add(copy); _suggestions.remove(sug); });
    _save();
    _notif.schedule(copy);
    HapticFeedback.lightImpact();
    _snack('Added to schedule ✓');
  }

  void _delete(ScheduledTask task) {
    setState(() => _tasks.remove(task));
    _save();
    _notif.cancel(task);
    HapticFeedback.mediumImpact();
  }

  void _markComplete(ScheduledTask task) {
    setState(() => task.status = TaskStatus.completed);
    _save();
    _notif.cancel(task);
    HapticFeedback.lightImpact();
    _snack('Task completed ✓');
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _txt, fontSize: 13)),
      backgroundColor: err ? const Color(0xFF1A0808) : const Color(0xFF0A1A28),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<ScheduledTask> get _pending =>
      _tasks.where((t) => t.status == TaskStatus.pending).toList()
        ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

  List<ScheduledTask> get _completed =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();

  double get _efficiency => _tasks.isEmpty ? 0 : _completed.length / _tasks.length;

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.high: return _red;
      case TaskPriority.low:  return _green;
      default:                return _amber;
    }
  }

  Color _categoryColor(TaskCategory c) {
    switch (c) {
      case TaskCategory.work:     return _accent;
      case TaskCategory.health:   return _green;
      case TaskCategory.finance:  return _amber;
      case TaskCategory.learning: return _purple;
      case TaskCategory.personal: return const Color(0xFFEC4899);
      default:                    return _muted;
    }
  }

  String _fmtTime(DateTime dt) {
    final h  = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m  = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  String _fmtDate(DateTime dt) {
    final now    = DateTime.now();
    final today  = DateTime(now.year, now.month, now.day);
    final day    = DateTime(dt.year, dt.month, dt.day);
    final diff   = day.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff < 0)  return 'Past';
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    if (diff < 7)  return days[dt.weekday - 1];
    return '${dt.day}/${dt.month}';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    _buildInputSection(),
                    const SizedBox(height: 24),
                    _buildUpcomingSection(),
                    const SizedBox(height: 20),
                    _buildStatsRow(),
                    const SizedBox(height: 20),
                    _buildSuggestionsSection(),
                    const SizedBox(height: 20),
                    _buildWorldClock(),
                    if (_completed.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildCompletedSection(),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _bg,
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: _txt, size: 14),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Smart Scheduler',
                  style: TextStyle(color: _txt, fontSize: 17, fontWeight: FontWeight.w800)),
              Text(
                '${_pending.length} upcoming · ${_completed.length} done',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ]),
          ),
          GestureDetector(
            onTap: _loadSuggestions,
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: _purple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: _purple.withOpacity(0.2)),
              ),
              child: _loadingSuggestions
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_purple)),
                    )
                  : const Icon(Icons.auto_awesome_rounded, color: _purple, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input Section ─────────────────────────────────────────────────────────
  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Schedule a Task',
            style: TextStyle(color: _txt, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        const Text(
          'Type naturally — "Call Alex tomorrow at 3pm" or "Team meeting Friday 10am"',
          style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.bolt_rounded, color: _accent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                style: const TextStyle(color: _txt, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Describe a task…',
                  hintStyle: TextStyle(color: _dim, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _parseAndAdd(),
              ),
            ),
            GestureDetector(
              onTap: _parsing ? null : _parseAndAdd,
              child: Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: _parsing ? _dim : _accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: _parsing
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_txt),
                        ),
                      )
                    : const Text('ADD',
                        style: TextStyle(
                          color: _txt, fontSize: 12,
                          fontWeight: FontWeight.w800, letterSpacing: 0.8,
                        )),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // Quick chip examples
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _chip('📞 Call tomorrow 3pm', '📞 Call tomorrow at 3pm'),
            const SizedBox(width: 8),
            _chip('🏋️ Gym Friday 7am', '🏋️ Gym session Friday at 7am'),
            const SizedBox(width: 8),
            _chip('📧 Review emails 9am', '📧 Review emails at 9am'),
          ]),
        ),
      ]),
    );
  }

  Widget _chip(String label, String fill) {
    return GestureDetector(
      onTap: () {
        _inputCtrl.text = fill;
        _parseAndAdd();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Text(label, style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    );
  }

  // ── Upcoming Section ──────────────────────────────────────────────────────
  Widget _buildUpcomingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(
            'UPCOMING',
            style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1.8),
          ),
          const Spacer(),
          if (_pending.isNotEmpty)
            Text(
              '${_pending.length} tasks',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
        ]),
        const SizedBox(height: 12),
        if (!_tasksLoaded)
          Container(
            height: 100,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(
              strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_accent),
            ),
          )
        else if (_pending.isEmpty)
          _emptyUpcoming()
        else
          ..._pending.take(6).map(_buildTaskCard),
      ]),
    );
  }

  Widget _emptyUpcoming() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.calendar_today_outlined, color: _accent, size: 22),
        ),
        const SizedBox(height: 14),
        const Text('No upcoming tasks', style: TextStyle(color: _txt, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Type a task above and tap ADD', style: TextStyle(color: _muted, fontSize: 13)),
      ]),
    );
  }

  Widget _buildTaskCard(ScheduledTask task) {
    final catColor = _categoryColor(task.category);
    final priColor = _priorityColor(task.priority);
    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _red.withOpacity(0.2)),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: _red, size: 20),
      ),
      onDismissed: (_) => _delete(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Left accent bar
          Container(
            width: 3,
            height: 50,
            margin: const EdgeInsets.only(right: 14),
            decoration: BoxDecoration(color: catColor, borderRadius: BorderRadius.circular(2)),
          ),
          // Emoji
          Text(task.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.title,
                  style: const TextStyle(color: _txt, fontSize: 14, fontWeight: FontWeight.w700),
                  maxLines: 2),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  width: 5, height: 5,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: priColor),
                ),
                const SizedBox(width: 5),
                Text(
                  '${_fmtDate(task.scheduledTime)} · ${_fmtTime(task.scheduledTime)}',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
                const SizedBox(width: 8),
                Text(
                  '${task.estimatedDuration}m',
                  style: const TextStyle(color: _dim, fontSize: 11),
                ),
              ]),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(task.description,
                    style: const TextStyle(color: _dim, fontSize: 11, height: 1.4),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
          // Complete button
          GestureDetector(
            onTap: () => _markComplete(task),
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: _green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: _green.withOpacity(0.2)),
              ),
              child: const Icon(Icons.check_rounded, color: _green, size: 15),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Stats Row ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final pct = (_efficiency * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Expanded(child: _statCard('${_tasks.length}', 'TOTAL', _accent)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('${_pending.length}', 'PENDING', _amber)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('${_completed.length}', 'DONE', _green)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('$pct%', 'RATE', _purple)),
      ]),
    );
  }

  Widget _statCard(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(color: color.withOpacity(0.5), fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 1.0)),
      ]),
    );
  }

  // ── Suggestions ────────────────────────────────────────────────────────────
  Widget _buildSuggestionsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('AI SUGGESTIONS',
              style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1.8)),
          const Spacer(),
          GestureDetector(
            onTap: _loadSuggestions,
            child: Text('Refresh',
                style: TextStyle(color: _accent.withOpacity(0.7), fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: _loadingSuggestions
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_purple),
                    ),
                  ),
                )
              : Column(
                  children: _suggestions.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text('Tap Refresh to load suggestions',
                                style: const TextStyle(color: _muted, fontSize: 13)),
                          )
                        ]
                      : _suggestions.asMap().entries.map((e) {
                          final isLast = e.key == _suggestions.length - 1;
                          return _buildSuggestionRow(e.value, isLast);
                        }).toList(),
                ),
        ),
      ]),
    );
  }

  Widget _buildSuggestionRow(ScheduledTask task, bool isLast) {
    final catColor = _categoryColor(task.category);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: catColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(task.emoji, style: const TextStyle(fontSize: 19))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.title,
                  style: const TextStyle(color: _txt, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                '${_fmtDate(task.scheduledTime)} · ${_fmtTime(task.scheduledTime)}',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ]),
          ),
          GestureDetector(
            onTap: () => _addSuggestion(task),
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: catColor.withOpacity(0.2)),
              ),
              child: Icon(Icons.add_rounded, color: catColor, size: 16),
            ),
          ),
        ]),
      ),
      if (!isLast)
        Divider(height: 1, color: Colors.white.withOpacity(0.04), indent: 16, endIndent: 16),
    ]);
  }

  // ── World Clock ────────────────────────────────────────────────────────────
  Widget _buildWorldClock() {
    final cities = [
      ('London', 0, '🇬🇧'),
      ('New York', -5, '🇺🇸'),
      ('Tokyo', 9, '🇯🇵'),
      ('Dubai', 4, '🇦🇪'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('WORLD CLOCK',
              style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1.8)),
          const SizedBox(height: 14),
          ...cities.asMap().entries.map((e) {
            final isLast = e.key == cities.length - 1;
            final city   = e.value;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Row(children: [
                Text(city.$3, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Text(city.$1, style: const TextStyle(color: _txt, fontSize: 14)),
                const Spacer(),
                Text(
                  _worldTime(city.$2),
                  style: const TextStyle(
                    color: _txt, fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    letterSpacing: 1.0,
                  ),
                ),
              ]),
            );
          }),
        ]),
      ),
    );
  }

  // ── Completed Section ──────────────────────────────────────────────────────
  Widget _buildCompletedSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('COMPLETED',
            style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1.8)),
        const SizedBox(height: 12),
        ..._completed.take(3).map((task) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
          ),
          child: Row(children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _green.withOpacity(0.1),
                border: Border.all(color: _green.withOpacity(0.3)),
              ),
              child: const Icon(Icons.check, color: _green, size: 12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(task.title,
                  style: TextStyle(
                    color: _txt.withOpacity(0.4),
                    fontSize: 13,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: _muted,
                  )),
            ),
            Text(task.emoji, style: const TextStyle(fontSize: 14)),
          ]),
        )),
      ]),
    );
  }

  // ── Task Preview Sheet ─────────────────────────────────────────────────────
  void _showPreview(ScheduledTask task) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _TaskPreviewSheet(task: task, onConfirm: _confirmAdd),
    );
  }

  void _showManualCreate(String title) {
    // Offline fallback: create task scheduled for tomorrow at 9am
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final task = ScheduledTask(
      id:                DateTime.now().millisecondsSinceEpoch.toString(),
      title:             title,
      description:       'Manually created task',
      scheduledTime:     DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9),
      category:          TaskCategory.other,
      priority:          TaskPriority.medium,
      estimatedDuration: 30,
      emoji:             '📋',
    );
    _snack('AI unavailable — created basic task');
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _TaskPreviewSheet(task: task, onConfirm: _confirmAdd),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Task Preview Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TaskPreviewSheet extends StatelessWidget {
  final ScheduledTask task;
  final void Function(ScheduledTask) onConfirm;

  const _TaskPreviewSheet({required this.task, required this.onConfirm});

  String _fmtDt(DateTime dt) {
    final now  = DateTime.now();
    final h    = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m    = dt.minute.toString().padLeft(2, '0');
    final ap   = dt.hour >= 12 ? 'PM' : 'AM';
    final t    = '$h:$m $ap';
    final diff = DateTime(dt.year, dt.month, dt.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (diff == 0) return 'Today $t';
    if (diff == 1) return 'Tomorrow $t';
    return '${dt.day}/${dt.month} $t';
  }

  Color _priColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.high: return _red;
      case TaskPriority.low:  return _green;
      default:                return _amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20, right: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accent.withOpacity(0.15)),
            ),
            child: Center(child: Text(task.emoji, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('AI PARSED YOUR TASK',
                  style: TextStyle(color: _accent, fontSize: 9,
                      fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              const SizedBox(height: 3),
              Text(task.title,
                  style: const TextStyle(color: _txt, fontSize: 17, fontWeight: FontWeight.w800),
                  maxLines: 2),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip(Icons.access_time_rounded, _fmtDt(task.scheduledTime), _accent),
          _chip(Icons.timer_outlined, '${task.estimatedDuration}m', _muted),
          _chip(Icons.flag_outlined, task.priority.name.toUpperCase(), _priColor(task.priority)),
          _chip(Icons.category_outlined, task.category.name, _purple),
        ]),
        if (task.description.isNotEmpty && task.description != 'Manually created task') ...[
          const SizedBox(height: 14),
          Text(task.description,
              style: const TextStyle(color: _muted, fontSize: 13, height: 1.5)),
        ],
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Center(child: Text('Cancel',
                    style: TextStyle(color: _muted, fontSize: 14, fontWeight: FontWeight.w600))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () { Navigator.pop(context); onConfirm(task); },
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_rounded, color: _txt, size: 18),
                  SizedBox(width: 6),
                  Text('Schedule Task',
                      style: TextStyle(color: _txt, fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
