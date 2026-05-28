import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'auth_service.dart';
import 'emergency_screen.dart';
import 'main.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final String riskLevel;
  final List<String> possibleConditions;
  final String? recommendedAction;
  final String? followUpQuestion;
  final String? disclaimer;
  final String? warning;
  final DateTime timestamp;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.riskLevel = 'low',
    this.possibleConditions = const [],
    this.recommendedAction,
    this.followUpQuestion,
    this.disclaimer,
    this.warning,
    required this.timestamp,
  });

  bool get isEmergency => riskLevel == 'emergency';
  bool get isHighRisk => riskLevel == 'high' || riskLevel == 'emergency';
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  static const _quickPrompts = <String>[
    'I have fever and headache',
    'How can I prevent malaria?',
    'When should I see a doctor?',
    'I feel chest pain',
  ];

  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _textFieldFocus = FocusNode();
  late final AnimationController _thinkingController;

  bool _isThinking = false;
  bool _isLoadingHistory = true;
  bool _isRedirectingToAuth = false;
  String? _lastSubmittedText;

  @override
  void initState() {
    super.initState();
    _thinkingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _loadHistory();
  }

  @override
  void dispose() {
    _thinkingController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _textFieldFocus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (!await AuthService.hasToken()) {
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
      await _redirectToAuthentication(
        message: 'Please sign in to view your healthcare chat.',
      );
      return;
    }

    try {
      final history = await AuthService.getChatHistory();
      final messages = <ChatMessage>[];

      for (final entry in history) {
        final timestamp =
            DateTime.tryParse(entry['created_at']?.toString() ?? '') ??
            DateTime.now();

        messages.add(
          ChatMessage(
            text: entry['user_message']?.toString() ?? '',
            isUser: true,
            timestamp: timestamp,
          ),
        );
        messages.add(
          ChatMessage(
            text: entry['ai_response']?.toString() ?? '',
            isUser: false,
            riskLevel: entry['risk_level']?.toString() ?? 'low',
            possibleConditions:
                (entry['possible_conditions'] as List?)
                    ?.map((item) => item.toString())
                    .toList() ??
                const [],
            recommendedAction: entry['recommended_action']?.toString(),
            followUpQuestion: entry['follow_up_question']?.toString(),
            disclaimer: entry['disclaimer']?.toString(),
            warning: entry['warning']?.toString(),
            timestamp: timestamp,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(messages);
        _isLoadingHistory = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (AuthService.isAuthenticationError(e)) {
        await _redirectToAuthentication(
          message: 'Please sign in to view your healthcare chat.',
        );
        return;
      }
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
    }
  }

  String _getBackendBaseUrl() {
    if (kIsWeb) {
      final browserUri = Uri.base;
      final host = browserUri.host.isEmpty ? '127.0.0.1' : browserUri.host;
      final scheme = browserUri.scheme == 'https' ? 'https' : 'http';
      return Uri(scheme: scheme, host: host, port: 8001).toString();
    }

    final configuredUrl = dotenv.env['BACKEND_URL']?.trim();
    if (configuredUrl != null && configuredUrl.isNotEmpty) {
      if (!kIsWeb && Platform.isAndroid) {
        final uri = Uri.tryParse(configuredUrl);
        if (uri != null && uri.host == 'localhost') {
          return configuredUrl.replaceFirst('localhost', '10.0.2.2');
        }
        return configuredUrl;
      }
      return configuredUrl;
    }

    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8001';
    }
    return 'http://127.0.0.1:8001';
  }

  Future<void> _handleSubmitted(String text) async {
    final message = text.trim();
    if (message.isEmpty || _isThinking) return;
    if (!await AuthService.hasToken()) {
      await _redirectToAuthentication(
        message: 'Please sign in again to continue chatting.',
      );
      return;
    }

    HapticFeedback.lightImpact();
    _textController.clear();
    _lastSubmittedText = message;

    setState(() {
      _messages.add(
        ChatMessage(text: message, isUser: true, timestamp: DateTime.now()),
      );
      _isThinking = true;
    });
    _scrollToBottom();
    await _processBotResponse(message);
  }

  Future<void> _retryLastMessage() async {
    final text = _lastSubmittedText;
    if (text == null || text.isEmpty || _isThinking) return;
    if (!await AuthService.hasToken()) {
      await _redirectToAuthentication(
        message: 'Please sign in again to continue chatting.',
      );
      return;
    }
    await _processBotResponse(text);
  }

  Future<void> _redirectToAuthentication({
    required String message,
  }) async {
    if (_isRedirectingToAuth || !mounted) return;

    _isRedirectingToAuth = true;
    setState(() {
      _isThinking = false;
      _isLoadingHistory = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade700,
      ),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthenticationScreen()),
      (route) => false,
    );
  }

  Future<void> _clearHistory() async {
    final shouldClear =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear history'),
            content: const Text(
              'This will remove your saved chat history from the app and backend.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldClear) return;

    try {
      await AuthService.clearChatHistory();
      if (!mounted) return;
      setState(() => _messages.clear());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat history cleared.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to clear history: $e')));
    }
  }

  Future<void> _processBotResponse(String text) async {
    try {
      final response = await http.post(
        Uri.parse('${_getBackendBaseUrl()}/chat'),
        headers: await AuthService.authHeaders(),
        body: jsonEncode({'message': text}),
      );

      if (!mounted) return;

      if (response.statusCode == 401 || response.statusCode == 403) {
        await _redirectToAuthentication(
          message: 'Your session expired. Please sign in again to continue chatting.',
        );
        return;
      }

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        final botMessage = ChatMessage(
          text:
              data['reply']?.toString() ??
              "I'm sorry, I couldn't understand the response.",
          isUser: false,
          riskLevel: data['risk_level']?.toString() ?? 'low',
          possibleConditions:
              (data['possible_conditions'] as List?)
                  ?.map((item) => item.toString())
                  .toList() ??
              const [],
          recommendedAction: data['recommended_action']?.toString(),
          followUpQuestion: data['follow_up_question']?.toString(),
          disclaimer: data['disclaimer']?.toString(),
          warning: data['warning']?.toString(),
          timestamp: DateTime.now(),
        );

        setState(() {
          _isThinking = false;
          _messages.add(botMessage);
        });
        _scrollToBottom();

        if (botMessage.isEmergency) {
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (!mounted) return;
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const EmergencyScreen()));
          });
        }
        return;
      }

      String errorMessage =
          'The healthcare assistant could not answer just now.';
      try {
        final errorBody = jsonDecode(response.body);
        if (errorBody is Map && errorBody['detail'] != null) {
          errorMessage = errorBody['detail'].toString();
        }
      } catch (_) {}

      setState(() {
        _isThinking = false;
        _messages.add(
          ChatMessage(
            text: errorMessage,
            isUser: false,
            riskLevel: 'low',
            warning: 'Request failed. You can retry the last message.',
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
    } catch (e) {
      if (AuthService.isAuthenticationError(e)) {
        await _redirectToAuthentication(
          message: 'Your session expired. Please sign in again to continue chatting.',
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _isThinking = false;
        _messages.add(
          ChatMessage(
            text:
                'Network error: $e\nPlease confirm the backend is running at ${_getBackendBaseUrl()}.',
            isUser: false,
            riskLevel: 'low',
            warning:
                'The assistant is offline right now. Retry when the backend is available.',
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
    }
  }

  bool get _hasRecentEmergency {
    for (var index = _messages.length - 1; index >= 0; index--) {
      final message = _messages[index];
      if (!message.isUser) return message.isEmergency;
    }
    return false;
  }

  bool get _showRetryAction {
    if (_messages.isEmpty || _isThinking || _lastSubmittedText == null) {
      return false;
    }
    final lastAssistant = _messages.reversed.firstWhere(
      (message) => !message.isUser,
      orElse: () =>
          ChatMessage(text: '', isUser: false, timestamp: DateTime.now()),
    );
    return lastAssistant.text.toLowerCase().contains('error') ||
        (lastAssistant.warning?.isNotEmpty ?? false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Color _riskColor(String riskLevel) {
    switch (riskLevel) {
      case 'emergency':
        return Colors.red.shade700;
      case 'high':
        return Colors.orange.shade700;
      case 'medium':
        return Colors.amber.shade800;
      default:
        return const Color(0xFF1F6E4A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('AI Health Assistant'),
        backgroundColor: const Color(0xFF1F6E4A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _isLoadingHistory ? null : _loadHistory,
            tooltip: 'Refresh history',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _messages.isEmpty ? null : _clearHistory,
            tooltip: 'Clear history',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_hasRecentEmergency)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: Colors.red.shade50,
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Potential emergency detected. Emergency guidance is ready below.',
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isLoadingHistory) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: GestureDetector(
                onTap: () => _textFieldFocus.unfocus(),
                child: _messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) =>
                            _buildMessageBubble(_messages[index]),
                      ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isThinking) _buildThinkingIndicator(),
                    if (_showRetryAction)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _retryLastMessage,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry last message'),
                          ),
                        ),
                      ),
                    _buildQuickPrompts(),
                    _buildInputArea(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F5ED),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.health_and_safety_outlined,
                size: 42,
                color: Color(0xFF1F6E4A),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Tell me how you are feeling today.',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'I can help you think through symptoms, spot red flags, and suggest safe next steps.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPrompts() {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _quickPrompts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final prompt = _quickPrompts[index];
          return ActionChip(
            label: Text(prompt),
            onPressed: _isThinking
                ? null
                : () {
                    _textController.text = prompt;
                    _handleSubmitted(prompt);
                  },
          );
        },
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: _thinkingController,
                child: const Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: Color(0xFF1F6E4A),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'The assistant is thinking...',
                style: TextStyle(
                  color: Color(0xFF1F6E4A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final timeLabel = DateFormat('HH:mm').format(message.timestamp);
    final riskColor = _riskColor(message.riskLevel);

    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F6E4A),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: Text(
                  message.text,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                timeLabel,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
          ),
          border: Border.all(
            color: message.isEmergency
                ? Colors.red.shade200
                : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.health_and_safety, size: 18, color: riskColor),
                const SizedBox(width: 8),
                Text(
                  'AI Assessment',
                  style: TextStyle(
                    color: riskColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: riskColor.withAlpha(31),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    message.riskLevel.toUpperCase(),
                    style: TextStyle(
                      color: riskColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            if ((message.warning?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: riskColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  message.warning!,
                  style: TextStyle(
                    color: riskColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            MarkdownBody(
              data: message.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  color: Colors.black87,
                  fontSize: 15,
                  height: 1.45,
                ),
                h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.4),
                h2: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, height: 1.4),
                h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.4),
                listBullet: const TextStyle(color: Colors.black87, fontSize: 15),
                code: TextStyle(
                  backgroundColor: Colors.grey.shade100,
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: const Color(0xFF1F6E4A),
                ),
                codeblockDecoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (message.possibleConditions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: message.possibleConditions
                    .map(
                      (condition) => Chip(
                        label: Text(condition),
                        side: BorderSide(color: riskColor.withAlpha(51)),
                      ),
                    )
                    .toList(),
              ),
            ],
            if ((message.recommendedAction?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Text(
                'Recommended action',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message.recommendedAction!,
                style: TextStyle(color: Colors.grey.shade800, height: 1.4),
              ),
            ],
            if ((message.followUpQuestion?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Text(
                'Follow-up question',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message.followUpQuestion!,
                style: TextStyle(color: Colors.grey.shade800, height: 1.4),
              ),
            ],
            if ((message.disclaimer?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Text(
                message.disclaimer!,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              timeLabel,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
            if (message.isEmergency) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EmergencyScreen()),
                  );
                },
                icon: const Icon(Icons.local_hospital_outlined),
                label: const Text('Open emergency guidance'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _textFieldFocus,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _handleSubmitted,
                  decoration: InputDecoration(
                    hintText:
                        'Describe your symptoms or ask a health question...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(
                        color: Color(0xFF1F6E4A),
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1F6E4A),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1F6E4A).withAlpha(64),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _isThinking
                      ? null
                      : () => _handleSubmitted(_textController.text),
                  tooltip: 'Send message',
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
