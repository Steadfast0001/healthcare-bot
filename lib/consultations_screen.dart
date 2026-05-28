import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'screens/call_screen.dart';

import 'auth_service.dart';
import 'patient_health_data_screen.dart';
import 'local_notification_service.dart';

// ── Shared colour tokens ─────────────────────────────────────────────────────
const _kBg     = Color(0xFF0D1B2A);
const _kCard   = Color(0xFF1A2D3F);
const _kAccent = Color(0xFF4FFFB0);
const _kGreen  = Color(0xFF0F7A5A);
const _kBorder = Color(0xFF2A4060);

Color _a(Color c, double opacity) => c.withValues(alpha: opacity);

// ── Specialty → avatar accent colour ─────────────────────────────────────────
Color _specialtyColor(String? specialty) {
  if (specialty == null || specialty.isEmpty) return _kAccent;
  final s = specialty.toLowerCase();
  if (s.contains('cardio'))                        return Colors.redAccent;
  if (s.contains('neuro'))                         return Colors.purpleAccent;
  if (s.contains('pedia') || s.contains('child'))  return Colors.orangeAccent;
  if (s.contains('ob') || s.contains('gyn') || s.contains('women')) return Colors.pinkAccent;
  if (s.contains('ortho') || s.contains('bone'))   return Colors.blueAccent;
  if (s.contains('derm') || s.contains('skin'))    return Colors.amberAccent;
  if (s.contains('psych') || s.contains('mental')) return Colors.tealAccent;
  return _kAccent;
}

// ── Root Screen ──────────────────────────────────────────────────────────────
class ConsultationsScreen extends StatefulWidget {
  const ConsultationsScreen({super.key});
  @override
  State<ConsultationsScreen> createState() => _ConsultationsScreenState();
}

class _ConsultationsScreenState extends State<ConsultationsScreen>
    with TickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _threads = [];
  bool _loading = true;
  String? _error;
  int _unreadCount = 0;
  String _currentUserRole = 'user';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadThreads();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadThreads() async {
    setState(() { _loading = true; _error = null; });
    try {
      final user = await AuthService.getCurrentUser();
      _currentUserRole = user['role'] ?? 'user';
      final threads = await AuthService.getConsultationThreads();
      final unread  = await AuthService.getConsultationUnreadCount();
      if (!mounted) return;
      
      final newLength = _currentUserRole == 'provider' ? 2 : 3;
      if (_tab.length != newLength) {
        _tab.dispose();
        _tab = TabController(length: newLength, vsync: this);
      }

      setState(() { _threads = threads; _unreadCount = unread; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _openThread(Map<String, dynamic> thread) {
    final isProvider = _currentUserRole == 'provider';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ThreadScreen(
        threadId:          thread['id']                 as String,
        providerName:      (isProvider ? thread['patient_name'] : thread['provider_name']) as String? ?? 'User',
        providerSpecialty: (isProvider ? 'Patient' : thread['provider_specialty']) as String? ?? '',
      ),
    )).then((_) => _loadThreads());
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = _currentUserRole == 'provider';
    final tabs = [
      Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.chat_bubble_rounded, size: 18),
        const SizedBox(width: 6),
        const Text('Messages', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        if (_unreadCount > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(10)),
            child: Text('$_unreadCount',
                style: const TextStyle(color: _kBg, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ],
      ])),
      if (!isProvider)
        const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_circle_rounded, size: 18), SizedBox(width: 6),
          Text('New', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ])),
      const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.videocam_rounded, size: 18), SizedBox(width: 6),
        Text('Calls', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ])),
    ];

    final tabViews = [
      _ThreadListTab(threads: _threads, loading: _loading, error: _error,
          onRefresh: _loadThreads, onTap: _openThread, isProvider: isProvider),
      if (!isProvider)
        _NewConsultationTab(onCreated: (t) { _loadThreads(); _tab.animateTo(0); _openThread(t); }),
      _CallRequestsTab(threads: _threads, loading: _loading,
          onRefresh: _loadThreads, onTap: _openThread, isProvider: isProvider),
    ];

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A5A40), Color(0xFF0F7A5A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Consultations',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          Row(children: [
            const Icon(Icons.lock_rounded, color: _kAccent, size: 10),
            const SizedBox(width: 4),
            Text('End-to-End Encrypted',
                style: TextStyle(color: _a(_kAccent, 0.8), fontSize: 10, letterSpacing: 0.3)),
          ]),
        ]),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: _kAccent,
          indicatorWeight: 3,
          labelColor: _kAccent,
          unselectedLabelColor: Colors.white54,
          tabs: tabs,
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: tabViews,
      ),
    );
  }
}

// ── Tab 1: Thread List ────────────────────────────────────────────────────────
class _ThreadListTab extends StatelessWidget {
  final List<Map<String, dynamic>> threads;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final void Function(Map<String, dynamic>) onTap;
  final bool isProvider;

  const _ThreadListTab({
    required this.threads, required this.loading,
    required this.onRefresh, required this.onTap, this.error,
    this.isProvider = false,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(color: _kAccent));
    if (error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 56),
          const SizedBox(height: 16),
          Text(error!, style: const TextStyle(color: Colors.white60, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton.icon(onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded), label: const Text('Retry'),
            style: ElevatedButton.styleFrom(backgroundColor: _kGreen, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        ],
      )));
    }
    if (threads.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 100, height: 100, decoration: BoxDecoration(
          shape: BoxShape.circle, color: _a(_kGreen, 0.1),
          border: Border.all(color: _a(_kGreen, 0.3), width: 2)),
          child: const Icon(Icons.chat_bubble_outline_rounded, color: _kAccent, size: 48)),
        const SizedBox(height: 20),
        const Text('No consultations yet',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(isProvider ? 'Wait for patient message consultations' : 'Start a new consultation from the New tab',
            style: const TextStyle(color: Colors.white38, fontSize: 14)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(), color: _kAccent, backgroundColor: _kCard,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        itemCount: threads.length,
        separatorBuilder: (_, i2) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _ThreadCard(thread: threads[i], onTap: () => onTap(threads[i]), isProvider: isProvider),
      ),
    );
  }
}

class _ThreadCard extends StatelessWidget {
  final Map<String, dynamic> thread;
  final VoidCallback onTap;
  final bool isProvider;
  const _ThreadCard({required this.thread, required this.onTap, this.isProvider = false});

  Color _statusColor(String s) => switch (s) {
    'active'          => _kAccent,
    'closed'          => Colors.white38,
    'video_scheduled' => Colors.blue,
    'voice_scheduled' => Colors.purple,
    _                 => Colors.white54,
  };

  IconData _typeIcon(String t) {
    if (t.contains('video')) return Icons.videocam_rounded;
    if (t.contains('voice')) return Icons.mic_rounded;
    return Icons.chat_bubble_rounded;
  }

  String _timeStr(String? s) {
    if (s == null) return '';
    try {
      final dt = DateTime.parse(s).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inDays == 0) return DateFormat('HH:mm').format(dt);
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7)  return DateFormat('EEE').format(dt);
      return DateFormat('MMM d').format(dt);
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final unread    = (thread['unread_count']      as num?)?.toInt() ?? 0;
    final status    = thread['status']             as String? ?? 'active';
    final type      = thread['consultation_type']  as String? ?? 'chat';
    final lastMsg   = thread['last_message']       as String?;
    final name      = isProvider 
        ? (thread['patient_name'] as String? ?? 'Patient') 
        : (thread['provider_name'] as String? ?? 'Provider');
    final specialty = isProvider 
        ? 'Patient ID: ${thread['user_id']?.substring(0, 8) ?? ''}' 
        : (thread['provider_specialty'] as String?);
    final ac        = _specialtyColor(isProvider ? null : specialty);
    final initials  = name.trim().split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
    final timeStr   = _timeStr(thread['last_message_at'] as String?);
    final sc        = _statusColor(status);
    final profilePicBase64 = isProvider
        ? (thread['patient_profile_picture'] as String?)
        : (thread['provider_profile_picture'] as String?);
    Uint8List? profilePicBytes;
    if (profilePicBase64 != null && profilePicBase64.isNotEmpty) {
      try {
        final cleanBase64 = profilePicBase64.contains(',')
            ? profilePicBase64.split(',').last
            : profilePicBase64;
        profilePicBytes = base64Decode(cleanBase64.trim());
      } catch (_) {}
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: unread > 0
              ? [const Color(0xFF1E3545), const Color(0xFF162232)]
              : [_kCard, const Color(0xFF162232)]),
          border: Border.all(color: unread > 0 ? _a(ac, 0.5) : _kBorder, width: unread > 0 ? 1.5 : 1),
          boxShadow: unread > 0 ? [BoxShadow(color: _a(ac, 0.1), blurRadius: 12, offset: const Offset(0, 4))] : [],
        ),
        child: Row(children: [
          Stack(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: profilePicBytes != null ? null : LinearGradient(colors: [_a(ac, 0.3), _a(ac, 0.1)]),
                border: Border.all(color: _a(ac, 0.5), width: 2),
                image: profilePicBytes != null
                    ? DecorationImage(
                        image: MemoryImage(profilePicBytes),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: profilePicBytes != null
                  ? null
                  : Center(child: Text(initials,
                      style: TextStyle(color: ac, fontWeight: FontWeight.w800, fontSize: 17)))),
            Positioned(bottom: 0, right: 0, child: Container(
              width: 18, height: 18,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _kBg,
                border: Border.all(color: _kBorder, width: 1)),
              child: Icon(_typeIcon(type), color: ac, size: 10))),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: TextStyle(color: Colors.white,
                fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600, fontSize: 15),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(timeStr, style: TextStyle(color: unread > 0 ? ac : Colors.white38,
                fontSize: 12, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal)),
            ]),
            if ((specialty ?? '').isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 1),
                child: Text(specialty!, style: TextStyle(color: _a(ac, 0.7), fontSize: 11, fontWeight: FontWeight.w500))),
            const SizedBox(height: 5),
            Row(children: [
              Expanded(child: Text(lastMsg ?? thread['subject'] as String? ?? 'New consultation',
                style: TextStyle(color: unread > 0 ? Colors.white : Colors.white54,
                  fontSize: 13, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (unread > 0)
                Container(margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: ac, borderRadius: BorderRadius.circular(10)),
                  child: Text('$unread', style: TextStyle(
                    color: ac == _kAccent ? _kBg : Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: _a(sc, 0.12), borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _a(sc, 0.3))),
              child: Text(status.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(color: sc, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
          ])),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
        ]),
      ),
    );
  }
}

// ── Tab 2: New Consultation ───────────────────────────────────────────────────
class _NewConsultationTab extends StatefulWidget {
  final void Function(Map<String, dynamic>) onCreated;
  const _NewConsultationTab({required this.onCreated});
  @override
  State<_NewConsultationTab> createState() => _NewConsultationTabState();
}

class _NewConsultationTabState extends State<_NewConsultationTab> {
  final _searchCtrl  = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _msgCtrl     = TextEditingController();
  List<Map<String, dynamic>> _providers = [];
  Map<String, dynamic>? _selected;
  String    _type      = 'chat';
  bool      _searching = false;
  bool      _creating  = false;
  bool      _isInstant = false;
  DateTime? _schedDate;
  TimeOfDay? _schedTime;
  Timer?    _debounce;

  @override
  void initState() { super.initState(); _searchCtrl.addListener(_onType); _search(); }

  void _onType() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    setState(() => _searching = true);
    try {
      final r = await AuthService.searchProviders(query: q.isEmpty ? null : q);
      if (!mounted) return;
      setState(() { _providers = r; _searching = false; });
    } catch (_) { if (mounted) setState(() => _searching = false); }
  }

  ThemeData _darkPickerTheme() => ThemeData.dark().copyWith(
    colorScheme: const ColorScheme.dark(
      primary: _kAccent, onPrimary: _kBg, surface: _kCard, onSurface: Colors.white),
  );

  Future<void> _pickSchedule() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(data: _darkPickerTheme(), child: child!),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context, initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (ctx, child) => Theme(data: _darkPickerTheme(), child: child!),
    );
    if (time == null || !mounted) return;
    setState(() { _schedDate = date; _schedTime = time; });
  }

  String? get _scheduleIso {
    if (_schedDate == null || _schedTime == null) return null;
    return DateTime(_schedDate!.year, _schedDate!.month, _schedDate!.day,
        _schedTime!.hour, _schedTime!.minute).toUtc().toIso8601String();
  }

  String get _scheduleDisplay {
    if (_schedDate == null || _schedTime == null) return 'Set date & time';
    return '${DateFormat('EEE, MMM d').format(_schedDate!)} at ${_schedTime!.format(context)}';
  }

  Future<void> _create() async {
    if (_selected == null) return;
    if (_type != 'chat' && !_isInstant && _schedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please set a date & time for the scheduled call'),
        backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _creating = true);
    try {
      final thread = await AuthService.createConsultationThread(
        providerId: _selected!['id'] as String, subject: _subjectCtrl.text.trim(),
        consultationType: _type, openingMessage: _msgCtrl.text.trim());
      if (_type != 'chat' && _scheduleIso != null) {
        await AuthService.requestConsultationCall(
          threadId: thread['id'] as String,
          callType: _type == 'video_request' ? 'video' : 'voice',
          scheduledCallAt: _scheduleIso);
      }
      if (!mounted) return;
      widget.onCreated(thread);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    } finally { if (mounted) setState(() => _creating = false); }
  }

  @override
  void dispose() {
    _debounce?.cancel(); _searchCtrl.removeListener(_onType);
    _searchCtrl.dispose(); _subjectCtrl.dispose(); _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('Find a Healthcare Provider'),
        const SizedBox(height: 12),
        // Search box
        Container(
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder)),
          child: Row(children: [
            const Padding(padding: EdgeInsets.symmetric(horizontal: 14),
              child: Icon(Icons.search_rounded, color: Colors.white38)),
            Expanded(child: TextField(controller: _searchCtrl, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: 'Search by name, specialty, city…',
                hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14)))),
            if (_searching) const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2))),
          ]),
        ),

        if (_providers.isNotEmpty) ...[
          const SizedBox(height: 16), _sectionLabel('Select Provider'), const SizedBox(height: 10),
          ..._providers.map((p) => _ProviderCard(
            provider: p, selected: _selected?['id'] == p['id'],
            onTap: () => setState(() => _selected = p))),
        ],
        if (_providers.isEmpty && !_searching && _searchCtrl.text.isNotEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(
            child: Text('No providers found for "${_searchCtrl.text}"',
              style: const TextStyle(color: Colors.white38, fontSize: 13)))),

        const SizedBox(height: 24),
        _sectionLabel('Consultation Type'),
        const SizedBox(height: 12),
        _TypeSelector(selected: _type, onSelect: (v) => setState(() {
          _type = v; if (v == 'chat') { _schedDate = null; _schedTime = null; }
        })),

        if (_type != 'chat') ...[
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Instant Call', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text('Call immediately after creating request', style: TextStyle(color: Colors.white38, fontSize: 12)),
            value: _isInstant,
            onChanged: (v) => setState(() {
              _isInstant = v;
              if (v) { _schedDate = null; _schedTime = null; }
            }),
            activeTrackColor: _a(_kAccent, 0.5),
            activeThumbColor: _kAccent,
            contentPadding: EdgeInsets.zero,
          ),
          if (!_isInstant) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickSchedule,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14), color: _kCard,
                  border: Border.all(color: _schedDate != null ? _kAccent : _kBorder,
                    width: _schedDate != null ? 1.5 : 1)),
                child: Row(children: [
                  Icon(Icons.calendar_today_rounded,
                    color: _schedDate != null ? _kAccent : Colors.white38, size: 18),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_scheduleDisplay, style: TextStyle(
                    color: _schedDate != null ? Colors.white : Colors.white38, fontSize: 14,
                    fontWeight: _schedDate != null ? FontWeight.w600 : FontWeight.normal))),
                  Icon(Icons.chevron_right_rounded,
                    color: _schedDate != null ? _kAccent : Colors.white24, size: 18),
                ]),
              ),
            ),
          ],
        ],

        const SizedBox(height: 20),
        _darkField(controller: _subjectCtrl, hint: 'Subject (optional)', icon: Icons.subject_rounded),
        const SizedBox(height: 12),
        _darkField(controller: _msgCtrl, hint: 'Opening message (optional)…',
          icon: Icons.edit_rounded, maxLines: 4),
        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity, height: 54,
          child: ElevatedButton(
            onPressed: _selected == null || _creating ? null : _create,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen, foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white10,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
            child: _creating
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(_type == 'video_request' ? Icons.videocam_rounded
                        : _type == 'voice_request' ? Icons.mic_rounded : Icons.send_rounded, size: 20),
                    const SizedBox(width: 10),
                    Text(_type == 'video_request' ? 'Request Video Call'
                        : _type == 'voice_request' ? 'Request Voice Call' : 'Start Chat Consultation',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
          ),
        ),
        if (_selected == null)
          const Padding(padding: EdgeInsets.only(top: 10), child: Center(
            child: Text('Select a provider above to continue',
              style: TextStyle(color: Colors.white38, fontSize: 12)))),
      ]),
    );
  }

  Widget _sectionLabel(String text) =>
      Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700));

  Widget _darkField({required TextEditingController controller, required String hint,
      required IconData icon, int maxLines = 1}) =>
      TextField(controller: controller, maxLines: maxLines, style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: Icon(icon, color: Colors.white38, size: 20), filled: true, fillColor: _kCard,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _kAccent, width: 1.5))));
}

class _ProviderCard extends StatelessWidget {
  final Map<String, dynamic> provider;
  final bool selected;
  final VoidCallback onTap;
  const _ProviderCard({required this.provider, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name      = provider['name']            as String? ?? 'Provider';
    final specialty = provider['specialty']        as String? ?? '';
    final city      = provider['city']             as String? ?? '';
    final rating    = (provider['average_rating'] as num?)?.toDouble() ?? 0;
    final reviews   = (provider['total_reviews']  as num?)?.toInt() ?? 0;
    final ac        = _specialtyColor(specialty.isEmpty ? null : specialty);
    final initials  = name.trim().split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

    return GestureDetector(onTap: onTap, child: AnimatedContainer(
      duration: const Duration(milliseconds: 200), margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14), decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: selected ? _a(_kGreen, 0.15) : _kCard,
        border: Border.all(color: selected ? _kAccent : _kBorder, width: selected ? 1.5 : 1)),
      child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle,
          gradient: LinearGradient(colors: [_a(ac, 0.3), _a(ac, 0.1)]),
          border: Border.all(color: _a(ac, 0.4), width: 1.5)),
          child: Center(child: Text(initials, style: TextStyle(color: ac, fontWeight: FontWeight.w800, fontSize: 15)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          if (specialty.isNotEmpty) Text(specialty, style: TextStyle(color: _a(ac, 0.8), fontSize: 12)),
          if (city.isNotEmpty) Text(city, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (reviews > 0) Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star_rounded, color: Colors.amber, size: 14), const SizedBox(width: 3),
            Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))]),
          if (selected) const Padding(padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.check_circle_rounded, color: _kAccent, size: 20)),
        ]),
      ]),
    ));
  }
}

class _TypeSelector extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;
  const _TypeSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Row(children: [
    _TypeChip(icon: Icons.chat_bubble_rounded,  label: 'Chat',  value: 'chat',
      color: _kAccent, selected: selected, onSelect: onSelect),
    const SizedBox(width: 10),
    _TypeChip(icon: Icons.videocam_rounded, label: 'Video', value: 'video_request',
      color: Colors.blue, selected: selected, onSelect: onSelect),
    const SizedBox(width: 10),
    _TypeChip(icon: Icons.mic_rounded, label: 'Voice', value: 'voice_request',
      color: Colors.purple, selected: selected, onSelect: onSelect),
  ]);
}

class _TypeChip extends StatelessWidget {
  final IconData icon;
  final String label, value, selected;
  final Color color;
  final void Function(String) onSelect;
  const _TypeChip({required this.icon, required this.label, required this.value,
      required this.color, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final on = selected == value;
    return Expanded(child: GestureDetector(onTap: () => onSelect(value),
      child: AnimatedContainer(duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
          color: on ? _a(color, 0.15) : _kCard,
          border: Border.all(color: on ? color : _kBorder, width: on ? 2 : 1)),
        child: Column(children: [
          Icon(icon, color: on ? color : Colors.white38, size: 22), const SizedBox(height: 4),
          Text(label, style: TextStyle(color: on ? color : Colors.white38, fontSize: 12,
            fontWeight: on ? FontWeight.w700 : FontWeight.normal)),
        ]))));
  }
}

// ── Tab 3: Call Requests ──────────────────────────────────────────────────────
class _CallRequestsTab extends StatelessWidget {
  final List<Map<String, dynamic>> threads;
  final bool loading;
  final VoidCallback onRefresh;
  final void Function(Map<String, dynamic>) onTap;
  final bool isProvider;

  const _CallRequestsTab({
    required this.threads,
    required this.loading,
    required this.onRefresh,
    required this.onTap,
    this.isProvider = false,
  });

  @override
  Widget build(BuildContext context) {
    final calls = threads.where((t) {
      final type = t['consultation_type'] as String? ?? '';
      return type.contains('video') || type.contains('voice');
    }).toList();

    if (loading) return const Center(child: CircularProgressIndicator(color: _kAccent));
    if (calls.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 100, height: 100, decoration: BoxDecoration(shape: BoxShape.circle,
          color: _a(Colors.blue, 0.08), border: Border.all(color: _a(Colors.blue, 0.3), width: 2)),
          child: const Icon(Icons.videocam_off_rounded, color: Colors.blue, size: 48)),
        const SizedBox(height: 20),
        const Text('No call requests yet',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Request a video or voice call from any chat',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      ]));
    }
    return RefreshIndicator(onRefresh: () async => onRefresh(), color: _kAccent, backgroundColor: _kCard,
      child: ListView.separated(padding: const EdgeInsets.all(16), itemCount: calls.length,
        separatorBuilder: (_, i2) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _CallCard(thread: calls[i], onTap: () => onTap(calls[i]), isProvider: isProvider)));
  }
}

class _CallCard extends StatelessWidget {
  final Map<String, dynamic> thread;
  final VoidCallback onTap;
  final bool isProvider;

  const _CallCard({
    required this.thread,
    required this.onTap,
    this.isProvider = false,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo     = (thread['consultation_type'] as String? ?? '').contains('video');
    final status      = thread['status'] as String? ?? 'active';
    final scheduledAt = thread['scheduled_call_at'] as String?;
    final name        = isProvider
        ? (thread['patient_name'] as String? ?? 'Patient')
        : (thread['provider_name'] as String? ?? 'Provider');
    final specialty   = isProvider
        ? 'Patient ID: ${thread['user_id']?.substring(0, 8) ?? ''}'
        : (thread['provider_specialty'] as String? ?? '');
    final cc          = isVideo ? Colors.blue : Colors.purple;
    final initials    = name.trim().split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
    String timeStr = 'Awaiting confirmation';
    if (scheduledAt != null) {
      try { timeStr = DateFormat('EEE, MMM d • HH:mm').format(DateTime.parse(scheduledAt).toLocal()); }
      catch (_) {}
    }

    return GestureDetector(onTap: onTap, child: Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: isVideo
          ? [const Color(0xFF0D1E3A), const Color(0xFF0A1830)]
          : [const Color(0xFF1A0D3A), const Color(0xFF150A2E)]),
        border: Border.all(color: _a(cc, 0.4), width: 1.5),
        boxShadow: [BoxShadow(color: _a(cc, 0.12), blurRadius: 20, offset: const Offset(0, 8))]),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: _a(cc, 0.1),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(bottom: BorderSide(color: _a(cc, 0.2)))),
          child: Row(children: [
            Icon(isVideo ? Icons.videocam_rounded : Icons.mic_rounded, color: cc, size: 18),
            const SizedBox(width: 8),
            Text(isVideo ? 'Video Consultation' : 'Voice Consultation',
              style: TextStyle(color: cc, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _a(cc, 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(status.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(color: cc, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: LinearGradient(colors: [_a(cc, 0.3), _a(cc, 0.1)]),
            border: Border.all(color: _a(cc, 0.4), width: 2)),
            child: Center(child: Text(initials,
              style: TextStyle(color: cc, fontWeight: FontWeight.w800, fontSize: 18)))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            if (specialty.isNotEmpty) Text(specialty, style: TextStyle(color: _a(cc, 0.7), fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.access_time_rounded, color: _a(cc, 0.7), size: 14), const SizedBox(width: 6),
              Expanded(child: Text(timeStr, style: TextStyle(color: _a(cc, 0.8), fontSize: 12, fontWeight: FontWeight.w500))),
            ]),
          ])),
          Icon(Icons.chevron_right_rounded, color: _a(cc, 0.5)),
        ])),
      ]),
    ));
  }
}

// ── Thread Chat Screen ────────────────────────────────────────────────────────
class _ThreadScreen extends StatefulWidget {
  final String threadId;
  final String providerName;
  final String providerSpecialty;
  const _ThreadScreen({required this.threadId, required this.providerName, required this.providerSpecialty});
  @override
  State<_ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<_ThreadScreen> with TickerProviderStateMixin {
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _thread;
  bool _loading    = true;
  bool _sending    = false;
  bool _showTyping = false;
  int  _charCount  = 0;
  Timer? _pollTimer;
  Timer? _typingTimer;
  final Set<String> _newIds = {};
  bool _isProvider = false;

  @override
  void initState() {
    super.initState();
    _msgCtrl.addListener(() => setState(() => _charCount = _msgCtrl.text.length));
    _initUserAndThread();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pollMessages());
  }

  Future<void> _initUserAndThread() async {
    try {
      final user = await AuthService.getCurrentUser();
      if (mounted) {
        setState(() {
          _isProvider = (user['role'] ?? 'user') == 'provider';
        });
      }
    } catch (_) {}
    await _loadThread();
  }

  @override
  void dispose() {
    _pollTimer?.cancel(); _typingTimer?.cancel();
    _msgCtrl.dispose(); _scrollCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _parseMsgs(Map<String, dynamic> data) =>
      (data['messages'] as List? ?? [])
          .whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

  Future<void> _loadThread() async {
    setState(() => _loading = true);
    try {
      final data = await AuthService.getConsultationThread(widget.threadId);
      if (!mounted) return;
      setState(() { _thread = data; _messages = _parseMsgs(data); _loading = false; });
      _scrollToBottom();
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _pollMessages() async {
    try {
      final data = await AuthService.getConsultationThread(widget.threadId);
      if (!mounted) return;
      final msgs = _parseMsgs(data);
      if (msgs.length != _messages.length) {
        final existing = _messages.map((m) => m['id'] as String? ?? '').toSet();
        for (final m in msgs) {
          final id = m['id'] as String? ?? '';
          if (!existing.contains(id)) _newIds.add(id);
        }
        setState(() { _messages = msgs; _thread = data; _showTyping = false; });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      final msg = await AuthService.sendConsultationMessage(threadId: widget.threadId, body: text);
      if (!mounted) return;
      _newIds.add(msg['id'] as String? ?? '');
      setState(() => _messages.add(msg));
      _scrollToBottom();
      _typingTimer?.cancel();
      setState(() => _showTyping = true);
      _typingTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showTyping = false);
      });
    } catch (e) {
      if (!mounted) return;
      _msgCtrl.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e'), backgroundColor: Colors.redAccent));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _showAttachmentMenu() async {
    HapticFeedback.mediumImpact();
    await showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
      builder: (_) => _AttachmentMenu(
        onPickImage: () => _pickImage(ImageSource.gallery),
        onTakePhoto: () => _pickImage(ImageSource.camera),
        onPickFile: _pickDocument));
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);
    try {
      final xfile = await ImagePicker().pickImage(source: source, imageQuality: 75, maxWidth: 1200);
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      final mime  = xfile.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      await _sendAttachment(xfile.name, base64Encode(bytes), mime);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _pickDocument() async {
    Navigator.pop(context);
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
    final file = result.files.first;
    await _sendAttachment(file.name, base64Encode(file.bytes!), _guessMime(file.name));
  }

  Future<void> _sendAttachment(String name, String b64, String mime) async {
    setState(() => _sending = true);
    try {
      final msg = await AuthService.sendConsultationMessage(
        threadId: widget.threadId, body: '',
        attachmentName: name, attachmentData: b64, attachmentMime: mime);
      if (!mounted) return;
      _newIds.add(msg['id'] as String? ?? '');
      setState(() => _messages.add(msg));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send file: $e'), backgroundColor: Colors.redAccent));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  String _guessMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    return const {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif',
      'pdf': 'application/pdf', 'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt': 'text/plain', 'csv': 'text/csv',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    }[ext] ?? 'application/octet-stream';
  }

  ThemeData _darkPickerTheme() => ThemeData.dark().copyWith(
    colorScheme: const ColorScheme.dark(
      primary: _kAccent, onPrimary: _kBg, surface: _kCard, onSurface: Colors.white));

  Future<void> _requestCallWithSchedule(String callType) async {
    HapticFeedback.lightImpact();
    final date = await showDatePicker(context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(data: _darkPickerTheme(), child: child!));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (ctx, child) => Theme(data: _darkPickerTheme(), child: child!));
    if (time == null || !mounted) return;

    final scheduled = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _sending = true);
    try {
      final updated = await AuthService.requestConsultationCall(
        threadId: widget.threadId, callType: callType,
        scheduledCallAt: scheduled.toUtc().toIso8601String());
      if (!mounted) return;
      setState(() => _thread = updated);
      await _loadThread();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          Icon(callType == 'video' ? Icons.videocam_rounded : Icons.mic_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text('${callType == 'video' ? 'Video' : 'Voice'} call scheduled for '
            '${DateFormat('EEE, MMM d').format(scheduled)} at ${time.format(context)}')),
        ]),
        backgroundColor: _kGreen, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _handleCallClick(String callType) async {
    final option = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Initiate ${callType == 'video' ? 'Video' : 'Voice'} Call',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.flash_on_rounded, color: _kAccent),
                title: const Text('Start Instant Call Now', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'instant'),
              ),
              const Divider(color: Colors.white10),
              ListTile(
                leading: const Icon(Icons.calendar_today_rounded, color: Colors.white70),
                title: const Text('Schedule Call for Later', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'schedule'),
              ),
            ],
          ),
        );
      },
    );

    if (option == 'instant') {
      _startInstantCall(callType);
    } else if (option == 'schedule') {
      _requestCallWithSchedule(callType);
    }
  }

  Future<void> _startInstantCall(String callType) async {
    setState(() => _sending = true);
    try {
      final updated = await AuthService.requestConsultationCall(
        threadId: widget.threadId,
        callType: callType,
      );
      setState(() => _thread = updated);
      await _loadThread();

      if (mounted) {
        _showCallingScreen(callType);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to request call: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool get _hasPendingCall =>
      (_thread?['consultation_type'] as String? ?? '').endsWith('_request');

  String get _pendingCallType =>
      (_thread?['consultation_type'] as String? ?? '').replaceAll('_request', '');

  void _joinPendingCall() {
    if (!_hasPendingCall) return;
    _showCallingScreen(_pendingCallType);
  }

  Widget _buildIncomingCallBanner() {
    final callType = _pendingCallType;
    final scheduledAt = _parseDate(_thread?['scheduled_call_at'] as String?);
    final isVideo = callType == 'video';
    final title = isVideo ? 'Video call request' : 'Voice call request';
    final subtitle = scheduledAt != null
        ? 'Scheduled for ${DateFormat('EEE, MMM d • HH:mm').format(scheduledAt)}'
        : 'Join now to answer the request.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF112235),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF2A6AF6).withOpacity(0.4)),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          ElevatedButton(
            onPressed: _joinPendingCall,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(scheduledAt != null ? 'Join' : 'Answer', style: const TextStyle(color: Colors.black)),
          ),
        ]),
      ),
    );
  }

  void _showCallingScreen(String callType) {
    final headerName = _isProvider 
        ? (_thread?['patient_name'] as String? ?? widget.providerName)
        : widget.providerName;
        
    String? targetId;
    if (_isProvider) {
      targetId = _thread?['user_id']?.toString();
    } else {
      targetId = _thread?['provider_id']?.toString();
    }
        
    if (targetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot find target user to call')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          targetUserId: targetId!,
          targetUserName: headerName,
          isVideoCall: callType == 'video',
          isCaller: !_hasPendingCall,
        ),
      ),
    );
  }

  Future<void> _closeThread() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: _kCard, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Close Consultation?',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: const Text('This will archive the thread. You can still view messages but cannot send new ones.',
        style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: const Text('Close Thread')),
      ]));
    if (ok != true) return;
    try {
      await AuthService.closeConsultationThread(widget.threadId);
      await _loadThread();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    }
  }

  void _showImageModal(Uint8List bytes) {
    showDialog(context: context, barrierColor: Colors.black87, builder: (_) => Dialog(
      backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(12),
      child: Stack(alignment: Alignment.topRight, children: [
        InteractiveViewer(child: ClipRRect(
          borderRadius: BorderRadius.circular(16), child: Image.memory(bytes))),
        GestureDetector(onTap: () => Navigator.pop(context), child: Container(
          margin: const EdgeInsets.all(8), width: 36, height: 36,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
          child: const Icon(Icons.close_rounded, color: Colors.white, size: 20))),
      ])));
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateLabel(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    if (_isSameDay(dt, now)) return 'Today';
    if (_isSameDay(dt, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat('EEEE, MMM d').format(dt);
  }

  DateTime? _parseDate(String? s) {
    if (s == null) return null;
    try { return DateTime.parse(s).toLocal(); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final isClosed    = _thread?['status'] == 'closed';
    final headerName = _isProvider 
        ? (_thread?['patient_name'] as String? ?? widget.providerName)
        : widget.providerName;
    final specialty = _isProvider 
        ? 'Patient' 
        : widget.providerSpecialty;
    final ac          = _specialtyColor(specialty == 'Patient' ? null : specialty);
    final initials    = headerName.trim().split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(
          colors: [Color(0xFF0A5A40), Color(0xFF0F7A5A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight))),
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: LinearGradient(colors: [_a(ac, 0.3), _a(ac, 0.1)]),
            border: Border.all(color: _a(ac, 0.5), width: 1.5)),
            child: Center(child: Text(initials, style: TextStyle(color: ac, fontWeight: FontWeight.w800, fontSize: 14)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(headerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            if (specialty.isNotEmpty)
              Text(specialty, style: const TextStyle(color: Colors.white70, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
        ]),
        actions: [
          if (_isProvider && _thread != null && _thread!['user_id'] != null)
            IconButton(
              tooltip: 'Patient Health Records',
              icon: const Icon(Icons.folder_shared_rounded, color: _kAccent),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PatientHealthDataScreen(
                      patientId: _thread!['user_id'] as String,
                      patientName: _thread!['patient_name'] as String? ?? widget.providerName,
                    ),
                  ),
                );
              },
            ),
          if (!isClosed) ...[
            IconButton(tooltip: 'Request Video Call',
              icon: const Icon(Icons.videocam_rounded, color: Colors.white),
              onPressed: _sending ? null : () => _handleCallClick('video')),
            IconButton(tooltip: 'Request Voice Call',
              icon: const Icon(Icons.mic_rounded, color: Colors.white),
              onPressed: _sending ? null : () => _handleCallClick('voice')),
            PopupMenuButton<String>(icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              color: _kCard, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (v) { if (v == 'close') _closeThread(); },
              itemBuilder: (_) => [const PopupMenuItem(value: 'close',
                child: Row(children: [Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                  SizedBox(width: 10), Text('Close Thread', style: TextStyle(color: Colors.white))]))]),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : Column(children: [
              // Encrypted banner
              Container(width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                color: _a(_kGreen, 0.08),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.lock_rounded, color: _kAccent, size: 11),
                  const SizedBox(width: 6),
                  Text(isClosed ? '🔒 This consultation is closed' : 'Messages are encrypted end-to-end',
                    style: TextStyle(
                      color: isClosed ? Colors.white38 : _a(_kAccent, 0.7),
                      fontSize: 11, letterSpacing: 0.3)),
                ])),
              if (_hasPendingCall && !isClosed) _buildIncomingCallBanner(),
              // Messages
              Expanded(child: _messages.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 80, height: 80, decoration: BoxDecoration(
                        shape: BoxShape.circle, color: _a(_kGreen, 0.1),
                        border: Border.all(color: _a(_kGreen, 0.3), width: 2)),
                        child: const Icon(Icons.waving_hand_rounded, color: _kAccent, size: 36)),
                      const SizedBox(height: 16),
                      const Text('Say hello!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('Start the conversation with your provider',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                    ]))
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      itemCount: _messages.length + (_showTyping ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i == _messages.length && _showTyping) return const _TypingIndicator();
                        final msg    = _messages[i];
                        final msgId  = msg['id'] as String? ?? '';
                        final currDt = _parseDate(msg['created_at'] as String?);
                        bool showDate = i == 0;
                        if (i > 0) {
                          final prevDt = _parseDate(_messages[i - 1]['created_at'] as String?);
                          if (prevDt != null && currDt != null && !_isSameDay(prevDt, currDt)) showDate = true;
                        }
                        final sameRolePrev = i > 0 && _messages[i-1]['sender_role'] == msg['sender_role'];
                        final sameRoleNext = i < _messages.length-1 && _messages[i+1]['sender_role'] == msg['sender_role'];
                        return Column(children: [
                          if (showDate) _DateSeparator(dateStr: _dateLabel(currDt)),
                          _MessageBubble(message: msg, isFirst: !sameRolePrev, isLast: !sameRoleNext,
                            animate: _newIds.contains(msgId), onImageTap: _showImageModal),
                        ]);
                      })),
              if (!isClosed) _buildInputBar(),
            ]),
    );
  }

  Widget _buildInputBar() => SafeArea(top: false, child: Container(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
    decoration: BoxDecoration(color: const Color(0xFF0F1E2D),
      border: const Border(top: BorderSide(color: _kBorder, width: 1)),
      boxShadow: [BoxShadow(color: _a(Colors.black, 0.3), blurRadius: 10)]),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton(icon: const Icon(Icons.attach_file_rounded, color: _kAccent),
          onPressed: _sending ? null : _showAttachmentMenu, tooltip: 'Attach file'),
        Expanded(child: Container(
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _kBorder)),
          child: TextField(controller: _msgCtrl, maxLines: 5, minLines: 1, maxLength: 4000,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(hintText: 'Type a message…',
              hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: InputBorder.none, counterText: ''),
            onSubmitted: (_) => _send()))),
        const SizedBox(width: 8),
        GestureDetector(onTap: (_sending || _charCount == 0) ? null : _send,
          child: AnimatedContainer(duration: const Duration(milliseconds: 200),
            width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: (_charCount > 0 && !_sending) ? const LinearGradient(
                colors: [Color(0xFF0F7A5A), Color(0xFF4FFFB0)],
                begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
              color: (_charCount > 0 && !_sending) ? null : Colors.white12),
            child: _sending
                ? const Center(child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                : Icon(Icons.send_rounded,
                    color: _charCount > 0 ? Colors.white : Colors.white24, size: 22))),
      ]),
      if (_charCount > 3800)
        Padding(padding: const EdgeInsets.only(top: 4, right: 8), child: Align(
          alignment: Alignment.centerRight,
          child: Text('${4000 - _charCount} remaining', style: TextStyle(
            color: _charCount > 3900 ? Colors.redAccent : Colors.white38, fontSize: 11)))),
    ])));
}

// ── Attachment Menu ───────────────────────────────────────────────────────────
class _AttachmentMenu extends StatelessWidget {
  final VoidCallback onPickImage, onTakePhoto, onPickFile;
  const _AttachmentMenu({required this.onPickImage, required this.onTakePhoto, required this.onPickFile});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _kBorder)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
      const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text('Share Content',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))),
      const Divider(color: _kBorder, height: 1),
      _AttachOption(icon: Icons.photo_library_rounded, label: 'Choose Image',
        subtitle: 'From your gallery', color: Colors.blue, onTap: onPickImage),
      _AttachOption(icon: Icons.camera_alt_rounded, label: 'Take Photo',
        subtitle: 'Use your camera', color: _kAccent, onTap: onTakePhoto),
      _AttachOption(icon: Icons.picture_as_pdf_rounded, label: 'Medical Report / Document',
        subtitle: 'PDF, Word, or any file', color: Colors.orange, onTap: onPickFile),
      const SizedBox(height: 8),
    ]));
}

class _AttachOption extends StatelessWidget {
  final IconData icon; final String label, subtitle; final Color color; final VoidCallback onTap;
  const _AttachOption({required this.icon, required this.label, required this.subtitle,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), child: Row(children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle,
        color: _a(color, 0.15), border: Border.all(color: _a(color, 0.3))),
        child: Icon(icon, color: color, size: 22)),
      const SizedBox(width: 16),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
        Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12))]),
      const Spacer(),
      const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
    ])));
}

// ── Typing Indicator ──────────────────────────────────────────────────────────
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.centerLeft,
    child: Container(margin: const EdgeInsets.only(left: 4, top: 4, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF1E3A55), Color(0xFF1A3050)]),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18),
          bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.only(right: 8),
          child: Icon(Icons.medical_services_rounded, color: _kAccent, size: 12)),
        ...List.generate(3, (i) => AnimatedBuilder(animation: _ctrl, builder: (_, child) {
          final t = ((_ctrl.value - i * 0.25) % 1.0).clamp(0.0, 1.0);
          final offset = math.sin(t * math.pi) * 5.0;
          return Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Transform.translate(offset: Offset(0, -offset), child: Container(
              width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle,
                color: _a(_kAccent, 0.5 + 0.5 * math.sin(t * math.pi))))));
        })),
      ])));
}

// ── Date Separator ────────────────────────────────────────────────────────────
class _DateSeparator extends StatelessWidget {
  final String dateStr;
  const _DateSeparator({required this.dateStr});
  @override
  Widget build(BuildContext context) {
    if (dateStr.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(children: [
      const Expanded(child: Divider(color: Color(0xFF2A4060))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(dateStr, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600))),
      const Expanded(child: Divider(color: Color(0xFF2A4060))),
    ]));
  }
}

// ── Message Bubble ─────────────────────────────────────────────────────────────
class _MessageBubble extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isFirst, isLast, animate;
  final void Function(Uint8List)? onImageTap;
  const _MessageBubble({required this.message, this.isFirst = true, this.isLast = true,
      this.animate = false, this.onImageTap});
  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _slide, _fade;

  @override
  void initState() {
    super.initState();
    final isPatient = (widget.message['sender_role'] as String? ?? '') == 'patient';
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slide = Tween<double>(begin: isPatient ? 40 : -40, end: 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    widget.animate ? _ctrl.forward() : (_ctrl.value = 1.0);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final role       = widget.message['sender_role'] as String? ?? 'patient';
    final isPatient  = role == 'patient';
    final isSystem   = role == 'system';
    final body        = widget.message['body']            as String? ?? '';
    final attachName  = widget.message['attachment_name'] as String?;
    final attachMime  = widget.message['attachment_mime'] as String?;
    final attachData  = widget.message['attachment_data'] as String?;
    final isRead      = widget.message['is_read']         as bool? ?? false;
    DateTime? dt;
    try { dt = DateTime.parse(widget.message['created_at'] as String? ?? '').toLocal(); } catch (_) {}
    final timeStr = dt != null ? DateFormat('HH:mm').format(dt) : '';

    if (isSystem) {
      return AnimatedBuilder(animation: _ctrl,
        builder: (_, child) => FadeTransition(opacity: _fade, child: child),
        child: Container(margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: _a(Colors.white, 0.06), borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12)),
          child: Text(body, style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)));
    }

    return AnimatedBuilder(animation: _ctrl, builder: (_, child) => FadeTransition(opacity: _fade,
      child: Transform.translate(offset: Offset(_slide.value, 0), child: child)),
      child: Padding(
        padding: EdgeInsets.only(top: widget.isFirst ? 6 : 2, bottom: widget.isLast ? 6 : 2),
        child: Align(alignment: isPatient ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (!isPatient)
              widget.isLast
                ? Container(width: 28, height: 28, margin: const EdgeInsets.only(right: 6, bottom: 2),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _a(_kGreen, 0.3),
                      border: Border.all(color: _a(_kAccent, 0.3))),
                    child: const Center(child: Icon(Icons.medical_services_rounded, color: _kAccent, size: 14)))
                : const SizedBox(width: 34),
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isPatient ? 18 : (widget.isLast ? 4 : 18)),
                  bottomRight: Radius.circular(isPatient ? (widget.isLast ? 4 : 18) : 18)),
                gradient: isPatient
                  ? const LinearGradient(colors: [Color(0xFF0F7A5A), Color(0xFF0A5540)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : const LinearGradient(colors: [Color(0xFF1E3A55), Color(0xFF1A3050)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: [BoxShadow(
                  color: _a(isPatient ? _kGreen : Colors.blue, 0.15),
                  blurRadius: 8, offset: const Offset(0, 3))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!isPatient && widget.isFirst)
                  const Padding(padding: EdgeInsets.only(bottom: 4),
                    child: Text('Provider', style: TextStyle(color: _kAccent, fontSize: 10,
                      fontWeight: FontWeight.w800, letterSpacing: 0.5))),
                if (body.isNotEmpty)
                  Text(body, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
                if (attachName != null) ...[
                  if (body.isNotEmpty) const SizedBox(height: 8),
                  _AttachmentPreview(name: attachName, mime: attachMime ?? '', data: attachData,
                    onImageTap: widget.onImageTap),
                ],
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  if (isPatient) ...[
                    const SizedBox(width: 4),
                    Icon(isRead ? Icons.done_all_rounded : Icons.done_rounded, size: 12,
                      color: isRead ? _kAccent : Colors.white38),
                  ],
                ]),
              ])),
          ]))));
  }
}

// ── Attachment Preview ────────────────────────────────────────────────────────
class _AttachmentPreview extends StatelessWidget {
  final String name, mime;
  final String? data;
  final void Function(Uint8List)? onImageTap;
  const _AttachmentPreview({required this.name, required this.mime, this.data, this.onImageTap});

  bool get _isImage => mime.startsWith('image/');
  bool get _isPdf   => mime.contains('pdf');

  String _fmtSize(int bytes) {
    if (bytes < 1024)        return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconFor(String m) {
    if (m.contains('word') || m.contains('doc')) return Icons.description_rounded;
    if (m.contains('sheet') || m.contains('csv'))return Icons.table_chart_rounded;
    if (m.contains('text'))                      return Icons.text_snippet_rounded;
    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (_isImage && data != null) {
      try {
        final bytes = base64Decode(data!);
        return GestureDetector(onTap: () => onImageTap?.call(bytes), child: Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, width: 220, fit: BoxFit.cover)),
          Positioned(bottom: 6, right: 6, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.zoom_in_rounded, color: Colors.white70, size: 12),
              const SizedBox(width: 4),
              Text(_fmtSize(bytes.length), style: const TextStyle(color: Colors.white70, fontSize: 10))]))),
        ]));
      } catch (_) {}
    }

    final approxSize = data != null ? _fmtSize((data!.length * 3 / 4).round()) : null;
    final iconData   = _isPdf ? Icons.picture_as_pdf_rounded : _iconFor(mime);
    final color      = _isPdf ? Colors.orange : Colors.blue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: _a(Colors.white, 0.07), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _a(color, 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _a(color, 0.15)),
          child: Icon(iconData, color: color, size: 18)),
        const SizedBox(width: 10),
        Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 2, overflow: TextOverflow.ellipsis),
          if (approxSize != null) Text(approxSize, style: TextStyle(color: _a(color, 0.7), fontSize: 10)),
        ])),
      ]),
    );
  }
}

class _CallingOverlay extends StatefulWidget {
  final String callType;
  final String name;
  final String specialty;
  final VoidCallback onHangUp;

  const _CallingOverlay({
    required this.callType,
    required this.name,
    required this.specialty,
    required this.onHangUp,
  });

  @override
  State<_CallingOverlay> createState() => _CallingOverlayState();
}

class _CallingOverlayState extends State<_CallingOverlay> {
  bool _connected = false;
  bool _muted = false;
  bool _videoOff = false;
  int _seconds = 0;
  Timer? _timer;
  Timer? _connectTimer;
  late String _currentCallType;

  @override
  void initState() {
    super.initState();
    _currentCallType = widget.callType;
    LocalNotificationService.startRinging();
    _connectTimer = Timer(const Duration(seconds: 4), () {
      LocalNotificationService.stopRinging();
      if (mounted) {
        setState(() {
          _connected = true;
        });
        _startTimer();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connectTimer?.cancel();
    LocalNotificationService.stopRinging();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) {
        setState(() {
          _seconds++;
        });
      }
    });
  }

  String _formatDuration(int totalSecs) {
    final m = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final s = (totalSecs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.name.trim().split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
    final isVideo = _currentCallType == 'video';

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFF070B19),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Spacer(),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!_connected)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.0, end: 1.8),
                    duration: const Duration(seconds: 1),
                    builder: (context, val, child) {
                      return Container(
                        width: 120 * val,
                        height: 120 * val,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.withOpacity((2.0 - val) * 0.15),
                        ),
                      );
                    },
                  ),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: isVideo
                          ? [const Color(0xFF0D1E3A), const Color(0xFF0E86D4)]
                          : [const Color(0xFF1A0D3A), Colors.purple],
                    ),
                    border: Border.all(color: Colors.white10, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            widget.name,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _connected ? 'Connected (${_formatDuration(_seconds)})' : 'Calling...',
            style: TextStyle(
              color: _connected ? const Color(0xFF4FFFB0) : Colors.white60,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isVideo ? (_videoOff ? Icons.videocam_off_rounded : Icons.videocam_rounded) : Icons.videocam_off_rounded,
                  color: isVideo && !_videoOff ? const Color(0xFF4FFFB0) : Colors.white38,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  isVideo
                      ? (_videoOff ? "Mic Active (Camera Muted)" : "Camera & Mic Active")
                      : "Mic Active (Camera Inactive)",
                  style: TextStyle(
                    color: isVideo && !_videoOff ? const Color(0xFF4FFFB0) : Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            decoration: const BoxDecoration(
              color: Color(0xFF111827),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () => setState(() => _muted = !_muted),
                  icon: Icon(
                    _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: _muted ? Colors.redAccent : Colors.white70,
                    size: 28,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: _muted ? Colors.redAccent.withOpacity(0.15) : Colors.white.withOpacity(0.05),
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                IconButton(
                  onPressed: widget.onHangUp,
                  icon: const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.all(20),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      if (_currentCallType == 'video') {
                        _currentCallType = 'voice';
                        _videoOff = true;
                      } else {
                        _currentCallType = 'video';
                        _videoOff = false;
                      }
                    });
                  },
                  icon: Icon(
                    isVideo ? (_videoOff ? Icons.videocam_off_rounded : Icons.videocam_rounded) : Icons.videocam_off_rounded,
                    color: isVideo ? (_videoOff ? Colors.redAccent : Colors.white70) : Colors.white38,
                    size: 28,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: isVideo
                        ? (_videoOff ? Colors.redAccent.withOpacity(0.15) : Colors.white.withOpacity(0.05))
                        : Colors.white.withOpacity(0.02),
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
