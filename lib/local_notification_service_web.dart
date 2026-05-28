// ignore_for_file: uri_does_not_exist, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:web_audio' as audio;
import 'package:flutter/material.dart';
import 'auth_service.dart';

class WebAlarmPlayer {
  static audio.AudioContext? _audioContext;
  static audio.OscillatorNode? _oscillator1;
  static audio.OscillatorNode? _oscillator2;
  static audio.GainNode? _gainNode;
  static bool _isPlaying = false;

  static void start() {
    if (_isPlaying) return;
    try {
      _audioContext = audio.AudioContext();
      _gainNode = _audioContext!.createGain();
      _gainNode!.connectNode(_audioContext!.destination!);
      
      // Siren effect combining sawtooth and sine oscillators
      _oscillator1 = _audioContext!.createOscillator();
      _oscillator1!.type = 'sawtooth';
      _oscillator1!.frequency?.setValueAtTime(880, _audioContext!.currentTime ?? 0.0);
      _oscillator1!.connectNode(_gainNode!);

      _oscillator2 = _audioContext!.createOscillator();
      _oscillator2!.type = 'sine';
      _oscillator2!.frequency?.setValueAtTime(440, _audioContext!.currentTime ?? 0.0);
      _oscillator2!.connectNode(_gainNode!);

      _gainNode!.gain?.setValueAtTime(0.2, _audioContext!.currentTime ?? 0.0);

      _oscillator1!.start2(0);
      _oscillator2!.start2(0);
      _isPlaying = true;
      _oscillate();
    } catch (e) {
      print('Web Alarm Player error: $e');
    }
  }

  static void _oscillate() async {
    while (_isPlaying && _audioContext != null) {
      final now = _audioContext!.currentTime ?? 0.0;
      _oscillator1?.frequency?.setValueAtTime(880, now);
      _oscillator1?.frequency?.linearRampToValueAtTime(1100, now + 0.5);
      _oscillator1?.frequency?.linearRampToValueAtTime(880, now + 1.0);
      
      _oscillator2?.frequency?.setValueAtTime(440, now);
      _oscillator2?.frequency?.linearRampToValueAtTime(550, now + 0.5);
      _oscillator2?.frequency?.linearRampToValueAtTime(440, now + 1.0);
      
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  static void stop() {
    if (!_isPlaying) return;
    _isPlaying = false;
    try {
      _oscillator1?.stop();
      _oscillator2?.stop();
      _oscillator1?.disconnect();
      _oscillator2?.disconnect();
      _gainNode?.disconnect();
      _audioContext?.close();
    } catch (_) {}
    _oscillator1 = null;
    _oscillator2 = null;
    _gainNode = null;
    _audioContext = null;
  }
}

class WebRingingPlayer {
  static audio.AudioContext? _audioContext;
  static audio.OscillatorNode? _osc1;
  static audio.OscillatorNode? _osc2;
  static audio.GainNode? _gainNode;
  static bool _ringing = false;

  static void start() {
    if (_ringing) return;
    _ringing = true;
    _ringLoop();
  }

  static void _ringLoop() async {
    try {
      while (_ringing) {
        _audioContext = audio.AudioContext();
        _gainNode = _audioContext!.createGain();
        _gainNode!.connectNode(_audioContext!.destination!);

        _osc1 = _audioContext!.createOscillator();
        _osc1!.type = 'sine';
        _osc1!.frequency?.setValueAtTime(440, _audioContext!.currentTime ?? 0.0);
        _osc1!.connectNode(_gainNode!);

        _osc2 = _audioContext!.createOscillator();
        _osc2!.type = 'sine';
        _osc2!.frequency?.setValueAtTime(480, _audioContext!.currentTime ?? 0.0);
        _osc2!.connectNode(_gainNode!);

        _gainNode!.gain?.setValueAtTime(0.0, _audioContext!.currentTime ?? 0.0);
        _gainNode!.gain?.linearRampToValueAtTime(0.2, (_audioContext!.currentTime ?? 0.0) + 0.1);
        _gainNode!.gain?.setValueAtTime(0.2, (_audioContext!.currentTime ?? 0.0) + 1.8);
        _gainNode!.gain?.linearRampToValueAtTime(0.0, (_audioContext!.currentTime ?? 0.0) + 2.0);

        _osc1!.start2(0);
        _osc2!.start2(0);

        await Future.delayed(const Duration(seconds: 2));

        _osc1?.stop();
        _osc2?.stop();
        _audioContext?.close();

        if (!_ringing) break;
        await Future.delayed(const Duration(seconds: 4));
      }
    } catch (_) {}
  }

  static void stop() {
    _ringing = false;
    try {
      _osc1?.stop();
      _osc2?.stop();
      _audioContext?.close();
    } catch (_) {}
  }
}

class LocalNotificationService {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final Map<int, Timer> _activeTimers = {};

  static Future<void> initialize() async {
    // Web initialization
  }

  static void startRinging() {
    WebRingingPlayer.start();
  }

  static void stopRinging() {
    WebRingingPlayer.stop();
  }

  static Future<void> scheduleAppointmentReminder({
    required int notificationId,
    required String title,
    required String body,
    required DateTime remindAt,
  }) async {
    await scheduleNotification(
      notificationId: notificationId,
      title: title,
      body: body,
      remindAt: remindAt,
      payload: 'appointment',
    );
  }

  static Future<void> scheduleNotification({
    required int notificationId,
    required String title,
    required String body,
    required DateTime remindAt,
    String? payload,
  }) async {
    cancelReminder(notificationId);
    
    final delay = remindAt.difference(DateTime.now());
    if (delay.isNegative) return; // Do not schedule in the past
    
    final timer = Timer(delay, () {
      _triggerAlarm(title, body);
    });
    _activeTimers[notificationId] = timer;
  }

  static Future<void> cancelReminder(int notificationId) async {
    _activeTimers[notificationId]?.cancel();
    _activeTimers.remove(notificationId);
  }

  static void _triggerAlarm(String title, String body) {
    WebAlarmPlayer.start();
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) {
      print('Warning: navigatorKey context is null when triggering alarm.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151D30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF222F4D)),
          ),
          title: Row(
            children: const [
              Icon(Icons.alarm, color: Color(0xFFE53935), size: 28),
              SizedBox(width: 12),
              Text('Alarm Alert!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(body, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                WebAlarmPlayer.stop();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
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
}
