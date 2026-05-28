import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'auth_service.dart';
import 'medication_screen.dart';

const Color _kBg = Color(0xFF060D1E);
const Color _kCard = Color(0xFF0F172A);
const Color _kGreen = Color(0xFF10B981);
const Color _kAccent = Color(0xFF00E676);
const Color _kOrange = Color(0xFFF97316);

class PatientHealthDataScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  const PatientHealthDataScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<PatientHealthDataScreen> createState() => _PatientHealthDataScreenState();
}

class _PatientHealthDataScreenState extends State<PatientHealthDataScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _vitals = [];
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _activityLogs = [];
  List<Map<String, dynamic>> _goals = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vitals = await AuthService.getVitals(patientId: widget.patientId);
      final reports = await AuthService.getHealthReports(patientId: widget.patientId);
      final records = await AuthService.getMedicalRecords(patientId: widget.patientId);
      final activity = await AuthService.getActivityLogs(patientId: widget.patientId);
      final goals = await AuthService.getGoals(patientId: widget.patientId);

      if (!mounted) return;
      setState(() {
        _vitals = vitals;
        _reports = reports;
        _records = records;
        _activityLogs = activity;
        _goals = goals;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatDateTime(String? s) {
    if (s == null) return '';
    try {
      final dt = DateTime.parse(s).toLocal();
      return DateFormat('MMM d, yyyy • HH:mm').format(dt);
    } catch (_) {
      return '';
    }
  }

  Widget _buildVitalTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A5A40), Color(0xFF0F7A5A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.patientName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Text(
              'Patient Health Record',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          indicatorColor: _kAccent,
          indicatorWeight: 3,
          labelColor: _kAccent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Vitals'),
            Tab(text: 'Medication'),
            Tab(text: 'Habits'),
            Tab(text: 'Goals'),
            Tab(text: 'Reports'),
            Tab(text: 'Records'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 56),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.white60, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _loadAllData,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    // Tab 1: Vitals View
                    _vitals.isEmpty
                        ? const Center(
                            child: Text(
                              'No vitals logged for this patient.',
                              style: TextStyle(color: Colors.white38),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadAllData,
                            color: _kAccent,
                            backgroundColor: _kCard,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _vitals.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final vital = _vitals[i];
                                final hasBp = vital['systolic_bp'] != null || vital['diastolic_bp'] != null;
                                final bpStr = hasBp
                                    ? '${vital['systolic_bp'] ?? '?'}/${vital['diastolic_bp'] ?? '?'}'
                                    : null;
                                final glStr = vital['blood_glucose'] != null ? '${vital['blood_glucose']}' : null;
                                final hrStr = vital['heart_rate'] != null ? '${vital['heart_rate']}' : null;
                                final teStr = vital['temperature'] != null ? '${vital['temperature']}' : null;
                                final weStr = vital['weight'] != null ? '${vital['weight']}' : null;

                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _kCard,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatDateTime(vital['created_at']),
                                        style: const TextStyle(
                                          color: _kAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      GridView.count(
                                        crossAxisCount: 2,
                                        childAspectRatio: 2.6,
                                        mainAxisSpacing: 8,
                                        crossAxisSpacing: 8,
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        children: [
                                          if (bpStr != null)
                                            _buildVitalTile(
                                              icon: Icons.heart_broken_rounded,
                                              label: 'BP (mmHg)',
                                              value: bpStr,
                                              color: Colors.redAccent,
                                            ),
                                          if (glStr != null)
                                            _buildVitalTile(
                                              icon: Icons.water_drop_rounded,
                                              label: 'Blood Glucose',
                                              value: '$glStr mg/dL',
                                              color: Colors.orangeAccent,
                                            ),
                                          if (hrStr != null)
                                            _buildVitalTile(
                                              icon: Icons.favorite_rounded,
                                              label: 'Heart Rate',
                                              value: '$hrStr bpm',
                                              color: Colors.pinkAccent,
                                            ),
                                          if (teStr != null)
                                            _buildVitalTile(
                                              icon: Icons.thermostat_rounded,
                                              label: 'Temp (°C)',
                                              value: teStr,
                                              color: Colors.tealAccent,
                                            ),
                                          if (weStr != null)
                                            _buildVitalTile(
                                              icon: Icons.scale_rounded,
                                              label: 'Weight (kg)',
                                              value: weStr,
                                              color: Colors.blueAccent,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),

                    // Tab 2: Medication Adherence & Prescription
                    MedicationScreen(
                      patientId: widget.patientId,
                      patientName: widget.patientName,
                      hideAppBar: true,
                    ),

                    // Tab 3: Habits View
                    _activityLogs.isEmpty
                        ? const Center(
                            child: Text(
                              'No habits logged for this patient.',
                              style: TextStyle(color: Colors.white38),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadAllData,
                            color: _kAccent,
                            backgroundColor: _kCard,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _activityLogs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final log = _activityLogs[i];
                                final dateStr = log['date']?.toString().split('T').first ?? '';
                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _kCard,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dateStr,
                                        style: const TextStyle(color: _kAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 12),
                                      GridView.count(
                                         crossAxisCount: 2,
                                         childAspectRatio: 2.6,
                                        mainAxisSpacing: 8,
                                        crossAxisSpacing: 8,
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        children: [
                                          if (log['steps'] != null)
                                            _buildVitalTile(
                                              icon: Icons.directions_walk_rounded,
                                              label: 'Steps',
                                              value: '${log['steps']}',
                                              color: Colors.greenAccent,
                                            ),
                                          if (log['water_intake'] != null)
                                            _buildVitalTile(
                                              icon: Icons.local_drink_rounded,
                                              label: 'Water Intake',
                                              value: '${log['water_intake']} ml',
                                              color: Colors.blueAccent,
                                            ),
                                          if (log['sleep_hours'] != null)
                                            _buildVitalTile(
                                              icon: Icons.bedtime_rounded,
                                              label: 'Sleep',
                                              value: '${log['sleep_hours']} hrs',
                                              color: Colors.indigoAccent,
                                            ),
                                          if (log['calories_burned'] != null)
                                            _buildVitalTile(
                                              icon: Icons.local_fire_department_rounded,
                                              label: 'Burned',
                                              value: '${log['calories_burned']} kcal',
                                              color: Colors.orangeAccent,
                                            ),
                                        ],
                                      ),
                                      if (log['meal_notes'] != null && log['meal_notes'].toString().isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        const Divider(color: Colors.white10),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Meal Notes: ${log['meal_notes']}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),

                    // Tab 4: Goals View
                    _goals.isEmpty
                        ? const Center(
                            child: Text(
                              'No goals configured for this patient.',
                              style: TextStyle(color: Colors.white38),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadAllData,
                            color: _kAccent,
                            backgroundColor: _kCard,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _goals.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final goal = _goals[i];
                                final progress = goal['target_value'] != null && goal['target_value'] > 0
                                    ? ((goal['current_value'] ?? 0.0) / goal['target_value'])
                                    : 0.0;
                                final isCompleted = goal['is_completed'] == true;
                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _kCard,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            (goal['goal_type'] as String? ?? '').toUpperCase(),
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isCompleted ? const Color(0xFF10B981).withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              isCompleted ? 'COMPLETED' : 'IN PROGRESS',
                                              style: TextStyle(
                                                color: isCompleted ? const Color(0xFF10B981) : Colors.orange,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      LinearProgressIndicator(
                                        value: progress > 1.0 ? 1.0 : progress,
                                        backgroundColor: Colors.white10,
                                        color: isCompleted ? const Color(0xFF10B981) : _kAccent,
                                        borderRadius: BorderRadius.circular(4),
                                        minHeight: 6,
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Progress: ${goal['current_value'] ?? 0} / ${goal['target_value'] ?? 0}',
                                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                                          ),
                                          if (goal['target_date'] != null)
                                            Text(
                                              'Target: ${DateFormat('MMM d, yyyy').format(DateTime.parse(goal['target_date']).toLocal())}',
                                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),

                    // Tab 5: Reports View
                    _reports.isEmpty
                        ? const Center(
                            child: Text(
                              'No health reports generated.',
                              style: TextStyle(color: Colors.white38),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadAllData,
                            color: _kAccent,
                            backgroundColor: _kCard,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _reports.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final r = _reports[i];
                                return Card(
                                  color: _kCard,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _kGreen.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.description_outlined, color: _kGreen, size: 24),
                                    ),
                                    title: Text(
                                      r['title'] ?? 'Health Report',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      'Period: ${_formatDateTime(r['period_start']).split(' •')[0]} - ${_formatDateTime(r['period_end']).split(' •')[0]}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 16),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _PatientReportDetailScreen(report: r),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                    // Tab 6: Records View
                    _records.isEmpty
                        ? const Center(
                            child: Text(
                              'No medical records uploaded.',
                              style: TextStyle(color: Colors.white38),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadAllData,
                            color: _kAccent,
                            backgroundColor: _kCard,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _records.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final rec = _records[i];
                                return Card(
                                  color: _kCard,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.blueAccent.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.snippet_folder_outlined, color: Colors.blueAccent, size: 24),
                                    ),
                                    title: Text(
                                      rec['title'] ?? 'Medical Record',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      'Type: ${rec['record_type']} • ${_formatDateTime(rec['record_date']).split(' •')[0]}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 16),
                                    onTap: () async {
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (_) => const Center(
                                          child: CircularProgressIndicator(color: _kAccent),
                                        ),
                                      );
                                      try {
                                        final fullRecord = await AuthService.getMedicalRecord(rec['id']);
                                        if (context.mounted) {
                                          Navigator.pop(context); // pop dialog
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => _PatientRecordDetailScreen(record: fullRecord),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          Navigator.pop(context); // pop dialog
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Error loading record: $e'), backgroundColor: Colors.redAccent),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                  ],
                ),
    );
  }
}

// ─── Patient Report Detail Screen ──────────────────────────────────────────────
class _PatientReportDetailScreen extends StatelessWidget {
  final Map<String, dynamic> report;

  const _PatientReportDetailScreen({required this.report});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Report Details'),
        backgroundColor: _kCard,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              report['title'] ?? 'Health Report',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Generated: ${report['created_at'] != null ? DateFormat('MMM d, yyyy').format(DateTime.parse(report['created_at']).toLocal()) : ''}',
              style: const TextStyle(color: _kGreen, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Divider(color: Colors.white10, height: 32),
            const Text(
              'Summary & Findings',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_parseReportSummary(report) != null)
              _buildStructuredReportContent(_parseReportSummary(report)!)
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  report['summary'] ?? 'No summary available.',
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Logged Vitals Snapshot',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _buildSnapshotContent(report['data_snapshot']),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic>? _parseReportSummary(Map<String, dynamic> report) {
    if (report['summary'] == null) return null;
    try {
      final parsed = jsonDecode(report['summary'].toString()) as Map<String, dynamic>;
      return parsed.isEmpty ? null : parsed;
    } catch (_) {
      return null;
    }
  }

  Widget _buildStructuredReportContent(Map<String, dynamic> data) {
    final summary = data['patient_summary'] as Map<String, dynamic>? ?? {};
    final vitals = data['clinical_vitals'] as Map<String, dynamic>? ?? {};
    final hpi = data['history_of_present_illness'] as Map<String, dynamic>? ?? {};
    final assessment = data['assessment_and_findings'] as Map<String, dynamic>? ?? {};
    final plan = data['plan_and_recommendations'] as Map<String, dynamic>? ?? {};
    final redFlags = data['red_flags'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCard(summary),
        _buildSectionHeader('Clinical Vitals Snapshot'),
        _buildVitalsGrid(vitals),
        _buildSectionHeader('History of Present Illness'),
        _buildHpiCard(hpi),
        _buildSectionHeader('Clinical Assessment'),
        _buildAssessmentCard(assessment),
        _buildSectionHeader('Treatment Plan & Advice'),
        _buildPlanCard(plan),
        if (redFlags.isNotEmpty) _buildRedFlagsCard(redFlags),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 8.0),
      child: Text(title,
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> summary) {
    final age = summary['age']?.toString() ?? 'N/A';
    final gender = summary['gender']?.toString() ?? 'N/A';
    final complaint = summary['chief_complaint']?.toString() ?? 'None recorded';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Patient Summary', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(children: [
          _buildTag('Age: $age'),
          const SizedBox(width: 8),
          _buildTag('Gender: $gender'),
        ]),
        const SizedBox(height: 12),
        const Text('CHIEF COMPLAINT', style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(complaint, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    );
  }

  Widget _buildVitalsGrid(Map<String, dynamic> vitals) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _buildMetricCard('Blood Pressure', vitals['blood_pressure']),
        _buildMetricCard('Heart Rate', vitals['heart_rate']),
        _buildMetricCard('Temperature', vitals['temperature']),
        _buildMetricCard('spO2', vitals['spO2']),
      ],
    );
  }

  Widget _buildMetricCard(String label, dynamic value) {
    final display = value?.toString() ?? 'Not recorded';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold)),
        Text(display, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildHpiCard(Map<String, dynamic> hpi) {
    final onset = hpi['onset']?.toString() ?? 'N/A';
    final duration = hpi['duration']?.toString() ?? 'N/A';
    final description = hpi['description']?.toString() ?? 'No narrative provided.';
    return Container(
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _buildTag('Onset: $onset'),
          const SizedBox(width: 8),
          _buildTag('Duration: $duration'),
        ]),
        const SizedBox(height: 16),
        const Text('CLINICAL DESCRIPTION', style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(description, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
      ]),
    );
  }

  Widget _buildAssessmentCard(Map<String, dynamic> assessment) {
    final primary = assessment['primary_diagnosis']?.toString() ?? 'Unknown Condition';
    final physical = assessment['physical_examination']?.toString() ?? 'Not recorded';
    final differentials = (assessment['differential_diagnoses'] as List?)?.cast<String>() ?? [];
    return Container(
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PRIMARY DIAGNOSIS', style: const TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(primary, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        const Divider(color: Colors.white10, height: 24),
        const Text('PHYSICAL EXAMINATION', style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(physical, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
        if (differentials.isNotEmpty) ...[
          const Divider(color: Colors.white10, height: 24),
          const Text('DIFFERENTIAL DIAGNOSES', style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: differentials.map((d) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(8)),
            child: Text(d, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          )).toList()),
        ],
      ]),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final medications = (plan['medications'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tests = (plan['diagnostic_tests_ordered'] as List?)?.cast<String>() ?? [];
    final advice = (plan['lifestyle_advice'] as List?)?.cast<String>() ?? [];
    final followUp = plan['follow_up']?.toString() ?? 'No follow-up recorded';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (medications.isNotEmpty) ...[
        const Text('Prescribed Medications', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...medications.map((med) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.medication_outlined, color: _kGreen, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(med['name']?.toString() ?? 'Medication', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${med['dosage'] ?? 'N/A'} • ${med['frequency'] ?? 'N/A'} • ${med['duration'] ?? 'N/A'}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
          ]),
        )),
        const SizedBox(height: 12),
      ],
      if (tests.isNotEmpty) ...[
        const Text('Diagnostic Tests Ordered', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: tests.map((t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row(children: [const Icon(Icons.check_box_outlined, color: _kAccent, size: 16), const SizedBox(width: 10), Expanded(child: Text(t, style: const TextStyle(color: Colors.white70, fontSize: 13))),]),
        )).toList())),
        const SizedBox(height: 16),
      ],
      if (advice.isNotEmpty) ...[
        const Text('Lifestyle & Dietary Advice', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: advice.map((a) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.arrow_right_rounded, color: _kGreen, size: 18), const SizedBox(width: 6), Expanded(child: Text(a, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3))),]),
        )).toList())),
        const SizedBox(height: 16),
      ],
      const Text('Follow-up Instructions', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)), child: Row(children: [const Icon(Icons.event_note_rounded, color: _kOrange, size: 18), const SizedBox(width: 10), Expanded(child: Text(followUp, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3))),]),),
    ]);
  }

  Widget _buildRedFlagsCard(List<dynamic> redFlags) {
    if (redFlags.isEmpty) return const SizedBox();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22), SizedBox(width: 8), Text('CRITICAL RED FLAGS', style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 10),
        const Text('Seek immediate professional medical care at an emergency room or hospital if you experience any of the following:', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3)),
        const SizedBox(height: 8),
        ...redFlags.map((flag) => Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('• ', style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold)), Expanded(child: Text(flag.toString(), style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3))),]),)).toList(),
      ]),
    );
  }

  Widget _buildSnapshotContent(dynamic snapshotData) {
    if (snapshotData == null) return const Text('No snapshot data.', style: TextStyle(color: Colors.white38));
    try {
      final map = snapshotData is Map ? snapshotData : jsonDecode(snapshotData.toString()) as Map;
      if (map.isEmpty) return const Text('No vitals logged in period.', style: TextStyle(color: Colors.white38));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: map.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(e.key.toString().toUpperCase(), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                Text(e.value.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        }).toList(),
      );
    } catch (_) {
      return const Text('Invalid snapshot format.', style: TextStyle(color: Colors.white38));
    }
  }
}

// ─── Patient Record Detail Screen ──────────────────────────────────────────────
class _PatientRecordDetailScreen extends StatelessWidget {
  final Map<String, dynamic> record;

  const _PatientRecordDetailScreen({required this.record});

  @override
  Widget build(BuildContext context) {
    final mime = record['file_mime'] as String? ?? '';
    final isImage = mime.startsWith('image/');
    
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Record Details'),
        backgroundColor: _kCard,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record['title'] ?? 'Medical Record',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Date: ${record['record_date'] != null ? DateFormat('MMM d, yyyy').format(DateTime.parse(record['record_date']).toLocal()) : ''}',
              style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Divider(color: Colors.white10, height: 32),
            _buildMetaRow('Record Type', record['record_type']),
            _buildMetaRow('Provider', record['provider_name']),
            const SizedBox(height: 16),
            const Text(
              'Doctor Notes',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                record['notes'] ?? 'No notes provided.',
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Attachment Preview',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (isImage && record['file_data'] != null && record['file_data'].toString().isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  base64Decode(record['file_data'].toString()),
                  fit: BoxFit.contain,
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, color: Colors.white38, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      record['file_name'] ?? 'File Attachment',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Size: ${(record['file_size'] as num? ?? 0) / 1024 > 1024 ? "${((record['file_size'] as num? ?? 0) / 1024 / 1024).toStringAsFixed(1)} MB" : "${((record['file_size'] as num? ?? 0) / 1024).toStringAsFixed(1)} KB"}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
