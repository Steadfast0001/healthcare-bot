import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'main.dart';
import 'profile_edit_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String email;

  const ProfileScreen({super.key, required this.email});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  bool _isLoading = true;
  String _selectedLanguage = 'English';
  List<Map<String, dynamic>> _chatHistory = [];
  bool _isHistoryLoading = true;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadChatHistory();
  }

  Future<void> _loadUser() async {
    try {
      final user = await AuthService.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _user = user;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _user = {'email': widget.email};
        _isLoading = false;
      });
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final history = await AuthService.getChatHistory();
      if (!mounted) return;
      setState(() {
        _chatHistory = history;
        _isHistoryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = 'Unable to load recent chats.';
        _isHistoryLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthenticationScreen()),
      (route) => false,
    );
  }

  String get _email => _readString(['email', 'username']) ?? widget.email;

  String get _fullName {
    return _readString(['full_name', 'fullName', 'name', 'username']) ??
        (_email.isNotEmpty ? _email.split('@').first : 'User');
  }

  String get _phone =>
      _readString(['phone_number', 'phoneNumber', 'phone']) ?? 'Not added';

  String get _age => _user?['age']?.toString() ?? 'Not added';

  String get _gender => _readString(['gender']) ?? 'Not added';

  String get _location {
    final country = _readString(['country']) ?? '';
    final city = _readString(['city']) ?? '';
    if (country.isEmpty && city.isEmpty) return 'Not added';
    return [city, country].where((part) => part.isNotEmpty).join(', ');
  }

  List<Map<String, dynamic>> get _emergencyContacts {
    final dynamic rawContacts = _user?['emergency_contacts'];
    if (rawContacts is List) {
      return rawContacts
          .whereType<Map>()
          .map((contact) => Map<String, dynamic>.from(contact))
          .toList();
    }
    final name = _readString(['emergency_contact_name']) ?? '';
    final phone = _readString(['emergency_contact_phone']) ?? '';
    if (name.isEmpty && phone.isEmpty) return const [];
    return [
      {
        'name': name,
        'phone_number': phone,
        'allow_call': true,
        'allow_whatsapp': false,
      },
    ];
  }

  String get _allergies => _readString(['allergies']) ?? 'Not added';

  String get _knownConditions =>
      _readString(['known_conditions']) ?? 'Not added';

  String get _medicalHistory =>
      _readString(['medical_history']) ?? 'Not added';

  String get _initial {
    final name = _fullName.trim();
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  String? _readString(List<String> keys) {
    final user = _user;
    if (user == null) return null;

    for (final key in keys) {
      final value = user[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isProvider = _user?['role'] == 'provider';

    final profilePicBase64 = _user?['profile_picture']?.toString();
    Uint8List? profilePicBytes;
    if (profilePicBase64 != null && profilePicBase64.isNotEmpty) {
      try {
        final cleanBase64 = profilePicBase64.contains(',')
            ? profilePicBase64.split(',').last
            : profilePicBase64;
        profilePicBytes = base64Decode(cleanBase64.trim());
      } catch (_) {}
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: const Color(0xFF1F6E4A),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24.0),
                color: const Color(0xFFE9F5F0),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final result = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => ProfileEditScreen(user: _user ?? {}),
                          ),
                        );
                        if (result == true) {
                          await _loadUser();
                        }
                      },
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: const Color(0xFF1F6E4A),
                            backgroundImage: profilePicBytes != null
                                ? MemoryImage(profilePicBytes)
                                : null,
                            child: profilePicBytes != null
                                ? null
                                : Text(
                                    _initial,
                                    style: const TextStyle(
                                      fontSize: 40,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1F6E4A),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt_outlined,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _fullName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _email,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    _buildInfoTile(
                      icon: Icons.email_outlined,
                      iconColor: Colors.blue.shade700,
                      title: 'Email',
                      subtitle: _email,
                    ),
                    const Divider(),
                    _buildInfoTile(
                      icon: Icons.phone_outlined,
                      iconColor: Colors.teal.shade700,
                      title: 'Phone',
                      subtitle: _phone,
                    ),
                    const Divider(),
                    _buildInfoTile(
                      icon: Icons.cake_outlined,
                      iconColor: Colors.deepPurple.shade700,
                      title: 'Age',
                      subtitle: _age,
                    ),
                    const Divider(),
                    _buildInfoTile(
                      icon: Icons.person_outline,
                      iconColor: Colors.indigo.shade700,
                      title: 'Gender',
                      subtitle: _gender,
                    ),
                    const Divider(),
                    _buildInfoTile(
                      icon: Icons.place_outlined,
                      iconColor: Colors.green.shade700,
                      title: 'Location',
                      subtitle: _location,
                    ),
                    if (isProvider) ...[
                      const Divider(),
                      _buildInfoTile(
                        icon: Icons.badge_outlined,
                        iconColor: Colors.amber.shade700,
                        title: 'License Number',
                        subtitle: _user?['license_number']?.toString() ?? 'Not added',
                      ),
                      const Divider(),
                      _buildInfoTile(
                        icon: Icons.medical_services_outlined,
                        iconColor: Colors.red.shade700,
                        title: 'Type of Doctor',
                        subtitle: _user?['provider_type']?.toString() ?? 'Doctor',
                      ),
                      const Divider(),
                      _buildInfoTile(
                        icon: Icons.stars_outlined,
                        iconColor: Colors.blue.shade700,
                        title: 'Specialty',
                        subtitle: _user?['specialty']?.toString() ?? 'General Practitioner',
                      ),
                      const Divider(),
                      _buildInfoTile(
                        icon: Icons.work_history_outlined,
                        iconColor: Colors.orange.shade700,
                        title: 'Working Experience',
                        subtitle: _user?['working_experience']?.toString() ?? 'Not added',
                      ),
                    ] else ...[
                      const Divider(),
                      _buildEmergencyContactsTile(),
                      const Divider(),
                      _buildInfoTile(
                        icon: Icons.warning_amber_outlined,
                        iconColor: Colors.orange.shade700,
                        title: 'Allergies',
                        subtitle: _allergies,
                      ),
                      const Divider(),
                      _buildInfoTile(
                        icon: Icons.favorite_outline,
                        iconColor: Colors.pink.shade700,
                        title: 'Known conditions',
                        subtitle: _knownConditions,
                      ),
                      const Divider(),
                      _buildInfoTile(
                        icon: Icons.history_edu_outlined,
                        iconColor: Colors.brown.shade700,
                        title: 'Medical history',
                        subtitle: _medicalHistory,
                      ),
                    ],
                    const Divider(),
                    ListTile(
                      leading: _buildIconCircle(
                        Icons.language,
                        Colors.purple.shade700,
                      ),
                      title: const Text(
                        'Language Settings',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      trailing: DropdownButton<String>(
                        value: _selectedLanguage,
                        underline: const SizedBox(),
                        items: const ['English', 'French']
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            ).toList()
                            ,
                        onChanged: (newValue) {
                          if (newValue == null) return;
                          setState(() => _selectedLanguage = newValue);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Language changed to $newValue'),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!isProvider) ...[
                      _buildChatHistorySection(),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => ProfileEditScreen(user: _user ?? {}),
                        ),
                      );
                      if (result == true) {
                        await _loadUser();
                      }
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text(
                      'EDIT PROFILE',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F6E4A),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text(
                      'LOGOUT',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red.shade700,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.red.shade200),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: _buildIconCircle(icon, iconColor),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle),
    );
  }

  Widget _buildEmergencyContactsTile() {
    final contacts = _emergencyContacts;
    final subtitle = contacts.isEmpty
        ? 'Not added'
        : contacts
              .map((contact) {
                final methods = <String>[];
                if (contact['allow_call'] == true) methods.add('Call');
                if (contact['allow_whatsapp'] == true) methods.add('WhatsApp');
                final methodText = methods.isEmpty ? 'No method' : methods.join('/');
                return '${contact['name'] ?? 'Unknown'} • ${contact['phone_number'] ?? ''} • $methodText';
              }).toList()
              .join('\n');
    return _buildInfoTile(
      icon: Icons.local_hospital_outlined,
      iconColor: Colors.red.shade700,
      title: 'Emergency contacts (${contacts.length}/10)',
      subtitle: subtitle,
    );
  }

  Widget _buildChatHistorySection() {
    if (_isHistoryLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent conversations',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await AuthService.clearChatHistory();
                  await _loadChatHistory();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chat history cleared.')),
                  );
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Unable to clear history.')),
                  );
                }
              },
              child: const Text('Clear'),
            ),
          ],
        ),
        if (_historyError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _historyError!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        const SizedBox(height: 12),
        if (_chatHistory.isEmpty)
          const Text('No conversations yet. Start a chat to see them here.'),
        if (_chatHistory.isNotEmpty)
          Column(
            children: _chatHistory.take(3).map((entry) {
              final risk = entry['risk_level']?.toString() ?? 'low';
              final snippet = entry['user_message']?.toString() ?? '';
              final timestamp = entry['created_at']?.toString() ?? '';
              return _buildHistoryCard(risk, snippet, timestamp);
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildHistoryCard(String riskLevel, String snippet, String timestamp) {
    final badgeColor = riskLevel == 'emergency'
        ? Colors.red.shade700
        : riskLevel == 'high'
        ? Colors.orange.shade700
        : riskLevel == 'medium'
        ? Colors.amber.shade700
        : Colors.green.shade700;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => Container()));
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withAlpha(41),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      riskLevel.toUpperCase(),
                      style: TextStyle(
                        color: badgeColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                timestamp,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconCircle(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withAlpha(31),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color),
    );
  }
}
