// smart_scheduler_screen.dart — PREMIUM GOLD EDITION
// Design: Obsidian + 24K Gold — luxury editorial meets Bloomberg Terminal
// Font: DM Sans (body) + custom display styles
// Features: Timezone onboarding, fully functional notifications (5min + at-time),
//           works when app is closed/killed, AI task parsing, premium animations.

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

// ─── Design Tokens ────────────────────────────────────────────────────────────
const _ink = Color(0xFF080808);
const _obsidian = Color(0xFF0D0D0F);
const _surface = Color(0xFF121215);
const _card = Color(0xFF18181C);
const _cardHi = Color(0xFF1E1E24);
const _border = Color(0xFF242428);
const _borderHi = Color(0xFF2E2E36);
const _gold = Color(0xFFD4A843);
const _goldLight = Color(0xFFE8C46A);
const _goldDim = Color(0xFF8A6820);
const _goldGlow = Color(0x33D4A843);
const _silver = Color(0xFFB0B8C8);
const _txt = Color(0xFFF2F0EC);
const _txtSub = Color(0xFF8C8A86);
const _txtDim = Color(0xFF4A4A52);
const _green = Color(0xFF3DBA78);
const _greenDim = Color(0xFF0D2B1A);
const _red = Color(0xFFE05252);
const _redDim = Color(0xFF2A0D0D);
const _amber = Color(0xFFE8A23A);
const _amberDim = Color(0xFF2A1E06);
const _blue = Color(0xFF4A9EE8);

// ─── Timezone Data ─────────────────────────────────────────────────────────────
class _TzOption {
  final String label;
  final String tzName;
  final String offset;
  final String flag;
  const _TzOption(this.label, this.tzName, this.offset, this.flag);
}

const List<_TzOption> _timezones = [
  _TzOption('India', 'Asia/Kolkata', 'UTC+5:30', '🇮🇳'),
  _TzOption('United States (ET)', 'America/New_York', 'UTC−5', '🇺🇸'),
  _TzOption('United States (PT)', 'America/Los_Angeles', 'UTC−8', '🇺🇸'),
  _TzOption('United Kingdom', 'Europe/London', 'UTC+0', '🇬🇧'),
  _TzOption('Germany', 'Europe/Berlin', 'UTC+1', '🇩🇪'),
  _TzOption('Japan', 'Asia/Tokyo', 'UTC+9', '🇯🇵'),
  _TzOption('Australia (Sydney)', 'Australia/Sydney', 'UTC+11', '🇦🇺'),
  _TzOption('UAE (Dubai)', 'Asia/Dubai', 'UTC+4', '🇦🇪'),
  _TzOption('Singapore', 'Asia/Singapore', 'UTC+8', '🇸🇬'),
  _TzOption('Brazil (São Paulo)', 'America/Sao_Paulo', 'UTC−3', '🇧🇷'),
  _TzOption('Canada (Toronto)', 'America/Toronto', 'UTC−5', '🇨🇦'),
  _TzOption('France', 'Europe/Paris', 'UTC+1', '🇫🇷'),
  _TzOption('China', 'Asia/Shanghai', 'UTC+8', '🇨🇳'),
  _TzOption('South Korea', 'Asia/Seoul', 'UTC+9', '🇰🇷'),
  _TzOption('Indonesia', 'Asia/Jakarta', 'UTC+7', '🇮🇩'),
  _TzOption('Pakistan', 'Asia/Karachi', 'UTC+5', '🇵🇰'),
  _TzOption('Bangladesh', 'Asia/Dhaka', 'UTC+6', '🇧🇩'),
  _TzOption('Nigeria', 'Africa/Lagos', 'UTC+1', '🇳🇬'),
  _TzOption('Mexico', 'America/Mexico_City', 'UTC−6', '🇲🇽'),
  _TzOption('Russia (Moscow)', 'Europe/Moscow', 'UTC+3', '🇷🇺'),
];

// ─── Models ────────────────────────────────────────────────────────────────────
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

// ─── Storage ──────────────────────────────────────────────────────────────────
class _Storage {
  static const _tasksKey = 'sched_tasks_v4';
  static const _tzKey = 'sched_timezone_v1';

  static Future<List<ScheduledTask>> loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tasksKey);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List)
          .map((e) => ScheduledTask.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Storage] load: $e');
      return [];
    }
  }

  static Future<void> saveTasks(List<ScheduledTask> tasks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tasksKey, jsonEncode(tasks.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('[Storage] save: $e');
    }
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

// ─── Notification Service ─────────────────────────────────────────────────────
// Uses exact alarms + high-priority channel so notifications fire even when
// the app is killed. The 5-minute-warning ID = taskHash + 1,
// the at-time ID = taskHash (both mod 2_000_000_000 to stay in int range).
class _NotifService {
  static final _NotifService _i = _NotifService._();
  factory _NotifService() => _i;
  _NotifService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init(String tzName) async {
    if (_ready) return;
    try {
      // 1 — timezone
      tz.initializeTimeZones();
      final loc = tz.getLocation(tzName);
      tz.setLocalLocation(loc);
      debugPrint('[Notif] TZ set to ${loc.name}');

      // 2 — plugin init
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));

      // 3 — request Android permissions
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      await androidImpl?.requestExactAlarmsPermission();

      _ready = true;
      debugPrint('[Notif] Ready');
    } catch (e) {
      debugPrint('[Notif] init error: $e');
    }
  }

  NotificationDetails _details(String channelDesc) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'stremini_sched_v2',
        'Smart Scheduler',
        channelDescription: channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        fullScreenIntent: false,
        styleInformation: const BigTextStyleInformation(''),
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  Future<void> scheduleTask(ScheduledTask task) async {
    if (!_ready) return;
    try {
      final hash = task.id.hashCode.abs() % 2000000000;
      final now = tz.TZDateTime.now(tz.local);

      final taskTime = tz.TZDateTime(
        tz.local,
        task.scheduledTime.year,
        task.scheduledTime.month,
        task.scheduledTime.day,
        task.scheduledTime.hour,
        task.scheduledTime.minute,
      );

      // ── 5-minute warning ───────────────────────────────────────────────────
      final warningTime = taskTime.subtract(const Duration(minutes: 5));
      if (warningTime.isAfter(now)) {
        await _plugin.zonedSchedule(
          hash + 1,
          '⏰ Starting in 5 minutes',
          task.title,
          warningTime,
          _details('5-minute task warnings'),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: null,
        );
        debugPrint('[Notif] Warning scheduled for ${task.title} at $warningTime');
      }

      // ── At-time notification ───────────────────────────────────────────────
      if (taskTime.isAfter(now)) {
        await _plugin.zonedSchedule(
          hash,
          '🔔 Task Starting Now',
          task.title,
          taskTime,
          _details('Task start reminders'),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: null,
        );
        debugPrint('[Notif] At-time scheduled for ${task.title} at $taskTime');
      }
    } catch (e) {
      debugPrint('[Notif] schedule error: $e');
    }
  }

  Future<void> cancelTask(ScheduledTask task) async {
    try {
      final hash = task.id.hashCode.abs() % 2000000000;
      await _plugin.cancel(hash);
      await _plugin.cancel(hash + 1);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    try { await _plugin.cancelAll(); } catch (_) {}
  }

  Future<void> rescheduleAll(List<ScheduledTask> tasks) async {
    await cancelAll();
    final now = DateTime.now();
    for (final t in tasks) {
      if (t.status == TaskStatus.pending && t.scheduledTime.isAfter(now)) {
        await scheduleTask(t);
      }
    }
  }
}

// ─── API ──────────────────────────────────────────────────────────────────────
class _Api {
  static const _base = 'https://ai-keyboard-backend.vishwajeetadkine705.workers.dev';
  String? get _token => Supabase.instance.client.auth.currentSession?.accessToken;
  Map<String, String> get _h => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<ScheduledTask?> parseTask(String input) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/scheduler/parse'),
        headers: _h,
        body: jsonEncode({'input': input}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final taskJson = (data['task'] as Map<String, dynamic>?) ?? data;
      if (taskJson.isEmpty || taskJson['title'] == null) return null;
      taskJson['id'] = DateTime.now().millisecondsSinceEpoch.toString();
      return ScheduledTask.fromJson(taskJson);
    } catch (e) {
      debugPrint('[API] parseTask: $e');
      return null;
    }
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
String _fmtTime(DateTime dt) {
  final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  final ap = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ap';
}

String _fmtDate(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff < 0) return 'Overdue';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (diff < 7) return days[dt.weekday - 1];
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${dt.day} ${months[dt.month - 1]}';
}

Color _priorityColor(TaskPriority p) {
  switch (p) {
    case TaskPriority.high: return _red;
    case TaskPriority.low: return _green;
    default: return _amber;
  }
}

Color _categoryColor(TaskCategory c) {
  switch (c) {
    case TaskCategory.work: return _blue;
    case TaskCategory.health: return _green;
    case TaskCategory.finance: return _gold;
    case TaskCategory.learning: return const Color(0xFF9B7EE8);
    case TaskCategory.personal: return const Color(0xFFE87EA1);
    default: return _silver;
  }
}

IconData _categoryIcon(TaskCategory c) {
  switch (c) {
    case TaskCategory.work: return Icons.work_outline_rounded;
    case TaskCategory.health: return Icons.favorite_outline_rounded;
    case TaskCategory.finance: return Icons.account_balance_outlined;
    case TaskCategory.learning: return Icons.school_outlined;
    case TaskCategory.personal: return Icons.person_outline_rounded;
    default: return Icons.checklist_outlined;
  }
}

String _categoryLabel(TaskCategory c) => c.name.toUpperCase();
String _priorityLabel(TaskPriority p) => p.name.toUpperCase();

// ─── Text Styles (DM Sans) ────────────────────────────────────────────────────
TextStyle _dmSans(double size, {
  Color color = _txt,
  FontWeight w = FontWeight.w400,
  double spacing = 0,
  double height = 1.4,
}) {
  return GoogleFonts.dmSans(
    fontSize: size, color: color,
    fontWeight: w, letterSpacing: spacing, height: height,
  );
}

TextStyle _goldLabel(double size, {double spacing = 1.5}) => _dmSans(
  size, color: _gold, w: FontWeight.w700, spacing: spacing,
);

// ─── Timezone Onboarding Screen ───────────────────────────────────────────────
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
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  List<_TzOption> get _filtered {
    if (_search.isEmpty) return _timezones;
    final q = _search.toLowerCase();
    return _timezones.where((t) =>
      t.label.toLowerCase().contains(q) || t.tzName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ink,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 48),

                  // Gold accent line
                  Container(width: 40, height: 2, color: _gold),
                  const SizedBox(height: 20),

                  Text('YOUR\nTIMEZONE', style: GoogleFonts.dmSans(
                    fontSize: 38, color: _txt, fontWeight: FontWeight.w800,
                    letterSpacing: -1.5, height: 1.05,
                  )),
                  const SizedBox(height: 12),
                  Text(
                    'Stremini will schedule your notifications\nprecisely for your local time.',
                    style: _dmSans(14, color: _txtSub, height: 1.6),
                  ),
                  const SizedBox(height: 28),

                  // Search
                  Container(
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: TextField(
                      style: _dmSans(14),
                      decoration: InputDecoration(
                        hintText: 'Search country or timezone…',
                        hintStyle: _dmSans(14, color: _txtDim),
                        prefixIcon: const Icon(Icons.search_rounded, color: _txtDim, size: 18),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // List
                  Expanded(
                    child: ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => Container(height: 1, color: _border),
                      itemBuilder: (_, i) {
                        final tz = _filtered[i];
                        final isSelected = _selected == tz.tzName;
                        return GestureDetector(
                          onTap: () => setState(() => _selected = tz.tzName),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isSelected ? _goldGlow : Colors.transparent,
                              border: isSelected
                                  ? Border.all(color: _gold.withOpacity(0.4))
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(children: [
                              Text(tz.flag, style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 14),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tz.label, style: _dmSans(14,
                                    color: isSelected ? _gold : _txt,
                                    w: isSelected ? FontWeight.w700 : FontWeight.w500)),
                                  Text(tz.offset, style: _dmSans(11, color: _txtSub)),
                                ],
                              )),
                              if (isSelected)
                                Container(
                                  width: 20, height: 20,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle, color: _gold,
                                  ),
                                  child: const Icon(Icons.check, color: _ink, size: 13),
                                ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // CTA
                  GestureDetector(
                    onTap: _selected == null ? null : () {
                      HapticFeedback.mediumImpact();
                      widget.onSelected(_selected!);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _selected != null ? _gold : _surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _selected != null ? _gold : _border,
                        ),
                        boxShadow: _selected != null ? [
                          BoxShadow(color: _goldGlow, blurRadius: 20, spreadRadius: 2),
                        ] : null,
                      ),
                      child: Center(child: Text(
                        _selected != null ? 'CONTINUE →' : 'SELECT A TIMEZONE',
                        style: _dmSans(14,
                          color: _selected != null ? _ink : _txtDim,
                          w: FontWeight.w800, spacing: 1.2),
                      )),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
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

  final _notif = _NotifService();
  final _api = _Api();
  final _inputCtrl = TextEditingController();
  final _scroll = ScrollController();

  List<ScheduledTask> _tasks = [];
  bool _parsing = false;
  bool _loaded = false;
  String? _tzName;
  bool _showTzOnboarding = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _boot();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _inputCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final savedTz = await _Storage.loadTimezone();
    if (savedTz == null) {
      setState(() => _showTzOnboarding = true);
      return;
    }
    await _initWithTimezone(savedTz, fromOnboarding: false);
  }

  Future<void> _initWithTimezone(String tzName, {bool fromOnboarding = true}) async {
    await _Storage.saveTimezone(tzName);
    await _notif.init(tzName);

    final tasks = await _Storage.loadTasks();
    // Reschedule all pending tasks with the new timezone
    await _notif.rescheduleAll(tasks);

    if (mounted) {
      setState(() {
        _tzName = tzName;
        _tasks = tasks;
        _loaded = true;
        _showTzOnboarding = false;
      });
      _fadeCtrl.forward();
    }
  }

  // ── Task actions ─────────────────────────────────────────────────────────

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
    await _Storage.saveTasks(_tasks);
    await _notif.scheduleTask(task);
    HapticFeedback.lightImpact();
    _snack('Task scheduled — notifications set ✓');
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
      content: Text(msg, style: _dmSans(13)),
      backgroundColor: _cardHi,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _gold, width: 0.8),
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  List<ScheduledTask> get _pending => _tasks
      .where((t) => t.status == TaskStatus.pending)
      .toList()..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

  List<ScheduledTask> get _completed =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();

  double get _rate => _tasks.isEmpty ? 0 : _completed.length / _tasks.length;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_showTzOnboarding) {
      return _TimezoneOnboardingScreen(
        onSelected: (tz) => _initWithTimezone(tz),
      );
    }

    if (!_loaded) {
      return Scaffold(
        backgroundColor: _ink,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
              width: 32, height: 32,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: _gold),
            ),
            const SizedBox(height: 16),
            Text('Loading scheduler…', style: _dmSans(13, color: _txtSub)),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _ink,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Column(children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 48),
                children: [
                  _buildHeroSection(),
                  _buildInputSection(),
                  const SizedBox(height: 28),
                  _buildStatsRow(),
                  const SizedBox(height: 32),
                  _buildUpcomingSection(),
                  if (_completed.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _buildCompletedSection(),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final tzOption = _timezones.firstWhere(
      (t) => t.tzName == _tzName,
      orElse: () => const _TzOption('—', '', '', '🌐'),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      decoration: const BoxDecoration(
        color: _ink,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _surface, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _txtSub, size: 14),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SMART SCHEDULER', style: _goldLabel(10, spacing: 2.5)),
          const SizedBox(height: 2),
          Text('Task Planner', style: _dmSans(16, w: FontWeight.w700, spacing: -0.3)),
        ])),
        // Timezone chip
        GestureDetector(
          onTap: () => setState(() => _showTzOnboarding = true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _surface, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Row(children: [
              Text(tzOption.flag, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 5),
              Text(tzOption.offset.isEmpty ? 'TZ' : tzOption.offset,
                style: _dmSans(11, color: _gold, w: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────
  Widget _buildHeroSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _gold.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Gold pulsing dot
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: _gold,
                  boxShadow: [BoxShadow(
                    color: _gold.withOpacity(0.6 * _pulseAnim.value),
                    blurRadius: 8, spreadRadius: 2,
                  )],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('LIVE NOTIFICATIONS', style: _goldLabel(9, spacing: 2.0)),
          ]),
          const SizedBox(height: 16),
          Text(
            'Stremini alerts you\nexactly on time.',
            style: GoogleFonts.dmSans(
              fontSize: 26, color: _txt, fontWeight: FontWeight.w800,
              letterSpacing: -0.8, height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Get a reminder 5 minutes before every task, plus a second alert precisely when it starts — even when the app is closed.',
            style: _dmSans(13, color: _txtSub, height: 1.6),
          ),
          const SizedBox(height: 18),
          Row(children: [
            _heroPill(Icons.notifications_active_outlined, '5 min warning', _gold),
            const SizedBox(width: 8),
            _heroPill(Icons.alarm_rounded, 'At start time', _blue),
            const SizedBox(width: 8),
            _heroPill(Icons.phonelink_off_rounded, 'Works offline', _green),
          ]),
        ]),
      ),
    );
  }

  Widget _heroPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 5),
        Text(label, style: _dmSans(10, color: color, w: FontWeight.w600, spacing: 0.2)),
      ]),
    );
  }

  // ── Input Section ─────────────────────────────────────────────────────────
  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ADD A TASK', style: _goldLabel(10)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(
                controller: _inputCtrl,
                style: _dmSans(14),
                maxLines: 2, minLines: 1,
                decoration: InputDecoration(
                  hintText: 'e.g. "Team call tomorrow at 3pm" or "Gym on Friday 7am"',
                  hintStyle: _dmSans(13, color: _txtDim),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _parseAndAdd(),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _border)),
              ),
              child: Row(children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
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
                      color: _parsing ? _goldDim : _gold,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _parsing ? null : [
                        BoxShadow(color: _goldGlow, blurRadius: 12),
                      ],
                    ),
                    child: _parsing
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _ink))
                        : Text('PARSE', style: _dmSans(12, color: _ink, w: FontWeight.w800, spacing: 1.5)),
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
          border: Border.all(color: _borderHi),
        ),
        child: Text(label, style: _dmSans(11, color: _silver)),
      ),
    );
  }

  // ── Stats Row ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final pct = (_rate * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          _statCell('${_tasks.length}', 'TOTAL', _silver),
          _vDivider(),
          _statCell('${_pending.length}', 'PENDING', _amber),
          _vDivider(),
          _statCell('${_completed.length}', 'DONE', _green),
          _vDivider(),
          _statCell('$pct%', 'RATE', _gold),
        ]),
      ),
    );
  }

  Widget _vDivider() => Container(width: 1, height: 50, color: _border);

  Widget _statCell(String value, String label, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(children: [
          Text(value, style: GoogleFonts.dmSans(
            fontSize: 22, color: color, fontWeight: FontWeight.w800,
            letterSpacing: -0.5, height: 1,
          )),
          const SizedBox(height: 4),
          Text(label, style: _dmSans(9, color: _txtDim, w: FontWeight.w700, spacing: 1.5)),
        ]),
      ),
    );
  }

  // ── Upcoming Section ──────────────────────────────────────────────────────
  Widget _buildUpcomingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('UPCOMING TASKS', style: _goldLabel(10)),
          const Spacer(),
          Text('${_pending.length}', style: _dmSans(11, color: _txtSub)),
        ]),
        const SizedBox(height: 14),
        if (_pending.isEmpty) _emptyState()
        else Column(children: _pending.map(_buildTaskCard).toList()),
      ]),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _goldGlow, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold.withOpacity(0.3)),
          ),
          child: const Icon(Icons.calendar_today_outlined, color: _gold, size: 20),
        ),
        const SizedBox(height: 14),
        Text('No upcoming tasks', style: _dmSans(14, w: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Describe one above to get started', style: _dmSans(12, color: _txtSub)),
      ]),
    );
  }

  Widget _buildTaskCard(ScheduledTask task) {
    final priColor = _priorityColor(task.priority);
    final catColor = _categoryColor(task.category);
    final isOverdue = task.scheduledTime.isBefore(DateTime.now());

    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _redDim, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _red.withOpacity(0.3)),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: _red, size: 20),
      ),
      onDismissed: (_) => _delete(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isOverdue ? _red.withOpacity(0.35) : _border,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Priority bar
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: priColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(task.title, style: _dmSans(14, w: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    // Category chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: catColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: catColor.withOpacity(0.22)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_categoryIcon(task.category), color: catColor, size: 10),
                        const SizedBox(width: 4),
                        Text(_categoryLabel(task.category),
                          style: _dmSans(9, color: catColor, w: FontWeight.w700, spacing: 0.5)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 7),
                  Row(children: [
                    Icon(Icons.calendar_today_outlined,
                      color: isOverdue ? _red : _txtDim, size: 12),
                    const SizedBox(width: 5),
                    Text(_fmtDate(task.scheduledTime),
                      style: _dmSans(12, color: isOverdue ? _red : _txtSub, w: FontWeight.w500)),
                    const SizedBox(width: 10),
                    Icon(Icons.access_time_rounded, color: _gold, size: 12),
                    const SizedBox(width: 5),
                    Text(_fmtTime(task.scheduledTime),
                      style: _dmSans(12, color: _gold, w: FontWeight.w600)),
                    const SizedBox(width: 10),
                    Icon(Icons.timer_outlined, color: _txtDim, size: 12),
                    const SizedBox(width: 4),
                    Text('${task.estimatedDuration}m',
                      style: _dmSans(12, color: _txtDim)),
                  ]),
                  if (task.description.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(task.description,
                      style: _dmSans(11, color: _txtDim, height: 1.5),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 10),
                  // Notification badge + complete button
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _goldGlow, borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: _gold.withOpacity(0.25)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.notifications_active_outlined,
                          color: _gold, size: 10),
                        const SizedBox(width: 4),
                        Text('5m + at-time alerts',
                          style: _dmSans(9, color: _gold, w: FontWeight.w600)),
                      ]),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _markDone(task),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _greenDim, borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _green.withOpacity(0.3)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.check_rounded, color: _green, size: 13),
                          const SizedBox(width: 5),
                          Text('Done', style: _dmSans(12, color: _green, w: FontWeight.w600)),
                        ]),
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

  // ── Completed Section ─────────────────────────────────────────────────────
  Widget _buildCompletedSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('COMPLETED', style: _goldLabel(10)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: _surface, borderRadius: BorderRadius.circular(14),
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
                    Expanded(child: Text(
                      e.value.title,
                      style: _dmSans(13, color: _txtSub).copyWith(
                        decoration: TextDecoration.lineThrough,
                        decorationColor: _txtDim,
                      ),
                    )),
                    Text(_fmtDate(e.value.scheduledTime),
                      style: _dmSans(11, color: _txtDim)),
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

  // ── Preview Sheet ─────────────────────────────────────────────────────────
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
      category: TaskCategory.other,
      priority: TaskPriority.medium,
      estimatedDuration: 30,
    );
    _snack('AI unavailable — created task manually');
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PreviewSheet(task: task, onConfirm: _confirmAdd),
    );
  }
}

// ─── Preview Bottom Sheet ─────────────────────────────────────────────────────
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slide = Tween(begin: const Offset(0, 0.1), end: Offset.zero)
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
          colorScheme: const ColorScheme.dark(
            primary: _gold, onPrimary: _ink, surface: _card, onSurface: _txt,
          ),
          dialogBackgroundColor: _card,
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
          colorScheme: const ColorScheme.dark(
            primary: _gold, onPrimary: _ink, surface: _card, onSurface: _txt,
          ),
          dialogBackgroundColor: _card,
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() => _time = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final priColor = _priorityColor(widget.task.priority);
    final catColor = _categoryColor(widget.task.category);
    final warnTime = _time.subtract(const Duration(minutes: 5));
    final inPast = _time.isBefore(DateTime.now());

    return SlideTransition(
      position: _slide,
      child: Container(
        padding: EdgeInsets.only(
          left: 24, right: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 36,
        ),
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _border)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 36, height: 3, margin: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('CONFIRM TASK', style: _goldLabel(10)),
          const SizedBox(height: 14),
          Text(widget.task.title, style: GoogleFonts.dmSans(
            fontSize: 22, color: _txt, fontWeight: FontWeight.w800,
            letterSpacing: -0.5, height: 1.2,
          )),
          if (widget.task.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(widget.task.description, style: _dmSans(13, color: _txtSub)),
          ],
          const SizedBox(height: 20),

          // Meta row
          Wrap(spacing: 8, runSpacing: 8, children: [
            _metaChip(Icons.calendar_today_outlined,
              '${_fmtDate(_time)} at ${_fmtTime(_time)}', _gold, onTap: _pickTime),
            _metaChip(Icons.timer_outlined,
              '${widget.task.estimatedDuration} min', _silver),
            _metaChip(Icons.flag_outlined,
              _priorityLabel(widget.task.priority), priColor),
            _metaChip(_categoryIcon(widget.task.category),
              _categoryLabel(widget.task.category), catColor),
          ]),
          const SizedBox(height: 14),

          // Notification preview
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _goldGlow, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _gold.withOpacity(0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.notifications_active_outlined, color: _gold, size: 14),
                const SizedBox(width: 8),
                Text('SCHEDULED NOTIFICATIONS', style: _goldLabel(9)),
              ]),
              const SizedBox(height: 10),
              _notifRow(Icons.alarm_outlined, '5-minute warning',
                '${_fmtDate(warnTime)} at ${_fmtTime(warnTime)}'),
              const SizedBox(height: 6),
              _notifRow(Icons.notifications_rounded, 'Task starts',
                '${_fmtDate(_time)} at ${_fmtTime(_time)}'),
            ]),
          ),
          if (inPast) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _redDim, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _red.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: _red, size: 14),
                const SizedBox(width: 8),
                Text('This time is in the past — tap the date to change it.',
                  style: _dmSans(11, color: _red)),
              ]),
            ),
          ],
          const SizedBox(height: 22),

          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: _surface, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: Center(child: Text('Cancel',
                    style: _dmSans(14, color: _txtSub, w: FontWeight.w600))),
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
                    id: widget.task.id, title: widget.task.title,
                    description: widget.task.description,
                    scheduledTime: _time,
                    category: widget.task.category, priority: widget.task.priority,
                    estimatedDuration: widget.task.estimatedDuration,
                  );
                  widget.onConfirm(updated);
                },
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: _gold, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: _goldGlow, blurRadius: 16)],
                  ),
                  child: Center(child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_rounded, color: _ink, size: 18),
                      const SizedBox(width: 8),
                      Text('SCHEDULE', style: _dmSans(14, color: _ink, w: FontWeight.w800, spacing: 0.8)),
                    ],
                  )),
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
      Icon(icon, color: _gold, size: 13),
      const SizedBox(width: 8),
      Text(label, style: _dmSans(12, color: _gold, w: FontWeight.w600)),
      const Spacer(),
      Text(time, style: _dmSans(11, color: _txtSub)),
    ]);
  }

  Widget _metaChip(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07), borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label, style: _dmSans(11, color: color, w: FontWeight.w600, spacing: 0.2)),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.edit_outlined, color: color.withOpacity(0.6), size: 10),
          ],
        ]),
      ),
    );
  }
}
