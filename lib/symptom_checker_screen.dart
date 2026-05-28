import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'emergency_screen.dart';

class SymptomCheckerScreen extends StatefulWidget {
  const SymptomCheckerScreen({super.key});

  @override
  State<SymptomCheckerScreen> createState() => _SymptomCheckerScreenState();
}

class _SymptomCheckerScreenState extends State<SymptomCheckerScreen> {
  final Map<String, bool> _symptoms = {
    'Fever': false,
    'Headache': false,
    'Cough': false,
    'Vomiting': false,
    'Chest Pain': false,
    'Shortness of Breath': false,
    'Fatigue': false,
    'Nausea': false,
  };
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitAssessment() async {
    final selectedSymptoms = _symptoms.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    if (selectedSymptoms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one symptom.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final response = await AuthService.submitSymptomAssessment(
      symptoms: selectedSymptoms,
      notes: _notesController.text,
    );
    setState(() => _isSubmitting = false);

    if (!mounted) return;

    if (response['detail'] != null && response['reply'] == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(response['detail'].toString())));
      return;
    }

    final riskLevel = response['risk_level']?.toString().toLowerCase() ?? 'low';
    final recommendedAction =
        response['recommended_action']?.toString() ?? 'No action provided.';
    final possibleConditions =
        (response['possible_conditions'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        const <String>[];
    final followUpQuestion = response['follow_up_question']?.toString();
    final warning = response['warning']?.toString();

    if (riskLevel == 'emergency') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const EmergencyScreen()));
      return;
    }

    _showResultBottomSheet(
      riskLevel: riskLevel,
      suggestedAction: recommendedAction,
      possibleConditions: possibleConditions,
      followUpQuestion: followUpQuestion,
      warning: warning,
    );
  }

  Color _riskColor(String riskLevel) {
    switch (riskLevel) {
      case 'high':
      case 'emergency':
        return Colors.red.shade700;
      case 'medium':
        return Colors.orange.shade700;
      default:
        return Colors.green.shade700;
    }
  }

  void _showResultBottomSheet({
    required String riskLevel,
    required String suggestedAction,
    required List<String> possibleConditions,
    String? followUpQuestion,
    String? warning,
  }) {
    final riskColor = _riskColor(riskLevel);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Assessment Result',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Risk Level: ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: riskColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        riskLevel.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                if (warning != null && warning.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: riskColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      warning,
                      style: TextStyle(
                        color: riskColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (possibleConditions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Possible conditions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: possibleConditions
                        .map((condition) => Chip(label: Text(condition)))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Recommended action',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  suggestedAction,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade800,
                    height: 1.4,
                  ),
                ),
                if (followUpQuestion != null &&
                    followUpQuestion.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Follow-up question',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    followUpQuestion,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade800,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Symptom Checker')),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: Colors.blue.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How are you feeling?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select your symptoms and add any notes for a smarter assessment.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.blueGrey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8),
                children: [
                  ..._symptoms.keys.map((symptom) {
                    return CheckboxListTile(
                      title: Text(
                        symptom,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      value: _symptoms[symptom],
                      activeColor: Colors.blue,
                      onChanged: (value) {
                        setState(() {
                          _symptoms[symptom] = value ?? false;
                        });
                      },
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: TextField(
                      controller: _notesController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: 'Additional notes',
                        hintText:
                            'Describe how long this has been happening or anything else that matters.',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.zero,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  24,
                  24,
                  24,
                  MediaQuery.of(context).padding.bottom + 24,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitAssessment,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Submit Assessment',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
