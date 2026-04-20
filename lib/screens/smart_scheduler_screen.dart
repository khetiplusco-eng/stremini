// smart_scheduler_screen.dart — iOS PREMIUM REDESIGN
// Aesthetic: Apple Calendar / Reminders feel — grouped lists, iOS dialogs,
//            spring animations, clean typography, zero noise.
// ALL LOGIC PRESERVED

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ── Design tokens — iOS Dark ──────────────────────────────────────────────────
const _bg           = Color(0xFF000000);
const _bgSecondary  = Color(0xFF1C1C1E);
const _bgTertiary   = Color(0xFF2C2C2E);
const _separator    = Color(0xFF38383A);
const _accent       = Color(0xFF0A84FF);
const _accentSoft   = Color(0xFF0A84FF15);
const _green        = Color(0xFF30D158);
const _greenSoft    = Color(0xFF30D15812);
const _red          = Color(0xFFFF453A);
const _redSoft      = Color(0xFFFF453A12);
const _amber        = Color(0xFFFF9F0A);
const _amberSoft    = Color(0xFFFF9F0A12);
const _purple       = Color(0xFFBF5AF2);
const _purpleSoft   = Color(0xFFBF5AF212);
const _pink         = Color(0xFFFF375F);
const _pinkSoft     = Color(0xFFFF375F12);
const _txt          = Color(0xFFFFFFFF);
const _txtSecondary = Color(0xFF8E8E93);
const _txtTertiary  = Color(0xFF48484A);

TextStyle _sf({
  double size       = 14,
  FontWeight weight = FontWeight.w400,
  Color color       = _txt,
  double height     = 1.5,
  double spacing    = -0.3,
}) => TextStyle(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

// ─── Timezone Data ─────────────────────────────────────────────────────────────
class _TzOption {
  final String label;
  final String tzName;
  final String offset;
  final String region;
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

// ─── Models (UNCHANGED) ────────────────────────────────────────────────────────
enum TaskPriority { high, medium, low }
enum TaskCategory { work, personal, health, finance, learning, other }
enum TaskStatus { pending, completed }

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
      try {
        if (raw is String && raw.isNotEmpty) return DateTime.parse(raw).toLocal();
      } catch (_) {}
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

// ─── Notification Service (UNCHANGED) ─────────────────────────────────────────
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
        channelDescription: channelDesc, importance: Importance.max,
        priority: Priority.high, playSound: true, enableVibration: true,
        icon: '@mipmap/ic_launcher'),
    iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
  );

  Future<void> scheduleTask(ScheduledTask task) async {
    if (!_ready) return;
    try {
      final hash = task.id.hashCode.abs() % 2000000000;
      final now  = tz.TZDateTime.now(tz.local);
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
  final h  = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m  = dt.minute.toString().padLeft(2, '0');
  final ap = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ap';
}

String _fmtDate(DateTime dt) {
  final now   = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day   = DateTime(dt.year, dt.month, dt.day);
  final diff  = day.difference(today).inDays;
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
  switch (p) { case TaskPriority.high: return _redSoft; case TaskPriority.low: return _greenSoft; default: return _amberSoft; }
}
Color _categoryColor(TaskCategory c) {
  switch (c) { case TaskCategory.work: return _accent; case TaskCategory.health: return _green; case TaskCategory.finance: return _amber; case TaskCategory.learning: return _purple; case TaskCategory.personal: return _pink; default: return _txtSecondary; }
}
Color _categoryBg(TaskCategory c) {
  switch (c) { case TaskCategory.work: return _accentSoft; case TaskCategory.health: return _greenSoft; case TaskCategory.finance: return _amberSoft; case TaskCategory.learning: return _purpleSoft; case TaskCategory.personal: return _pinkSoft; default: return _bgTertiary; }
}
IconData _categoryIcon(TaskCategory c) {
  switch (c) { case TaskCategory.work: return Icons.briefcase_fill; case TaskCategory.health: return Icons.heart_fill; case TaskCategory.finance: return Icons.banknote; case TaskCategory.learning: return Icons.book_fill; case TaskCategory.personal: return Icons.person_crop_circle_fill; default: return Icons.checkmark_circle_fill; }
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
        leading: Navigator.canPop(context)
            ? GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: _txtSecondary, size: 14),
                ),
              )
            : null,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(0.5),
            child: Container(height: 0.5, color: _separator)),
      ),
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Select Timezone', style: _sf(size: 28, weight: FontWeight.w700, spacing: -1.0)),
              const SizedBox(height: 6),
              Text('Notifications fire precisely at your local time.',
                  style: _sf(size: 15, color: _txtSecondary)),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(12)),
                child: TextField(
                  style: _sf(size: 15),
                  decoration: InputDecoration(
                    hintText: 'Search country or region…',
                    hintStyle: _sf(size: 15, color: _txtTertiary),
                    prefixIcon: const Icon(Icons.magnifyingglass, color: _txtSecondary, size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(height: 16),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              physics: const BouncingScrollPhysics(),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => Container(height: 0.5, color: _separator, margin: const EdgeInsets.only(left: 54)),
              itemBuilder: (_, i) {
                final tz = _filtered[i];
                final selected = _selected == tz.tzName;
                return GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); setState(() => _selected = tz.tzName); },
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: selected ? _accentSoft : _bgSecondary,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.globe_americas_fill, color: selected ? _accent : _txtSecondary, size: 17),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tz.label, style: _sf(size: 15, color: selected ? _txt : _txtSecondary, weight: selected ? FontWeight.w500 : FontWeight.w400)),
                        Text(tz.offset, style: _sf(size: 12, color: selected ? _accent : _txtTertiary)),
                      ])),
                      if (selected) const Icon(Icons.checkmark_circle_fill, color: _accent, size: 22),
                    ]),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
            child: GestureDetector(
              onTap: _selected == null ? null : () { HapticFeedback.mediumImpact(); widget.onSelected(_selected!); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity, height: 54,
                decoration: BoxDecoration(
                  color: _selected != null ? _accent : _bgSecondary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(child: Text(
                  _selected != null ? 'Confirm Timezone' : 'Select a timezone above',
                  style: _sf(size: 16, weight: FontWeight.w600,
                      color: _selected != null ? _txt : _txtTertiary),
                )),
              ),
            ),
          ),
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
    if (task != null) { _inputCtrl.clear(); _showPreview(task); } else { _showManualCreate(input); }
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
      content: Text(msg, style: _sf(size: 13)),
      backgroundColor: _bgSecondary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

    if (!_loaded) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_accent)),
          const SizedBox(height: 16),
          Text('Loading scheduler…', style: _sf(size: 14, color: _txtSecondary)),
        ])),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
        child: ListView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 60),
          children: [
            _buildStatsRow(),
            const SizedBox(height: 28),
            _buildInputSection(),
            const SizedBox(height: 32),
            _buildUpcomingSection(),
            if (_completed.isNotEmpty) ...[
              const SizedBox(height: 32),
              _buildCompletedSection(),
            ],
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final tzOption = _timezones.firstWhere((t) => t.tzName == _tzName,
        orElse: () => const _TzOption('Unknown', '', '', ''));

    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _txtSecondary, size: 14),
          ),
        ),
      ),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Smart Scheduler', style: _sf(size: 17, weight: FontWeight.w700, spacing: -0.5)),
        Text('AI Task Planner', style: _sf(size: 12, color: _txtSecondary)),
      ]),
      actions: [
        GestureDetector(
          onTap: () => setState(() => _showTzOnboarding = true),
          child: Container(
            margin: const EdgeInsets.fromLTRB(0, 10, 16, 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.globe_americas_fill, color: _txtSecondary, size: 13),
              const SizedBox(width: 5),
              Text(tzOption.offset.isEmpty ? 'TZ' : tzOption.offset,
                  style: _sf(size: 12, color: _accent, weight: FontWeight.w500)),
            ]),
          ),
        ),
      ],
      bottom: PreferredSize(preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: _separator)),
    );
  }

  Widget _buildStatsRow() {
    final pct = (_rate * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Row(children: [
        _statCard('${_tasks.length}', 'Total', _txtSecondary),
        const SizedBox(width: 10),
        _statCard('${_pending.length}', 'Pending', _amber),
        const SizedBox(width: 10),
        _statCard('${_completed.length}', 'Done', _green),
        const SizedBox(width: 10),
        _statCard('$pct%', 'Rate', _accent),
      ]),
    );
  }

  Widget _statCard(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text(value, style: _sf(size: 24, color: color, weight: FontWeight.w700, spacing: -0.5, height: 1.0)),
          const SizedBox(height: 4),
          Text(label, style: _sf(size: 11, color: _txtSecondary)),
        ]),
      ),
    );
  }

  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Add Task', style: _sf(size: 22, weight: FontWeight.w700, spacing: -0.5)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(
                controller: _inputCtrl,
                style: _sf(size: 15),
                maxLines: 2, minLines: 1,
                decoration: InputDecoration(
                  hintText: 'e.g. "Team call tomorrow at 3pm"',
                  hintStyle: _sf(size: 15, color: _txtTertiary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _parseAndAdd(),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _parsing ? null : _parseAndAdd,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: _parsing ? _accentSoft : _accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _parsing
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_txt)))
                        : Text('Parse', style: _sf(size: 14, weight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // Notification info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: _accentSoft, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.bell_badge_fill, color: _accent, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Two alerts per task', style: _sf(size: 14, weight: FontWeight.w500)),
              Text('5-min warning + at-time alert, works when app is closed',
                  style: _sf(size: 12, color: _txtSecondary)),
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
        decoration: BoxDecoration(
          color: _bgTertiary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: _sf(size: 12, color: _txtSecondary)),
      ),
    );
  }

  Widget _buildUpcomingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Upcoming', style: _sf(size: 22, weight: FontWeight.w700, spacing: -0.5)),
          const Spacer(),
          Text('${_pending.length} task${_pending.length == 1 ? '' : 's'}',
              style: _sf(size: 14, color: _txtSecondary)),
        ]),
        const SizedBox(height: 14),
        if (_pending.isEmpty)
          _emptyState()
        else
          Container(
            decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: _pending.asMap().entries.map((e) {
                final isLast = e.key == _pending.length - 1;
                return Column(children: [
                  _buildTaskRow(e.value),
                  if (!isLast) Container(height: 0.5, color: _separator, margin: const EdgeInsets.only(left: 64)),
                ]);
              }).toList(),
            ),
          ),
      ]),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: _accentSoft, borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.calendar_badge_plus_fill, color: _accent, size: 22),
        ),
        const SizedBox(height: 12),
        Text('No upcoming tasks', style: _sf(size: 16, weight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Describe a task above to get started', style: _sf(size: 13, color: _txtSecondary)),
      ]),
    );
  }

  Widget _buildTaskRow(ScheduledTask task) {
    final priColor = _priorityColor(task.priority);
    final catColor = _categoryColor(task.category);
    final catBg    = _categoryBg(task.category);
    final isOverdue = task.scheduledTime.isBefore(DateTime.now());

    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: const BoxDecoration(
          color: _red,
          borderRadius: BorderRadius.only(topRight: Radius.circular(16), bottomRight: Radius.circular(16)),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.trash_fill, color: _txt, size: 20),
      ),
      onDismissed: (_) => _delete(task),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Category icon
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: catBg, borderRadius: BorderRadius.circular(11)),
            child: Icon(_categoryIcon(task.category), color: catColor, size: 19),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.title, style: _sf(size: 15, weight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(children: [
              Text(
                '${_fmtDate(task.scheduledTime)} · ${_fmtTime(task.scheduledTime)} · ${task.estimatedDuration}m',
                style: _sf(size: 12, color: isOverdue ? _red : _txtSecondary),
              ),
            ]),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(task.description, style: _sf(size: 12, color: _txtTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ])),
          const SizedBox(width: 10),
          // Priority dot + done button
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: priColor),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _markDone(task),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _greenSoft,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text('Done', style: _sf(size: 12, color: _green, weight: FontWeight.w600)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildCompletedSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Completed', style: _sf(size: 22, weight: FontWeight.w700, spacing: -0.5)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(color: _bgSecondary, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: _completed.take(5).toList().asMap().entries.map((e) {
              final isLast = e.key == (_completed.take(5).length - 1);
              final task = e.value;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(children: [
                    Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _greenSoft),
                      child: const Icon(Icons.checkmark, color: _green, size: 14),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(task.title,
                        style: _sf(size: 14, color: _txtTertiary).copyWith(
                          decoration: TextDecoration.lineThrough,
                          decorationColor: _txtTertiary,
                        ))),
                    Text(_fmtDate(task.scheduledTime), style: _sf(size: 12, color: _txtTertiary)),
                  ]),
                ),
                if (!isLast) Container(height: 0.5, color: _separator, margin: const EdgeInsets.only(left: 54)),
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
          colorScheme: const ColorScheme.dark(primary: _accent, onPrimary: _txt, surface: Color(0xFF1C1C1E), onSurface: _txt),
          dialogBackgroundColor: const Color(0xFF1C1C1E),
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
          colorScheme: const ColorScheme.dark(primary: _accent, onPrimary: _txt, surface: Color(0xFF1C1C1E), onSurface: _txt),
          dialogBackgroundColor: const Color(0xFF1C1C1E),
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
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: _bgTertiary, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // Header
          Row(children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: catBg, borderRadius: BorderRadius.circular(13)),
              child: Icon(_categoryIcon(widget.task.category), color: catColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.task.title, style: _sf(size: 20, weight: FontWeight.w700, spacing: -0.5)),
              if (widget.task.description.isNotEmpty)
                Text(widget.task.description, style: _sf(size: 13, color: _txtSecondary)),
            ])),
          ]),

          const SizedBox(height: 20),

          // Meta chips
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(Icons.calendar_fill, '${_fmtDate(_time)}  ${_fmtTime(_time)}', _accent, onTap: _pickTime),
            _chip(Icons.timer_fill, '${widget.task.estimatedDuration} min', _txtSecondary),
            _chip(Icons.flag_fill, _priorityLabel(widget.task.priority), priColor),
            _chip(_categoryIcon(widget.task.category), _categoryLabel(widget.task.category), catColor),
          ]),

          const SizedBox(height: 16),

          // Notification preview
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.bell_badge_fill, color: _accent, size: 14),
                const SizedBox(width: 8),
                Text('Scheduled Alerts', style: _sf(size: 12, color: _accent, weight: FontWeight.w600)),
              ]),
              const SizedBox(height: 10),
              _notifRow(Icons.alarm_fill, '5-minute warning', '${_fmtDate(warnTime)}  ${_fmtTime(warnTime)}'),
              const SizedBox(height: 6),
              _notifRow(Icons.bell_fill, 'Task starts', '${_fmtDate(_time)}  ${_fmtTime(_time)}'),
            ]),
          ),

          if (inPast) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _redSoft, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.exclamationmark_triangle_fill, color: _red, size: 15),
                const SizedBox(width: 8),
                Expanded(child: Text('This time is in the past. Tap the date above to update.',
                    style: _sf(size: 13, color: _red))),
              ]),
            ),
          ],

          const SizedBox(height: 20),

          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(color: _bgTertiary, borderRadius: BorderRadius.circular(14)),
                  child: Center(child: Text('Cancel', style: _sf(size: 16, color: _txtSecondary, weight: FontWeight.w500))),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  final updated = ScheduledTask(
                    id: widget.task.id, title: widget.task.title, description: widget.task.description,
                    scheduledTime: _time, category: widget.task.category,
                    priority: widget.task.priority, estimatedDuration: widget.task.estimatedDuration,
                  );
                  widget.onConfirm(updated);
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.checkmark, color: _txt, size: 18),
                    const SizedBox(width: 8),
                    Text('Schedule Task', style: _sf(size: 16, weight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _notifRow(IconData icon, String label, String time) {
    return Row(children: [
      Icon(icon, color: _accent, size: 13),
      const SizedBox(width: 8),
      Text(label, style: _sf(size: 13, color: _accent)),
      const Spacer(),
      Text(time, style: _sf(size: 12, color: _txtSecondary)),
    ]);
  }

  Widget _chip(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 6),
          Text(label, style: _sf(size: 13, color: color, weight: FontWeight.w500)),
          if (onTap != null) ...[
            const SizedBox(width: 5),
            Icon(Icons.pencil, color: color.withOpacity(0.5), size: 11),
          ],
        ]),
      ),
    );
  }
}
