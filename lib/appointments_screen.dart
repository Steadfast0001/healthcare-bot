import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'auth_service.dart';
import 'consultations_screen.dart';
import 'local_notification_service.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  final _searchController = TextEditingController();
  final _reasonController = TextEditingController();
  final _cityController = TextEditingController();
  String _providerType = 'all';
  DateTime? _selectedDateTime;
  Map<String, dynamic>? _selectedProvider;
  bool _isLoading = true;
  bool _isBooking = false;
  bool _isCancelling = false;
  bool _isRescheduling = false;
  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _appointments = [];
  String _userRole = 'user';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _reasonController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = await AuthService.getCurrentUser();
      final role = user['role']?.toString() ?? 'user';
      
      List<Map<String, dynamic>> providers = [];
      if (role != 'provider') {
        providers = await AuthService.searchProviders(
          query: _searchController.text,
          providerType: _providerType == 'all' ? null : _providerType,
          city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
        );
      }
      final appointments = await AuthService.getAppointments();
      if (!mounted) return;
      setState(() {
        _userRole = role;
        _providers = providers;
        _appointments = appointments;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load appointments data: $e')),
      );
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() {
      _selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _bookAppointment() async {
    if (_selectedProvider == null || _selectedDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select provider and appointment time first.')),
      );
      return;
    }
    setState(() => _isBooking = true);
    try {
      final appointment = await AuthService.bookAppointment(
        providerId: _selectedProvider!['id'].toString(),
        scheduledAt: _selectedDateTime!,
        reason: _reasonController.text,
        reminderMinutesBefore: 60,
      );
      final reminder = await AuthService.getAppointmentReminder(
        appointment['id'].toString(),
      );
      final reminderAt = DateTime.tryParse(
        reminder['reminder_at']?.toString() ?? '',
      );
      if (reminderAt != null) {
        await LocalNotificationService.scheduleAppointmentReminder(
          notificationId: appointment['id'].toString().hashCode,
          title: 'Appointment Reminder',
          body:
              'Upcoming appointment with ${_selectedProvider?['name'] ?? 'provider'}',
          remindAt: reminderAt.toLocal(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reminder['message']?.toString() ?? 'Booked.')),
      );
      _reasonController.clear();
      _selectedDateTime = null;
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  Future<void> _cancelAppointment(String id) async {
    if (_isCancelling) return;
    setState(() => _isCancelling = true);
    try {
      await AuthService.cancelAppointment(id);
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment cancelled.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Future<void> _rescheduleAppointment(String id) async {
    if (_isRescheduling) return;
    setState(() => _isRescheduling = true);
    try {
      final now = DateTime.now();
      final date = await showDatePicker(
        context: context,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
        initialDate: now.add(const Duration(days: 1)),
      );
      if (date == null || !mounted) {
        setState(() => _isRescheduling = false);
        return;
      }
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 2))),
      );
      if (time == null || !mounted) {
        setState(() => _isRescheduling = false);
        return;
      }
      final newTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      final updated = await AuthService.rescheduleAppointment(
        appointmentId: id,
        scheduledAt: newTime,
      );
      final reminder = await AuthService.getAppointmentReminder(
        updated['id'].toString(),
      );
      final reminderAt = DateTime.tryParse(
        reminder['reminder_at']?.toString() ?? '',
      );
      if (reminderAt != null) {
        await LocalNotificationService.scheduleAppointmentReminder(
          notificationId: updated['id'].toString().hashCode,
          title: 'Appointment Reminder',
          body:
              'Upcoming appointment with ${updated['provider']?['name'] ?? 'provider'}',
          remindAt: reminderAt.toLocal(),
        );
      }
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment rescheduled.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reschedule failed: $e')));
    } finally {
      if (mounted) setState(() => _isRescheduling = false);
    }
  }

  Future<void> _submitReview(Map<String, dynamic> provider) async {
    int rating = 5;
    final reviewController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Review ${provider['name'] ?? 'Provider'}'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: rating,
                  items: List.generate(
                    5,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('${index + 1} star'),
                    ),
                  ),
                  onChanged: (v) => setDialogState(() => rating = v ?? 5),
                  decoration: const InputDecoration(
                    labelText: 'Rating',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reviewController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Review (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AuthService.submitProviderReview(
        providerId: provider['id'].toString(),
        rating: rating,
        reviewText: reviewController.text,
      );
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review submitted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Review failed: $e')));
    } finally {
      reviewController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _userRole == 'provider' ? 'Patient Bookings' : 'Appointment Management';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF1F6E4A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: _userRole == 'provider'
                    ? [
                        _buildPatientBookingsCard(),
                      ]
                    : [
                        _buildProviderSearchCard(),
                        const SizedBox(height: 16),
                        _buildBookingCard(),
                        const SizedBox(height: 16),
                        _buildAppointmentsCard(),
                      ],
              ),
            ),
    );
  }

  Widget _buildProviderSearchCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Doctor/Hospital Search',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Name or specialty',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cityController,
              decoration: const InputDecoration(
                labelText: 'City',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _providerType,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'doctor', child: Text('Doctor')),
                DropdownMenuItem(value: 'hospital', child: Text('Hospital')),
              ],
              onChanged: (v) => setState(() => _providerType = v ?? 'all'),
              decoration: const InputDecoration(
                labelText: 'Provider type',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Search'),
            ),
            const SizedBox(height: 12),
            ..._providers.map((provider) {
              final selected = _selectedProvider?['id'] == provider['id'];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(provider['name']?.toString() ?? 'Unknown'),
                subtitle: Text(
                  '${provider['provider_type']} • ${provider['specialty'] ?? ''}\n'
                  'Rating: ${provider['average_rating'] ?? 0} (${provider['total_reviews'] ?? 0} reviews)',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Submit review',
                      onPressed: () => _submitReview(provider),
                      icon: const Icon(Icons.reviews_outlined),
                    ),
                    selected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => setState(() => _selectedProvider = provider),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Book Appointment',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedProvider == null
                  ? 'No provider selected'
                  : 'Provider: ${_selectedProvider!['name']}',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickDateTime,
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _selectedDateTime == null
                    ? 'Pick date & time'
                    : DateFormat('EEE, dd MMM yyyy • HH:mm').format(
                        _selectedDateTime!,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isBooking ? null : _bookAppointment,
              icon: const Icon(Icons.event_available),
              label: Text(_isBooking ? 'Booking...' : 'Book now'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Appointments',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (_appointments.isEmpty)
              const Text('No appointments yet.')
            else
              ..._appointments.map((appointment) {
                final provider = appointment['provider'] as Map<String, dynamic>?;
                final scheduledAt =
                    DateTime.tryParse(appointment['scheduled_at']?.toString() ?? '');
                final status = appointment['status']?.toString() ?? 'booked';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(provider?['name']?.toString() ?? 'Provider'),
                  subtitle: Text(
                    '${scheduledAt != null ? DateFormat('EEE, dd MMM yyyy • HH:mm').format(scheduledAt.toLocal()) : 'Unknown time'}\n'
                    'Status: $status',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (_isCancelling || _isRescheduling) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please wait, processing action...')),
                        );
                        return;
                      }
                      if (action == 'reschedule') {
                        _rescheduleAppointment(appointment['id'].toString());
                      } else if (action == 'cancel') {
                        _cancelAppointment(appointment['id'].toString());
                      } else if (action == 'reminder') {
                        AuthService.getAppointmentReminder(
                          appointment['id'].toString(),
                        ).then((reminder) {
                          if (!mounted) return;
                          final reminderAt = DateTime.tryParse(
                            reminder['reminder_at']?.toString() ?? '',
                          );
                          if (reminderAt != null) {
                            LocalNotificationService.scheduleAppointmentReminder(
                              notificationId:
                                  appointment['id'].toString().hashCode,
                              title: 'Appointment Reminder',
                              body:
                                  'Upcoming appointment with ${provider?['name'] ?? 'provider'}',
                              remindAt: reminderAt.toLocal(),
                            );
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                reminder['message']?.toString() ??
                                    'Reminder configured.',
                              ),
                            ),
                          );
                        });
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'reschedule',
                        child: Text('Reschedule'),
                      ),
                      PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                      PopupMenuItem(
                        value: 'reminder',
                        child: Text('Reminder'),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _respondAndConsult(Map<String, dynamic> appointment, String patientName, String patientId) async {
    final responseController = TextEditingController();
    responseController.text = "Hello $patientName, I received your booking request for the appointment scheduled on ${appointment['scheduled_at'] != null ? DateFormat('EEE, dd MMM yyyy • HH:mm').format(DateTime.parse(appointment['scheduled_at']).toLocal()) : ''}. How can I assist you today?";
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Respond to $patientName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will send an initial response message and create an active consultation thread.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: responseController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Response Message',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F6E4A), foregroundColor: Colors.white),
            child: const Text('Send & Open Chat'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    
    setState(() => _isLoading = true);
    try {
      await AuthService.createConsultationThread(
        providerId: appointment['provider']?['id']?.toString() ?? '',
        subject: 'Consultation about: ${appointment['reason'] ?? 'Appointment'}',
        consultationType: 'chat',
        openingMessage: responseController.text.trim(),
        patientId: patientId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Consultation started successfully! Redirecting...')),
      );
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ConsultationsScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start consultation: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      responseController.dispose();
    }
  }

  Widget _buildPatientBookingsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Incoming Bookings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1F6E4A)),
            ),
            const SizedBox(height: 12),
            if (_appointments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No patient bookings found.',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              )
            else
              ..._appointments.map((appointment) {
                final patient = appointment['patient'] as Map<String, dynamic>?;
                final scheduledAt = DateTime.tryParse(appointment['scheduled_at']?.toString() ?? '');
                final status = appointment['status']?.toString() ?? 'booked';
                final reason = appointment['reason']?.toString() ?? 'No reason provided';
                
                if (patient == null || patient['role'] != 'user') return const SizedBox.shrink();

                final patientName = patient['full_name']?.toString() ?? 'Patient';
                final patientEmail = patient['email']?.toString() ?? '';
                final patientPhone = patient['phone_number']?.toString() ?? 'No phone number';
                final patientAge = patient['age']?.toString() ?? '';
                final patientGender = patient['gender']?.toString() ?? '';
                
                final ageGenderText = [
                  if (patientAge.isNotEmpty) '$patientAge yrs',
                  if (patientGender.isNotEmpty) patientGender
                ].join(' • ');

                final picBase64 = patient['profile_picture']?.toString();
                Uint8List? picBytes;
                if (picBase64 != null && picBase64.isNotEmpty) {
                  try {
                    final cleanBase64 = picBase64.contains(',') ? picBase64.split(',').last : picBase64;
                    picBytes = base64Decode(cleanBase64.trim());
                  } catch (_) {}
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  color: Colors.grey.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: const Color(0xFF1F6E4A).withAlpha(31),
                              backgroundImage: picBytes != null ? MemoryImage(picBytes) : null,
                              child: picBytes != null
                                  ? null
                                  : Text(
                                      patientName.isNotEmpty ? patientName[0].toUpperCase() : 'P',
                                      style: const TextStyle(
                                        color: Color(0xFF1F6E4A),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    patientName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (ageGenderText.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      ageGenderText,
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                    ),
                                  ],
                                  const SizedBox(height: 2),
                                    Text(
                                      '$patientEmail • $patientPhone',
                                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'reschedule') {
                                  _rescheduleAppointment(appointment['id'].toString());
                                } else if (action == 'cancel') {
                                  _cancelAppointment(appointment['id'].toString());
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'reschedule', child: Text('Reschedule')),
                                PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          children: [
                            const Icon(Icons.event_outlined, size: 16, color: Color(0xFF1F6E4A)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                scheduledAt != null
                                    ? DateFormat('EEEE, dd MMM yyyy • HH:mm').format(scheduledAt.toLocal())
                                    : 'Unknown time',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: status == 'booked'
                                    ? Colors.blue.shade50
                                    : status == 'cancelled'
                                        ? Colors.red.shade50
                                        : Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: status == 'booked'
                                      ? Colors.blue.shade700
                                      : status == 'cancelled'
                                          ? Colors.red.shade700
                                          : Colors.amber.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.description_outlined, size: 16, color: Colors.grey),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Reason: $reason',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _respondAndConsult(appointment, patientName, patient['id'].toString()),
                            icon: const Icon(Icons.forum_outlined, size: 18),
                            label: const Text(
                              'RESPOND & START CONSULTATION',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1F6E4A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
