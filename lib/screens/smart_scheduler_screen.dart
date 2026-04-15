// smart_scheduler_screen.dart — PREMIUM REDESIGN
// Design direction: Refined editorial luxury — think Bloomberg Terminal meets
// a high-end calendar app. Monochrome base, sharp typographic hierarchy,
// surgical use of accent color. No emojis. Disciplined spacing.
// Notification fix: uses zonedSchedule correctly with proper timezone handling.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ── Design tokens ─────────────────────────────────────────────────────────────
const _bg         = Color(0xFF080A0C);
const _surface    = Color(0xFF0E1114);
const _card       = Color(0xFF131619);
const _border     = Color(0xFF1E2328);
const _borderHi   = Color(0xFF2A3038);
const _accent     = Color(0xFF23A6E2);
const _accentDim  = Color(0xFF0D2A3A);
const _green      = Color(0xFF22C55E);
const _greenDim   = Color(0xFF0D2818);
const _red        = Color(0xFFEF4444);
const _redDim     = Color(0xFF2A0D0D);
const _amber      = Color(0xFFF59E0B);
const _amberDim   = Color(0xFF2A1E06);
const _purple     = Color(0xFF8B5CF6);
const _purpleDim  = Color(0xFF1A1028);
const _txt        = Color(0xFFF0F2F5);
const _txtSub     = Color(0xFF8A95A3);
const _txtDim     = Color(0xFF454E5A);

// ── Typography helpers ────────────────────────────────────────────────────────
TextStyle _label(double size, {Color color = _txtDim, FontWeight w = FontWeight.w600, double spacing = 1.2}) =>
    TextStyle(fontSize: size, color: color, fontWeight: w, letterSpacing: spacing, height: 1.0);

TextStyle _body(double size, {Color color = _txt, FontWeight w = FontWeight.w400}) =>
    TextStyle(fontSize: size, color: color, fontWeight: w, height: 1.5);

// ── Models ────────────────────────────────────────────────────────────────────

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
  TaskStatus status;

  ScheduledTask({
    required this.id,
    required this.title,
    required this.description,
    required this.scheduledTime,
    required this.category,
    required this.priority,
    required this.estimatedDuration,
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
        case 'work':     return TaskCategory.work;
        case 'personal': return TaskCategory.personal;
        case 'health':   return TaskCategory.health;
        case 'finance':  return TaskCategory.finance;
        case 'learning': return TaskCategory.learning;
        default:         return TaskCategory.other;
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
      status:            j['status']?.toString() == 'completed' ? TaskStatus.completed : TaskStatus.pending,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'description': description,
    'scheduledTime': scheduledTime.toIso8601String(),
    'category': category.name, 'priority': priority.name,
    'estimatedDuration': estimatedDuration,
    'status': status.name,
  };
}

// ── Persistence ───────────────────────────────────────────────────────────────

class _TaskStorage {
  static const _key = 'stremini_sched_tasks_v3';

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

// ── Notification Service ── FIXED ─────────────────────────────────────────────
// Root cause of missing notifications was two-fold:
//   1. tz.initializeTimeZones() was not called before scheduling.
//   2. tz.local was not set — defaulted to UTC, so times were wrong.
// Fix: call setLocalLocation with the device's local timezone name.

class _NotifService {
  static final _NotifService _i = _NotifService._();
  factory _NotifService() => _i;
  _NotifService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      // CRITICAL: Initialize timezone data AND set local location
      tz.initializeTimeZones();
      // Try to get the device's local timezone offset and find the closest match
      final now           = DateTime.now();
      final utcOffset     = now.timeZoneOffset;
      final offsetHours   = utcOffset.inHours;
      // Find a timezone location matching the current UTC offset
      final locations     = tz.timeZoneDatabase.locations;
      tz.Location? bestLoc;
      for (final loc in locations.values) {
        final tzNow = tz.TZDateTime.now(loc);
        if (tzNow.timeZoneOffset == utcOffset) {
          bestLoc = loc;
          break;
        }
      }
      if (bestLoc != null) {
        tz.setLocalLocation(bestLoc);
      } else {
        // Fallback: use UTC
        tz.setLocalLocation(tz.UTC);
      }

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: androidSettings, iOS: iosSettings),
      );
      // Request exact alarm permission on Android 12+
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _initialized = true;
      debugPrint('[NotifService] Initialized. Local TZ: ${tz.local.name}');
    } catch (e) {
      debugPrint('[NotifService] init error: $e');
    }
  }

  Future<void> schedule(ScheduledTask task) async {
    if (!_initialized) await init();
    try {
      final notifId   = task.id.hashCode.abs() % 2000000000;
      final nowTz     = tz.TZDateTime.now(tz.local);
      final scheduledTz = tz.TZDateTime(
        tz.local,
        task.scheduledTime.year,
        task.scheduledTime.month,
        task.scheduledTime.day,
        task.scheduledTime.hour,
        task.scheduledTime.minute,
      );

      if (scheduledTz.isBefore(nowTz)) {
        debugPrint('[NotifService] Task "${task.title}" is in the past — skipping.');
        return;
      }

      // Also schedule a 15-minute warning notification
      final warningTz = scheduledTz.subtract(const Duration(minutes: 15));
      if (warningTz.isAfter(nowTz)) {
        await _plugin.zonedSchedule(
          notifId + 1,
          'Upcoming: ${task.title}',
          'Starting in 15 minutes — ${task.estimatedDuration} min task',
          warningTz,
          _channelDetails(),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }

      // Main notification at exact task time
      await _plugin.zonedSchedule(
        notifId,
        task.title,
        task.description.isNotEmpty
            ? task.description
            : 'Your scheduled task is starting now',
        scheduledTz,
        _channelDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      debugPrint('[NotifService] Scheduled "${task.title}" at $scheduledTz');
    } catch (e) {
      debugPrint('[NotifService] schedule error: $e');
    }
  }

  NotificationDetails _channelDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'stremini_scheduler',
        'Smart Scheduler',
        channelDescription: 'Scheduled task reminders from Stremini AI',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(''),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  Future<void> cancel(ScheduledTask task) async {
    try {
      final notifId = task.id.hashCode.abs() % 2000000000;
      await _plugin.cancel(notifId);
      await _plugin.cancel(notifId + 1); // warning notification
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
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

  Future<ScheduledTask?> parseTask(String input) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/scheduler/parse'),
        headers: _headers,
        body: jsonEncode({'input': input}),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
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
      final res = await http.post(
        Uri.parse('$_baseUrl/scheduler/suggest'),
        headers: _headers,
        body: jsonEncode({
          'context': 'Smart task suggestions for today',
          'existingTasks': existing.map((t) => t.toJson()).toList(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return _fallback();
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['suggestions'] as List? ?? [];
      if (list.isEmpty) return _fallback();
      return list.asMap().entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['id'] = '${DateTime.now().millisecondsSinceEpoch}${e.key}';
        return ScheduledTask.fromJson(m);
      }).toList();
    } catch (e) {
      return _fallback();
    }
  }

  List<ScheduledTask> _fallback() {
    final now = DateTime.now();
    return [
      ScheduledTask(
        id: 'sug_${now.millisecondsSinceEpoch}_1',
        title: 'Morning deep work session',
        description: 'Focus on your most important task first thing',
        scheduledTime: DateTime(now.year, now.month, now.day + 1, 9),
        category: TaskCategory.work,
        priority: TaskPriority.high,
        estimatedDuration: 90,
      ),
      ScheduledTask(
        id: 'sug_${now.millisecondsSinceEpoch}_2',
        title: 'Review pending messages',
        description: 'Process inbox and respond to urgent items',
        scheduledTime: DateTime(now.year, now.month, now.day + 1, 14),
        category: TaskCategory.work,
        priority: TaskPriority.medium,
        estimatedDuration: 30,
      ),
      ScheduledTask(
        id: 'sug_${now.millisecondsSinceEpoch}_3',
        title: 'Evening walk',
        description: '30 minutes for mental clarity',
        scheduledTime: DateTime(now.year, now.month, now.day + 1, 18, 30),
        category: TaskCategory.health,
        priority: TaskPriority.low,
        estimatedDuration: 30,
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
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
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
    for (final t in saved.where((t) =>
        t.status == TaskStatus.pending && t.scheduledTime.isAfter(DateTime.now()))) {
      await _notif.schedule(t);
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
    if (input.isEmpty) { _snack('Describe a task first'); return; }
    setState(() => _parsing = true);
    HapticFeedback.lightImpact();
    final task = await _api.parseTask(input);
    if (!mounted) return;
    setState(() => _parsing = false);
    if (task != null) {
      _inputCtrl.clear();
      _showPreview(task);
    } else {
      _showManualCreate(input);
    }
  }

  void _confirmAdd(ScheduledTask task) async {
    setState(() => _tasks.add(task));
    await _save();
    await _notif.schedule(task);
    _snack('Task scheduled');
  }

  void _addSuggestion(ScheduledTask sug) async {
    final copy = ScheduledTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: sug.title, description: sug.description,
      scheduledTime: sug.scheduledTime, category: sug.category,
      priority: sug.priority, estimatedDuration: sug.estimatedDuration,
    );
    setState(() { _tasks.add(copy); _suggestions.remove(sug); });
    await _save();
    await _notif.schedule(copy);
    HapticFeedback.lightImpact();
    _snack('Added to schedule');
  }

  void _delete(ScheduledTask task) async {
    setState(() => _tasks.remove(task));
    await _save();
    await _notif.cancel(task);
    HapticFeedback.mediumImpact();
  }

  void _markComplete(ScheduledTask task) async {
    setState(() => task.status = TaskStatus.completed);
    await _save();
    await _notif.cancel(task);
    HapticFeedback.lightImpact();
    _snack('Marked complete');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: _body(13, color: _txt)),
      backgroundColor: _surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _border),
      ),
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
      case TaskPriority.high:   return _red;
      case TaskPriority.low:    return _green;
      default:                  return _amber;
    }
  }

  Color _categoryColor(TaskCategory c) {
    switch (c) {
      case TaskCategory.work:     return _accent;
      case TaskCategory.health:   return _green;
      case TaskCategory.finance:  return _amber;
      case TaskCategory.learning: return _purple;
      case TaskCategory.personal: return const Color(0xFFEC4899);
      default:                    return _txtSub;
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
    if (diff < 0)  return 'Overdue';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (diff < 7)  return days[dt.weekday - 1];
    return '${dt.day} / ${dt.month}';
  }

  String _categoryLabel(TaskCategory c) {
    switch (c) {
      case TaskCategory.work:     return 'WORK';
      case TaskCategory.health:   return 'HEALTH';
      case TaskCategory.finance:  return 'FINANCE';
      case TaskCategory.learning: return 'LEARNING';
      case TaskCategory.personal: return 'PERSONAL';
      default:                    return 'OTHER';
    }
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
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    _buildInputSection(),
                    const SizedBox(height: 32),
                    _buildStatsRow(),
                    const SizedBox(height: 32),
                    _buildUpcomingSection(),
                    const SizedBox(height: 32),
                    _buildSuggestionsSection(),
                    const SizedBox(height: 32),
                    _buildWorldClock(),
                    if (_completed.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      _buildCompletedSection(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(bottom: BorderSide(color: _border, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: _txtSub, size: 14),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SCHEDULER', style: _label(10, spacing: 2.5)),
              const SizedBox(height: 3),
              Text('Smart Task Planner', style: _body(16, w: FontWeight.w700)),
            ]),
          ),
          GestureDetector(
            onTap: _loadSuggestions,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _loadingSuggestions ? _purpleDim : _surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _loadingSuggestions ? _purple.withOpacity(0.4) : _border,
                ),
              ),
              child: _loadingSuggestions
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: _purple),
                    )
                  : const Icon(Icons.auto_awesome_outlined, color: _txtSub, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input Section ──────────────────────────────────────────────────────────
  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NEW TASK', style: _label(10, spacing: 2.5)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _inputCtrl,
                style: _body(14),
                decoration: InputDecoration(
                  hintText: 'e.g. "Call client tomorrow at 3pm" or "Team standup Friday 10am"',
                  hintStyle: _body(13, color: _txtDim),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                maxLines: 2,
                minLines: 1,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _parseAndAdd(),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _quickChip('Deep work 9am'),
                      const SizedBox(width: 8),
                      _quickChip('Team sync Friday'),
                      const SizedBox(width: 8),
                      _quickChip('Review emails 2pm'),
                    ]),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _parsing ? null : _parseAndAdd,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: _parsing ? _accentDim : _accent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: _parsing
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Parse', style: _body(13, w: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _quickChip(String label) {
    return GestureDetector(
      onTap: () {
        _inputCtrl.text = label;
        _parseAndAdd();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _border),
        ),
        child: Text(label, style: _label(11, color: _txtSub, spacing: 0)),
      ),
    );
  }

  // ── Stats Row ──────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final pct = (_efficiency * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        Expanded(child: _statTile('${_tasks.length}', 'TOTAL', _txtSub)),
        _divider(),
        Expanded(child: _statTile('${_pending.length}', 'PENDING', _amber)),
        _divider(),
        Expanded(child: _statTile('${_completed.length}', 'DONE', _green)),
        _divider(),
        Expanded(child: _statTile('$pct%', 'RATE', _accent)),
      ]),
    );
  }

  Widget _divider() => Container(width: 1, height: 40, color: _border);

  Widget _statTile(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(
          color: color, fontSize: 22, fontWeight: FontWeight.w800,
          height: 1.0, letterSpacing: -0.5,
        )),
        const SizedBox(height: 5),
        Text(label, style: _label(9, spacing: 1.5)),
      ]),
    );
  }

  // ── Upcoming Section ───────────────────────────────────────────────────────
  Widget _buildUpcomingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('UPCOMING', style: _label(10, spacing: 2.5)),
          const Spacer(),
          if (_pending.isNotEmpty)
            Text('${_pending.length} tasks', style: _label(11, color: _txtSub, spacing: 0)),
        ]),
        const SizedBox(height: 16),
        if (!_tasksLoaded)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(strokeWidth: 1.5, color: _accent),
            ),
          )
        else if (_pending.isEmpty)
          _emptyState()
        else
          ..._pending.take(8).map(_buildTaskRow),
      ]),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: const Icon(Icons.calendar_today_outlined, color: _txtDim, size: 18),
        ),
        const SizedBox(height: 14),
        Text('No upcoming tasks', style: _body(14, w: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Describe a task above to get started', style: _body(12, color: _txtSub)),
      ]),
    );
  }

  Widget _buildTaskRow(ScheduledTask task) {
    final catColor  = _categoryColor(task.category);
    final priColor  = _priorityColor(task.priority);
    final isOverdue = task.scheduledTime.isBefore(DateTime.now());

    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: _redDim,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _red.withOpacity(0.3)),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: _red, size: 18),
      ),
      onDismissed: (_) => _delete(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isOverdue ? _red.withOpacity(0.25) : _border),
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Priority accent bar
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: priColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(task.title, style: _body(14, w: FontWeight.w600)),
                      const SizedBox(height: 5),
                      Row(children: [
                        Text(
                          _fmtDate(task.scheduledTime),
                          style: _label(11,
                            color: isOverdue ? _red : _txtSub, spacing: 0),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          width: 3, height: 3,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: _txtDim,
                          ),
                        ),
                        Text(
                          _fmtTime(task.scheduledTime),
                          style: _label(11, color: _txtSub, spacing: 0),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${task.estimatedDuration}m',
                          style: _label(11, color: _txtDim, spacing: 0),
                        ),
                      ]),
                      if (task.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          task.description,
                          style: _body(11, color: _txtDim),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: catColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: catColor.withOpacity(0.2)),
                      ),
                      child: Text(
                        _categoryLabel(task.category),
                        style: _label(9, color: catColor, spacing: 0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _markComplete(task),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: _greenDim,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _green.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.check_rounded, color: _green, size: 14),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Suggestions Section ────────────────────────────────────────────────────
  Widget _buildSuggestionsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('AI SUGGESTIONS', style: _label(10, spacing: 2.5)),
          const Spacer(),
          GestureDetector(
            onTap: _loadSuggestions,
            child: Text('Refresh', style: _label(11, color: _accent, spacing: 0)),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: _loadingSuggestions
              ? const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: _purple,
                  )),
                )
              : _suggestions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('Tap Refresh to load AI suggestions',
                          style: _body(13, color: _txtSub)),
                    )
                  : Column(
                      children: _suggestions.asMap().entries.map((e) {
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
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: catColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: catColor.withOpacity(0.2)),
            ),
            child: Icon(
              _categoryIcon(task.category),
              color: catColor, size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.title, style: _body(13, w: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                '${_fmtDate(task.scheduledTime)} at ${_fmtTime(task.scheduledTime)}',
                style: _label(11, color: _txtSub, spacing: 0),
              ),
            ]),
          ),
          GestureDetector(
            onTap: () => _addSuggestion(task),
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: _accentDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent.withOpacity(0.3)),
              ),
              child: const Icon(Icons.add_rounded, color: _accent, size: 15),
            ),
          ),
        ]),
      ),
      if (!isLast) Container(height: 1, color: _border),
    ]);
  }

  IconData _categoryIcon(TaskCategory c) {
    switch (c) {
      case TaskCategory.work:     return Icons.work_outline_rounded;
      case TaskCategory.health:   return Icons.favorite_outline_rounded;
      case TaskCategory.finance:  return Icons.account_balance_outlined;
      case TaskCategory.learning: return Icons.school_outlined;
      case TaskCategory.personal: return Icons.person_outline_rounded;
      default:                    return Icons.checklist_outlined;
    }
  }

  // ── World Clock ────────────────────────────────────────────────────────────
  Widget _buildWorldClock() {
    final cities = [
      ('London', 0, 'GMT+0'),
      ('New York', -5, 'GMT−5'),
      ('Tokyo', 9, 'GMT+9'),
      ('Dubai', 4, 'GMT+4'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('WORLD CLOCK', style: _label(10, spacing: 2.5)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: cities.asMap().entries.map((e) {
              final isLast = e.key == cities.length - 1;
              final city   = e.value;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(city.$1, style: _body(13, w: FontWeight.w600)),
                        Text(city.$3, style: _label(10, spacing: 0)),
                      ]),
                    ),
                    Text(
                      _worldTime(city.$2),
                      style: TextStyle(
                        color: _txt, fontSize: 18, fontWeight: FontWeight.w700,
                        fontFamily: 'monospace', letterSpacing: 1.5,
                      ),
                    ),
                  ]),
                ),
                if (!isLast) Container(height: 1, color: _border),
              ]);
            }).toList(),
          ),
        ),
      ]),
    );
  }

  // ── Completed Section ──────────────────────────────────────────────────────
  Widget _buildCompletedSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('COMPLETED', style: _label(10, spacing: 2.5)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: _completed.take(5).toList().asMap().entries.map((e) {
              final isLast = e.key == _completed.take(5).length - 1;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(children: [
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, color: _greenDim,
                        border: Border.all(color: _green.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.check, color: _green, size: 11),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        e.value.title,
                        style: TextStyle(
                          color: _txtSub, fontSize: 13,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: _txtDim,
                        ),
                      ),
                    ),
                    Text(
                      _categoryLabel(e.value.category),
                      style: _label(9, color: _txtDim, spacing: 0.8),
                    ),
                  ]),
                ),
                if (!isLast) Container(height: 1, color: _border),
              ]);
            }).toList(),
          ),
        ),
      ]),
    );
  }

  // ── Preview Sheet ──────────────────────────────────────────────────────────
  void _showPreview(ScheduledTask task) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _TaskPreviewSheet(task: task, onConfirm: _confirmAdd),
    );
  }

  void _showManualCreate(String title) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final task = ScheduledTask(
      id:                DateTime.now().millisecondsSinceEpoch.toString(),
      title:             title,
      description:       '',
      scheduledTime:     DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9),
      category:          TaskCategory.other,
      priority:          TaskPriority.medium,
      estimatedDuration: 30,
    );
    _snack('AI unavailable — created basic task');
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _TaskPreviewSheet(task: task, onConfirm: _confirmAdd),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Task Preview Sheet — premium bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TaskPreviewSheet extends StatefulWidget {
  final ScheduledTask task;
  final void Function(ScheduledTask) onConfirm;
  const _TaskPreviewSheet({required this.task, required this.onConfirm});

  @override
  State<_TaskPreviewSheet> createState() => _TaskPreviewSheetState();
}

class _TaskPreviewSheetState extends State<_TaskPreviewSheet> {
  late DateTime _selectedTime;

  @override
  void initState() {
    super.initState();
    _selectedTime = widget.task.scheduledTime;
  }

  String _fmtDt(DateTime dt) {
    final now  = DateTime.now();
    final h    = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m    = dt.minute.toString().padLeft(2, '0');
    final ap   = dt.hour >= 12 ? 'PM' : 'AM';
    final diff = DateTime(dt.year, dt.month, dt.day)
        .difference(DateTime(now.year, now.month, now.day)).inDays;
    final dateLabel = diff == 0 ? 'Today' : diff == 1 ? 'Tomorrow' : '${dt.day}/${dt.month}';
    return '$dateLabel at $h:$m $ap';
  }

  Color _priColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.high: return _red;
      case TaskPriority.low:  return _green;
      default:                return _amber;
    }
  }

  Future<void> _pickTime() async {
    final picked = await showDateTimePicker(context, _selectedTime);
    if (picked != null) setState(() => _selectedTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    final priColor = _priColor(widget.task.priority);
    return Container(
      padding: EdgeInsets.only(
        left: 24, right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: const BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: 32, height: 3,
            margin: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Text('CONFIRM TASK', style: _label(10, spacing: 2.5)),
        const SizedBox(height: 14),

        // Task title
        Text(widget.task.title, style: TextStyle(
          color: _txt, fontSize: 20, fontWeight: FontWeight.w800,
          letterSpacing: -0.4, height: 1.2,
        )),
        if (widget.task.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(widget.task.description, style: _body(13, color: _txtSub)),
        ],
        const SizedBox(height: 20),

        // Meta chips row
        Wrap(spacing: 8, runSpacing: 8, children: [
          _metaChip(
            Icons.calendar_today_outlined,
            _fmtDt(_selectedTime),
            _accent,
            onTap: _pickTime,
          ),
          _metaChip(
            Icons.timer_outlined,
            '${widget.task.estimatedDuration} min',
            _txtSub,
          ),
          _metaChip(
            Icons.flag_outlined,
            widget.task.priority.name.toUpperCase(),
            priColor,
          ),
          _metaChip(
            Icons.folder_outlined,
            widget.task.category.name.toUpperCase(),
            _txtSub,
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _accentDim,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _accent.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_active_outlined, color: _accent, size: 13),
            const SizedBox(width: 8),
            Text(
              'You will receive a notification at ${_fmtDt(_selectedTime)} and 15 min before',
              style: _label(11, color: _accent, spacing: 0),
            ),
          ]),
        ),
        const SizedBox(height: 24),

        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Center(child: Text('Cancel', style: _body(13, color: _txtSub, w: FontWeight.w600))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                // Build task with potentially updated time
                final updated = ScheduledTask(
                  id: widget.task.id,
                  title: widget.task.title,
                  description: widget.task.description,
                  scheduledTime: _selectedTime,
                  category: widget.task.category,
                  priority: widget.task.priority,
                  estimatedDuration: widget.task.estimatedDuration,
                );
                widget.onConfirm(updated);
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text('Schedule Task', style: _body(14, w: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _metaChip(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label, style: _label(11, color: color, spacing: 0.3)),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.edit_outlined, color: color.withOpacity(0.6), size: 10),
          ],
        ]),
      ),
    );
  }
}

// ── Date-time picker helper ────────────────────────────────────────────────────

Future<DateTime?> showDateTimePicker(BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 365)),
    builder: (ctx, child) => Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: _accent, onPrimary: Colors.white,
          surface: _card, onSurface: _txt,
        ),
        dialogBackgroundColor: _card,
      ),
      child: child!,
    ),
  );
  if (date == null) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    builder: (ctx, child) => Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: _accent, onPrimary: Colors.white,
          surface: _card, onSurface: _txt,
        ),
        dialogBackgroundColor: _card,
      ),
      child: child!,
    ),
  );
  if (time == null) return null;

  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
