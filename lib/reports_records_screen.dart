import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'auth_service.dart';
import 'main.dart';

// ─── Design Tokens ──────────────────────────────────────────────────────────
const _kBg = Color(0xFF0B0F19);
const _kCard = Color(0xFF151D30);
const _kAccent = Color(0xFF0E86D4);
const _kGreen = Color(0xFF00A86B);
const _kBorder = Color(0xFF222F4D);
const _kRed = Color(0xFFE53935);
const _kOrange = Color(0xFFFB8C00);

Color _a(Color color, double opacity) => color.withValues(alpha: opacity);

class ReportsRecordsScreen extends StatefulWidget {
  const ReportsRecordsScreen({super.key});

  @override
  State<ReportsRecordsScreen> createState() => _ReportsRecordsScreenState();
}

class _ReportsRecordsScreenState extends State<ReportsRecordsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // State
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _shares = [];

  bool _loadingReports = true;
  bool _loadingRecords = true;
  bool _loadingShares = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchReports();
    _fetchRecords();
    _fetchShares();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchReports() async {
    setState(() => _loadingReports = true);
    try {
      final res = await AuthService.getHealthReports();
      setState(() {
        _reports = res;
        _loadingReports = false;
      });
    } catch (e) {
      setState(() => _loadingReports = false);
      _showErr('Could not load reports: $e');
    }
  }

  Future<void> _fetchRecords() async {
    setState(() => _loadingRecords = true);
    try {
      final res = await AuthService.getMedicalRecords();
      setState(() {
        _records = res;
        _loadingRecords = false;
      });
    } catch (e) {
      setState(() => _loadingRecords = false);
      _showErr('Could not load records: $e');
    }
  }

  Future<void> _fetchShares() async {
    setState(() => _loadingShares = true);
    try {
      final res = await AuthService.getShareLinks();
      setState(() {
        _shares = res;
        _loadingShares = false;
      });
    } catch (e) {
      setState(() => _loadingShares = false);
      _showErr('Could not load share links: $e');
    }
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _kGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _a(_kBg, 0.95),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const MainPage(email: ''))
              );
            }
          },
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _a(_kAccent, 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.description_outlined, color: _kAccent, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Reports & Records',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _kAccent,
          labelColor: _kAccent,
          unselectedLabelColor: Colors.grey.shade400,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Reports', icon: Icon(Icons.analytics_outlined, size: 20)),
            Tab(text: 'Records', icon: Icon(Icons.folder_open_rounded, size: 20)),
            Tab(text: 'Sharing', icon: Icon(Icons.share_outlined, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReportsTab(),
          _buildRecordsTab(),
          _buildSharingTab(),
        ],
      ),
    );
  }

  // ─── Reports Tab ───────────────────────────────────────────────────────────

  Widget _buildReportsTab() {
    if (_loadingReports) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    return RefreshIndicator(
      onRefresh: _fetchReports,
      color: _kAccent,
      backgroundColor: _kCard,
      child: Column(
        children: [
          Expanded(
            child: _reports.isEmpty
                ? _buildEmptyState(
                    icon: Icons.analytics_outlined,
                    title: 'No Health Reports Yet',
                    subtitle: 'Generate a report using your logged vital, activity, or symptom history.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _reports.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, idx) => _ReportCard(
                      report: _reports[idx],
                      onTap: () => _viewReport(_reports[idx]),
                      onDelete: () => _deleteReport(_reports[idx]['id']),
                      onShare: () => _shareItem('report', _reports[idx]['id']),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ElevatedButton.icon(
              onPressed: _openGenerateReportDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Generate AI Health Report', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  void _viewReport(Map<String, dynamic> report) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ReportDetailScreen(
          report: report,
          onDelete: () async {
            await AuthService.deleteHealthReport(report['id']);
            _fetchReports();
          },
          onShare: () => _shareItem('report', report['id']),
        ),
      ),
    );
  }

  Future<void> _deleteReport(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Delete Report?', style: TextStyle(color: Colors.white)),
        content: const Text('This will permanently delete the generated health report.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await AuthService.deleteHealthReport(id);
        _showSuccess('Report deleted successfully');
        _fetchReports();
      } catch (e) {
        _showErr('Could not delete report: $e');
      }
    }
  }

  void _openGenerateReportDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GenerateReportSheet(
        onGenerated: (report) {
          _fetchReports();
          _viewReport(report);
        },
      ),
    );
  }

  // ─── Records Tab ───────────────────────────────────────────────────────────

  Widget _buildRecordsTab() {
    if (_loadingRecords) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    return RefreshIndicator(
      onRefresh: _fetchRecords,
      color: _kAccent,
      backgroundColor: _kCard,
      child: Column(
        children: [
          Expanded(
            child: _records.isEmpty
                ? _buildEmptyState(
                    icon: Icons.folder_open_rounded,
                    title: 'No Medical Records',
                    subtitle: 'Upload prescriptions, clinical imaging, lab reports or clinical summaries.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _records.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, idx) => _RecordCard(
                      record: _records[idx],
                      onTap: () => _viewRecord(_records[idx]),
                      onDelete: () => _deleteRecord(_records[idx]['id']),
                      onShare: () => _shareItem('record', _records[idx]['id']),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ElevatedButton.icon(
              onPressed: _openUploadRecordDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Upload Document / Image', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  void _viewRecord(Map<String, dynamic> record) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RecordDetailScreen(
          recordId: record['id'],
          onDelete: () async {
            await AuthService.deleteMedicalRecord(record['id']);
            _fetchRecords();
          },
          onShare: () => _shareItem('record', record['id']),
        ),
      ),
    );
  }

  Future<void> _deleteRecord(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Delete Record?', style: TextStyle(color: Colors.white)),
        content: const Text('This will permanently delete the uploaded medical document.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await AuthService.deleteMedicalRecord(id);
        _showSuccess('Record deleted');
        _fetchRecords();
      } catch (e) {
        _showErr('Could not delete record: $e');
      }
    }
  }

  void _openUploadRecordDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UploadRecordSheet(
        onUploaded: () {
          _fetchRecords();
        },
      ),
    );
  }

  // ─── Sharing Tab ───────────────────────────────────────────────────────────

  Widget _buildSharingTab() {
    if (_loadingShares) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    return RefreshIndicator(
      onRefresh: _fetchShares,
      color: _kAccent,
      backgroundColor: _kCard,
      child: Column(
        children: [
          Expanded(
            child: _shares.isEmpty
                ? _buildEmptyState(
                    icon: Icons.share_outlined,
                    title: 'No Shared Links',
                    subtitle: 'Securely share reports or record sheets with doctors or family members.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _shares.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, idx) => _ShareLinkCard(
                      share: _shares[idx],
                      onRevoke: () => _revokeShare(_shares[idx]['id']),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ElevatedButton.icon(
              onPressed: () => _shareItem('all_reports', null),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kCard,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: _kBorder, width: 1),
                ),
              ),
              icon: const Icon(Icons.screen_share_outlined, color: _kAccent),
              label: const Text('Create Global Share Access Link', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  void _shareItem(String shareType, String? targetId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreateShareLinkSheet(
        shareType: shareType,
        targetId: targetId,
        onCreated: () {
          _fetchShares();
          _tabController.animateTo(2);
        },
      ),
    );
  }

  Future<void> _revokeShare(String shareId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Revoke Share Link?', style: TextStyle(color: Colors.white)),
        content: const Text('This will instantly disable all access for the recipient to this data.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kRed),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await AuthService.revokeShareLink(shareId);
        _showSuccess('Access link revoked');
        _fetchShares();
      } catch (e) {
        _showErr('Could not revoke access: $e');
      }
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 72, color: _a(_kAccent, 0.25)),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Report Card Component ──────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const _ReportCard({
    required this.report,
    required this.onTap,
    required this.onDelete,
    required this.onShare,
  });

  Color get _typeColor {
    switch (report['report_type']) {
      case 'vitals':
        return _kRed;
      case 'activity':
        return _kAccent;
      case 'symptoms':
        return _kOrange;
      default:
        return _kGreen;
    }
  }

  IconData get _typeIcon {
    switch (report['report_type']) {
      case 'vitals':
        return Icons.favorite_rounded;
      case 'activity':
        return Icons.directions_run_rounded;
      case 'symptoms':
        return Icons.thermostat_rounded;
      default:
        return Icons.assessment_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime.parse(report['period_start']);
    final end = DateTime.parse(report['period_end']);
    final df = DateFormat('MMM d, yyyy');

    String summaryText = report['summary'] ?? '';
    try {
      final decoded = jsonDecode(summaryText);
      if (decoded is Map<String, dynamic>) {
        final findings = decoded['assessment_and_findings'] as Map<String, dynamic>?;
        final patient = decoded['patient_summary'] as Map<String, dynamic>?;
        final primary = findings?['primary_diagnosis'] ?? 'Unknown';
        final complaint = patient?['chief_complaint'] ?? 'No complaint';
        summaryText = 'Diagnosis: $primary\nComplaint: $complaint';
      }
    } catch (_) {}

    return Card(
      color: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _a(_typeColor, 0.2), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _a(_typeColor, 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_typeIcon, color: _typeColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report['title'] ?? 'AI Health Summary',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${df.format(start)} - ${df.format(end)}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                summaryText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const Divider(color: _kBorder, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    report['report_type'].toString().toUpperCase(),
                    style: TextStyle(color: _typeColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: onShare,
                        icon: const Icon(Icons.share_outlined, color: Colors.grey, size: 20),
                        tooltip: 'Share Report',
                      ),
                      IconButton(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 20),
                        tooltip: 'Delete Report',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Record Card Component ──────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const _RecordCard({
    required this.record,
    required this.onTap,
    required this.onDelete,
    required this.onShare,
  });

  IconData get _typeIcon {
    switch (record['record_type']) {
      case 'lab_result':
        return Icons.biotech_rounded;
      case 'prescription':
        return Icons.receipt_long_rounded;
      case 'imaging':
        return Icons.camera_rounded;
      case 'discharge':
        return Icons.assignment_turned_in_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final recordDate = DateTime.parse(record['record_date']);
    final df = DateFormat('MMM d, yyyy');

    return Card(
      color: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _a(_kAccent, 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_typeIcon, color: _kAccent, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record['title'] ?? 'Medical Document',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    if (record['provider_name'] != null && record['provider_name'].toString().isNotEmpty) ...[
                      Text(
                        record['provider_name'],
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      children: [
                        Text(
                          df.format(recordDate),
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(color: Colors.white30, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatSize(record['file_size']),
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    onPressed: onShare,
                    icon: const Icon(Icons.share_outlined, color: Colors.grey, size: 20),
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Share Link Card Component ──────────────────────────────────────────────

class _ShareLinkCard extends StatelessWidget {
  final Map<String, dynamic> share;
  final VoidCallback onRevoke;

  const _ShareLinkCard({
    required this.share,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final expiry = DateTime.parse(share['expires_at']);
    final isExpired = expiry.isBefore(DateTime.now());
    final statusColor = share['is_revoked']
        ? _kRed
        : isExpired
            ? _kOrange
            : _kGreen;

    final statusText = share['is_revoked']
        ? 'Revoked'
        : isExpired
            ? 'Expired'
            : 'Active';

    final df = DateFormat('MMM d, yyyy HH:mm');

    return Card(
      color: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                Text(
                  'Views: ${share['access_count']}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Shared with: ${share['recipient_name']}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            if (share['recipient_email'] != null && share['recipient_email'].toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                share['recipient_email'],
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Expires: ${df.format(expiry)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const Divider(color: _kBorder, height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isExpired || share['is_revoked']
                        ? null
                        : () => _shareLink(context, share['share_token']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _a(_kAccent, 0.15),
                      foregroundColor: _kAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Share Access Link', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (!isExpired && !share['is_revoked']) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: onRevoke,
                    icon: const Icon(Icons.cancel_outlined, color: _kRed),
                    tooltip: 'Revoke Access',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _shareLink(BuildContext context, String token) {
    // Generate public shared link format
    final url = 'http://172.30.90.114:8001/shared/$token';
    // ignore: deprecated_member_use
    Share.share('Here is a secure link to my medical records: $url');
  }
}

// ─── Generate Report Sheet ──────────────────────────────────────────────────

class _GenerateReportSheet extends StatefulWidget {
  final Function(Map<String, dynamic>) onGenerated;

  const _GenerateReportSheet({required this.onGenerated});

  @override
  State<_GenerateReportSheet> createState() => _GenerateReportSheetState();
}

class _GenerateReportSheetState extends State<_GenerateReportSheet> {
  String _type = 'comprehensive';
  DateTime _start = DateTime.now().subtract(const Duration(days: 30));
  DateTime _end = DateTime.now();
  bool _submitting = false;

  void _generate() async {
    setState(() => _submitting = true);
    try {
      final res = await AuthService.generateHealthReport(
        reportType: _type,
        periodStart: _start,
        periodEnd: _end,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onGenerated(res);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate health summary: $e'),
          backgroundColor: _kRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, yyyy');

    return Container(
      decoration: const BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Generate Health Report Summary',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select Report Scope',
            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildTypeChip('vitals', 'Vitals'),
              const SizedBox(width: 8),
              _buildTypeChip('activity', 'Activity'),
              const SizedBox(width: 8),
              _buildTypeChip('symptoms', 'Symptoms'),
              const SizedBox(width: 8),
              _buildTypeChip('comprehensive', 'All'),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Select Report Date Range',
            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${df.format(_start)} to ${df.format(_end)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Tap to change duration', style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.calendar_today_rounded, color: _kAccent),
            onTap: _pickDateRange,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _submitting ? null : _generate,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Generate Summary with Gemini AI', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String val, String label) {
    final active = _type == val;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (sel) {
        if (sel) setState(() => _type = val);
      },
      selectedColor: _a(_kAccent, 0.25),
      checkmarkColor: _kAccent,
      backgroundColor: Colors.transparent,
      labelStyle: TextStyle(
        color: active ? _kAccent : Colors.grey.shade400,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: active ? _kAccent : _kBorder, width: 1.5),
      ),
    );
  }

  void _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _start, end: _end),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _kAccent,
            onPrimary: Colors.white,
            surface: _kCard,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _start = picked.start;
        _end = picked.end;
      });
    }
  }
}

// ─── Upload Record Sheet ────────────────────────────────────────────────────

class _UploadRecordSheet extends StatefulWidget {
  final VoidCallback onUploaded;

  const _UploadRecordSheet({required this.onUploaded});

  @override
  State<_UploadRecordSheet> createState() => _UploadRecordSheetState();
}

class _UploadRecordSheetState extends State<_UploadRecordSheet> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _providerCtrl = TextEditingController();
  DateTime _recordDate = DateTime.now();

  String _type = 'lab_result';
  String? _fileName;
  String? _fileDataB64;
  String? _fileMime;
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _providerCtrl.dispose();
    super.dispose();
  }

  void _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (res != null && res.files.isNotEmpty) {
      final file = res.files.first;
      if (file.bytes == null) return;
      setState(() {
        _fileName = file.name;
        _fileDataB64 = base64Encode(file.bytes!);
        _fileMime = _getMime(file.extension ?? '');
        if (_titleCtrl.text.isEmpty) {
          _titleCtrl.text = file.name.split('.').first.replaceAll('_', ' ').replaceAll('-', ' ');
        }
      });
    }
  }

  void _captureImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _fileName = picked.name;
        _fileDataB64 = base64Encode(bytes);
        _fileMime = 'image/jpeg';
        if (_titleCtrl.text.isEmpty) {
          _titleCtrl.text = picked.name.split('.').first;
        }
      });
    }
  }

  String _getMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'png':
        return 'image/png';
      default:
        return 'image/jpeg';
    }
  }

  void _upload() async {
    if (_fileName == null || _fileDataB64 == null || _fileMime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or capture a file document'), backgroundColor: _kRed),
      );
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please specify a title for the record'), backgroundColor: _kRed),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await AuthService.uploadMedicalRecord(
        recordType: _type,
        title: _titleCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        fileName: _fileName!,
        fileData: _fileDataB64!,
        fileMime: _fileMime!,
        providerName: _providerCtrl.text.trim().isEmpty ? null : _providerCtrl.text.trim(),
        recordDate: _recordDate,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onUploaded();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: _kRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, yyyy');

    return Container(
      decoration: const BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Upload Medical Document',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kAccent,
                      side: const BorderSide(color: _kBorder, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.file_present_rounded),
                    label: const Text('Pick File'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _captureImage,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kAccent,
                      side: const BorderSide(color: _kBorder, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Camera'),
                  ),
                ),
              ],
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _a(_kAccent, 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _a(_kAccent, 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: _kGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _fileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Document Type',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildTypeChip('lab_result', 'Lab Result'),
                _buildTypeChip('prescription', 'Prescription'),
                _buildTypeChip('imaging', 'Imaging'),
                _buildTypeChip('discharge', 'Discharge Note'),
                _buildTypeChip('other', 'Other'),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Document Title',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _providerCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Issuing Care Provider / Doctor',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Notes',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                df.format(_recordDate),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Record Event Date', style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: const Icon(Icons.calendar_today_rounded, color: _kAccent),
              onTap: _pickRecordDate,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitting ? null : _upload,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Upload & Save Record', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String val, String label) {
    final active = _type == val;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (sel) {
        if (sel) setState(() => _type = val);
      },
      selectedColor: _a(_kAccent, 0.25),
      checkmarkColor: _kAccent,
      backgroundColor: Colors.transparent,
      labelStyle: TextStyle(
        color: active ? _kAccent : Colors.grey.shade400,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: active ? _kAccent : _kBorder, width: 1.5),
      ),
    );
  }

  void _pickRecordDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordDate,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _kAccent,
            onPrimary: Colors.white,
            surface: _kCard,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _recordDate = picked);
    }
  }
}

// ─── Create Share Link Sheet ────────────────────────────────────────────────

class _CreateShareLinkSheet extends StatefulWidget {
  final String shareType;
  final String? targetId;
  final VoidCallback onCreated;

  const _CreateShareLinkSheet({
    required this.shareType,
    required this.targetId,
    required this.onCreated,
  });

  @override
  State<_CreateShareLinkSheet> createState() => _CreateShareLinkSheetState();
}

class _CreateShareLinkSheetState extends State<_CreateShareLinkSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  int _expiryDays = 7;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _create() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please specify recipient name'), backgroundColor: _kRed),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await AuthService.createShareLink(
        shareType: widget.shareType,
        targetId: widget.targetId,
        recipientName: _nameCtrl.text.trim(),
        recipientEmail: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        expiresInDays: _expiryDays,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sharing failed: $e'), backgroundColor: _kRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Generate Shared Access Link',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Generates a secure time-limited URL for external clinicians to access the documents.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Recipient Clinician / Doctor Name',
              labelStyle: const TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kAccent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Recipient Email (Optional)',
              labelStyle: const TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kAccent),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Link Expiry Period',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildExpiryChip(1, '1 Day'),
              const SizedBox(width: 8),
              _buildExpiryChip(3, '3 Days'),
              const SizedBox(width: 8),
              _buildExpiryChip(7, '7 Days'),
              const SizedBox(width: 8),
              _buildExpiryChip(30, '30 Days'),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _submitting ? null : _create,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Generate Secure Link', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiryChip(int days, String label) {
    final active = _expiryDays == days;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (sel) {
        if (sel) setState(() => _expiryDays = days);
      },
      selectedColor: _a(_kAccent, 0.25),
      checkmarkColor: _kAccent,
      backgroundColor: Colors.transparent,
      labelStyle: TextStyle(
        color: active ? _kAccent : Colors.grey.shade400,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: active ? _kAccent : _kBorder, width: 1.5),
      ),
    );
  }
}

// ─── Report Detail Screen ───────────────────────────────────────────────────

class _ReportDetailScreen extends StatelessWidget {
  final Map<String, dynamic> report;
  final Future<void> Function() onDelete;
  final VoidCallback onShare;

  const _ReportDetailScreen({
    required this.report,
    required this.onDelete,
    required this.onShare,
  });

  Widget _buildConfidentialityBadge(String? level) {
    if (level == null) return const SizedBox();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _a(_kAccent, 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _a(_kAccent, 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, color: _kAccent, size: 12),
          const SizedBox(width: 4),
          Text(
            level.toUpperCase(),
            style: const TextStyle(color: _kAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityChip(String? severity) {
    if (severity == null) return const SizedBox();
    Color color = _kGreen;
    if (severity.toLowerCase() == 'severe') {
      color = _kRed;
    } else if (severity.toLowerCase() == 'moderate') {
      color = _kOrange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _a(color, 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _a(color, 0.3)),
      ),
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientSummaryCard(Map<String, dynamic> summary, String? confidentiality) {
    final age = summary['age'] ?? 'N/A';
    final gender = summary['gender'] ?? 'N/A';
    final complaint = summary['chief_complaint'] ?? 'None recorded';
    return Card(
      color: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Patient Demographics',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                _buildConfidentialityBadge(confidentiality),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildDemographicChip(Icons.person_outline, 'Age: $age'),
                const SizedBox(width: 8),
                _buildDemographicChip(Icons.transgender_outlined, 'Gender: $gender'),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'CHIEF COMPLAINT',
              style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            Text(
              complaint,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemographicChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _a(Colors.white, 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 14),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
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
        _buildVitalCard('Blood Pressure', vitals['blood_pressure'], Icons.heart_broken_outlined, _kRed),
        _buildVitalCard('Heart Rate', vitals['heart_rate'], Icons.favorite_border_rounded, _kRed),
        _buildVitalCard('Temperature', vitals['temperature'], Icons.thermostat_outlined, _kOrange),
        _buildVitalCard('spO2 (Oxygen)', vitals['spO2'], Icons.bloodtype_outlined, _kAccent),
      ],
    );
  }

  Widget _buildVitalCard(String label, String? value, IconData icon, Color color) {
    final displayValue = (value == null || value.toString().toLowerCase() == 'null' || value.toString().isEmpty)
        ? 'Not recorded'
        : value;
    final isNotRecorded = displayValue == 'Not recorded';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              Icon(icon, color: _a(color, 0.6), size: 16),
            ],
          ),
          Text(
            displayValue,
            style: TextStyle(
              color: isNotRecorded ? Colors.white38 : Colors.white,
              fontSize: isNotRecorded ? 13 : 18,
              fontWeight: isNotRecorded ? FontWeight.bold : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHpiCard(Map<String, dynamic> hpi) {
    final onset = hpi['onset'] ?? 'N/A';
    final duration = hpi['duration'] ?? 'N/A';
    final description = hpi['description'] ?? 'No narrative provided.';
    final severity = hpi['severity'];

    return Card(
      color: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _buildDemographicChip(Icons.access_time_rounded, 'Onset: $onset'),
                    const SizedBox(width: 8),
                    _buildDemographicChip(Icons.hourglass_empty_rounded, 'Dur: $duration'),
                  ],
                ),
                _buildSeverityChip(severity),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'CLINICAL DESCRIPTION',
              style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssessmentCard(Map<String, dynamic> assessment) {
    final primary = assessment['primary_diagnosis'] ?? 'Unknown Condition';
    final icd = assessment['icd_10_code'];
    final physical = assessment['physical_examination'] ?? 'Not recorded';
    final differentials = (assessment['differential_diagnoses'] as List?)?.cast<String>() ?? [];

    return Card(
      color: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PRIMARY DIAGNOSIS',
                        style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        primary,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (icd != null && icd.toString().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _a(_kAccent, 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _a(_kAccent, 0.3)),
                    ),
                    child: Text(
                      'ICD-10: $icd',
                      style: const TextStyle(color: _kAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ]
              ],
            ),
            const Divider(color: _kBorder, height: 24),
            const Text(
              'PHYSICAL EXAMINATION',
              style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 6),
            Text(
              physical,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            if (differentials.isNotEmpty) ...[
              const Divider(color: _kBorder, height: 24),
              const Text(
                'DIFFERENTIAL DIAGNOSES',
                style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: differentials.map((d) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _a(Colors.white, 0.03),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Text(
                      d,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlanSection(Map<String, dynamic> plan) {
    final medications = plan['medications'] as List? ?? [];
    final tests = (plan['diagnostic_tests_ordered'] as List?)?.cast<String>() ?? [];
    final advice = (plan['lifestyle_advice'] as List?)?.cast<String>() ?? [];
    final followUp = plan['follow_up'] ?? 'No specific follow-up recorded';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (medications.isNotEmpty) ...[
          const Text(
            'Prescribed Pharmacological Medications',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...medications.map((med) {
            final medMap = med as Map<String, dynamic>;
            final name = medMap['name'] ?? 'Medication';
            final dosage = medMap['dosage'] ?? 'N/A';
            final frequency = medMap['frequency'] ?? 'N/A';
            final duration = medMap['duration'] ?? 'N/A';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _a(_kGreen, 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.medication_outlined, color: _kGreen, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$dosage • $frequency • $duration',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
        ],
        if (tests.isNotEmpty) ...[
          const Text(
            'Diagnostic Tests Ordered',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: tests.map((t) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      const Icon(Icons.check_box_outlined, color: _kAccent, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (advice.isNotEmpty) ...[
          const Text(
            'Lifestyle & Dietary Advice',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: advice.map((a) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.arrow_right_rounded, color: _kGreen, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          a,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const Text(
          'Follow-up Instructions',
          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.event_note_rounded, color: _kOrange, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  followUp,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRedFlagsCard(List<dynamic> redFlags) {
    if (redFlags.isEmpty) return const SizedBox();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _a(_kRed, 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _a(_kRed, 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: _kRed, size: 22),
              const SizedBox(width: 8),
              const Text(
                'CRITICAL RED FLAGS',
                style: TextStyle(color: _kRed, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Seek immediate professional medical care at an emergency room or hospital if you experience any of the following:',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 8),
          ...redFlags.map((flag) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: _kRed, fontSize: 14, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      flag.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500, height: 1.3),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStructuredReportUI(BuildContext context, Map<String, dynamic> data) {
    final summary = data['patient_summary'] as Map<String, dynamic>? ?? {};
    final vitals = data['clinical_vitals'] as Map<String, dynamic>? ?? {};
    final hpi = data['history_of_present_illness'] as Map<String, dynamic>? ?? {};
    final assessment = data['assessment_and_findings'] as Map<String, dynamic>? ?? {};
    final plan = data['plan_and_recommendations'] as Map<String, dynamic>? ?? {};
    final redFlags = data['red_flags'] as List? ?? [];
    final metadata = data['report_metadata'] as Map<String, dynamic>? ?? {};
    final confidentiality = metadata['confidentiality_level']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPatientSummaryCard(summary, confidentiality),
        _buildSectionHeader('Clinical Vitals Snapshot', Icons.favorite_rounded, _kRed),
        _buildVitalsGrid(vitals),
        _buildSectionHeader('History of Present Illness', Icons.notes_rounded, _kAccent),
        _buildHpiCard(hpi),
        _buildSectionHeader('Clinical Assessment', Icons.medical_services_outlined, _kOrange),
        _buildAssessmentCard(assessment),
        _buildSectionHeader('Treatment Plan & Advice', Icons.playlist_add_check_rounded, _kGreen),
        _buildPlanSection(plan),
        _buildRedFlagsCard(redFlags),
        if (data['disclaimer'] != null && data['disclaimer'].toString().isNotEmpty) ...[
          const SizedBox(height: 24),
          const Divider(color: _kBorder),
          const SizedBox(height: 8),
          Text(
            data['disclaimer'],
            style: const TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic, height: 1.4),
          ),
        ] else ...[
          const SizedBox(height: 24),
          const Divider(color: _kBorder),
          const SizedBox(height: 8),
          const Text(
            'Standard Disclaimer: I am not a replacement for a licensed clinician. Use this guidance for education and seek professional medical care for diagnosis or treatment.',
            style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic, height: 1.4),
          ),
        ]
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime.parse(report['period_start']);
    final end = DateTime.parse(report['period_end']);
    final df = DateFormat('MMM d, yyyy');

    Map<String, dynamic>? parsedJson;
    try {
      parsedJson = jsonDecode(report['summary'] ?? '') as Map<String, dynamic>;
    } catch (_) {
      parsedJson = null;
    }

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Clinical Health Summary'),
        actions: [
          IconButton(
            onPressed: onShare,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            onPressed: () async {
              await onDelete();
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline_rounded, color: _kRed),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              report['title'] ?? 'AI Report Summary',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${df.format(start)} - ${df.format(end)}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            if (parsedJson != null)
              _buildStructuredReportUI(context, parsedJson)
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kBorder),
                ),
                child: SelectableText(
                  report['summary'] ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Raw Data Reference Snapshot',
              style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildSnapshotViewer(report['data_snapshot']),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotViewer(String rawSnapshot) {
    try {
      final decoded = jsonDecode(rawSnapshot) as Map<String, dynamic>;
      final vitalsCount = (decoded['vitals'] as List).length;
      final activitiesCount = (decoded['activities'] as List).length;
      final symptomsCount = (decoded['symptoms'] as List).length;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          children: [
            _buildSnapshotRow(Icons.favorite_rounded, _kRed, 'Vitals Log Entries', '$vitalsCount'),
            const Divider(color: _kBorder, height: 24),
            _buildSnapshotRow(Icons.directions_run_rounded, _kAccent, 'Activity Logs', '$activitiesCount'),
            const Divider(color: _kBorder, height: 24),
            _buildSnapshotRow(Icons.thermostat_rounded, _kOrange, 'Symptom Checker Logs', '$symptomsCount'),
          ],
        ),
      );
    } catch (_) {
      return const SizedBox();
    }
  }

  Widget _buildSnapshotRow(IconData icon, Color color, String title, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
        Text(val, style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ─── Record Detail Screen ───────────────────────────────────────────────────

class _RecordDetailScreen extends StatefulWidget {
  final String recordId;
  final Future<void> Function() onDelete;
  final VoidCallback onShare;

  const _RecordDetailScreen({
    required this.recordId,
    required this.onDelete,
    required this.onShare,
  });

  @override
  State<_RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<_RecordDetailScreen> {
  Map<String, dynamic>? _record;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  void _fetchDetails() async {
    try {
      final res = await AuthService.getMedicalRecord(widget.recordId);
      setState(() {
        _record = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load file: $e'), backgroundColor: _kRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(child: CircularProgressIndicator(color: _kAccent)),
      );
    }
    if (_record == null) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(child: Text('Document not found', style: TextStyle(color: Colors.white))),
      );
    }

    final isImg = _record!['file_mime'].toString().startsWith('image/');

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_record!['title'] ?? 'Document Details'),
        actions: [
          IconButton(
            onPressed: widget.onShare,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            onPressed: () async {
              await widget.onDelete();
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline_rounded, color: _kRed),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) => Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: isImg
                      ? InteractiveViewer(
                          maxScale: 4.0,
                          child: Image.memory(
                            base64Decode(_record!['file_data']),
                            fit: BoxFit.contain,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.picture_as_pdf_rounded, size: 84, color: _kRed),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Text(
                                _record!['file_name'],
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _record!['file_mime'],
                              style: const TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('Download PDF Document'),
                            )
                          ],
                        ),
                ),
              ),
            ),
            if (_record!['notes'] != null && _record!['notes'].toString().isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notes',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _record!['notes'],
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
