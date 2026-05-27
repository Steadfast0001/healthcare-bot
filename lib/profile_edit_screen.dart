import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'auth_service.dart';

class ProfileEditScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const ProfileEditScreen({super.key, required this.user});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _ageController;
  late final TextEditingController _genderController;
  late final TextEditingController _countryController;
  late final TextEditingController _cityController;
  late final TextEditingController _allergiesController;
  late final TextEditingController _knownConditionsController;
  late final TextEditingController _medicalHistoryController;
  late final TextEditingController _typeController;
  late final TextEditingController _specialtyController;
  late final TextEditingController _licenseController;
  late final TextEditingController _experienceController;
  final List<_EmergencyContactFormEntry> _emergencyContacts = [];
  bool _isSaving = false;
  String? _profilePictureBase64;
  Uint8List? _profilePictureBytes;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    final initialPic = user['profile_picture']?.toString();
    if (initialPic != null && initialPic.isNotEmpty) {
      _profilePictureBase64 = initialPic;
      try {
        final cleanBase64 = initialPic.contains(',')
            ? initialPic.split(',').last
            : initialPic;
        _profilePictureBytes = base64Decode(cleanBase64.trim());
      } catch (_) {}
    }
    _fullNameController = TextEditingController(
      text: user['full_name']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: user['phone_number']?.toString() ?? '',
    );
    _ageController = TextEditingController(text: user['age']?.toString() ?? '');
    _genderController = TextEditingController(
      text: user['gender']?.toString() ?? '',
    );
    _countryController = TextEditingController(
      text: user['country']?.toString() ?? '',
    );
    _cityController = TextEditingController(text: user['city']?.toString() ?? '');
    _allergiesController = TextEditingController(
      text: user['allergies']?.toString() ?? '',
    );
    _knownConditionsController = TextEditingController(
      text: user['known_conditions']?.toString() ?? '',
    );
    _medicalHistoryController = TextEditingController(
      text: user['medical_history']?.toString() ?? '',
    );
    _typeController = TextEditingController(
      text: user['provider_type']?.toString() ?? '',
    );
    _specialtyController = TextEditingController(
      text: user['specialty']?.toString() ?? '',
    );
    _licenseController = TextEditingController(
      text: user['license_number']?.toString() ?? '',
    );
    _experienceController = TextEditingController(
      text: user['working_experience']?.toString() ?? '',
    );
    _initializeEmergencyContacts(user);
  }

  void _initializeEmergencyContacts(Map<String, dynamic> user) {
    final rawContacts = user['emergency_contacts'];
    if (rawContacts is List) {
      for (final item in rawContacts.take(AuthService.maxEmergencyContacts)) {
        if (item is Map) {
          _emergencyContacts.add(
            _EmergencyContactFormEntry(
              name: item['name']?.toString() ?? '',
              phoneNumber: item['phone_number']?.toString() ?? '',
              allowCall: item['allow_call'] == true,
              allowWhatsApp: item['allow_whatsapp'] == true,
            ),
          );
        }
      }
    }
    if (_emergencyContacts.isEmpty) {
      final fallbackName = user['emergency_contact_name']?.toString() ?? '';
      final fallbackPhone = user['emergency_contact_phone']?.toString() ?? '';
      if (fallbackName.isNotEmpty || fallbackPhone.isNotEmpty) {
        _emergencyContacts.add(
          _EmergencyContactFormEntry(
            name: fallbackName,
            phoneNumber: fallbackPhone,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _genderController.dispose();
    _countryController.dispose();
    _cityController.dispose();
    _allergiesController.dispose();
    _knownConditionsController.dispose();
    _medicalHistoryController.dispose();
    _typeController.dispose();
    _specialtyController.dispose();
    _licenseController.dispose();
    _experienceController.dispose();
    for (final contact in _emergencyContacts) {
      contact.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (pickedFile == null) return;
      final bytes = await pickedFile.readAsBytes();
      final base64String = 'data:image/png;base64,${base64Encode(bytes)}';
      setState(() {
        _profilePictureBytes = bytes;
        _profilePictureBase64 = base64String;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final contactsPayload = <Map<String, dynamic>>[];
    for (final contact in _emergencyContacts) {
      final name = contact.nameController.text.trim();
      final phone = contact.phoneController.text.trim();
      if (name.isEmpty && phone.isEmpty) continue;
      if (!contact.allowCall && !contact.allowWhatsApp) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Each emergency contact must allow call or WhatsApp.',
            ),
          ),
        );
        return;
      }
      contactsPayload.add({
        'name': name,
        'phone_number': phone,
        'allow_call': contact.allowCall,
        'allow_whatsapp': contact.allowWhatsApp,
      });
    }

    setState(() => _isSaving = true);
    try {
      final isProvider = widget.user['role'] == 'provider';
      if (isProvider) {
        await AuthService.updateProfile(
          fullName: _fullNameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          age: int.tryParse(_ageController.text.trim()),
          gender: _genderController.text.trim(),
          country: _countryController.text.trim(),
          city: _cityController.text.trim(),
          providerType: _typeController.text.trim(),
          specialty: _specialtyController.text.trim(),
          licenseNumber: _licenseController.text.trim(),
          workingExperience: _experienceController.text.trim(),
          profilePicture: _profilePictureBase64,
        );
      } else {
        await AuthService.updateProfile(
          fullName: _fullNameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          age: int.tryParse(_ageController.text.trim()),
          gender: _genderController.text.trim(),
          country: _countryController.text.trim(),
          city: _cityController.text.trim(),
          emergencyContactName: contactsPayload.isNotEmpty
              ? contactsPayload.first['name']?.toString()
              : '',
          emergencyContactPhone: contactsPayload.isNotEmpty
              ? contactsPayload.first['phone_number']?.toString()
              : '',
          emergencyContacts: contactsPayload,
          allergies: _allergiesController.text.trim(),
          knownConditions: _knownConditionsController.text.trim(),
          medicalHistory: _medicalHistoryController.text.trim(),
          profilePicture: _profilePictureBase64,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save profile: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: const Color(0xFF1F6E4A),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: const Color(0xFF1F6E4A),
                        backgroundImage: _profilePictureBytes != null
                            ? MemoryImage(_profilePictureBytes!)
                            : null,
                        child: _profilePictureBytes != null
                            ? null
                            : const Icon(
                                Icons.person_add_alt_1_outlined,
                                size: 50,
                                color: Colors.white,
                              ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1F6E4A),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt_outlined,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildTextField('Full name', _fullNameController),
              const SizedBox(height: 16),
              _buildTextField(
                'Phone number',
                _phoneController,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                'Age',
                _ageController,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildTextField('Gender', _genderController),
              const SizedBox(height: 16),
              _buildTextField('Country', _countryController),
              const SizedBox(height: 16),
              _buildTextField('City', _cityController),
              const SizedBox(height: 16),
              if (widget.user['role'] == 'provider') ...[
                _buildTextField('Type of Doctor', _typeController),
                const SizedBox(height: 16),
                _buildTextField('Specialty', _specialtyController),
                const SizedBox(height: 16),
                _buildTextField('License number', _licenseController),
                const SizedBox(height: 16),
                _buildTextField('Working experience', _experienceController, maxLines: 2),
                const SizedBox(height: 24),
              ] else ...[
                _buildEmergencyContactsSection(),
                const SizedBox(height: 16),
                _buildTextField('Allergies', _allergiesController, maxLines: 2),
                const SizedBox(height: 16),
                _buildTextField(
                  'Known conditions',
                  _knownConditionsController,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  'Medical history',
                  _medicalHistoryController,
                  maxLines: 4,
                ),
                const SizedBox(height: 24),
              ],
              ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F6E4A),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Save profile',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmergencyContactsSection() {
    final canAddMore =
        _emergencyContacts.length < AuthService.maxEmergencyContacts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Emergency contacts',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${_emergencyContacts.length}/${AuthService.maxEmergencyContacts}',
            ),
            IconButton(
              onPressed: canAddMore
                  ? () {
                      setState(() {
                        _emergencyContacts.add(_EmergencyContactFormEntry());
                      });
                    }
                  : null,
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Add emergency contact',
            ),
          ],
        ),
        if (_emergencyContacts.isEmpty)
          const Text(
            'Add doctors, family, or trusted people. Max 10 contacts.',
          ),
        for (var i = 0; i < _emergencyContacts.length; i++)
          _buildEmergencyContactCard(_emergencyContacts[i], i),
      ],
    );
  }

  Widget _buildEmergencyContactCard(
    _EmergencyContactFormEntry contact,
    int index,
  ) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Contact ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      final removed = _emergencyContacts.removeAt(index);
                      removed.dispose();
                    });
                  },
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove contact',
                ),
              ],
            ),
            _buildTextField('Name', contact.nameController),
            const SizedBox(height: 12),
            _buildTextField(
              'Phone number',
              contact.phoneController,
              keyboardType: TextInputType.phone,
            ),
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: contact.allowCall,
                    onChanged: (v) =>
                        setState(() => contact.allowCall = v ?? false),
                    title: const Text('Call'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: contact.allowWhatsApp,
                    onChanged: (v) =>
                        setState(() => contact.allowWhatsApp = v ?? false),
                    title: const Text('WhatsApp'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF1F6E4A), width: 2),
        ),
      ),
    );
  }
}

class _EmergencyContactFormEntry {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  bool allowCall;
  bool allowWhatsApp;

  _EmergencyContactFormEntry({
    String name = '',
    String phoneNumber = '',
    this.allowCall = true,
    this.allowWhatsApp = false,
  }) : nameController = TextEditingController(text: name),
       phoneController = TextEditingController(text: phoneNumber);

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
  }
}
