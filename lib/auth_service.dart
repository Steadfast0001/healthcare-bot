import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthRequiredException implements Exception {
  final String message;

  const AuthRequiredException([
    this.message = 'Your session has expired. Please sign in again.',
  ]);

  @override
  String toString() => message;
}

class AuthService {
  static const int maxEmergencyContacts = 10;
  static String get _baseUrl {
    if (kIsWeb) {
      final browserUri = Uri.base;
      final host = browserUri.host.isEmpty ? '127.0.0.1' : browserUri.host;
      final scheme = browserUri.scheme == 'https' ? 'https' : 'http';
      return Uri(scheme: scheme, host: host, port: 8001).toString();
    }

    final configuredUrl = dotenv.env['BACKEND_URL']?.trim();
    final rawUrl = configuredUrl != null && configuredUrl.isNotEmpty
        ? configuredUrl
        : 'http://localhost:8001';

    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.host.isEmpty) {
      return 'http://localhost:8001';
    }

    if (!kIsWeb && Platform.isAndroid) {
      final host = uri.host;
      // For Android emulator: convert localhost to the emulator host alias.
      if (host == 'localhost') {
        return uri.replace(host: '10.0.2.2').toString();
      }

      // For a real Android device using adb reverse, keep 127.0.0.1 as configured.
      // For emulator aliases or explicit remote hosts, preserve the raw URL.
      if (host == '10.0.2.2' || host == '10.0.3.2' || host == '127.0.0.1') {
        return rawUrl;
      }
    }

    return rawUrl;
  }

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<void> saveToken(String token) async {
    final prefs = await _prefs;
    await prefs.setString('auth_token', token);
  }

  static Future<String?> getToken() async {
    final prefs = await _prefs;
    return prefs.getString('auth_token');
  }

  static Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> logout() async {
    try {
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        final headers = await authHeaders();
        await http.post(
          Uri.parse('$_baseUrl/auth/logout'),
          headers: headers,
        ).timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      // Best-effort logout: ignore server errors so the user is always logged out locally
      debugPrint('Error calling backend logout: $e');
    } finally {
      final prefs = await _prefs;
      await prefs.remove('auth_token');
      await prefs.remove('saved_email');
    }
  }

  static Future<Map<String, String>> authHeaders() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw const AuthRequiredException();
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static bool isAuthenticationError(Object error) {
    if (error is AuthRequiredException) {
      return true;
    }

    final message = error.toString().toLowerCase();
    return message.contains('authentication token') ||
        message.contains('session has expired') ||
        message.contains('sign in again') ||
        message.contains('not authenticated') ||
        message.contains('unauthorized') ||
        message.contains('401');
  }

  static String _formatNetworkError(dynamic error) {
    if (error is AuthRequiredException) {
      return error.message;
    }
    if (error is SocketException) {
      return 'Network connection failed. Please check:\n'
          '1. Your device is connected to WiFi or mobile data\n'
          '2. Backend server is running (run_backend.bat on Windows)\n'
          '3. Backend URL is correct in .env file';
    } else if (error is http.ClientException) {
      return 'Could not connect to backend server.\n'
          'Check that the backend is running on: $_baseUrl\n'
          'Run: run_backend.bat on your development machine';
    } else if (error is TimeoutException) {
      return 'Connection timeout. Backend server may be slow or unreachable.\n'
          'Ensure the server is running at: $_baseUrl';
    }
    return 'Network error: $error\n'
        'Backend URL: $_baseUrl\n'
        'Check your internet connection and backend server status.';
  }

  static Future<Map<String, dynamic>> signup({
    required String fullName,
    required String email,
    String? phoneNumber,
    required String password,
    required String confirmPassword,
    String? username,
    String? role,
    String? licenseNumber,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/signup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'full_name': fullName,
              'email': email,
              if (phoneNumber != null && phoneNumber.isNotEmpty)
                'phone_number': phoneNumber,
              'password': password,
              'confirm_password': confirmPassword,
              if (username != null && username.isNotEmpty) 'username': username,
              if (role != null) 'role': role,
              if (licenseNumber != null && licenseNumber.isNotEmpty)
                'license_number': licenseNumber,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(response.body);
    } on SocketException catch (e) {
      return {'detail': _formatNetworkError(e), 'error_type': 'network'};
    } on TimeoutException catch (_) {
      return {
        'detail': _formatNetworkError(TimeoutException('Request timeout')),
        'error_type': 'timeout',
      };
    } catch (e) {
      return {'detail': _formatNetworkError(e), 'error_type': 'network'};
    }
  }

  static Future<bool> checkBackendConnection() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/health'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        try {
          final body = jsonDecode(response.body);
          return body['status'] == 'ok';
        } catch (_) {
          return true; // Assume OK if we got 200
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
    required bool rememberMe,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email_or_username': identifier,
              'password': password,
              'remember_me': rememberMe,
            }),
          )
          .timeout(const Duration(seconds: 10));

      // Try to parse response
      try {
        return jsonDecode(response.body);
      } catch (_) {
        // If response is not JSON, return error with status code info
        return {
          'detail':
              'Server returned unexpected response (Status: ${response.statusCode})',
          'error_type': 'server_error',
        };
      }
    } on SocketException catch (e) {
      return {'detail': _formatNetworkError(e), 'error_type': 'network'};
    } on TimeoutException catch (_) {
      return {
        'detail': _formatNetworkError(TimeoutException('Request timeout')),
        'error_type': 'timeout',
      };
    } catch (e) {
      return {'detail': _formatNetworkError(e), 'error_type': 'network'};
    }
  }

  static Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/forgot-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(response.body);
    } on SocketException catch (e) {
      return {'detail': _formatNetworkError(e)};
    } on TimeoutException catch (_) {
      return {
        'detail': _formatNetworkError(TimeoutException('Request timeout')),
      };
    } catch (e) {
      return {'detail': _formatNetworkError(e)};
    }
  }

  static Future<Map<String, dynamic>> resetPassword({
    required String token,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/reset-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': token,
              'password': password,
              'confirm_password': confirmPassword,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(response.body);
    } on SocketException catch (e) {
      return {'detail': _formatNetworkError(e)};
    } on TimeoutException catch (_) {
      return {
        'detail': _formatNetworkError(TimeoutException('Request timeout')),
      };
    } catch (e) {
      return {'detail': _formatNetworkError(e)};
    }
  }

  static Future<Map<String, dynamic>> verifyEmail({
    required String token,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/auth/verify-email?token=$token'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(response.body);
    } on SocketException catch (e) {
      return {'detail': _formatNetworkError(e)};
    } on TimeoutException catch (_) {
      return {
        'detail': _formatNetworkError(TimeoutException('Request timeout')),
      };
    } catch (e) {
      return {'detail': _formatNetworkError(e)};
    }
  }

  static Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      final headers = await authHeaders();
      final response = await http
          .get(Uri.parse('$_baseUrl/auth/me'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['detail'] ?? 'Failed to retrieve user');
      }

      return jsonDecode(response.body);
    } on AuthRequiredException {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  static Future<Map<String, dynamic>> updateProfile({
    String? fullName,
    String? phoneNumber,
    int? age,
    String? gender,
    String? country,
    String? city,
    String? emergencyContactName,
    String? emergencyContactPhone,
    List<Map<String, dynamic>>? emergencyContacts,
    String? allergies,
    String? knownConditions,
    String? medicalHistory,
    String? specialty,
    String? providerType,
    String? workingExperience,
    String? licenseNumber,
    String? profilePicture,
  }) async {
    try {
      final headers = await authHeaders();
      final payload = <String, dynamic>{};
      if (fullName != null) payload['full_name'] = fullName;
      if (phoneNumber != null) payload['phone_number'] = phoneNumber;
      if (age != null) payload['age'] = age;
      if (gender != null) payload['gender'] = gender;
      if (country != null) payload['country'] = country;
      if (city != null) payload['city'] = city;
      if (emergencyContactName != null) {
        payload['emergency_contact_name'] = emergencyContactName;
      }
      if (emergencyContactPhone != null) {
        payload['emergency_contact_phone'] = emergencyContactPhone;
      }
      if (emergencyContacts != null) {
        payload['emergency_contacts'] = emergencyContacts;
      }
      if (allergies != null) payload['allergies'] = allergies;
      if (knownConditions != null) {
        payload['known_conditions'] = knownConditions;
      }
      if (medicalHistory != null) {
        payload['medical_history'] = medicalHistory;
      }
      if (specialty != null) payload['specialty'] = specialty;
      if (providerType != null) payload['provider_type'] = providerType;
      if (workingExperience != null) {
        payload['working_experience'] = workingExperience;
      }
      if (licenseNumber != null) payload['license_number'] = licenseNumber;
      if (profilePicture != null) payload['profile_picture'] = profilePicture;

      final response = await http
          .put(
            Uri.parse('$_baseUrl/auth/me'),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['detail'] ?? 'Failed to update profile');
      }

      return jsonDecode(response.body);
    } on AuthRequiredException {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  static Future<List<Map<String, dynamic>>> getChatHistory() async {
    try {
      final headers = await authHeaders();
      final response = await http
          .get(Uri.parse('$_baseUrl/chat/history'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to load chat history');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } on AuthRequiredException {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  static Future<void> clearChatHistory() async {
    try {
      final headers = await authHeaders();
      final response = await http
          .delete(Uri.parse('$_baseUrl/chat/history'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to clear chat history');
      }
    } on AuthRequiredException {
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getHealthTips() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health-tips'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to load health tips');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  static Future<Map<String, dynamic>> submitSymptomAssessment({
    required List<String> symptoms,
    String? notes,
  }) async {
    try {
      final headers = await authHeaders();
      final response = await http
          .post(
            Uri.parse('$_baseUrl/symptom-assessment'),
            headers: headers,
            body: jsonEncode({
              'symptoms': symptoms,
              if (notes != null && notes.trim().isNotEmpty)
                'notes': notes.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthRequiredException catch (e) {
      return {'detail': e.message, 'requires_auth': true};
    } on SocketException catch (e) {
      return {'detail': _formatNetworkError(e)};
    } on TimeoutException catch (_) {
      return {
        'detail': _formatNetworkError(TimeoutException('Request timeout')),
      };
    } catch (e) {
      return {'detail': _formatNetworkError(e)};
    }
  }

  static Future<String?> getSavedEmail() async {
    final prefs = await _prefs;
    return prefs.getString('saved_email');
  }

  static bool isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(email);
  }

  static bool isStrongPassword(String password) {
    final regex = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^\w\s]).{8,}$');
    return regex.hasMatch(password);
  }

  static Future<List<Map<String, dynamic>>> searchProviders({
    String? query,
    String? providerType,
    String? city,
  }) async {
    final headers = await authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/providers/search',
    ).replace(
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
        if (providerType != null && providerType.trim().isNotEmpty)
          'provider_type': providerType.trim(),
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
      },
    );
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Failed to load providers');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getAppointments() async {
    final headers = await authHeaders();
    final response = await http
        .get(Uri.parse('$_baseUrl/appointments'), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Failed to load appointments');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> bookAppointment({
    required String providerId,
    required DateTime scheduledAt,
    String? reason,
    int reminderMinutesBefore = 60,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .post(
          Uri.parse('$_baseUrl/appointments'),
          headers: headers,
          body: jsonEncode({
            'provider_id': providerId,
            'scheduled_at': scheduledAt.toUtc().toIso8601String(),
            if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
            'reminder_minutes_before': reminderMinutesBefore,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to book appointment');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> rescheduleAppointment({
    required String appointmentId,
    required DateTime scheduledAt,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .patch(
          Uri.parse('$_baseUrl/appointments/$appointmentId/reschedule'),
          headers: headers,
          body: jsonEncode({'scheduled_at': scheduledAt.toUtc().toIso8601String()}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to reschedule appointment');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> cancelAppointment(
    String appointmentId,
  ) async {
    final headers = await authHeaders();
    final response = await http
        .patch(
          Uri.parse('$_baseUrl/appointments/$appointmentId/cancel'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to cancel appointment');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> getAppointmentReminder(
    String appointmentId,
  ) async {
    final headers = await authHeaders();
    final response = await http
        .get(
          Uri.parse('$_baseUrl/appointments/$appointmentId/reminder'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to get reminder');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> submitProviderReview({
    required String providerId,
    required int rating,
    String? reviewText,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .post(
          Uri.parse('$_baseUrl/providers/$providerId/reviews'),
          headers: headers,
          body: jsonEncode({
            'rating': rating,
            if (reviewText != null && reviewText.trim().isNotEmpty)
              'review_text': reviewText.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to submit review');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<List<Map<String, dynamic>>> getVitals({String? patientId}) async {
    final headers = await authHeaders();
    final url = patientId != null
        ? '$_baseUrl/health-tracker/vitals?patient_id=$patientId'
        : '$_baseUrl/health-tracker/vitals';
    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Failed to load vitals');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> logVitals({
    int? systolicBp,
    int? diastolicBp,
    int? bloodGlucose,
    int? heartRate,
    double? temperature,
    double? weight,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .post(
          Uri.parse('$_baseUrl/health-tracker/vitals'),
          headers: headers,
          body: jsonEncode({
            if (systolicBp != null) 'systolic_bp': systolicBp,
            if (diastolicBp != null) 'diastolic_bp': diastolicBp,
            if (bloodGlucose != null) 'blood_glucose': bloodGlucose,
            if (heartRate != null) 'heart_rate': heartRate,
            if (temperature != null) 'temperature': temperature,
            if (weight != null) 'weight': weight,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to log vitals');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<List<Map<String, dynamic>>> getActivityLogs({String? patientId}) async {
    final headers = await authHeaders();
    final url = patientId != null
        ? '$_baseUrl/health-tracker/activity?patient_id=$patientId'
        : '$_baseUrl/health-tracker/activity';
    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Failed to load activity logs');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> logActivity({
    int? steps,
    int? caloriesBurned,
    int? waterIntake,
    double? sleepHours,
    int? caloriesConsumed,
    String? mealNotes,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .post(
          Uri.parse('$_baseUrl/health-tracker/activity'),
          headers: headers,
          body: jsonEncode({
            if (steps != null) 'steps': steps,
            if (caloriesBurned != null) 'calories_burned': caloriesBurned,
            if (waterIntake != null) 'water_intake': waterIntake,
            if (sleepHours != null) 'sleep_hours': sleepHours,
            if (caloriesConsumed != null) 'calories_consumed': caloriesConsumed,
            if (mealNotes != null && mealNotes.trim().isNotEmpty)
              'meal_notes': mealNotes.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to log activity');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<List<Map<String, dynamic>>> getGoals({String? patientId}) async {
    final headers = await authHeaders();
    final url = patientId != null
        ? '$_baseUrl/health-tracker/goals?patient_id=$patientId'
        : '$_baseUrl/health-tracker/goals';
    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Failed to load goals');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> createGoal({
    required String goalType,
    required double targetValue,
    required DateTime targetDate,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .post(
          Uri.parse('$_baseUrl/health-tracker/goals'),
          headers: headers,
          body: jsonEncode({
            'goal_type': goalType,
            'target_value': targetValue,
            'target_date': targetDate.toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to create goal');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> updateGoalProgress(
    String goalId, {
    required double currentValue,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .patch(
          Uri.parse('$_baseUrl/health-tracker/goals/$goalId/progress'),
          headers: headers,
          body: jsonEncode({
            'current_value': currentValue,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to update goal progress');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<void> deleteGoal(String goalId) async {
    final headers = await authHeaders();
    final response = await http
        .delete(
          Uri.parse('$_baseUrl/health-tracker/goals/$goalId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to delete goal');
    }
  }

  // ─── Consultations ───────────────────────────────────────────────────────

  static Future<int> getConsultationUnreadCount() async {
    try {
      final headers = await authHeaders();
      final response = await http
          .get(Uri.parse('$_baseUrl/consultations/unread-count'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return 0;
      final decoded = jsonDecode(response.body);
      return (decoded['unread_count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<Map<String, dynamic>>> getConsultationThreads() async {
    final headers = await authHeaders();
    final response = await http
        .get(Uri.parse('$_baseUrl/consultations/threads'), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Failed to load threads');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<Map<String, dynamic>> createConsultationThread({
    required String providerId,
    String subject = '',
    String consultationType = 'chat',
    String openingMessage = '',
    String? patientId,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .post(
          Uri.parse('$_baseUrl/consultations/threads'),
          headers: headers,
          body: jsonEncode({
            'provider_id': providerId,
            'subject': subject,
            'consultation_type': consultationType,
            'opening_message': openingMessage,
            if (patientId != null) 'patient_id': patientId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 201) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to create thread');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> getConsultationThread(String threadId) async {
    final headers = await authHeaders();
    final response = await http
        .get(Uri.parse('$_baseUrl/consultations/threads/$threadId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Failed to load thread');
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> sendConsultationMessage({
    required String threadId,
    String body = '',
    String? attachmentName,
    String? attachmentData,
    String? attachmentMime,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .post(
          Uri.parse('$_baseUrl/consultations/threads/$threadId/messages'),
          headers: headers,
          body: jsonEncode({
            'body': body,
            if (attachmentName != null) 'attachment_name': attachmentName,
            if (attachmentData != null) 'attachment_data': attachmentData,
            if (attachmentMime != null) 'attachment_mime': attachmentMime,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 201) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to send message');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<void> closeConsultationThread(String threadId) async {
    final headers = await authHeaders();
    await http
        .patch(Uri.parse('$_baseUrl/consultations/threads/$threadId/close'), headers: headers)
        .timeout(const Duration(seconds: 10));
  }

  static Future<Map<String, dynamic>> requestConsultationCall({
    required String threadId,
    required String callType,
    String? scheduledCallAt,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .post(
          Uri.parse('$_baseUrl/consultations/threads/$threadId/call-request'),
          headers: headers,
          body: jsonEncode({
            'call_type': callType,
            if (scheduledCallAt != null) 'scheduled_call_at': scheduledCallAt,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to request call');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  // ─── Reports & Records ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> generateHealthReport({
    required String reportType,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .post(
          Uri.parse('$_baseUrl/reports/generate'),
          headers: headers,
          body: jsonEncode({
            'report_type': reportType,
            'period_start': periodStart.toUtc().toIso8601String(),
            'period_end': periodEnd.toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 40));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to generate report');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<List<Map<String, dynamic>>> getHealthReports({String? patientId}) async {
    final headers = await authHeaders();
    final url = patientId != null
        ? '$_baseUrl/reports?patient_id=$patientId'
        : '$_baseUrl/reports';
    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Failed to load reports');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<Map<String, dynamic>> getHealthReport(String reportId) async {
    final headers = await authHeaders();
    final response = await http
        .get(Uri.parse('$_baseUrl/reports/$reportId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Failed to load report');
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<void> deleteHealthReport(String reportId) async {
    final headers = await authHeaders();
    final response = await http
        .delete(Uri.parse('$_baseUrl/reports/$reportId'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Failed to delete report');
  }

  static Future<Map<String, dynamic>> uploadMedicalRecord({
    required String recordType,
    required String title,
    String? notes,
    required String fileName,
    required String fileData,
    required String fileMime,
    String? providerName,
    required DateTime recordDate,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .post(
          Uri.parse('$_baseUrl/records'),
          headers: headers,
          body: jsonEncode({
            'record_type': recordType,
            'title': title,
            'notes': notes,
            'file_name': fileName,
            'file_data': fileData,
            'file_mime': fileMime,
            'provider_name': providerName,
            'record_date': recordDate.toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 40));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to upload record');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<List<Map<String, dynamic>>> getMedicalRecords({String? patientId}) async {
    final headers = await authHeaders();
    final url = patientId != null
        ? '$_baseUrl/records?patient_id=$patientId'
        : '$_baseUrl/records';
    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Failed to load records');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<Map<String, dynamic>> getMedicalRecord(String recordId) async {
    final headers = await authHeaders();
    final response = await http
        .get(Uri.parse('$_baseUrl/records/$recordId'), headers: headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('Failed to load record details');
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<void> deleteMedicalRecord(String recordId) async {
    final headers = await authHeaders();
    final response = await http
        .delete(Uri.parse('$_baseUrl/records/$recordId'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Failed to delete record');
  }

  static Future<Map<String, dynamic>> createShareLink({
    required String shareType,
    String? targetId,
    required String recipientName,
    String? recipientEmail,
    int expiresInDays = 7,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .post(
          Uri.parse('$_baseUrl/share'),
          headers: headers,
          body: jsonEncode({
            'share_type': shareType,
            'target_id': targetId,
            'recipient_name': recipientName,
            'recipient_email': recipientEmail,
            'expires_in_days': expiresInDays,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to create share link');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<List<Map<String, dynamic>>> getShareLinks() async {
    final headers = await authHeaders();
    final response = await http
        .get(Uri.parse('$_baseUrl/share'), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Failed to load share links');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> revokeShareLink(String shareId) async {
    final headers = await authHeaders();
    final response = await http
        .delete(Uri.parse('$_baseUrl/share/$shareId'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Failed to revoke share link');
  }

  static Future<List<Map<String, dynamic>>> getReminders({String? patientId}) async {
    final headers = await authHeaders();
    final url = patientId != null
        ? '$_baseUrl/reminders?patient_id=$patientId'
        : '$_baseUrl/reminders';
    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Failed to load reminders');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> createReminder({
    required String type,
    required String title,
    required String body,
    required DateTime triggerTime,
    String? metadataJson,
    String? patientId,
  }) async {
    final headers = await authHeaders();
    final uri = Uri.parse('$_baseUrl/reminders').replace(
      queryParameters: {
        if (patientId != null) 'patient_id': patientId,
      },
    );
    final response = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode({
            'type': type,
            'title': title,
            'body': body,
            'trigger_time': triggerTime.toUtc().toIso8601String(),
            'metadata_json': metadataJson,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 201) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to create reminder');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> toggleReminder(String id, bool isEnabled) async {
    final headers = await authHeaders();
    final response = await http
        .patch(
          Uri.parse('$_baseUrl/reminders/$id/toggle'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to toggle reminder');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> updateReminder({
    required String id,
    required String type,
    required String title,
    required String body,
    required DateTime triggerTime,
    String? metadataJson,
  }) async {
    final headers = await authHeaders();
    final response = await http
        .put(
          Uri.parse('$_baseUrl/reminders/$id'),
          headers: headers,
          body: jsonEncode({
            'type': type,
            'title': title,
            'body': body,
            'trigger_time': triggerTime.toUtc().toIso8601String(),
            'metadata_json': metadataJson,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to update reminder');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<void> deleteReminder(String id) async {
    final headers = await authHeaders();
    final response = await http
        .delete(Uri.parse('$_baseUrl/reminders/$id'), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 204) {
      throw Exception('Failed to delete reminder');
    }
  }
}




