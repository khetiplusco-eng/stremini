// smart_scheduler_screen.dart — THEME MATCH
// Design: Pure black bg, #0AFFE0 teal accent, same card/border/typography as home/agent screens
// ALL LOGIC PRESERVED

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ── Design tokens — consistent with all screens ───────────────────────────────
const _bg           = Color(0xFF000000);
const _card         = Color(0xFF111111);
const _cardHi       = Color(0xFF161616);
const _border       = Color(0xFF1C1C1C);
const _borderSub    = Color(0xFF141414);
const _separator    = Color(0xFF1A1A1A);

const _teal         = Color(0xFF0AFFE0);
const _tealDim      = Color(0xFF071A18);
const _tealMid      = Color(0xFF0AC8B4);

const _green        = Color(0xFF30D158);
const _greenDim     = Color(0xFF071A0F);
const _red          = Color(0xFFFF453A);
const _redDim       = Color(0xFF1A0805);
const _amber        = Color(0xFFFF9F0A);
const _amberDim     = Color(0xFF1A1000);
const _purple       = Color(0xFFBF5AF2);
const _purpleDim    = Color(0xFF1A0D28);
const _blue         = Color(0xFF4A9EFF);
const _blueDim      = Color(0xFF071020);
const _pink         = Color(0xFFFF375F);
const _pinkDim      = Color(0xFF1A0510);

const _txt          = Color(0xFFFFFFFF);
const _txtSub       = Color(0xFF8C8C8C);
const _txtDim       = Color(0xFF404040);

TextStyle _t(double size, {
  Color color = _txt, FontWeight w = FontWeight.w400,
  double spacing = 0, double h = 1.4,
}) => GoogleFonts.dmSans(fontSize: size, color: color, fontWeight: w, letterSpacing: spacing, height: h);

// ─── Timezone Data ────────────────────────────────────────────────────────────
class _TzOption {
  final String label, tzName, offset, region;
  const _TzOption(this.label, this.tzName, this.offset, this.region);
}

const List<_TzOption> _timezones = [
  _TzOption('India', 'Asia/Kolkata', 'UTC+5:30', 'Asia'),
  _TzOption('United States — Eastern', 'America/New_York', 'UTC−5', 'Americas'),
  _TzOption('United States — Pacific', 'America/Los_Angeles', 'UTC−8', 'Americas'),
  _TzOption('United Kingdom', 'Europe/London', 'UTC+0', 'Europe'),
  _TzOption('Germany', 'Europe/Berlin', 'UTC+1', 'Europe'),
  _TzOption('Japan', 'Asia/Tokyo', 'UTC+9', 'Asia'),
  _TzOption('Australia — Sydney', 'Australia/Sydney', 'UTC+11', 'Oceania'),
  _TzOption('UAE — Dubai', 'Asia/Dubai', 'UTC+4', 'Asia'),
  _TzOption('Singapore', 'Asia/Singapore', 'UTC+8', 'Asia'),
  _TzOption('Brazil — São Paulo', 'America/Sao_Paulo', 'UTC−3', 'Americas'),
  _TzOption('Canada — Toronto', 'America/Toronto', 'UTC−5', 'Americas'),
  _TzOption('France', 'Europe/Paris', 'UTC+1', 'Europe'),
  _TzOption('China', 'Asia/Shanghai', 'UTC+8', 'Asia'),
  _TzOption('South Korea', 'Asia/Seoul', 'UTC+9', 'Asia'),
  _TzOption('Indonesia', 'Asia/Jakarta', 'UTC+7', 'Asia'),
  _TzOption('Pakistan', 'Asia/Karachi', 'UTC+5', 'Asia'),
  _TzOption('Bangladesh', 'Asia/Dhaka', 'UTC+6', 'Asia'),
  _TzOption('Nigeria', 'Africa/Lagos', 'UTC+1', 'Africa'),
  _TzOption('Mexico', 'America/Mexico_City', 'UTC−6', 'Americas'),
  _TzOption('Russia — Moscow', 'Europe/Moscow', 'UTC+3', 'Europe'),
];

// ─── Models (UNCHANGED) ───────────────────────────────────────────────────────
enum TaskPriority { high, medium, low }
enum TaskCategory { work, personal, health, finance, learning, other }
enum TaskStatus { pending, completed }

class ScheduledTask {
  final String id, title, description;
  final DateTime scheduledTime;
  final TaskCategory category;
  final TaskPriority priority;
  final int estimatedDuration;
  TaskStatus status;

  ScheduledTask({
    required this.id, required this.title, required this.description,
    required this.scheduledTime, required this.category,
    required this.priority, required this.estimatedDuration,
    this.status = TaskStatus.pending,
  });

  factory ScheduledTask.fromJson(Map<String, dynamic> j) {
    TaskPriority parsePriority(String? s) {
      if (s?.toLowerCase() == 'high') return TaskPriority.high;
      if (s?.toLowerCase() == 'low') return TaskPriority.low;
      return TaskPriority.medium;
    }
    TaskCategory parseCategory(String? s) {
      switch (s?.toLowerCase()) {
        case 'work': return TaskCategory.work;
        case 'personal': return TaskCategory.personal;
        case 'health': return TaskCategory.health;
        case 'finance': return TaskCategory.finance;
        case 'learning': return TaskCategory.learning;
        default: return TaskCategory.other;
      }
    }
    DateTime parseTime(dynamic raw) {
      try { if (raw is String && raw.isNotEmpty) return DateTime.parse(raw).toLocal(); } catch (_) {}
      return DateTime.now().add(const Duration(days: 1));
    }
    return ScheduledTask(
      id: j['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: j['title']?.toString() ?? 'Untitled Task',
      description: j['description']?.toString() ?? '',
      scheduledTime: parseTime(j['scheduledTime'] ?? j['scheduled_time'] ?? j['time']),
      category: parseCategory(j['category']?.toString()),
      priority: parsePriority(j['priority']?.toString()),
      estimatedDuration: (j['estimatedDuration'] as num?)?.toInt() ?? 30,
      status: j['status']?.toString() == 'completed' ? TaskStatus.completed : TaskStatus.pending,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'description': description,
    'scheduledTime': scheduledTime.toIso8601String(),
    'category': category.name, 'priority': priority.name,
    'estimatedDuration': estimatedDuration, 'status': status.name,
  };
}

// ─── Storage (UNCHANGED) ──────────────────────────────────────────────────────
class _Storage {
  static const _tasksKey = 'sched_tasks_v4';
  static const _tzKey    = 'sched_timezone_v1';

  static Future<List<ScheduledTask>> loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tasksKey);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List).map((e) => ScheduledTask.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) { debugPrint('[Storage] load: $e'); return []; }
  }

  static Future<void> saveTasks(List<ScheduledTask> tasks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tasksKey, jsonEncode(tasks.map((t) => t.toJson()).toList()));
    } catch (e) { debugPrint('[Storage] save: $e'); }
  }

  static Future<String?> loadTimezone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tzKey);
  }

  static Future<void> saveTimezone(String tzName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tzKey, tzName);
  }
}

// ─── Notification Service (UNCHANGED) ────────────────────────────────────────
class _NotifService {
  static final _NotifService _i = _NotifService._();
  factory _NotifService() => _i;
  _NotifService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init(String tzName) async {
    if (_ready) return;
    try {
      tz.initializeTimeZones();
      final loc = tz.getLocation(tzName);
      tz.setLocalLocation(loc);
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true);
      await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      await androidImpl?.requestExactAlarmsPermission();
      _ready = true;
    } catch (e) { debugPrint('[Notif] init error: $e'); }
  }

  NotificationDetails _details(String channelDesc) => NotificationDetails(
    android: AndroidNotificationDetails('stremini_sched_v2', 'Smart Scheduler',
        channelDescription: channelDesc, importance: Importance.max, priority: Priority.high,
        playSound: true, enableVibration: true, icon: '@mipmap/ic_launcher'),
    iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
  );

  Future<void> scheduleTask(ScheduledTask task) async {
    if (!_ready) return;
    try {
      final hash = task.id.hashCode.abs() % 2000000000;
      final now = tz.TZDateTime.now(tz.local);
      final taskTime = tz.TZDateTime(tz.local, task.scheduledTime.year, task.scheduledTime.month,
          task.scheduledTime.day, task.scheduledTime.hour, task.scheduledTime.minute);
      final warningTime = taskTime.subtract(const Duration(minutes: 5));
      if (warningTime.isAfter(now)) {
        await _plugin.zonedSchedule(hash + 1, 'Starting in 5 minutes', task.title, warningTime,
            _details('5-minute task warnings'), androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, matchDateTimeComponents: null);
      }
      if (taskTime.isAfter(now)) {
        await _plugin.zonedSchedule(hash, 'Task Starting Now', task.title, taskTime,
            _details('Task start reminders'), androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, matchDateTimeComponents: null);
      }
    } catch (e) { debugPrint('[Notif] schedule error: $e'); }
  }

  Future<void> cancelTask(ScheduledTask task) async {
    try { final hash = task.id.hashCode.abs() % 2000000000; await _plugin.cancel(hash); await _plugin.cancel(hash + 1); } catch (_) {}
  }

  Future<void> cancelAll() async { try { await _plugin.cancelAll(); } catch (_) {} }

  Future<void> rescheduleAll(List<ScheduledTask> tasks) async {
    await cancelAll();
    final now = DateTime.now();
    for (final t in tasks) {
      if (t.status == TaskStatus.pending && t.scheduledTime.isAfter(now)) await scheduleTask(t);
    }
  }
}

// ─── API (UNCHANGED) ──────────────────────────────────────────────────────────
class _Api {
  static const _base = 'https://ai-keyboard-backend.vishwajeetadkine705.workers.dev';
  String? get _token => Supabase.instance.client.auth.currentSession?.accessToken;
  Map<String, String> get _h => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<ScheduledTask?> parseTask(String input) async {
    try {
      final res = await http.post(Uri.parse('$_base/scheduler/parse'), headers: _h,
          body: jsonEncode({'input': input})).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final taskJson = (data['task'] as Map<String, dynamic>?) ?? data;
      if (taskJson.isEmpty || taskJson['title'] == null) return null;
      taskJson['id'] = DateTime.now().millisecondsSinceEpoch.toString();
      return ScheduledTask.fromJson(taskJson);
    } catch (e) { debugPrint('[API] parseTask: $e'); return null; }
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
String _fmtTime(DateTime dt) {
  final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
}

String _fmtDate(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff < 0)  return 'Overdue';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (diff < 7)  return days[dt.weekday - 1];
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${dt.day} ${months[dt.month - 1]}';
}

Color _priorityColor(TaskPriority p) {
  switch (p) { case TaskPriority.high: return _red; case TaskPriority.low: return _green; default: return _amber; }
}
Color _priorityBg(TaskPriority p) {
  switch (p) { case TaskPriority.high: return _redDim; case TaskPriority.low: return _greenDim; default: return _amberDim; }
}
Color _categoryColor(TaskCategory c) {
  switch (c) { case TaskCategory.work: return _blue; case TaskCategory.health: return _green; case TaskCategory.finance: return _amber; case TaskCategory.learning: return _purple; case TaskCategory.personal: return _pink; default: return _txtSub; }
}
Color _categoryBg(TaskCategory c) {
  switch (c) { case TaskCategory.work: return _blueDim; case TaskCategory.health: return _greenDim; case TaskCategory.finance: return _amberDim; case TaskCategory.learning: return _purpleDim; case TaskCategory.personal: return _pinkDim; default: return const Color(0xFF141414); }
}
IconData _categoryIcon(TaskCategory c) {
  switch (c) { case TaskCategory.work: return Icons.work_outline_rounded; case TaskCategory.health: return Icons.favorite_outline_rounded; case TaskCategory.finance: return Icons.payments_outlined; case TaskCategory.learning: return Icons.book_outlined; case TaskCategory.personal: return Icons.person_outline_rounded; default: return Icons.check_circle_outline_rounded; }
}
String _categoryLabel(TaskCategory c) => c.name[0].toUpperCase() + c.name.substring(1);
String _priorityLabel(TaskPriority p) => p.name[0].toUpperCase() + p.name.substring(1);

// ─── Timezone Onboarding ──────────────────────────────────────────────────────
class _TimezoneOnboardingScreen extends StatefulWidget {
  final void Function(String tzName) onSelected;
  const _TimezoneOnboardingScreen({required this.onSelected});
  @override
  State<_TimezoneOnboardingScreen> createState() => _TimezoneOnboardingScreenState();
}

class _TimezoneOnboardingScreenState extends State<_TimezoneOnboardingScreen>
    with SingleTickerProviderStateMixin {
  String? _selected;
  String _search = '';
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..forward();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  List<_TzOption> get _filtered {
    if (_search.isEmpty) return _timezones;
    final q = _search.toLowerCase();
    return _timezones.where((t) =>
        t.label.toLowerCase().contains(q) ||
        t.tzName.toLowerCase().contains(q) ||
        t.region.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Navigator.canPop(context) ? GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _txtSub, size: 14),
          ),
        ) : null,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(0.5),
            child: Container(height: 0.5, color: _border)),
      ),
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 28, 20, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Select Timezone', style: _t(26, w: FontWeight.w700, spacing: -1.0)),
            const SizedBox(height: 6),
            Text('Notifications fire precisely at your local time.', style: _t(14, color: _txtSub)),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
              child: TextField(
                style: _t(15),
                decoration: InputDecoration(
                  hintText: 'Search country or region…',
                  hintStyle: _t(15, color: _txtDim),
                  prefixIcon: const Icon(Icons.search, color: _txtSub, size: 18),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(height: 16),
          ])),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              physics: const BouncingScrollPhysics(),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => Container(height: 0.5, color: _borderSub, margin: const EdgeInsets.only(left: 54)),
              itemBuilder: (_, i) {
                final tz = _filtered[i];
                final selected = _selected == tz.tzName;
                return GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); setState(() => _selected = tz.tzName); },
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(children: [
                      Container(width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: selected ? _tealDim : _card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: selected ? _teal.withOpacity(0.3) : _border),
                        ),
                        child: Icon(Icons.public_rounded, color: selected ? _teal : _txtSub, size: 17),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tz.label, style: _t(15, color: selected ? _txt : _txtSub, w: selected ? FontWeight.w600 : FontWeight.w400)),
                        Text(tz.offset, style: _t(12, color: selected ? _teal : _txtDim)),
                      ])),
                      if (selected) Icon(Icons.check_circle_rounded, color: _teal, size: 22),
                    ]),
                  ),
                );
              },
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 36), child: GestureDetector(
            onTap: _selected == null ? null : () { HapticFeedback.mediumImpact(); widget.onSelected(_selected!); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity, height: 56,
              decoration: BoxDecoration(
                color: _selected != null ? _teal : _card,
                borderRadius: BorderRadius.circular(16),
                border: _selected == null ? Border.all(color: _border) : null,
              ),
              child: Center(child: Text(
                _selected != null ? 'Confirm Timezone' : 'Select a timezone above',
                style: _t(16, w: FontWeight.w700, color: _selected != null ? Colors.black : _txtDim),
              )),
            ),
          )),
        ]),
      ),
    );
  }
}

// ─── Main Scheduler Screen ────────────────────────────────────────────────────
class SmartSchedulerScreen extends StatefulWidget {
  const SmartSchedulerScreen({super.key});
  @override
  State<SmartSchedulerScreen> createState() => _SmartSchedulerScreenState();
}

class _SmartSchedulerScreenState extends State<SmartSchedulerScreen>
    with TickerProviderStateMixin {
  final _notif     = _NotifService();
  final _api       = _Api();
  final _inputCtrl = TextEditingController();
  final _scroll    = ScrollController();

  List<ScheduledTask> _tasks = [];
  bool _parsing              = false;
  bool _loaded               = false;
  String? _tzName;
  bool _showTzOnboarding     = false;

  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _boot();
  }

  @override
  void dispose() { _fadeCtrl.dispose(); _inputCtrl.dispose(); _scroll.dispose(); super.dispose(); }

  Future<void> _boot() async {
    final savedTz = await _Storage.loadTimezone();
    if (savedTz == null) { setState(() => _showTzOnboarding = true); return; }
    await _initWithTimezone(savedTz, fromOnboarding: false);
  }

  Future<void> _initWithTimezone(String tzName, {bool fromOnboarding = true}) async {
    await _Storage.saveTimezone(tzName);
    await _notif.init(tzName);
    final tasks = await _Storage.loadTasks();
    await _notif.rescheduleAll(tasks);
    if (mounted) {
      setState(() { _tzName = tzName; _tasks = tasks; _loaded = true; _showTzOnboarding = false; });
      _fadeCtrl.forward();
    }
  }

  Future<void> _parseAndAdd() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty) { _snack('Describe a task first'); return; }
    setState(() => _parsing = true);
    HapticFeedback.lightImpact();
    final task = await _api.parseTask(input);
    if (!mounted) return;
    setState(() => _parsing = false);
    if (task != null) { _inputCtrl.clear(); _showPreview(task); }
    else { _showManualCreate(input); }
  }

  void _confirmAdd(ScheduledTask task) async {
    setState(() => _tasks.add(task));
    await _Storage.saveTasks(_tasks);
    await _notif.scheduleTask(task);
    HapticFeedback.lightImpact();
    _snack('Task scheduled');
  }

  void _delete(ScheduledTask task) async {
    await _notif.cancelTask(task);
    setState(() => _tasks.remove(task));
    await _Storage.saveTasks(_tasks);
    HapticFeedback.mediumImpact();
  }

  void _markDone(ScheduledTask task) async {
    await _notif.cancelTask(task);
    setState(() => task.status = TaskStatus.completed);
    await _Storage.saveTasks(_tasks);
    HapticFeedback.lightImpact();
    _snack('Marked complete');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: _t(13)),
      backgroundColor: _card,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _border)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      duration: const Duration(seconds: 3),
    ));
  }

  List<ScheduledTask> get _pending => _tasks.where((t) => t.status == TaskStatus.pending).toList()
    ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
  List<ScheduledTask> get _completed => _tasks.where((t) => t.status == TaskStatus.completed).toList();
  double get _rate => _tasks.isEmpty ? 0 : _completed.length / _tasks.length;

  @override
  Widget build(BuildContext context) {
    if (_showTzOnboarding) return _TimezoneOnboardingScreen(onSelected: (tz) => _initWithTimezone(tz));
    if (!_loaded) return Scaffold(
      backgroundColor: _bg,
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_teal)),
        const SizedBox(height: 16),
        Text('Loading scheduler…', style: _t(14, color: _txtSub)),
      ])),
    );

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          Expanded(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
              child: ListView(
                controller: _scroll,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 20),
                children: [
                  _statsRow(),
                  const SizedBox(height: 28),
                  _inputSection(),
                  const SizedBox(height: 32),
                  _upcomingSection(),
                  if (_completed.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _completedSection(),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          _bottomNav(context),
        ]),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _topBar() {
    final tzOption = _tzName != null
        ? _timezones.firstWhere((t) => t.tzName == _tzName, orElse: () => const _TzOption('', '', '', ''))
        : const _TzOption('', '', '', '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(color: _bg, border: Border(bottom: BorderSide(color: _border, width: 0.5))),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _txtSub, size: 14),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('STREMINI AI', style: _t(16, w: FontWeight.w800, spacing: 1.0)),
          Text('SMART SCHEDULER', style: _t(10, color: _txtSub, spacing: 2.0)),
        ])),
        if (_tzName != null) GestureDetector(
          onTap: () => setState(() => _showTzOnboarding = true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.public_rounded, color: _txtSub, size: 13),
              const SizedBox(width: 5),
              Text(tzOption.offset.isEmpty ? 'TZ' : tzOption.offset,
                  style: _t(12, color: _teal, w: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Stats row ──────────────────────────────────────────────────────────────
  Widget _statsRow() {
    final pct = (_rate * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
      child: Row(children: [
        _statCard('${_tasks.length}', 'Total', _txtSub),
        const SizedBox(width: 10),
        _statCard('${_pending.length}', 'Pending', _amber),
        const SizedBox(width: 10),
        _statCard('${_completed.length}', 'Done', _green),
        const SizedBox(width: 10),
        _statCard('$pct%', 'Rate', _teal),
      ]),
    );
  }

  Widget _statCard(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(children: [
          Text(value, style: _t(24, color: color, w: FontWeight.w700, spacing: -0.5, h: 1.0)),
          const SizedBox(height: 4),
          Text(label, style: _t(11, color: _txtSub)),
        ]),
      ),
    );
  }

  // ── Input section ──────────────────────────────────────────────────────────
  Widget _inputSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('ADD TASK'),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(
                controller: _inputCtrl,
                style: _t(15),
                maxLines: 2, minLines: 1,
                decoration: InputDecoration(
                  hintText: 'e.g. "Team call tomorrow at 3pm"',
                  hintStyle: _t(15, color: _txtDim),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _parseAndAdd(),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _separator, width: 0.5))),
              child: Row(children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(children: [
                      _quickChip('Deep work 9am'),
                      const SizedBox(width: 8),
                      _quickChip('Meeting Friday 2pm'),
                      const SizedBox(width: 8),
                      _quickChip('Gym tomorrow 7am'),
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _parsing ? null : _parseAndAdd,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: _parsing ? _tealDim : _teal,
                      borderRadius: BorderRadius.circular(10),
                      border: _parsing ? Border.all(color: _teal.withOpacity(0.3)) : null,
                    ),
                    child: _parsing
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_teal)))
                        : Text('Parse', style: _t(14, color: Colors.black, w: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // Notification info card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
          child: Row(children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(color: _tealDim, borderRadius: BorderRadius.circular(10), border: Border.all(color: _teal.withOpacity(0.2))),
              child: const Icon(Icons.notifications_active_rounded, color: _teal, size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Two alerts per task', style: _t(13, w: FontWeight.w600)),
              Text('5-min warning + at-time alert, works when app is closed', style: _t(12, color: _txtSub, h: 1.4)),
            ])),
          ]),
        ),
      ]),
    );
  }

  Widget _quickChip(String label) {
    return GestureDetector(
      onTap: () { _inputCtrl.text = label; _parseAndAdd(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
        child: Text(label, style: _t(12, color: _txtSub)),
      ),
    );
  }

  Widget _sectionLabel(String text) => Row(children: [
    Container(width: 3, height: 14, color: _teal, margin: const EdgeInsets.only(right: 10)),
    Text(text, style: _t(11, color: _txtSub, w: FontWeight.w700, spacing: 2.0)),
  ]);

  // ── Upcoming section ───────────────────────────────────────────────────────
  Widget _upcomingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionLabel('UPCOMING'),
          const Spacer(),
          Text('${_pending.length} task${_pending.length == 1 ? '' : 's'}', style: _t(13, color: _txtSub)),
        ]),
        const SizedBox(height: 14),
        if (_pending.isEmpty)
          _emptyState()
        else
          Container(
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
            child: Column(
              children: _pending.asMap().entries.map((e) {
                final isLast = e.key == _pending.length - 1;
                return Column(children: [
                  _taskRow(e.value),
                  if (!isLast) Container(height: 0.5, color: _separator, margin: const EdgeInsets.only(left: 70)),
                ]);
              }).toList(),
            ),
          ),
      ]),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 52, height: 52,
          decoration: BoxDecoration(color: _tealDim, borderRadius: BorderRadius.circular(14), border: Border.all(color: _teal.withOpacity(0.2))),
          child: const Icon(Icons.event_available_rounded, color: _teal, size: 24),
        ),
        const SizedBox(height: 14),
        Text('No upcoming tasks', style: _t(16, w: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Describe a task above to get started', style: _t(13, color: _txtSub)),
      ]),
    );
  }

  Widget _taskRow(ScheduledTask task) {
    final priColor = _priorityColor(task.priority);
    final catColor = _categoryColor(task.category);
    final catBg    = _categoryBg(task.category);
    final isOverdue = task.scheduledTime.isBefore(DateTime.now());

    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: const BoxDecoration(
          color: _red,
          borderRadius: BorderRadius.only(topRight: Radius.circular(16), bottomRight: Radius.circular(16)),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline_rounded, color: _txt, size: 20),
      ),
      onDismissed: (_) => _delete(task),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 42, height: 42,
            decoration: BoxDecoration(color: catBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(_categoryIcon(task.category), color: catColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.title, style: _t(15, w: FontWeight.w600)),
            const SizedBox(height: 5),
            Row(children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: priColor)),
              const SizedBox(width: 6),
              Text(
                '${_fmtDate(task.scheduledTime)} · ${_fmtTime(task.scheduledTime)} · ${task.estimatedDuration}m',
                style: _t(12, color: isOverdue ? _red : _txtSub),
              ),
            ]),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(task.description, style: _t(12, color: _txtDim), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ])),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _markDone(task),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _greenDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _green.withOpacity(0.25)),
              ),
              child: Text('Done', style: _t(12, color: _green, w: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Completed section ──────────────────────────────────────────────────────
  Widget _completedSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionLabel('COMPLETED'),
          const Spacer(),
          Text('${_completed.length}', style: _t(13, color: _txtSub)),
        ]),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
          child: Column(
            children: _completed.take(5).toList().asMap().entries.map((e) {
              final isLast = e.key == (_completed.take(5).length - 1);
              final task = e.value;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Container(width: 28, height: 28,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _greenDim, border: Border.all(color: _green.withOpacity(0.2))),
                      child: const Icon(Icons.check_rounded, color: _green, size: 14),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(task.title,
                      style: _t(14, color: _txtDim).copyWith(decoration: TextDecoration.lineThrough, decorationColor: _txtDim),
                    )),
                    Text(_fmtDate(task.scheduledTime), style: _t(12, color: _txtDim)),
                  ]),
                ),
                if (!isLast) Container(height: 0.5, color: _separator, margin: const EdgeInsets.only(left: 56)),
              ]);
            }).toList(),
          ),
        ),
      ]),
    );
  }

  void _showPreview(ScheduledTask task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PreviewSheet(task: task, onConfirm: _confirmAdd),
    );
  }

  void _showManualCreate(String title) {
    final t = DateTime.now().add(const Duration(days: 1));
    final task = ScheduledTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title, description: '',
      scheduledTime: DateTime(t.year, t.month, t.day, 9),
      category: TaskCategory.other, priority: TaskPriority.medium,
      estimatedDuration: 30,
    );
    _snack('AI unavailable — created task manually');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PreviewSheet(task: task, onConfirm: _confirmAdd),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────
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
        _navBtn(icon: Icons.code_rounded, onTap: () => Navigator.pop(context)),
        _navBtn(icon: Icons.chat_bubble_outline_rounded, onTap: () => Navigator.pop(context)),
        _navBtn(icon: Icons.settings_outlined, active: true, onTap: () {}),
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

// ─── Preview Sheet ─────────────────────────────────────────────────────────────
class _PreviewSheet extends StatefulWidget {
  final ScheduledTask task;
  final void Function(ScheduledTask) onConfirm;
  const _PreviewSheet({required this.task, required this.onConfirm});
  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet>
    with SingleTickerProviderStateMixin {
  late DateTime _time;
  late AnimationController _ctrl;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _time = widget.task.scheduledTime;
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _teal, onPrimary: Colors.black, surface: Color(0xFF111111), onSurface: _txt),
          dialogBackgroundColor: const Color(0xFF111111),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _teal, onPrimary: Colors.black, surface: Color(0xFF111111), onSurface: _txt),
          dialogBackgroundColor: const Color(0xFF111111),
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() => _time = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final catColor = _categoryColor(widget.task.category);
    final catBg    = _categoryBg(widget.task.category);
    final priColor = _priorityColor(widget.task.priority);
    final inPast   = _time.isBefore(DateTime.now());
    final warnTime = _time.subtract(const Duration(minutes: 5));

    return SlideTransition(
      position: _slide,
      child: Container(
        padding: EdgeInsets.only(
          left: 20, right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 40,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D0D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _border, width: 0.5)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)),
          )),

          // Header
          Row(children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(color: catBg, borderRadius: BorderRadius.circular(14)),
              child: Icon(_categoryIcon(widget.task.category), color: catColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.task.title, style: _t(19, w: FontWeight.w700, spacing: -0.3)),
              if (widget.task.description.isNotEmpty) Text(widget.task.description, style: _t(13, color: _txtSub)),
            ])),
          ]),

          const SizedBox(height: 20),

          // Meta chips
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(Icons.calendar_month_rounded, '${_fmtDate(_time)}  ${_fmtTime(_time)}', _teal, onTap: _pickTime),
            _chip(Icons.timer_outlined, '${widget.task.estimatedDuration} min', _txtSub),
            _chip(Icons.flag_outlined, _priorityLabel(widget.task.priority), priColor),
            _chip(_categoryIcon(widget.task.category), _categoryLabel(widget.task.category), catColor),
          ]),

          const SizedBox(height: 16),

          // Notification preview
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _tealDim, borderRadius: BorderRadius.circular(12), border: Border.all(color: _teal.withOpacity(0.2))),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.notifications_active_rounded, color: _teal, size: 14),
                const SizedBox(width: 8),
                Text('Scheduled Alerts', style: _t(12, color: _teal, w: FontWeight.w600)),
              ]),
              const SizedBox(height: 10),
              _notifRow(Icons.alarm_rounded, '5-minute warning', '${_fmtDate(warnTime)}  ${_fmtTime(warnTime)}'),
              const SizedBox(height: 6),
              _notifRow(Icons.notifications_rounded, 'Task starts', '${_fmtDate(_time)}  ${_fmtTime(_time)}'),
            ]),
          ),

          if (inPast) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _redDim, borderRadius: BorderRadius.circular(10), border: Border.all(color: _red.withOpacity(0.25))),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: _red, size: 15),
                const SizedBox(width: 8),
                Expanded(child: Text('This time is in the past. Tap the date above to update.', style: _t(13, color: _red))),
              ]),
            ),
          ],

          const SizedBox(height: 20),

          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(height: 52,
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
                child: Center(child: Text('Cancel', style: _t(15, color: _txtSub, w: FontWeight.w600))),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                final updated = ScheduledTask(
                  id: widget.task.id, title: widget.task.title, description: widget.task.description,
                  scheduledTime: _time, category: widget.task.category,
                  priority: widget.task.priority, estimatedDuration: widget.task.estimatedDuration,
                );
                widget.onConfirm(updated);
              },
              child: Container(height: 52,
                decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.check_rounded, color: Colors.black, size: 18),
                  const SizedBox(width: 8),
                  Text('Schedule Task', style: _t(15, color: Colors.black, w: FontWeight.w700)),
                ]),
              ),
            )),
          ]),
        ]),
      ),
    );
  }

  Widget _notifRow(IconData icon, String label, String time) {
    return Row(children: [
      Icon(icon, color: _tealMid, size: 13),
      const SizedBox(width: 8),
      Text(label, style: _t(13, color: _tealMid)),
      const Spacer(),
      Text(time, style: _t(12, color: _txtSub)),
    ]);
  }

  Widget _chip(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 6),
          Text(label, style: _t(13, color: color, w: FontWeight.w500)),
          if (onTap != null) ...[const SizedBox(width: 5), Icon(Icons.edit_rounded, color: color.withOpacity(0.5), size: 11)],
        ]),
      ),
    );
  }
}
