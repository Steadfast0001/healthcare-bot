import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';

class Medication {
  Medication({
    required this.id,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.nextDose,
    this.notes = '',
    this.takenCount = 0,
    this.missedCount = 0,
    List<String>? sideEffects,
    this.refillRequested = false,
    this.transferRequested = false,
  }) : sideEffects = sideEffects ?? [];

  final String id;
  final String name;
  final String dosage;
  final String frequency;
  DateTime nextDose;
  String notes;
  int takenCount;
  int missedCount;
  List<String> sideEffects;
  bool refillRequested;
  bool transferRequested;

  double get adherenceRate {
    final total = takenCount + missedCount;
    return total == 0 ? 0 : (takenCount * 100 / total);
  }

  factory Medication.fromReminder(Map<String, dynamic> r) {
    final metaStr = r['metadata_json'] as String?;
    Map<String, dynamic> meta = {};
    if (metaStr != null && metaStr.isNotEmpty) {
      try {
        meta = jsonDecode(metaStr) as Map<String, dynamic>;
      } catch (_) {}
    }

    String freq = 'Once daily';
    if (meta.containsKey('frequency')) {
      freq = meta['frequency'] as String;
    } else if (meta.containsKey('frequency_hours')) {
      final hours = meta['frequency_hours'] as int;
      if (hours == 24) {
        freq = 'Once daily';
      } else if (hours == 12) {
        freq = 'Twice daily';
      } else if (hours == 8) {
        freq = 'Every 8 hours';
      } else {
        freq = 'Every $hours hours';
      }
    }

    return Medication(
      id: r['id'].toString(),
      name: r['title'] ?? '',
      dosage: r['body'] ?? '',
      frequency: freq,
      nextDose: DateTime.tryParse(r['trigger_time']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      notes: meta['notes']?.toString() ?? '',
      takenCount: meta['takenCount'] as int? ?? 0,
      missedCount: meta['missedCount'] as int? ?? 0,
      sideEffects: List<String>.from(meta['sideEffects'] as List<dynamic>? ?? []),
      refillRequested: meta['refillRequested'] as bool? ?? false,
      transferRequested: meta['transferRequested'] as bool? ?? false,
    );
  }

  String toMetadataJson() {
    int hours = 24;
    if (frequency == 'Once daily') {
      hours = 24;
    } else if (frequency == 'Twice daily') {
      hours = 12;
    } else if (frequency == 'Every 8 hours') {
      hours = 8;
    } else if (frequency.startsWith('Every ') && frequency.endsWith(' hours')) {
      hours = int.tryParse(frequency.replaceAll('Every ', '').replaceAll(' hours', '')) ?? 8;
    }

    return jsonEncode({
      'frequency': frequency,
      'frequency_hours': hours,
      'notes': notes,
      'takenCount': takenCount,
      'missedCount': missedCount,
      'sideEffects': sideEffects,
      'refillRequested': refillRequested,
      'transferRequested': transferRequested,
    });
  }
}

class MedicationScreen extends StatefulWidget {
  final String? patientId;
  final String? patientName;
  final bool hideAppBar;

  const MedicationScreen({
    super.key,
    this.patientId,
    this.patientName,
    this.hideAppBar = false,
  });

  @override
  State<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends State<MedicationScreen> {
  bool _isLoading = true;
  List<Medication> _medications = [];

  @override
  void initState() {
    super.initState();
    _loadMedications();
  }

  Future<void> _loadMedications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final reminders = await AuthService.getReminders(patientId: widget.patientId);
      _medications = reminders
          .where((r) => r['type'] == 'medication')
          .map((r) => Medication.fromReminder(r))
          .toList();
    } catch (e) {
      _showErr('Failed to load medications: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF00A86B),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _addMedication() async {
    final nameController = TextEditingController();
    final dosageController = TextEditingController();
    final notesController = TextEditingController();
    String frequency = 'Once daily';
    DateTime selectedDateTime = DateTime.now().add(const Duration(minutes: 10));

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0F19),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Add Medication Alert',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(false),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFF222F4D)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Medication Name',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'e.g., Paracetamol, Aspirin',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF151D30),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF222F4D))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF222F4D))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0E86D4))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dosageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Dosage / Directions',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'e.g., 1 tablet, 500mg',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF151D30),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF222F4D))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF222F4D))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0E86D4))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Notes (optional)',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'e.g., Take with food',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF151D30),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF222F4D))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF222F4D))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0E86D4))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Frequency', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF151D30),
                      initialValue: frequency,
                      items: const [
                        DropdownMenuItem(value: 'Once daily', child: Text('Once daily', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'Twice daily', child: Text('Twice daily', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'Every 8 hours', child: Text('Every 8 hours', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'As needed', child: Text('As needed', style: TextStyle(color: Colors.white))),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => frequency = v);
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF151D30),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF222F4D))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF222F4D))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('First Alarm Time', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: dialogContext,
                          initialDate: selectedDateTime,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: Color(0xFF0E86D4),
                                  onPrimary: Colors.white,
                                  surface: Color(0xFF151D30),
                                  onSurface: Colors.white,
                                ),
                                dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF0B0F19)),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (date == null) return;
                        if (!dialogContext.mounted) return;
                        final time = await showTimePicker(
                          context: dialogContext,
                          initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: Color(0xFF0E86D4),
                                  onPrimary: Colors.white,
                                  surface: Color(0xFF151D30),
                                  onSurface: Colors.white,
                                ),
                                dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF0B0F19)),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (time == null) return;
                        setDialogState(() {
                          selectedDateTime = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151D30),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF222F4D)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('EEE, dd MMM yyyy • HH:mm').format(selectedDateTime),
                              style: const TextStyle(color: Colors.white),
                            ),
                            const Icon(Icons.calendar_today, color: Color(0xFF0E86D4), size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        if (nameController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(content: Text('Please enter medication name.')),
                          );
                          return;
                        }
                        if (dosageController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(content: Text('Please enter dosage directions.')),
                          );
                          return;
                        }
                        Navigator.of(dialogContext).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E86D4),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Schedule Medication',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final tempMed = Medication(
      id: '',
      name: nameController.text.trim(),
      dosage: dosageController.text.trim(),
      frequency: frequency,
      nextDose: selectedDateTime,
      notes: notesController.text.trim(),
    );

    try {
      final created = await AuthService.createReminder(
        type: 'medication',
        title: tempMed.name,
        body: tempMed.dosage,
        triggerTime: tempMed.nextDose,
        metadataJson: tempMed.toMetadataJson(),
        patientId: widget.patientId,
      );

      if (widget.patientId == null) {
        final id = created['id'].toString();
        await LocalNotificationService.scheduleNotification(
          notificationId: id.hashCode,
          title: created['title'] ?? 'Medication Alert',
          body: '${created['title']}: ${created['body']}',
          remindAt: selectedDateTime,
          payload: 'medication',
        );
      }

      _showSuccess('Medication added.');
      _loadMedications();
    } catch (e) {
      _showErr('Failed to create medication alert: $e');
    }
  }

  Future<void> _markDoseTaken(Medication medication) async {
    medication.takenCount += 1;
    int hours = 24;
    if (medication.frequency == 'Once daily') {
      hours = 24;
    } else if (medication.frequency == 'Twice daily') {
      hours = 12;
    } else if (medication.frequency == 'Every 8 hours') {
      hours = 8;
    } else if (medication.frequency.startsWith('Every ') && medication.frequency.endsWith(' hours')) {
      hours = int.tryParse(medication.frequency.replaceAll('Every ', '').replaceAll(' hours', '')) ?? 8;
    }

    final newTriggerTime = medication.nextDose.add(Duration(hours: hours));
    medication.nextDose = newTriggerTime;

    try {
      await AuthService.updateReminder(
        id: medication.id,
        type: 'medication',
        title: medication.name,
        body: medication.dosage,
        triggerTime: newTriggerTime,
        metadataJson: medication.toMetadataJson(),
      );

      await LocalNotificationService.scheduleNotification(
        notificationId: medication.id.hashCode,
        title: medication.name,
        body: '${medication.name}: ${medication.dosage}',
        remindAt: newTriggerTime.toLocal(),
        payload: 'medication',
      );

      _showSuccess('Logged as taken! Next dose scheduled.');
      _loadMedications();
    } catch (e) {
      _showErr('Failed to log dose: $e');
    }
  }

  Future<void> _logSideEffect(Medication medication) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151D30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF222F4D)),
        ),
        title: Text(
          'Log side effect for ${medication.name}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Describe the side effect',
            labelStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: const Color(0xFF0B0F19),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF222F4D))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF222F4D))),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.of(context).pop(true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0E86D4)),
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || controller.text.trim().isEmpty) return;

    medication.sideEffects.add(controller.text.trim());
    try {
      await AuthService.updateReminder(
        id: medication.id,
        type: 'medication',
        title: medication.name,
        body: medication.dosage,
        triggerTime: medication.nextDose,
        metadataJson: medication.toMetadataJson(),
      );
      _showSuccess('Side effect logged.');
      _loadMedications();
    } catch (e) {
      _showErr('Failed to log side effect: $e');
    }
  }

  Future<void> _requestRefill(Medication medication) async {
    medication.refillRequested = true;
    try {
      await AuthService.updateReminder(
        id: medication.id,
        type: 'medication',
        title: medication.name,
        body: medication.dosage,
        triggerTime: medication.nextDose,
        metadataJson: medication.toMetadataJson(),
      );
      _showSuccess('Refill request sent.');
      _loadMedications();
    } catch (e) {
      _showErr('Failed to request refill: $e');
    }
  }

  Future<void> _requestTransfer(Medication medication) async {
    medication.transferRequested = true;
    try {
      await AuthService.updateReminder(
        id: medication.id,
        type: 'medication',
        title: medication.name,
        body: medication.dosage,
        triggerTime: medication.nextDose,
        metadataJson: medication.toMetadataJson(),
      );
      _showSuccess('Transfer request sent.');
      _loadMedications();
    } catch (e) {
      _showErr('Failed to request transfer: $e');
    }
  }

  Future<void> _scheduleReminder(Medication medication) async {
    try {
      await LocalNotificationService.scheduleNotification(
        notificationId: medication.id.hashCode,
        title: 'Medication Reminder',
        body: 'Time to take ${medication.name} (${medication.dosage})',
        remindAt: medication.nextDose,
        payload: 'medication',
      );
      _showSuccess('Reminder alarm scheduled.');
    } catch (e) {
      _showErr('Failed to schedule reminder: $e');
    }
  }

  Future<void> _deleteMedication(Medication medication) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151D30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF222F4D)),
        ),
        title: const Text('Delete Medication', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete ${medication.name}?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AuthService.deleteReminder(medication.id);
      if (widget.patientId == null) {
        await LocalNotificationService.cancelReminder(medication.id.hashCode);
      }
      _showSuccess('Medication deleted.');
      _loadMedications();
    } catch (e) {
      _showErr('Failed to delete medication: $e');
    }
  }

  double _calculateAverageAdherence() {
    if (_medications.isEmpty) return 0;
    final values = _medications.map((m) => m.adherenceRate).toList();
    return values.reduce((a, b) => a + b) / values.length;
  }

  Widget _buildSummaryCard() {
    final total = _medications.length;
    final totalTaken = _medications.fold<int>(0, (sum, item) => sum + item.takenCount);
    final averageAdherence = _calculateAverageAdherence();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151D30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222F4D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Adherence Summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              if (total > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E86D4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${averageAdherence.toStringAsFixed(0)}% Adherence',
                    style: const TextStyle(color: Color(0xFF0E86D4), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile('Active Meds', '$total', Icons.medical_services_outlined, const Color(0xFF0E86D4)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile('Doses Taken', '$totalTaken', Icons.check_circle_outline, const Color(0xFF00A86B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F19),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF222F4D)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationCard(Medication medication) {
    final adherenceRate = medication.adherenceRate;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF151D30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222F4D)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1F293D),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          medication.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${medication.dosage} • ${medication.frequency}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      if (medication.refillRequested)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFB8C00).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFB8C00).withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'Refill Pending',
                            style: TextStyle(color: Color(0xFFFB8C00), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      IconButton(
                        onPressed: () => _deleteMedication(medication),
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFE53935), size: 22),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.alarm, color: Color(0xFF0E86D4), size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Next Dose: ${DateFormat('EEE, dd MMM yyyy • HH:mm').format(medication.nextDose)}',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (medication.notes.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.note_alt_outlined, color: Colors.white30, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Notes: ${medication.notes}',
                            style: const TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Doses: ${medication.takenCount} taken',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      Text(
                        'Adherence: ${adherenceRate.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: adherenceRate >= 80
                              ? const Color(0xFF00A86B)
                              : (adherenceRate >= 50 ? const Color(0xFFFB8C00) : const Color(0xFFE53935)),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (widget.patientId == null) ...[
                    const Divider(color: Color(0xFF222F4D)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _markDoseTaken(medication),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Mark Taken'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00A86B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _scheduleReminder(medication),
                          icon: const Icon(Icons.notifications_active_outlined, size: 16, color: Color(0xFF0E86D4)),
                          label: const Text('Set Alarm', style: TextStyle(color: Color(0xFF0E86D4))),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF0E86D4)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _logSideEffect(medication),
                          icon: const Icon(Icons.bug_report_outlined, size: 16, color: Colors.white70),
                          label: const Text('Side Effect', style: TextStyle(color: Colors.white70)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF222F4D)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        if (!medication.refillRequested)
                          TextButton(
                            onPressed: () => _requestRefill(medication),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFFB8C00),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const Text('Request Refill'),
                          ),
                        if (!medication.transferRequested)
                          TextButton(
                            onPressed: () => _requestTransfer(medication),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF0E86D4),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const Text('Request Transfer'),
                          ),
                      ],
                    ),
                  ],
                  if (medication.sideEffects.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFF222F4D)),
                    const SizedBox(height: 8),
                    const Text(
                      'Logged Side Effects:',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    ...medication.sideEffects.map(
                      (effect) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.chevron_right, color: Color(0xFFE53935), size: 16),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                effect,
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              title: Text(
                widget.patientName != null
                    ? '${widget.patientName}\'s Medications'
                    : 'Medication Management',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: const Color(0xFF151D30),
              foregroundColor: Colors.white,
              elevation: 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(color: const Color(0xFF222F4D), height: 1),
              ),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0E86D4)))
          : RefreshIndicator(
              color: const Color(0xFF0E86D4),
              backgroundColor: const Color(0xFF151D30),
              onRefresh: _loadMedications,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _addMedication,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: Text(
                      widget.patientId != null ? 'Prescribe Medication' : 'Add Medication',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0E86D4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_medications.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151D30),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF222F4D)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'No medications tracked yet.',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add a medication to start tracking dosages, reminders, adherence, side effects, and requests.',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._medications.map(_buildMedicationCard),
                ],
              ),
            ),
    );
  }
}
