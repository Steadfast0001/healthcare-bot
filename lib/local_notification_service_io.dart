import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'auth_service.dart';

class LocalNotificationService {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _notifications.initialize(settings: settings);

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> scheduleAppointmentReminder({
    required int notificationId,
    required String title,
    required String body,
    required DateTime remindAt,
  }) async {
    final target = remindAt.isBefore(DateTime.now())
        ? DateTime.now().add(const Duration(seconds: 2))
        : remindAt;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'appointments',
        'Appointments',
        channelDescription: 'Appointment reminders and notifications',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    await _notifications.zonedSchedule(
      id: notificationId,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(target, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'appointment_reminder',
    );
  }

  static Future<void> scheduleNotification({
    required int notificationId,
    required String title,
    required String body,
    required DateTime remindAt,
    String? payload,
  }) async {
    final target = remindAt.isBefore(DateTime.now())
        ? DateTime.now().add(const Duration(seconds: 2))
        : remindAt;
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        'reminders',
        'Reminders & Alerts',
        channelDescription: 'Medication alerts and health check reminders',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    await _notifications.zonedSchedule(
      id: notificationId,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(target, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload ?? 'reminder',
    );
  }

  static Future<void> cancelReminder(int notificationId) async {
    await _notifications.cancel(id: notificationId);
  }

  static Future<void> syncAlarmsFromServer() async {
    try {
      final reminders = await AuthService.getReminders();
      for (final r in reminders) {
        if (r['is_enabled'] == true) {
          final idStr = r['id'].toString();
          final triggerTimeStr = r['trigger_time']?.toString() ?? '';
          final triggerTime = DateTime.tryParse(triggerTimeStr);
          if (triggerTime != null && triggerTime.isAfter(DateTime.now())) {
            await scheduleNotification(
              notificationId: idStr.hashCode,
              title: r['title'] ?? 'Reminder',
              body: r['body'] ?? '',
              remindAt: triggerTime.toLocal(),
              payload: r['type'],
            );
          }
        }
      }
    } catch (_) {}
  }

  static void startRinging() {
    // Stub
  }

  static void stopRinging() {
    // Stub
  }
}
