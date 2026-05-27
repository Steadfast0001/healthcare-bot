import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling_service.dart';

class CallScreen extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;
  final bool isVideoCall;
  final bool isCaller;

  const CallScreen({
    Key? key,
    required this.targetUserId,
    required this.targetUserName,
    this.isVideoCall = true,
    this.isCaller = true,
  }) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final SignalingService _signalingService = SignalingService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  bool _isMicMuted = false;
  bool _isVideoEnabled = true;

  @override
  void initState() {
    super.initState();
    _isVideoEnabled = widget.isVideoCall;
    _initRenderers();
    _connectAndSetupWebRTC();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _connectAndSetupWebRTC() async {
    // 1. Connect to signaling server
    await _signalingService.connect(widget.targetUserId);
    _signalingService.onMessage = _handleSignalingMessage;

    // 2. Setup WebRTC Peer Connection
    await _createPeerConnection();

    // 3. Get local media
    await _getUserMedia();

    // 4. If we are the caller, send an offer
    if (widget.isCaller) {
      _createOffer();
    }
  }

  Future<void> _createPeerConnection() async {
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"url": "stun:stun.l.google.com:19302"},
        {"url": "stun:stun1.l.google.com:19302"},
      ]
    };

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };

    _peerConnection = await createPeerConnection(configuration, offerSdpConstraints);

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      debugPrint('Got ICE candidate');
      _signalingService.sendIceCandidate(candidate);
    };

    _peerConnection!.onAddStream = (MediaStream stream) {
      debugPrint('Got remote stream');
      setState(() {
        _remoteStream = stream;
        _remoteRenderer.srcObject = _remoteStream;
      });
    };
  }

  Future<void> _getUserMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': _isVideoEnabled ? {'facingMode': 'user'} : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      
      // Add tracks to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
      
      setState(() {});
    } catch (e) {
      debugPrint("Error accessing media devices: $e");
    }
  }

  Future<void> _createOffer() async {
    try {
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      _signalingService.sendOffer(offer);
    } catch (e) {
      debugPrint("Error creating offer: $e");
    }
  }

  void _handleSignalingMessage(String type, Map<String, dynamic> data, String senderId) async {
    if (senderId != widget.targetUserId) return; // Ignore messages from others

    switch (type) {
      case 'offer':
        final offer = RTCSessionDescription(data['sdp'], type);
        await _peerConnection!.setRemoteDescription(offer);
        // Create answer
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _signalingService.sendAnswer(answer);
        break;
      case 'answer':
        final answer = RTCSessionDescription(data['sdp'], type);
        await _peerConnection!.setRemoteDescription(answer);
        break;
      case 'ice_candidate':
        final candidateData = data['candidate'];
        final candidate = RTCIceCandidate(
          candidateData['candidate'],
          candidateData['sdpMid'],
          candidateData['sdpMLineIndex'],
        );
        await _peerConnection!.addCandidate(candidate);
        break;
      case 'hangup':
        _endCall();
        break;
    }
  }

  void _toggleMic() {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks()[0];
      audioTrack.enabled = !audioTrack.enabled;
      setState(() {
        _isMicMuted = !audioTrack.enabled;
      });
    }
  }

  void _toggleCamera() async {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isEmpty) {
        // Upgrade from Audio to Video call
        try {
          final newStream = await navigator.mediaDevices.getUserMedia({'video': true});
          final newVideoTrack = newStream.getVideoTracks()[0];
          _localStream!.addTrack(newVideoTrack);
          _peerConnection!.addTrack(newVideoTrack, _localStream!);
          // renegotiation needed, ideally create an offer again
          _createOffer();
          setState(() {
            _isVideoEnabled = true;
          });
        } catch (e) {
          debugPrint("Failed to enable video: $e");
        }
      } else {
        // Toggle existing video track
        final videoTrack = videoTracks[0];
        videoTrack.enabled = !videoTrack.enabled;
        setState(() {
          _isVideoEnabled = videoTrack.enabled;
        });
      }
    }
  }

  void _endCall() {
    _signalingService.sendHangup();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peerConnection?.close();
    _signalingService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.targetUserName),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Remote Video (Full Screen)
          if (_remoteStream != null && _remoteStream!.getVideoTracks().isNotEmpty)
            RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.blue.withValues(alpha: 0.2),
                    child: Icon(Icons.person, size: 50, color: Colors.blue),
                  ),
                  SizedBox(height: 20),
                  Text(
                    "Calling ${widget.targetUserName}...",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
            
          // Local Video (Picture in Picture)
          if (_isVideoEnabled)
            Positioned(
              right: 20,
              bottom: 120,
              child: Container(
                width: 100,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),

          // Call Controls
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FloatingActionButton(
                    heroTag: "btn_mic",
                    backgroundColor: _isMicMuted ? Colors.red : Colors.white24,
                    onPressed: _toggleMic,
                    child: Icon(
                      _isMicMuted ? Icons.mic_off : Icons.mic,
                      color: Colors.white,
                    ),
                  ),
                  FloatingActionButton(
                    heroTag: "btn_hangup",
                    backgroundColor: Colors.red,
                    onPressed: _endCall,
                    child: Icon(Icons.call_end, color: Colors.white),
                  ),
                  FloatingActionButton(
                    heroTag: "btn_cam",
                    backgroundColor: _isVideoEnabled ? Colors.white24 : Colors.red,
                    onPressed: _toggleCamera,
                    child: Icon(
                      _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
