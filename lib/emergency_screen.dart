import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_service.dart';
import 'profile_edit_screen.dart';

// ─── Design Tokens ──────────────────────────────────────────────────────────
const _kBg = Color(0xFF0B0F19);
const _kCard = Color(0xFF151D30);
const _kAccent = Color(0xFF0E86D4);
const _kRed = Color(0xFFE53935);
const _kBorder = Color(0xFF222F4D);
const _kGreen = Color(0xFF00A86B);

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  Map<String, dynamic>? _user;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEmergencyData();
  }

  Future<void> _loadEmergencyData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = await AuthService.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _user = user;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Unable to fetch emergency data from database.";
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _emergencyContacts {
    final dynamic rawContacts = _user?['emergency_contacts'];
    if (rawContacts is List) {
      return rawContacts
          .whereType<Map>()
          .map((contact) => Map<String, dynamic>.from(contact))
          .toList();
    }
    final name = _user?['emergency_contact_name']?.toString() ?? '';
    final phone = _user?['emergency_contact_phone']?.toString() ?? '';
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

  String get _allergies => _user?['allergies']?.toString() ?? 'None listed';
  String get _knownConditions => _user?['known_conditions']?.toString() ?? 'None listed';

  Future<void> _makeCall(String name, String phoneNumber) async {
    HapticFeedback.mediumImpact();
    final Uri telUri = Uri.parse('tel:$phoneNumber');
    try {
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri);
      } else {
        throw 'Could not launch dialer.';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to call $name: $e'),
          backgroundColor: _kRed,
        ),
      );
      Clipboard.setData(ClipboardData(text: phoneNumber));
    }
  }

  Future<void> _launchWhatsApp(String name, String phoneNumber) async {
    // Keep only numbers to build a clean wa.me link
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    final Uri waUri = Uri.parse('https://wa.me/$cleanPhone');
    try {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to launch WhatsApp: $e'),
          backgroundColor: _kRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text(
          'Emergency Information',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadEmergencyData,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kRed))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 60, color: _kRed),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loadEmergencyData,
                          style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
                          child: const Text('Retry'),
                        )
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Red Alert Header Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _kRed,
                                _kRed.withRed(180),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _kRed.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.warning_rounded,
                                size: 50,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'MEDICAL EMERGENCY ALERT',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Patient: ${_user?['full_name'] ?? "Nkenganyi Steadfast Bekwike"}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Section: Patient Medical Profile (Allergies & Conditions)
                        const Text(
                          'CLINICAL INFORMATION',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Column(
                            children: [
                              _buildProfileItem(
                                icon: Icons.warning_amber_rounded,
                                iconColor: Colors.orange,
                                title: 'Allergies',
                                value: _allergies,
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12.0),
                                child: Divider(color: _kBorder, height: 1),
                              ),
                              _buildProfileItem(
                                icon: Icons.favorite_rounded,
                                iconColor: _kRed,
                                title: 'Known Conditions',
                                value: _knownConditions,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Section: Personal Emergency Contacts from DB
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'PERSONAL EMERGENCY CONTACTS',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final result = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => ProfileEditScreen(user: _user ?? {}),
                                  ),
                                );
                                if (result == true) {
                                  _loadEmergencyData();
                                }
                              },
                              icon: const Icon(Icons.edit_outlined, size: 14, color: _kAccent),
                              label: const Text(
                                'Manage',
                                style: TextStyle(fontSize: 12, color: _kAccent, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_emergencyContacts.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: _kCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _kBorder),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.contacts_outlined, color: Colors.white24, size: 40),
                                const SizedBox(height: 12),
                                const Text(
                                  'No emergency contacts stored in database.',
                                  style: TextStyle(color: Colors.white60, fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () async {
                                    final result = await Navigator.of(context).push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => ProfileEditScreen(user: _user ?? {}),
                                      ),
                                    );
                                    if (result == true) {
                                      _loadEmergencyData();
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
                                  child: const Text('Add Contact'),
                                )
                              ],
                            ),
                          )
                        else
                          Column(
                            children: _emergencyContacts.map((contact) {
                              final name = contact['name'] ?? 'Emergency Contact';
                              final phone = contact['phone_number'] ?? '';
                              final allowCall = contact['allow_call'] ?? true;
                              final allowWhatsApp = contact['allow_whatsapp'] ?? false;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _kCard,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _kBorder),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: _kRed.withValues(alpha: 0.1),
                                      child: const Icon(Icons.person, color: _kRed),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            phone,
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (allowCall && phone.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.phone, color: _kGreen),
                                        onPressed: () => _makeCall(name, phone),
                                      ),
                                    if (allowWhatsApp && phone.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.message, color: _kAccent),
                                        onPressed: () => _launchWhatsApp(name, phone),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 24),

                        // Section: Local Emergency Services (Cameroon)
                        const Text(
                          'LOCAL EMERGENCY SERVICES (CAMEROON)',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Column(
                            children: [
                              _buildServiceRow(
                                title: 'SAMU (Medical Emergency)',
                                number: '119',
                                iconColor: _kRed,
                              ),
                              const Divider(color: _kBorder, height: 24),
                              _buildServiceRow(
                                title: 'National Police',
                                number: '117',
                                iconColor: _kAccent,
                              ),
                              const Divider(color: _kBorder, height: 24),
                              _buildServiceRow(
                                title: 'Gendarmerie (Highway Patrol)',
                                number: '112',
                                iconColor: Colors.amber,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildProfileItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServiceRow({
    required String title,
    required String number,
    required Color iconColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Shortcode: $number',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => _makeCall(title, number),
          icon: const Icon(Icons.phone, size: 16, color: Colors.white),
          label: Text(
            number,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: iconColor.withValues(alpha: 0.2),
            foregroundColor: iconColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: iconColor.withValues(alpha: 0.4)),
            ),
          ),
        ),
      ],
    );
  }
}
