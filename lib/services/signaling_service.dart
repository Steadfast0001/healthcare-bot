import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef SignalingMessageCallback = void Function(
    String type, Map<String, dynamic> data, String senderId);

class SignalingService {
  WebSocketChannel? _channel;
  SignalingMessageCallback? onMessage;
  String? _targetId;

  Future<void> connect(String targetUserId) async {
    _targetId = targetUserId;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) {
      debugPrint('SignalingService: No auth token found.');
      return;
    }

    final backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://10.0.2.2:8001';
    final wsUrl = backendUrl.replaceAll('http', 'ws');
    final url = '$wsUrl/ws/call/$token';

    debugPrint('SignalingService: Connecting to $url');
    _channel = WebSocketChannel.connect(Uri.parse(url));

    _channel!.stream.listen((message) {
      try {
        final data = jsonDecode(message);
        final type = data['type'];
        final senderId = data['sender_id'];
        
        if (onMessage != null && type != null && senderId != null) {
          onMessage!(type, data, senderId.toString());
        }
      } catch (e) {
        debugPrint('SignalingService: Error parsing message: $e');
      }
    }, onDone: () {
      debugPrint('SignalingService: Connection closed');
    }, onError: (error) {
      debugPrint('SignalingService: WebSocket Error: $error');
    });
  }

  void sendOffer(RTCSessionDescription offer) {
    if (_channel == null || _targetId == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
      'target_id': _targetId,
    }));
  }

  void sendAnswer(RTCSessionDescription answer) {
    if (_channel == null || _targetId == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'answer',
      'sdp': answer.sdp,
      'target_id': _targetId,
    }));
  }

  void sendIceCandidate(RTCIceCandidate candidate) {
    if (_channel == null || _targetId == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'ice_candidate',
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
      'target_id': _targetId,
    }));
  }
  
  void sendHangup() {
    if (_channel == null || _targetId == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'hangup',
      'target_id': _targetId,
    }));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
