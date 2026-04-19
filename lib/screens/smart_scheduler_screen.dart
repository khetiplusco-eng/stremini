// smart_scheduler_screen.dart — REDESIGNED to match app design system
// Design: Dark editorial — consistent with home_screen.dart & chat_screen.dart
// Tokens, typography, card styles, permission rows all match the existing app.
// No emoji usage anywhere. Structured, professional, premium.
// ALL LOGIC PRESERVED from original.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ── Design tokens — exact match to home_screen.dart ──────────────────────────
const _bg        = Color(0xFF080A0C);
const _surface   = Color(0xFF0E1114);
const _card      = Color(0xFF131619);
const _cardHi    = Color(0xFF1A1E24);
const _border    = Color(0xFF1E2328);
const _borderHi  = Color(0xFF2A3038);
const _accent    = Color(0xFF23A6E2);
const _accentDim = Color(0xFF0D2A3A);
const _green     = Color(0xFF22C55E);
const _greenDim  = Color(0xFF0D2818);
const _red       = Color(0xFFEF4444);
const _redDim    = Color(0xFF1A0808);
const _amber     = Color(0xFFF59E0B);
const _amberDim  = Color(0xFF1E1604);
const _purple    = Color(0xFF8B5CF6);
const _txt       = Color(0xFFF0F2F5);
const _txtSub    = Color(0xFF8A95A3);
const _txtDim    = Color(0xFF454E5A);

// ── Typography helpers — mirrors home_screen.dart ────────────────────────────
TextStyle _label(double size,
        {Color color = _txtDim,
        FontWeight w = FontWeight.w600,
        double spacing = 1.2}) =>
    TextStyle(
        fontSize: size,
        color: color,
        fontWeight: w,
        letterSpacing: spacing,
        height: 1.0);

TextStyle _body(double size,
        {Color color = _txt, FontWeight w = FontWeight.w400}) =>
    TextStyle(fontSize: size, color: color, fontWeight: w, height: 1.5);

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
      id: j['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: j['title']?.toString() ?? 'Untitled Task',
      description: j['description']?.toString() ?? '',
      scheduledTime: parseTime(j['scheduledTime'] ?? j['scheduled_time'] ?? j['time']),
      category: parseCategory(j['category']?.toString()),
      priority: parsePriority(j['priority']?.toString()),
      estimatedDuration: (j['estimatedDuration'] as num?)?.toInt() ?? 30,
      status: j['status']?.toString() == 'completed'
          ? TaskStatus.completed
          : TaskStatus.pending,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'scheduledTime': scheduledTime.toIso8601String(),
        'category': category.name,
        'priority': priority.name,
        'estimatedDuration': estimatedDuration,
        'status': status.name,
      };
}

// ─── Storage ──────────────────────────────────────────────────────────────────
class _Storage {
  static const _tasksKey = 'sched_tasks_v4';
  static const _tzKey    = 'sched_timezone_v1';

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
      await prefs.setString(
          _tasksKey, jsonEncode(tasks.map((t) => t.toJson()).toList()));
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
class _NotifService {
  static final _NotifService _i = _NotifService._();
  factory _NotifService() => _i;
  _NotifService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready   = false;

  Future<void> init(String tzName) async {
    if (_ready) return;
    try {
      tz.initializeTimeZones();
      final loc = tz.getLocation(tzName);
      tz.setLocalLocation(loc);

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
          const InitializationSettings(android: android, iOS: ios));

      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      await androidImpl?.requestExactAlarmsPermission();

      _ready = true;
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
      final hash    = task.id.hashCode.abs() % 2000000000;
      final now     = tz.TZDateTime.now(tz.local);
      final taskTime = tz.TZDateTime(
        tz.local,
        task.scheduledTime.year,
        task.scheduledTime.month,
        task.scheduledTime.day,
        task.scheduledTime.hour,
        task.scheduledTime.minute,
      );

      final warningTime = taskTime.subtract(const Duration(minutes: 5));
      if (warningTime.isAfter(now)) {
        await _plugin.zonedSchedule(
          hash + 1,
          'Starting in 5 minutes',
          task.title,
          warningTime,
          _details('5-minute task warnings'),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: null,
        );
      }

      if (taskTime.isAfter(now)) {
        await _plugin.zonedSchedule(
          hash,
          'Task Starting Now',
          task.title,
          taskTime,
          _details('Task start reminders'),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: null,
        );
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
    try {
      await _plugin.cancelAll();
    } catch (_) {}
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
  static const _base =
      'https://ai-keyboard-backend.vishwajeetadkine705.workers.dev';
  String? get _token =>
      Supabase.instance.client.auth.currentSession?.accessToken;
  Map<String, String> get _h => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<ScheduledTask?> parseTask(String input) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/scheduler/parse'),
            headers: _h,
            body: jsonEncode({'input': input}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final data    = jsonDecode(res.body) as Map<String, dynamic>;
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
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

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
    case TaskCategory.personal: return const Color(0xFFE87EA1);
    default:                    return _txtSub;
  }
}

IconData _categoryIcon(TaskCategory c) {
  switch (c) {
    case TaskCategory.work:     return Icons.work_outline_rounded;
    case TaskCategory.health:   return Icons.favorite_border_rounded;
    case TaskCategory.finance:  return Icons.account_balance_outlined;
    case TaskCategory.learning: return Icons.school_outlined;
    case TaskCategory.personal: return Icons.person_outline_rounded;
    default:                    return Icons.checklist_rounded;
  }
}

String _categoryLabel(TaskCategory c) => c.name[0].toUpperCase() + c.name.substring(1);
String _priorityLabel(TaskPriority p) => p.name[0].toUpperCase() + p.name.substring(1);

// ─── Timezone Onboarding ──────────────────────────────────────────────────────
class _TimezoneOnboardingScreen extends StatefulWidget {
  final void Function(String tzName) onSelected;
  const _TimezoneOnboardingScreen({required this.onSelected});

  @override
  State<_TimezoneOnboardingScreen> createState() =>
      _TimezoneOnboardingScreenState();
}

class _TimezoneOnboardingScreenState extends State<_TimezoneOnboardingScreen>
    with SingleTickerProviderStateMixin {
  String? _selected;
  String _search = '';
  late AnimationController _ctrl;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<_TzOption> get _filtered {
    if (_search.isEmpty) return _timezones;
    final q = _search.toLowerCase();
    return _timezones
        .where((t) =>
            t.label.toLowerCase().contains(q) ||
            t.tzName.toLowerCase().contains(q) ||
            t.region.toLowerCase().contains(q))
        .toList();
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
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: _txtSub, size: 14),
                ),
              )
            : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: FadeTransition(
        opacity: _fade,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SELECT TIMEZONE',
                      style: _label(10, color: _accent, spacing: 2.5)),
                  const SizedBox(height: 8),
                  Text('Your local timezone',
                      style: _body(26,
                          w: FontWeight.w800).copyWith(letterSpacing: -0.8)),
                  const SizedBox(height: 6),
                  Text(
                    'Notifications will fire precisely at your local time.',
                    style: _body(13, color: _txtSub),
                  ),
                  const SizedBox(height: 20),

                  // ── Search ────────────────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: TextField(
                      style: _body(14),
                      decoration: InputDecoration(
                        hintText: 'Search country or region…',
                        hintStyle: _body(14, color: _txtDim),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: _txtDim, size: 17),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // ── List ───────────────────────────────────────────────────────
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                itemCount: _filtered.length,
                separatorBuilder: (_, __) =>
                    Container(height: 1, color: _border),
                itemBuilder: (_, i) {
                  final tz       = _filtered[i];
                  final selected = _selected == tz.tzName;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = tz.tzName),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected
                            ? _accent.withOpacity(0.06)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: selected ? _accentDim : _surface,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: selected
                                  ? _accent.withOpacity(0.3)
                                  : _border,
                            ),
                          ),
                          child: Icon(Icons.language_rounded,
                              color: selected ? _accent : _txtDim, size: 16),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tz.label,
                                  style: _body(13,
                                      color: selected ? _txt : _txtSub,
                                      w: selected
                                          ? FontWeight.w600
                                          : FontWeight.w400)),
                              Text(tz.offset,
                                  style: _label(10,
                                      color: selected ? _accent : _txtDim,
                                      spacing: 0)),
                            ],
                          ),
                        ),
                        if (selected)
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _accent,
                            ),
                            child: const Icon(Icons.check,
                                color: Colors.white, size: 12),
                          ),
                      ]),
                    ),
                  );
                },
              ),
            ),

            // ── CTA ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
              child: GestureDetector(
                onTap: _selected == null
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        widget.onSelected(_selected!);
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _selected != null ? _accent : _surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _selected != null
                            ? _accent
                            : _border),
                  ),
                  child: Center(
                    child: Text(
                      _selected != null
                          ? 'Confirm Timezone'
                          : 'Select a timezone above',
                      style: _body(14,
                          color: _selected != null ? Colors.white : _txtDim,
                          w: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
  final _notif     = _NotifService();
  final _api       = _Api();
  final _inputCtrl = TextEditingController();
  final _scroll    = ScrollController();

  List<ScheduledTask> _tasks        = [];
  bool _parsing                     = false;
  bool _loaded                      = false;
  String? _tzName;
  bool _showTzOnboarding            = false;

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _boot();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
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

  Future<void> _initWithTimezone(String tzName,
      {bool fromOnboarding = true}) async {
    await _Storage.saveTimezone(tzName);
    await _notif.init(tzName);
    final tasks = await _Storage.loadTasks();
    await _notif.rescheduleAll(tasks);
    if (mounted) {
      setState(() {
        _tzName             = tzName;
        _tasks              = tasks;
        _loaded             = true;
        _showTzOnboarding   = false;
      });
      _fadeCtrl.forward();
    }
  }

  // ── Task actions ──────────────────────────────────────────────────────────

  Future<void> _parseAndAdd() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty) {
      _snack('Describe a task first');
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
      _showManualCreate(input);
    }
  }

  void _confirmAdd(ScheduledTask task) async {
    setState(() => _tasks.add(task));
    await _Storage.saveTasks(_tasks);
    await _notif.scheduleTask(task);
    HapticFeedback.lightImpact();
    _snack('Task scheduled — notifications active');
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
      content: Text(msg,
          style: const TextStyle(color: _txt, fontSize: 13)),
      backgroundColor: _card,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: _border),
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  List<ScheduledTask> get _pending => _tasks
      .where((t) => t.status == TaskStatus.pending)
      .toList()
    ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

  List<ScheduledTask> get _completed =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();

  double get _rate =>
      _tasks.isEmpty ? 0 : _completed.length / _tasks.length;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_showTzOnboarding) {
      return _TimezoneOnboardingScreen(
          onSelected: (tz) => _initWithTimezone(tz));
    }

    if (!_loaded) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(_accent)),
            ),
            const SizedBox(height: 16),
            Text('Loading scheduler…',
                style: _body(13, color: _txtSub)),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 60),
          children: [
            _buildStatsRow(),
            const SizedBox(height: 24),
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

  // ── AppBar — mirrors home_screen.dart top bar style ───────────────────────
  PreferredSizeWidget _buildAppBar() {
    final tzOption = _timezones.firstWhere(
      (t) => t.tzName == _tzName,
      orElse: () => const _TzOption('Unknown', '', '', ''),
    );

    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: _txtSub, size: 14),
          ),
        ),
      ),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Smart Scheduler',
            style: _body(15, w: FontWeight.w700)
                .copyWith(letterSpacing: -0.2)),
        Text('AI Task Planner',
            style: _label(10, color: _txtDim, spacing: 0.5)),
      ]),
      actions: [
        // Timezone chip — tappable to change
        GestureDetector(
          onTap: () => setState(() => _showTzOnboarding = true),
          child: Container(
            margin: const EdgeInsets.fromLTRB(0, 10, 14, 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.language_rounded, color: _txtDim, size: 12),
              const SizedBox(width: 5),
              Text(tzOption.offset.isEmpty ? 'TZ' : tzOption.offset,
                  style: _label(11, color: _accent, spacing: 0)),
            ]),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  // ── Stats Row — mirrors home module card grid ─────────────────────────────
  Widget _buildStatsRow() {
    final pct = (_rate * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
      child: Row(children: [
        _statCard('${_tasks.length}', 'Total', _txtSub),
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  color: color,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.0)),
          const SizedBox(height: 4),
          Text(label, style: _label(10, spacing: 0)),
        ]),
      ),
    );
  }

  // ── Input Section ─────────────────────────────────────────────────────────
  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ADD TASK', style: _label(10, spacing: 2.5)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Column(children: [
            // Text input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(
                controller: _inputCtrl,
                style: _body(14),
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  hintText:
                      'e.g. "Team call tomorrow at 3pm" or "Gym Friday 7am"',
                  hintStyle: _body(13, color: _txtDim),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 16),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _parseAndAdd(),
              ),
            ),
            // Bottom row: chips + parse button
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                  border:
                      Border(top: BorderSide(color: _border))),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: _parsing
                          ? _accentDim
                          : _accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _parsing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white)),
                          )
                        : Text('Parse',
                            style: _body(13,
                                w: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ]),
        ),

        const SizedBox(height: 14),

        // Info row — notification behaviour
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _accentDim,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: _accent.withOpacity(0.2)),
              ),
              child: const Icon(Icons.notifications_active_outlined,
                  color: _accent, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Two alerts per task',
                        style: _body(13, w: FontWeight.w600)),
                    Text(
                        '5-minute warning + at-time alert, works when app is closed.',
                        style: _label(11, spacing: 0)),
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
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _borderHi),
        ),
        child: Text(label, style: _label(11, color: _txtSub, spacing: 0)),
      ),
    );
  }

  // ── Upcoming Section ──────────────────────────────────────────────────────
  Widget _buildUpcomingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('UPCOMING', style: _label(10, spacing: 2.5)),
          const Spacer(),
          Text('${_pending.length} task${_pending.length == 1 ? '' : 's'}',
              style: _label(10, spacing: 0)),
        ]),
        const SizedBox(height: 14),
        if (_pending.isEmpty)
          _emptyState()
        else
          Column(
              children: _pending.map(_buildTaskCard).toList()),
      ]),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _accentDim,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: _accent.withOpacity(0.2)),
          ),
          child: const Icon(Icons.calendar_today_outlined,
              color: _accent, size: 18),
        ),
        const SizedBox(height: 12),
        Text('No upcoming tasks', style: _body(14, w: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Describe a task above to get started',
            style: _label(11, spacing: 0)),
      ]),
    );
  }

  Widget _buildTaskCard(ScheduledTask task) {
    final priColor  = _priorityColor(task.priority);
    final catColor  = _categoryColor(task.category);
    final isOverdue = task.scheduledTime.isBefore(DateTime.now());

    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _redDim,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _red.withOpacity(0.3)),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: _red, size: 18),
      ),
      onDismissed: (_) => _delete(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isOverdue ? _red.withOpacity(0.3) : _border,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Priority accent bar — left edge
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: priColor,
                borderRadius: const BorderRadius.only(
                  topLeft:    Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + category chip
                      Row(children: [
                        Expanded(
                          child: Text(task.title,
                              style: _body(14, w: FontWeight.w700)),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: catColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: catColor.withOpacity(0.2)),
                          ),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_categoryIcon(task.category),
                                    color: catColor, size: 11),
                                const SizedBox(width: 4),
                                Text(_categoryLabel(task.category),
                                    style: _label(9,
                                        color: catColor, spacing: 0.4)),
                              ]),
                        ),
                      ]),

                      const SizedBox(height: 8),

                      // Date / time / duration row
                      Row(children: [
                        Icon(Icons.calendar_today_outlined,
                            color: isOverdue ? _red : _txtDim, size: 12),
                        const SizedBox(width: 5),
                        Text(_fmtDate(task.scheduledTime),
                            style: _label(12,
                                color: isOverdue ? _red : _txtSub,
                                spacing: 0)),
                        const SizedBox(width: 12),
                        Icon(Icons.access_time_rounded,
                            color: _accent, size: 12),
                        const SizedBox(width: 5),
                        Text(_fmtTime(task.scheduledTime),
                            style: _label(12,
                                color: _accent,
                                w: FontWeight.w700,
                                spacing: 0)),
                        const SizedBox(width: 12),
                        Icon(Icons.timer_outlined,
                            color: _txtDim, size: 12),
                        const SizedBox(width: 4),
                        Text('${task.estimatedDuration} min',
                            style: _label(12, spacing: 0)),
                      ]),

                      if (task.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(task.description,
                            style: _label(11, spacing: 0),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],

                      const SizedBox(height: 12),

                      // Notif badge + priority + done button
                      Row(children: [
                        // Priority badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: priColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                color: priColor.withOpacity(0.2)),
                          ),
                          child: Text(_priorityLabel(task.priority),
                              style: _label(9,
                                  color: priColor, spacing: 0.5)),
                        ),
                        const SizedBox(width: 8),
                        // Notification badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: _accentDim,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                color: _accent.withOpacity(0.2)),
                          ),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                    Icons.notifications_active_outlined,
                                    color: _accent,
                                    size: 10),
                                const SizedBox(width: 4),
                                Text('Alerts set',
                                    style: _label(9,
                                        color: _accent, spacing: 0.3)),
                              ]),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _markDone(task),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _greenDim,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _green.withOpacity(0.25)),
                            ),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_rounded,
                                      color: _green, size: 13),
                                  const SizedBox(width: 5),
                                  Text('Done',
                                      style: _label(12,
                                          color: _green,
                                          w: FontWeight.w700,
                                          spacing: 0)),
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
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('COMPLETED', style: _label(10, spacing: 2.5)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: _completed.take(5).toList().asMap().entries.map((e) {
              final isLast = e.key == (_completed.take(5).length - 1);
              final task   = e.value;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  child: Row(children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _greenDim,
                        border: Border.all(
                            color: _green.withOpacity(0.35)),
                      ),
                      child: const Icon(Icons.check,
                          color: _green, size: 11),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        task.title,
                        style: _label(13,
                                color: _txtDim, spacing: 0)
                            .copyWith(
                          decoration: TextDecoration.lineThrough,
                          decorationColor: _txtDim,
                        ),
                      ),
                    ),
                    Text(_fmtDate(task.scheduledTime),
                        style: _label(10, spacing: 0)),
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

  // ── Preview / manual sheet ────────────────────────────────────────────────
  void _showPreview(ScheduledTask task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PreviewSheet(task: task, onConfirm: _confirmAdd),
    );
  }

  void _showManualCreate(String title) {
    final t    = DateTime.now().add(const Duration(days: 1));
    final task = ScheduledTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: '',
      scheduledTime: DateTime(t.year, t.month, t.day, 9),
      category: TaskCategory.other,
      priority: TaskPriority.medium,
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
  late DateTime          _time;
  late AnimationController _ctrl;
  late Animation<Offset>   _slide;

  @override
  void initState() {
    super.initState();
    _time  = widget.task.scheduledTime;
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _slide = Tween(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            onPrimary: Colors.white,
            surface: _card,
            onSurface: _txt,
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
            primary: _accent,
            onPrimary: Colors.white,
            surface: _card,
            onSurface: _txt,
          ),
          dialogBackgroundColor: _card,
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() => _time = DateTime(
        date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final priColor  = _priorityColor(widget.task.priority);
    final catColor  = _categoryColor(widget.task.category);
    final warnTime  = _time.subtract(const Duration(minutes: 5));
    final inPast    = _time.isBefore(DateTime.now());

    return SlideTransition(
      position: _slide,
      child: Container(
        padding: EdgeInsets.only(
          left: 22,
          right: 22,
          bottom: MediaQuery.of(context).viewInsets.bottom + 36,
        ),
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: _border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 32,
                height: 3,
                margin: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text('CONFIRM TASK', style: _label(10, color: _accent, spacing: 2.5)),
            const SizedBox(height: 12),

            Text(widget.task.title,
                style: _body(20, w: FontWeight.w800)
                    .copyWith(letterSpacing: -0.5)),
            if (widget.task.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(widget.task.description,
                  style: _body(13, color: _txtSub)),
            ],

            const SizedBox(height: 18),

            // Meta chips
            Wrap(spacing: 8, runSpacing: 8, children: [
              _metaChip(Icons.calendar_today_outlined,
                  '${_fmtDate(_time)}  ${_fmtTime(_time)}', _accent,
                  onTap: _pickTime),
              _metaChip(Icons.timer_outlined,
                  '${widget.task.estimatedDuration} min', _txtSub),
              _metaChip(Icons.flag_outlined,
                  _priorityLabel(widget.task.priority), priColor),
              _metaChip(_categoryIcon(widget.task.category),
                  _categoryLabel(widget.task.category), catColor),
            ]),

            const SizedBox(height: 16),

            // Notification preview block
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _accentDim,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent.withOpacity(0.2)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.notifications_active_outlined,
                          color: _accent, size: 14),
                      const SizedBox(width: 8),
                      Text('SCHEDULED NOTIFICATIONS',
                          style: _label(9, color: _accent, spacing: 1.5)),
                    ]),
                    const SizedBox(height: 12),
                    _notifRow(Icons.alarm_outlined, '5-minute warning',
                        '${_fmtDate(warnTime)}  ${_fmtTime(warnTime)}'),
                    const SizedBox(height: 8),
                    _notifRow(Icons.notifications_rounded, 'Task starts',
                        '${_fmtDate(_time)}  ${_fmtTime(_time)}'),
                  ]),
            ),

            if (inPast) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _redDim,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _red.withOpacity(0.25)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: _red, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'This time is in the past. Tap the date above to update.',
                        style: _body(12, color: _red)),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 20),

            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: Center(
                        child: Text('Cancel',
                            style: _body(14,
                                color: _txtSub,
                                w: FontWeight.w600))),
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
                      id: widget.task.id,
                      title: widget.task.title,
                      description: widget.task.description,
                      scheduledTime: _time,
                      category: widget.task.category,
                      priority: widget.task.priority,
                      estimatedDuration: widget.task.estimatedDuration,
                    );
                    widget.onConfirm(updated);
                  },
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_rounded,
                              color: Colors.white, size: 17),
                          const SizedBox(width: 8),
                          Text('Schedule Task',
                              style: _body(14, w: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _notifRow(IconData icon, String label, String time) {
    return Row(children: [
      Icon(icon, color: _accent, size: 13),
      const SizedBox(width: 8),
      Text(label, style: _label(12, color: _accent, spacing: 0)),
      const Spacer(),
      Text(time, style: _label(11, spacing: 0)),
    ]);
  }

  Widget _metaChip(IconData icon, String label, Color color,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label, style: _label(11, color: color, spacing: 0.2)),
          if (onTap != null) ...[
            const SizedBox(width: 5),
            Icon(Icons.edit_outlined,
                color: color.withOpacity(0.5), size: 10),
          ],
        ]),
      ),
    );
  }
}
