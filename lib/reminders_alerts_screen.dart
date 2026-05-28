import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';

// ─── Design Tokens ──────────────────────────────────────────────────────────
const _kBg = Color(0xFF0B0F19);
const _kCard = Color(0xFF151D30);
const _kAccent = Color(0xFF0E86D4);
const _kGreen = Color(0xFF00A86B);
const _kBorder = Color(0xFF222F4D);
const _kRed = Color(0xFFE53935);
const _kOrange = Color(0xFFFB8C00);

Color _a(Color color, double opacity) => color.withValues(alpha: opacity);

class RemindersAlertsScreen extends StatefulWidget {
  const RemindersAlertsScreen({super.key});

  @override
  State<RemindersAlertsScreen> createState() => _RemindersAlertsScreenState();
}

class _RemindersAlertsScreenState extends State<RemindersAlertsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _reminders = [];
  List<Map<String, dynamic>> _appointments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final reminders = await AuthService.getReminders();
      final appointments = await AuthService.getAppointments();
      if (!mounted) return;
      setState(() {
        _reminders = reminders;
        _appointments = appointments;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErr('Failed to load data: $e');
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

  Map<String, dynamic>? _findAppointmentReminder(String appointmentId) {
    for (final r in _reminders) {
      if (r['type'] == 'appointment' && r['metadata_json'] != null) {
        try {
          final meta = jsonDecode(r['metadata_json']);
          if (meta['appointment_id'].toString() == appointmentId) {
            return r;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  Future<void> _toggleReminder(Map<String, dynamic> reminder) async {
    final id = reminder['id'].toString();
    final currentEnabled = reminder['is_enabled'] == true;
    try {
      final updated = await AuthService.toggleReminder(id, !currentEnabled);
      final isNowEnabled = updated['is_enabled'] == true;
      final triggerTimeStr = updated['trigger_time']?.toString() ?? '';
      final triggerTime = DateTime.tryParse(triggerTimeStr);

      if (isNowEnabled && triggerTime != null) {
        await LocalNotificationService.scheduleNotification(
          notificationId: id.hashCode,
          title: updated['title'] ?? 'Reminder',
          body: updated['body'] ?? '',
          remindAt: triggerTime.toLocal(),
          payload: updated['type'],
        );
        _showSuccess('Reminder enabled & scheduled.');
      } else {
        await LocalNotificationService.cancelReminder(id.hashCode);
        _showSuccess('Reminder disabled.');
      }
      await _loadData();
    } catch (e) {
      _showErr('Failed to toggle reminder: $e');
    }
  }

  Future<void> _deleteReminder(String id) async {
    try {
      await AuthService.deleteReminder(id);
      await LocalNotificationService.cancelReminder(id.hashCode);
      _showSuccess('Reminder deleted.');
      await _loadData();
    } catch (e) {
      _showErr('Failed to delete reminder: $e');
    }
  }

  Future<void> _showAppointmentReminderDialog(Map<String, dynamic> appointment) async {
    final appointmentId = appointment['id'].toString();
    final provider = appointment['provider'] as Map<String, dynamic>?;
    final providerName = provider?['name']?.toString() ?? 'Provider';
    final scheduledAtStr = appointment['scheduled_at']?.toString() ?? '';
    final scheduledAt = DateTime.tryParse(scheduledAtStr);

    if (scheduledAt == null) {
      _showErr('Invalid appointment date/time.');
      return;
    }

    final existingReminder = _findAppointmentReminder(appointmentId);
    int currentMinutesBefore = 30;
    if (existingReminder != null && existingReminder['metadata_json'] != null) {
      try {
        final meta = jsonDecode(existingReminder['metadata_json']);
        currentMinutesBefore = (meta['minutes_before'] as num?)?.toInt() ?? 30;
      } catch (_) {}
    }

    final selectedMinutes = await showDialog<int>(
      context: context,
      builder: (context) {
        int tempMinutes = currentMinutesBefore;
        return AlertDialog(
          backgroundColor: _kCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _kBorder),
          ),
          title: Text(
            'Reminder for $providerName',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appointment on ${DateFormat('EEE, dd MMM yyyy • HH:mm').format(scheduledAt.toLocal())}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Set reminder alert for:',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    dropdownColor: _kCard,
                    initialValue: tempMinutes,
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 minutes before', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 30, child: Text('30 minutes before', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 60, child: Text('1 hour before', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 120, child: Text('2 hours before', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 1440, child: Text('1 day before', style: TextStyle(color: Colors.white))),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() => tempMinutes = v);
                      }
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _a(_kBg, 0.5),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            if (existingReminder != null)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(-1); // Indicator to delete
                },
                child: const Text('Remove Reminder', style: TextStyle(color: _kRed)),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(tempMinutes),
              style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
              child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (selectedMinutes == null) return;

    if (selectedMinutes == -1 && existingReminder != null) {
      await _deleteReminder(existingReminder['id'].toString());
      return;
    }

    final triggerTime = scheduledAt.subtract(Duration(minutes: selectedMinutes));
    if (triggerTime.isBefore(DateTime.now())) {
      _showErr('Cannot set a reminder in the past. Appointment is too close or already completed.');
      return;
    }

    final title = 'Upcoming Appointment';
    final body = 'Your appointment with $providerName starts in $selectedMinutes minutes.';
    final metadataJson = jsonEncode({
      'appointment_id': appointmentId,
      'minutes_before': selectedMinutes,
    });

    try {
      if (existingReminder != null) {
        final updated = await AuthService.updateReminder(
          id: existingReminder['id'].toString(),
          type: 'appointment',
          title: title,
          body: body,
          triggerTime: triggerTime,
          metadataJson: metadataJson,
        );
        await LocalNotificationService.scheduleNotification(
          notificationId: updated['id'].toString().hashCode,
          title: title,
          body: body,
          remindAt: triggerTime.toLocal(),
          payload: 'appointment',
        );
        _showSuccess('Appointment reminder updated.');
      } else {
        final created = await AuthService.createReminder(
          type: 'appointment',
          title: title,
          body: body,
          triggerTime: triggerTime,
          metadataJson: metadataJson,
        );
        await LocalNotificationService.scheduleNotification(
          notificationId: created['id'].toString().hashCode,
          title: title,
          body: body,
          remindAt: triggerTime.toLocal(),
          payload: 'appointment',
        );
        _showSuccess('Appointment reminder scheduled.');
      }
      await _loadData();
    } catch (e) {
      _showErr('Failed to save reminder: $e');
    }
  }

  Future<void> _showMedicationDialog({Map<String, dynamic>? existingReminder}) async {
    final nameController = TextEditingController();
    final dosageController = TextEditingController();
    final notesController = TextEditingController();
    int frequencyHours = 8;
    DateTime selectedDateTime = DateTime.now().add(const Duration(minutes: 10));

    if (existingReminder != null) {
      nameController.text = existingReminder['title'] ?? '';
      dosageController.text = existingReminder['body'] ?? '';
      final triggerTimeStr = existingReminder['trigger_time']?.toString() ?? '';
      selectedDateTime = DateTime.tryParse(triggerTimeStr)?.toLocal() ?? selectedDateTime;
      if (existingReminder['metadata_json'] != null) {
        try {
          final meta = jsonDecode(existingReminder['metadata_json']);
          notesController.text = meta['notes']?.toString() ?? '';
          frequencyHours = (meta['frequency_hours'] as num?)?.toInt() ?? 8;
        } catch (_) {}
      }
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
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
                        Text(
                          existingReminder == null ? 'Add Medication Alert' : 'Edit Medication Alert',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const Divider(color: _kBorder),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Medication Name',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'e.g., Aspirin, Vitamin D',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: _kCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kAccent)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dosageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Dosage / Directions',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'e.g., 1 tablet, 500mg, with water',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: _kCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kAccent)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Notes (optional)',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'e.g., Take with food, Avoid milk',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: _kCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kAccent)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Frequency', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      dropdownColor: _kCard,
                      initialValue: frequencyHours,
                      items: const [
                        DropdownMenuItem(value: 4, child: Text('Every 4 hours', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 6, child: Text('Every 6 hours', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 8, child: Text('Every 8 hours', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 12, child: Text('Every 12 hours (Twice daily)', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 24, child: Text('Every 24 hours (Once daily)', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 48, child: Text('Every 48 hours (Every 2 days)', style: TextStyle(color: Colors.white))),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setBottomSheetState(() => frequencyHours = v);
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _kCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('First Alarm Time', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDateTime,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: _kAccent,
                                  onPrimary: Colors.white,
                                  surface: _kCard,
                                  onSurface: Colors.white,
                                ),
                                dialogTheme: const DialogThemeData(backgroundColor: _kBg),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (date == null || !context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: _kAccent,
                                  onPrimary: Colors.white,
                                  surface: _kCard,
                                  onSurface: Colors.white,
                                ),
                                dialogTheme: const DialogThemeData(backgroundColor: _kBg),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (time == null) return;
                        setBottomSheetState(() {
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
                          color: _kCard,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('EEE, dd MMM yyyy • HH:mm').format(selectedDateTime),
                              style: const TextStyle(color: Colors.white),
                            ),
                            const Icon(Icons.calendar_today, color: _kAccent, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        if (nameController.text.trim().isEmpty) {
                          _showErr('Please enter medication name.');
                          return;
                        }
                        if (dosageController.text.trim().isEmpty) {
                          _showErr('Please enter dosage directions.');
                          return;
                        }
                        Navigator.of(context).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        existingReminder == null ? 'Schedule Medication' : 'Save Changes',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

    if (saved != true) return;

    final metadataJson = jsonEncode({
      'frequency_hours': frequencyHours,
      'notes': notesController.text.trim(),
    });

    try {
      if (existingReminder != null) {
        final id = existingReminder['id'].toString();
        final updated = await AuthService.updateReminder(
          id: id,
          type: 'medication',
          title: nameController.text.trim(),
          body: dosageController.text.trim(),
          triggerTime: selectedDateTime,
          metadataJson: metadataJson,
        );

        if (updated['is_enabled'] == true && selectedDateTime.isAfter(DateTime.now())) {
          await LocalNotificationService.scheduleNotification(
            notificationId: id.hashCode,
            title: updated['title'] ?? 'Medication Alert',
            body: '${updated['title']}: ${updated['body']}',
            remindAt: selectedDateTime,
            payload: 'medication',
          );
        } else {
          await LocalNotificationService.cancelReminder(id.hashCode);
        }
        _showSuccess('Medication alert updated.');
      } else {
        final created = await AuthService.createReminder(
          type: 'medication',
          title: nameController.text.trim(),
          body: dosageController.text.trim(),
          triggerTime: selectedDateTime,
          metadataJson: metadataJson,
        );

        await LocalNotificationService.scheduleNotification(
          notificationId: created['id'].toString().hashCode,
          title: created['title'] ?? 'Medication Alert',
          body: '${created['title']}: ${created['body']}',
          remindAt: selectedDateTime,
          payload: 'medication',
        );
        _showSuccess('Medication alert scheduled.');
      }
      await _loadData();
    } catch (e) {
      _showErr('Failed to save medication: $e');
    }
  }

  Future<void> _markMedicationTaken(Map<String, dynamic> reminder) async {
    final id = reminder['id'].toString();
    final title = reminder['title'] ?? '';
    final body = reminder['body'] ?? '';
    final triggerTimeStr = reminder['trigger_time']?.toString() ?? '';
    final currentTrigger = DateTime.tryParse(triggerTimeStr) ?? DateTime.now();

    int frequencyHours = 8;
    String notes = '';
    if (reminder['metadata_json'] != null) {
      try {
        final meta = jsonDecode(reminder['metadata_json']);
        frequencyHours = (meta['frequency_hours'] as num?)?.toInt() ?? 8;
        notes = meta['notes']?.toString() ?? '';
      } catch (_) {}
    }

    final newTriggerTime = currentTrigger.add(Duration(hours: frequencyHours));
    final metadataJson = jsonEncode({
      'frequency_hours': frequencyHours,
      'notes': notes,
    });

    try {
      final updated = await AuthService.updateReminder(
        id: id,
        type: 'medication',
        title: title,
        body: body,
        triggerTime: newTriggerTime,
        metadataJson: metadataJson,
      );

      if (updated['is_enabled'] == true) {
        await LocalNotificationService.scheduleNotification(
          notificationId: id.hashCode,
          title: title,
          body: '$title: $body',
          remindAt: newTriggerTime.toLocal(),
          payload: 'medication',
        );
      }
      _showSuccess('Logged as taken! Next dose scheduled for ${DateFormat('dd MMM, HH:mm').format(newTriggerTime.toLocal())}.');
      await _loadData();
    } catch (e) {
      _showErr('Failed to log medication: $e');
    }
  }

  Future<void> _showHealthCheckDialog({Map<String, dynamic>? existingReminder}) async {
    final nameController = TextEditingController();
    final detailsController = TextEditingController();
    int frequencyDays = 7;
    DateTime selectedDateTime = DateTime.now().add(const Duration(minutes: 10));

    if (existingReminder != null) {
      nameController.text = existingReminder['title'] ?? '';
      detailsController.text = existingReminder['body'] ?? '';
      final triggerTimeStr = existingReminder['trigger_time']?.toString() ?? '';
      selectedDateTime = DateTime.tryParse(triggerTimeStr)?.toLocal() ?? selectedDateTime;
      if (existingReminder['metadata_json'] != null) {
        try {
          final meta = jsonDecode(existingReminder['metadata_json']);
          frequencyDays = (meta['frequency_days'] as num?)?.toInt() ?? 7;
        } catch (_) {}
      }
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
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
                        Text(
                          existingReminder == null ? 'Add Health Check Reminder' : 'Edit Health Check Reminder',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const Divider(color: _kBorder),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Check Name',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'e.g., Blood Pressure check, Eye exam',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: _kCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kAccent)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: detailsController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Instructions / Details',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'e.g., Check sitting after 5 mins rest',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: _kCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kAccent)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Frequency', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      dropdownColor: _kCard,
                      initialValue: frequencyDays,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Daily', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 7, child: Text('Weekly', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 14, child: Text('Every 2 weeks', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 30, child: Text('Monthly', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 90, child: Text('Quarterly', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 365, child: Text('Annually', style: TextStyle(color: Colors.white))),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setBottomSheetState(() => frequencyDays = v);
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _kCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Next Reminder Time', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDateTime,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: _kAccent,
                                  onPrimary: Colors.white,
                                  surface: _kCard,
                                  onSurface: Colors.white,
                                ),
                                dialogTheme: const DialogThemeData(backgroundColor: _kBg),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (date == null || !context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: _kAccent,
                                  onPrimary: Colors.white,
                                  surface: _kCard,
                                  onSurface: Colors.white,
                                ),
                                dialogTheme: const DialogThemeData(backgroundColor: _kBg),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (time == null) return;
                        setBottomSheetState(() {
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
                          color: _kCard,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('EEE, dd MMM yyyy • HH:mm').format(selectedDateTime),
                              style: const TextStyle(color: Colors.white),
                            ),
                            const Icon(Icons.calendar_today, color: _kAccent, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        if (nameController.text.trim().isEmpty) {
                          _showErr('Please enter check name.');
                          return;
                        }
                        Navigator.of(context).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        existingReminder == null ? 'Schedule Health Check' : 'Save Changes',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

    if (saved != true) return;

    final metadataJson = jsonEncode({
      'frequency_days': frequencyDays,
    });

    try {
      if (existingReminder != null) {
        final id = existingReminder['id'].toString();
        final updated = await AuthService.updateReminder(
          id: id,
          type: 'health_check',
          title: nameController.text.trim(),
          body: detailsController.text.trim(),
          triggerTime: selectedDateTime,
          metadataJson: metadataJson,
        );

        if (updated['is_enabled'] == true && selectedDateTime.isAfter(DateTime.now())) {
          await LocalNotificationService.scheduleNotification(
            notificationId: id.hashCode,
            title: updated['title'] ?? 'Health Check Alert',
            body: '${updated['title']}: ${updated['body']}',
            remindAt: selectedDateTime,
            payload: 'health_check',
          );
        } else {
          await LocalNotificationService.cancelReminder(id.hashCode);
        }
        _showSuccess('Health check reminder updated.');
      } else {
        final created = await AuthService.createReminder(
          type: 'health_check',
          title: nameController.text.trim(),
          body: detailsController.text.trim(),
          triggerTime: selectedDateTime,
          metadataJson: metadataJson,
        );

        await LocalNotificationService.scheduleNotification(
          notificationId: created['id'].toString().hashCode,
          title: created['title'] ?? 'Health Check Alert',
          body: '${created['title']}: ${created['body']}',
          remindAt: selectedDateTime,
          payload: 'health_check',
        );
        _showSuccess('Health check reminder scheduled.');
      }
      await _loadData();
    } catch (e) {
      _showErr('Failed to save health check: $e');
    }
  }

  Future<void> _markHealthCheckDone(Map<String, dynamic> reminder) async {
    final id = reminder['id'].toString();
    final title = reminder['title'] ?? '';
    final body = reminder['body'] ?? '';
    final triggerTimeStr = reminder['trigger_time']?.toString() ?? '';
    final currentTrigger = DateTime.tryParse(triggerTimeStr) ?? DateTime.now();

    int frequencyDays = 7;
    if (reminder['metadata_json'] != null) {
      try {
        final meta = jsonDecode(reminder['metadata_json']);
        frequencyDays = (meta['frequency_days'] as num?)?.toInt() ?? 7;
      } catch (_) {}
    }

    final newTriggerTime = currentTrigger.add(Duration(days: frequencyDays));
    final metadataJson = jsonEncode({
      'frequency_days': frequencyDays,
    });

    try {
      final updated = await AuthService.updateReminder(
        id: id,
        type: 'health_check',
        title: title,
        body: body,
        triggerTime: newTriggerTime,
        metadataJson: metadataJson,
      );

      if (updated['is_enabled'] == true) {
        await LocalNotificationService.scheduleNotification(
          notificationId: id.hashCode,
          title: title,
          body: body,
          remindAt: newTriggerTime.toLocal(),
          payload: 'health_check',
        );
      }
      _showSuccess('Marked done! Next check scheduled for ${DateFormat('dd MMM yyyy').format(newTriggerTime.toLocal())}.');
      await _loadData();
    } catch (e) {
      _showErr('Failed to update health check: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _a(_kBg, 0.95),
        elevation: 0,
        foregroundColor: Colors.white,
        leading: const BackButton(color: Colors.white),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _a(_kAccent, 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.notifications_active_outlined, color: _kAccent, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Reminders & Alerts',
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
            Tab(text: 'Appointments', icon: Icon(Icons.calendar_month, size: 20)),
            Tab(text: 'Medications', icon: Icon(Icons.medication_outlined, size: 20)),
            Tab(text: 'Health Checks', icon: Icon(Icons.assignment_turned_in_outlined, size: 20)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAppointmentsTab(),
                _buildMedicationsTab(),
                _buildHealthChecksTab(),
              ],
            ),
    );
  }

  // ─── Tab Builders ──────────────────────────────────────────────────────────

  Widget _buildAppointmentsTab() {
    final upcomingAppointments = _appointments.where((app) {
      final status = app['status']?.toString().toLowerCase();
      if (status == 'cancelled' || status == 'rejected') return false;
      final timeStr = app['scheduled_at']?.toString() ?? '';
      final time = DateTime.tryParse(timeStr);
      if (time == null) return false;
      return time.isAfter(DateTime.now().subtract(const Duration(hours: 1)));
    }).toList();

    if (upcomingAppointments.isEmpty) {
      return _buildEmptyState(
        icon: Icons.calendar_month,
        title: 'No Upcoming Appointments',
        subtitle: 'Once you book an appointment, you can configure reminders here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _kAccent,
      backgroundColor: _kCard,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: upcomingAppointments.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final app = upcomingAppointments[index];
          final provider = app['provider'] as Map<String, dynamic>?;
          final providerName = provider?['name']?.toString() ?? 'Provider';
          final specialty = provider?['specialty']?.toString() ?? 'General';
          final scheduledAtStr = app['scheduled_at']?.toString() ?? '';
          final scheduledAt = DateTime.tryParse(scheduledAtStr) ?? DateTime.now();

          final reminder = _findAppointmentReminder(app['id'].toString());
          final hasReminder = reminder != null;
          final isReminderEnabled = reminder?['is_enabled'] == true;

          int minutesBefore = 0;
          if (hasReminder && reminder['metadata_json'] != null) {
            try {
              final meta = jsonDecode(reminder['metadata_json']);
              minutesBefore = (meta['minutes_before'] as num?)?.toInt() ?? 0;
            } catch (_) {}
          }

          return Card(
            color: _kCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: _kBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              providerName,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              specialty,
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _a(_kAccent, 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          DateFormat('dd MMM, HH:mm').format(scheduledAt.toLocal()),
                          style: const TextStyle(color: _kAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: _kBorder, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            hasReminder ? Icons.notifications_active : Icons.notifications_none,
                            color: hasReminder ? (isReminderEnabled ? _kOrange : Colors.grey) : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            hasReminder
                                ? (isReminderEnabled ? 'Alert: $minutesBefore mins before' : 'Alert Disabled')
                                : 'No alert set',
                            style: TextStyle(
                              color: hasReminder ? (isReminderEnabled ? Colors.white : Colors.grey) : Colors.grey.shade500,
                              fontSize: 13,
                              fontWeight: hasReminder ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (hasReminder) ...[
                            Switch(
                              value: isReminderEnabled,
                              activeThumbColor: _kAccent,
                              onChanged: (val) => _toggleReminder(reminder),
                            ),
                            const SizedBox(width: 8),
                          ],
                          OutlinedButton.icon(
                            onPressed: () => _showAppointmentReminderDialog(app),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _kAccent,
                              side: const BorderSide(color: _kBorder),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.settings, size: 16),
                            label: Text(hasReminder ? 'Edit' : 'Set Alert', style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      )
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMedicationsTab() {
    final meds = _reminders.where((r) => r['type'] == 'medication').toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _kAccent,
      backgroundColor: _kCard,
      child: Column(
        children: [
          Expanded(
            child: meds.isEmpty
                ? _buildEmptyState(
                    icon: Icons.medication_outlined,
                    title: 'No Medication Alerts',
                    subtitle: 'Add your medications, dosage, and alarm times to receive alerts.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: meds.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final reminder = meds[index];
                      final id = reminder['id'].toString();
                      final isEnabled = reminder['is_enabled'] == true;
                      final triggerTimeStr = reminder['trigger_time']?.toString() ?? '';
                      final triggerTime = DateTime.tryParse(triggerTimeStr) ?? DateTime.now();

                      int frequencyHours = 8;
                      String notes = '';
                      if (reminder['metadata_json'] != null) {
                        try {
                          final meta = jsonDecode(reminder['metadata_json']);
                          frequencyHours = (meta['frequency_hours'] as num?)?.toInt() ?? 8;
                          notes = meta['notes']?.toString() ?? '';
                        } catch (_) {}
                      }

                      return Card(
                        color: _kCard,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: _kBorder),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _a(_kAccent, 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.medication, color: _kAccent, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          reminder['title'] ?? 'Medication',
                                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${reminder['body'] ?? 'Dosage details'} • Every $frequencyHours hours',
                                          style: TextStyle(color: Colors.grey.shade300, fontSize: 14),
                                        ),
                                        if (notes.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Notes: $notes',
                                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontStyle: FontStyle.italic),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: isEnabled,
                                    activeThumbColor: _kAccent,
                                    onChanged: (val) => _toggleReminder(reminder),
                                  ),
                                ],
                              ),
                              const Divider(color: _kBorder, height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Next Alarm:',
                                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isEnabled
                                            ? DateFormat('EEE, dd MMM • HH:mm').format(triggerTime.toLocal())
                                            : 'Alarm Off',
                                        style: TextStyle(
                                          color: isEnabled ? _kOrange : Colors.grey,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: () => _showMedicationDialog(existingReminder: reminder),
                                        icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                                        tooltip: 'Edit Alert',
                                      ),
                                      IconButton(
                                        onPressed: () => _deleteReminder(id),
                                        icon: const Icon(Icons.delete_outline, color: _kRed, size: 20),
                                        tooltip: 'Delete Alert',
                                      ),
                                      const SizedBox(width: 4),
                                      ElevatedButton.icon(
                                        onPressed: isEnabled ? () => _markMedicationTaken(reminder) : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _kGreen,
                                          disabledBackgroundColor: _a(_kGreen, 0.2),
                                          foregroundColor: Colors.white,
                                          disabledForegroundColor: Colors.white30,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                        icon: const Icon(Icons.check, size: 16),
                                        label: const Text('Taken', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => _showMedicationDialog(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add Medication Reminder', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthChecksTab() {
    final checks = _reminders.where((r) => r['type'] == 'health_check').toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _kAccent,
      backgroundColor: _kCard,
      child: Column(
        children: [
          Expanded(
            child: checks.isEmpty
                ? _buildEmptyState(
                    icon: Icons.assignment_turned_in_outlined,
                    title: 'No Health Checks Scheduled',
                    subtitle: 'Schedule recurring checks (e.g., Blood Pressure log) to maintain logs.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: checks.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final reminder = checks[index];
                      final id = reminder['id'].toString();
                      final isEnabled = reminder['is_enabled'] == true;
                      final triggerTimeStr = reminder['trigger_time']?.toString() ?? '';
                      final triggerTime = DateTime.tryParse(triggerTimeStr) ?? DateTime.now();

                      int frequencyDays = 7;
                      if (reminder['metadata_json'] != null) {
                        try {
                          final meta = jsonDecode(reminder['metadata_json']);
                          frequencyDays = (meta['frequency_days'] as num?)?.toInt() ?? 7;
                        } catch (_) {}
                      }

                      String freqText = 'Every $frequencyDays days';
                      if (frequencyDays == 1) freqText = 'Daily';
                      if (frequencyDays == 7) freqText = 'Weekly';
                      if (frequencyDays == 30) freqText = 'Monthly';
                      if (frequencyDays == 365) freqText = 'Annually';

                      return Card(
                        color: _kCard,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: _kBorder),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _a(_kOrange, 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.assignment_turned_in_outlined, color: _kOrange, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          reminder['title'] ?? 'Health Check',
                                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          reminder['body'] ?? 'Instructions details',
                                          style: TextStyle(color: Colors.grey.shade300, fontSize: 14),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _a(Colors.grey, 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            freqText,
                                            style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: isEnabled,
                                    activeThumbColor: _kAccent,
                                    onChanged: (val) => _toggleReminder(reminder),
                                  ),
                                ],
                              ),
                              const Divider(color: _kBorder, height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Next Check Due:',
                                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isEnabled
                                            ? DateFormat('EEE, dd MMM • HH:mm').format(triggerTime.toLocal())
                                            : 'Reminders Off',
                                        style: TextStyle(
                                          color: isEnabled ? _kOrange : Colors.grey,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: () => _showHealthCheckDialog(existingReminder: reminder),
                                        icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                                        tooltip: 'Edit Alert',
                                      ),
                                      IconButton(
                                        onPressed: () => _deleteReminder(id),
                                        icon: const Icon(Icons.delete_outline, color: _kRed, size: 20),
                                        tooltip: 'Delete Alert',
                                      ),
                                      const SizedBox(width: 4),
                                      ElevatedButton.icon(
                                        onPressed: isEnabled ? () => _markHealthCheckDone(reminder) : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _kAccent,
                                          disabledBackgroundColor: _a(_kAccent, 0.2),
                                          foregroundColor: Colors.white,
                                          disabledForegroundColor: Colors.white30,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                        icon: const Icon(Icons.done_all, size: 16),
                                        label: const Text('Log Done', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => _showHealthCheckDialog(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add Health Check Reminder', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

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
