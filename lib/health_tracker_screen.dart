import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'auth_service.dart';

// Custom emerald color since Colors.emerald doesn't exist in Flutter
const Color kEmerald = Color(0xFF10B981);
const Color kEmeraldDark = Color(0xFF059669);
const Color kEmeraldLight = Color(0xFFD1FAE5);

class HealthTrackerScreen extends StatefulWidget {
  const HealthTrackerScreen({super.key});

  @override
  State<HealthTrackerScreen> createState() => _HealthTrackerScreenState();
}

class _HealthTrackerScreenState extends State<HealthTrackerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _error;

  List<Map<String, dynamic>> _vitals = const [];
  List<Map<String, dynamic>> _activities = const [];
  List<Map<String, dynamic>> _goals = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        AuthService.getVitals(),
        AuthService.getActivityLogs(),
        AuthService.getGoals(),
      ]);

      if (!mounted) return;
      setState(() {
        _vitals = results[0];
        _activities = results[1];
        _goals = results[2];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthService.isAuthenticationError(e)
            ? 'Your session has expired. Please sign in again.'
            : 'Failed to load health tracking data. Please try again.';
        _isLoading = false;
      });
    }
  }

  // --- Vital Log Extractors ---
  Map<String, dynamic>? _getLatestVitalWithValue(String key) {
    for (final log in _vitals) {
      if (log[key] != null) return log;
    }
    return null;
  }

  Map<String, dynamic>? _getLatestBP() {
    for (final log in _vitals) {
      if (log['systolic_bp'] != null && log['diastolic_bp'] != null) return log;
    }
    return null;
  }

  // ===================== DIALOG: Log Vitals =====================
  void _showLogVitalsDialog() {
    final formKey = GlobalKey<FormState>();
    final systolicController = TextEditingController();
    final diastolicController = TextEditingController();
    final glucoseController = TextEditingController();
    final heartRateController = TextEditingController();
    final tempController = TextEditingController();
    final weightController = TextEditingController();
    bool isSubmitting = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kEmeraldLight,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.favorite_rounded, color: kEmeraldDark),
                  ),
                  const SizedBox(width: 12),
                  const Text('Log Today\'s Vitals',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Enter any vitals you want to log. Leave fields blank if not tracking today.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: systolicController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Systolic BP',
                                suffixText: 'mmHg',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                              validator: (val) {
                                if (val != null && val.isNotEmpty) {
                                  final n = int.tryParse(val);
                                  if (n == null || n <= 0) return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: diastolicController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Diastolic BP',
                                suffixText: 'mmHg',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                              validator: (val) {
                                if (val != null && val.isNotEmpty) {
                                  final n = int.tryParse(val);
                                  if (n == null || n <= 0) return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: glucoseController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Blood Glucose',
                          suffixText: 'mg/dL',
                          prefixIcon: const Icon(Icons.water_drop,
                              color: Colors.orange),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          if (val != null && val.isNotEmpty) {
                            final n = int.tryParse(val);
                            if (n == null || n <= 0) {
                              return 'Please enter a valid glucose level';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: heartRateController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Heart Rate',
                          suffixText: 'bpm',
                          prefixIcon:
                              const Icon(Icons.favorite, color: Colors.red),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          if (val != null && val.isNotEmpty) {
                            final n = int.tryParse(val);
                            if (n == null || n <= 0) {
                              return 'Please enter a valid heart rate';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: tempController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Temperature',
                                suffixText: '°C',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                              validator: (val) {
                                if (val != null && val.isNotEmpty) {
                                  final n = double.tryParse(val);
                                  if (n == null || n <= 0) return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: weightController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Weight',
                                suffixText: 'kg',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                              validator: (val) {
                                if (val != null && val.isNotEmpty) {
                                  final n = double.tryParse(val);
                                  if (n == null || n <= 0) return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            final systolic = int.tryParse(systolicController.text);
                            final diastolic = int.tryParse(diastolicController.text);
                            final glucose = int.tryParse(glucoseController.text);
                            final heartRate = int.tryParse(heartRateController.text);
                            final temp = double.tryParse(tempController.text);
                            final weight = double.tryParse(weightController.text);

                            if (systolic == null && diastolic == null &&
                                glucose == null && heartRate == null &&
                                temp == null && weight == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Please log at least one vital parameter.')),
                              );
                              return;
                            }

                            setDialogState(() => isSubmitting = true);

                            try {
                              await AuthService.logVitals(
                                systolicBp: systolic,
                                diastolicBp: diastolic,
                                bloodGlucose: glucose,
                                heartRate: heartRate,
                                temperature: temp,
                                weight: weight,
                              );
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Vitals logged successfully!'),
                                  backgroundColor: kEmeraldDark,
                                ),
                              );
                              _loadAllData();
                            } catch (e) {
                              setDialogState(() => isSubmitting = false);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to save vitals: $e')),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kEmeraldDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Vitals'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===================== DIALOG: Log Activity =====================
  void _showLogActivityDialog() {
    final formKey = GlobalKey<FormState>();
    final stepsController = TextEditingController();
    final caloriesBurnedController = TextEditingController();
    final waterController = TextEditingController();
    final sleepController = TextEditingController();
    final caloriesConsumedController = TextEditingController();
    final mealNotesController = TextEditingController();
    bool isSubmitting = false;

    if (_activities.isNotEmpty) {
      final latest = _activities.first;
      if (latest['steps'] != null) {
        stepsController.text = latest['steps'].toString();
      }
      if (latest['calories_burned'] != null) {
        caloriesBurnedController.text = latest['calories_burned'].toString();
      }
      if (latest['water_intake'] != null) {
        waterController.text = latest['water_intake'].toString();
      }
      if (latest['sleep_hours'] != null) {
        sleepController.text = latest['sleep_hours'].toString();
      }
      if (latest['calories_consumed'] != null) {
        caloriesConsumedController.text = latest['calories_consumed'].toString();
      }
      if (latest['meal_notes'] != null) {
        mealNotesController.text = latest['meal_notes'].toString();
      }
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.directions_run_rounded,
                        color: Colors.blue.shade700),
                  ),
                  const SizedBox(width: 12),
                  const Text('Track Habits & Activity',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Track your steps, water, sleep, calories, and meals for today.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: stepsController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Steps Today',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                              validator: (val) {
                                if (val != null && val.isNotEmpty) {
                                  final n = int.tryParse(val);
                                  if (n == null || n < 0) return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: caloriesBurnedController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Active Burn (kcal)',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                              validator: (val) {
                                if (val != null && val.isNotEmpty) {
                                  final n = int.tryParse(val);
                                  if (n == null || n < 0) return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: waterController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Water Intake',
                                suffixText: 'ml',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                              validator: (val) {
                                if (val != null && val.isNotEmpty) {
                                  final n = int.tryParse(val);
                                  if (n == null || n < 0) return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: sleepController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Sleep Time',
                                suffixText: 'hrs',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                              validator: (val) {
                                if (val != null && val.isNotEmpty) {
                                  final n = double.tryParse(val);
                                  if (n == null || n < 0 || n > 24) return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: caloriesConsumedController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Calories Consumed (kcal)',
                          prefixIcon: const Icon(Icons.restaurant,
                              color: Colors.teal),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          if (val != null && val.isNotEmpty) {
                            final n = int.tryParse(val);
                            if (n == null || n < 0) return 'Invalid calories';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: mealNotesController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Meal Notes / What did you eat?',
                          prefixIcon: const Icon(Icons.notes,
                              color: Colors.grey),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            final steps = int.tryParse(stepsController.text);
                            final burned = int.tryParse(caloriesBurnedController.text);
                            final water = int.tryParse(waterController.text);
                            final sleep = double.tryParse(sleepController.text);
                            final consumed = int.tryParse(caloriesConsumedController.text);
                            final mealNotes = mealNotesController.text;

                            setDialogState(() => isSubmitting = true);

                            try {
                              await AuthService.logActivity(
                                steps: steps,
                                caloriesBurned: burned,
                                waterIntake: water,
                                sleepHours: sleep,
                                caloriesConsumed: consumed,
                                mealNotes: mealNotes,
                              );
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Activity logged successfully!'),
                                  backgroundColor: Colors.blue,
                                ),
                              );
                              _loadAllData();
                            } catch (e) {
                              setDialogState(() => isSubmitting = false);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to log habits: $e')),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Tracker'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===================== DIALOG: Create Goal =====================
  void _showCreateGoalDialog() {
    final formKey = GlobalKey<FormState>();
    String selectedGoalType = 'steps';
    final targetController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    bool isSubmitting = false;

    const typeDisplayNames = {
      'steps': 'Steps (daily)',
      'sleep': 'Sleep (hours)',
      'water': 'Water Intake (ml)',
      'weight': 'Weight Target (kg)',
      'calories_burned': 'Active Calories Burned (kcal)',
    };

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.track_changes_rounded,
                        color: Colors.indigo.shade700),
                  ),
                  const SizedBox(width: 12),
                  const Text('Set a Health Goal',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedGoalType,
                        decoration: InputDecoration(
                          labelText: 'Goal Metric',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        items: typeDisplayNames.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedGoalType = val);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: targetController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Target Value',
                          hintText: selectedGoalType == 'steps'
                              ? '10000'
                              : selectedGoalType == 'sleep'
                                  ? '8.0'
                                  : selectedGoalType == 'water'
                                      ? '2000'
                                      : 'e.g. 70.5',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'Please enter a target value';
                          }
                          final n = double.tryParse(val);
                          if (n == null || n <= 0) {
                            return 'Please enter a valid positive target';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Target Date',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.calendar_month),
                          ),
                          child: Text(
                            DateFormat('EEEE, MMM d, yyyy').format(selectedDate),
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            final target = double.parse(targetController.text);
                            setDialogState(() => isSubmitting = true);

                            try {
                              await AuthService.createGoal(
                                goalType: selectedGoalType,
                                targetValue: target,
                                targetDate: selectedDate,
                              );
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Goal created successfully!'),
                                  backgroundColor: Colors.indigo,
                                ),
                              );
                              _loadAllData();
                            } catch (e) {
                              setDialogState(() => isSubmitting = false);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Failed to set goal: $e')),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create Goal'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===================== DIALOG: Update Goal Progress =====================
  void _showUpdateGoalProgressDialog(Map<String, dynamic> goal) {
    final formKey = GlobalKey<FormState>();
    final progressController = TextEditingController(
        text: goal['current_value']?.toString() ?? '0');
    bool isSubmitting = false;
    final goalId = goal['id']?.toString() ?? '';

    const typeDisplayNames = {
      'steps': 'Steps (daily)',
      'sleep': 'Sleep (hours)',
      'water': 'Water Intake (ml)',
      'weight': 'Weight Target (kg)',
      'calories_burned': 'Active Calories Burned (kcal)',
    };
    final goalType = goal['goal_type']?.toString() ?? 'steps';
    final target = goal['target_value'] as num? ?? 1.0;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              title: const Text('Update Goal Progress',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Goal: ${typeDisplayNames[goalType] ?? goalType}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Target value: ${target.toStringAsFixed(1)}',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: progressController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Current Progress Value',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Please enter current value';
                        }
                        final n = double.tryParse(val);
                        if (n == null || n < 0) {
                          return 'Please enter a valid non-negative number';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            final current =
                                double.parse(progressController.text);
                            setDialogState(() => isSubmitting = true);

                            try {
                              await AuthService.updateGoalProgress(goalId,
                                  currentValue: current);
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Goal progress updated!'),
                                  backgroundColor: Colors.indigo,
                                ),
                              );
                              _loadAllData();
                            } catch (e) {
                              setDialogState(() => isSubmitting = false);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Failed to update progress: $e')),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===================== DIALOG: Confirm Delete Goal =====================
  void _confirmDeleteGoal(String goalId) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Goal?'),
          content: const Text(
              'Are you sure you want to delete this goal? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  await AuthService.deleteGoal(goalId);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Goal deleted successfully')),
                  );
                  _loadAllData();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete goal: $e')),
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  // ===================== MAIN BUILD =====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Tracker'),
        backgroundColor: const Color(0xFF1F6E4A),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.favorite_rounded), text: 'Vitals'),
            Tab(icon: Icon(Icons.directions_run_rounded), text: 'Habits'),
            Tab(icon: Icon(Icons.track_changes_rounded), text: 'Goals'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadAllData,
            tooltip: 'Sync data',
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildErrorState()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildVitalsTab(),
                      _buildHabitsTab(),
                      _buildGoalsTab(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 52, color: Colors.red.shade400),
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadAllData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry connection'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F6E4A),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== TAB 1: VITALS =====================
  Widget _buildVitalsTab() {
    final bpLog = _getLatestBP();
    final glucoseLog = _getLatestVitalWithValue('blood_glucose');
    final heartRateLog = _getLatestVitalWithValue('heart_rate');
    final tempLog = _getLatestVitalWithValue('temperature');
    final weightLog = _getLatestVitalWithValue('weight');

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: kEmerald,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Vitals Status',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            const SizedBox(height: 6),
            Text(
              'Shows the most recently logged data across all categories.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),

            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                final crossAxisCount = isWide ? 3 : 2;
                final childAspectRatio = isWide ? 1.5 : 1.15;

                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: childAspectRatio,
                  children: [
                    _buildVitalCard(
                      title: 'Blood Pressure',
                      value: bpLog != null
                          ? '${bpLog['systolic_bp']}/${bpLog['diastolic_bp']}'
                          : '-- / --',
                      unit: 'mmHg',
                      icon: Icons.heart_broken_rounded,
                      color: Colors.blue.shade600,
                      time: bpLog != null
                          ? _formatDateTimeString(bpLog['created_at'])
                          : 'No records yet',
                    ),
                    _buildVitalCard(
                      title: 'Blood Glucose',
                      value: glucoseLog != null
                          ? '${glucoseLog['blood_glucose']}'
                          : '--',
                      unit: 'mg/dL',
                      icon: Icons.water_drop,
                      color: Colors.orange.shade700,
                      time: glucoseLog != null
                          ? _formatDateTimeString(glucoseLog['created_at'])
                          : 'No records yet',
                    ),
                    _buildVitalCard(
                      title: 'Heart Rate',
                      value: heartRateLog != null
                          ? '${heartRateLog['heart_rate']}'
                          : '--',
                      unit: 'bpm',
                      icon: Icons.favorite,
                      color: Colors.red.shade600,
                      time: heartRateLog != null
                          ? _formatDateTimeString(heartRateLog['created_at'])
                          : 'No records yet',
                    ),
                    _buildVitalCard(
                      title: 'Temperature',
                      value: tempLog != null ? '${tempLog['temperature']}' : '--',
                      unit: '°C',
                      icon: Icons.thermostat,
                      color: Colors.teal.shade600,
                      time: tempLog != null
                          ? _formatDateTimeString(tempLog['created_at'])
                          : 'No records yet',
                    ),
                    _buildVitalCard(
                      title: 'Weight',
                      value: weightLog != null ? '${weightLog['weight']}' : '--',
                      unit: 'kg',
                      icon: Icons.monitor_weight_rounded,
                      color: Colors.purple.shade600,
                      time: weightLog != null
                          ? _formatDateTimeString(weightLog['created_at'])
                          : 'No records yet',
                    ),
                    // Log New Vitals quick-action card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                            color: kEmerald.withAlpha(80), width: 1.5),
                      ),
                      color: kEmeraldLight.withAlpha(100),
                      child: InkWell(
                        onTap: _showLogVitalsDialog,
                        borderRadius: BorderRadius.circular(20),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: const BoxDecoration(
                                  color: kEmeraldLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add,
                                    color: kEmeraldDark, size: 28),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Log New Vitals',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: kEmeraldDark,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),
            const Text(
              'Vitals History Log',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            const SizedBox(height: 12),

            _vitals.isEmpty
                ? _buildEmptyState(
                    icon: Icons.playlist_remove_rounded,
                    message:
                        'No vitals logged yet. Log your first reading above!',
                    actionLabel: 'Log Vitals',
                    onAction: _showLogVitalsDialog,
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _vitals.length,
                    itemBuilder: (context, index) {
                      final log = _vitals[index];
                      final date = _formatDateTimeString(log['created_at']);

                      final List<String> metrics = [];
                      if (log['systolic_bp'] != null) {
                        metrics.add(
                            'BP: ${log['systolic_bp']}/${log['diastolic_bp']} mmHg');
                      }
                      if (log['blood_glucose'] != null) {
                        metrics.add('Glucose: ${log['blood_glucose']} mg/dL');
                      }
                      if (log['heart_rate'] != null) {
                        metrics.add('Pulse: ${log['heart_rate']} bpm');
                      }
                      if (log['temperature'] != null) {
                        metrics.add('Temp: ${log['temperature']} °C');
                      }
                      if (log['weight'] != null) {
                        metrics.add('Weight: ${log['weight']} kg');
                      }

                      return Card(
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: kEmerald.withAlpha(26),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.favorite_rounded,
                                color: kEmeraldDark, size: 20),
                          ),
                          title: Text(
                            metrics.join('  •  '),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(date,
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 12)),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
    required String time,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withAlpha(26),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              time,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== TAB 2: HABITS =====================
  Widget _buildHabitsTab() {
    double currentSteps = 0;
    double currentWater = 0;
    double currentSleep = 0;
    double currentBurned = 0;
    double currentConsumed = 0;
    String? mealNotes;
    String latestDate = '';

    if (_activities.isNotEmpty) {
      final latest = _activities.first;
      currentSteps = (latest['steps'] as num? ?? 0).toDouble();
      currentWater = (latest['water_intake'] as num? ?? 0).toDouble();
      currentSleep = (latest['sleep_hours'] as num? ?? 0).toDouble();
      currentBurned = (latest['calories_burned'] as num? ?? 0).toDouble();
      currentConsumed = (latest['calories_consumed'] as num? ?? 0).toDouble();
      mealNotes = latest['meal_notes']?.toString();
      latestDate = _formatDateTimeString(latest['date']);
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: Colors.blue,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's Health Indicators",
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showLogActivityDialog,
                  icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                  label: const Text('Update'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),
            if (latestDate.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Text(
                  'Latest update: $latestDate',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 12),

            // Progress Rings Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                return GridView.count(
                  crossAxisCount: isWide ? 4 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.85,
                  children: [
                    CircularProgressRing(
                      value: currentSteps,
                      target: 10000,
                      unit: 'steps',
                      icon: Icons.directions_walk_rounded,
                      color: kEmerald,
                      label: 'Walk Steps',
                    ),
                    CircularProgressRing(
                      value: currentWater,
                      target: 2000,
                      unit: 'ml',
                      icon: Icons.water_drop_rounded,
                      color: Colors.blue.shade600,
                      label: 'Water Intake',
                    ),
                    CircularProgressRing(
                      value: currentSleep,
                      target: 8.0,
                      unit: 'hours',
                      icon: Icons.bedtime_rounded,
                      color: Colors.indigo.shade600,
                      label: 'Sleep Hours',
                    ),
                    CircularProgressRing(
                      value: currentBurned,
                      target: 500,
                      unit: 'kcal',
                      icon: Icons.local_fire_department_rounded,
                      color: Colors.orange.shade700,
                      label: 'Calories Burned',
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 24),

            // Nutrition Overview Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.withAlpha(26),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.restaurant_menu_rounded,
                              color: Colors.teal),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Nutrition & Dietary Logs',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Calories Consumed:',
                            style: TextStyle(
                                fontSize: 14, color: Colors.black87)),
                        Text(
                          currentConsumed > 0
                              ? '${currentConsumed.toStringAsFixed(0)} kcal'
                              : 'Not logged yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: currentConsumed > 0
                                ? Colors.teal.shade700
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Meal Notes:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        (mealNotes != null && mealNotes.trim().isNotEmpty)
                            ? mealNotes
                            : 'No meal notes for today.',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle:
                              (mealNotes != null && mealNotes.trim().isNotEmpty)
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                          color:
                              (mealNotes != null && mealNotes.trim().isNotEmpty)
                                  ? Colors.black87
                                  : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
            const Text(
              'Habits History Timeline',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            const SizedBox(height: 12),

            _activities.isEmpty
                ? _buildEmptyState(
                    icon: Icons.event_busy_rounded,
                    message:
                        'No habits logged yet. Start tracking your lifestyle today!',
                    actionLabel: 'Track Habits',
                    onAction: _showLogActivityDialog,
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _activities.length,
                    itemBuilder: (context, index) {
                      final act = _activities[index];
                      final date = _formatDateTimeString(act['date']);
                      final List<String> details = [];
                      if (act['steps'] != null) {
                        details.add('${act['steps']} steps');
                      }
                      if (act['water_intake'] != null) {
                        details.add('${act['water_intake']}ml water');
                      }
                      if (act['sleep_hours'] != null) {
                        details.add('${act['sleep_hours']}hrs sleep');
                      }
                      if (act['calories_burned'] != null) {
                        details.add('${act['calories_burned']}kcal active');
                      }
                      if (act['calories_consumed'] != null) {
                        details.add('${act['calories_consumed']}kcal food');
                      }

                      return Card(
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.calendar_month,
                                      color: Colors.blue.shade700, size: 16),
                                  const SizedBox(width: 8),
                                  Text(date,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                details.join('  •  '),
                                style: TextStyle(
                                    color: Colors.grey.shade700, fontSize: 13),
                              ),
                              if (act['meal_notes'] != null &&
                                  act['meal_notes']
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Meal Notes: ${act['meal_notes']}',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic),
                                ),
                              ]
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  // ===================== TAB 3: GOALS =====================
  Widget _buildGoalsTab() {
    const typeDisplayNames = {
      'steps': 'Walk Steps Target',
      'sleep': 'Daily Sleep Hours',
      'water': 'Water Hydration',
      'weight': 'Weight Milestone',
      'calories_burned': 'Active Burn Target',
    };
    const units = {
      'steps': 'steps',
      'sleep': 'hours',
      'water': 'ml',
      'weight': 'kg',
      'calories_burned': 'kcal',
    };
    const goalColors = <String, Color>{
      'steps': kEmerald,
      'sleep': Colors.indigo,
      'water': Colors.blue,
      'weight': Colors.purple,
      'calories_burned': Colors.orange,
    };
    const goalIcons = <String, IconData>{
      'steps': Icons.directions_walk,
      'sleep': Icons.bedtime,
      'water': Icons.water_drop,
      'weight': Icons.monitor_weight,
      'calories_burned': Icons.local_fire_department,
    };

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: Colors.indigo,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Health & Fitness Goals',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showCreateGoalDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add goal'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _goals.isEmpty
                ? _buildEmptyState(
                    icon: Icons.track_changes_rounded,
                    message:
                        'No health goals configured. Challenge yourself with a fitness or lifestyle goal today!',
                    actionLabel: 'Define Target Goal',
                    onAction: _showCreateGoalDialog,
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _goals.length,
                    itemBuilder: (context, index) {
                      final goal = _goals[index];
                      final goalId = goal['id']?.toString() ?? '';
                      final goalType =
                          goal['goal_type']?.toString() ?? 'steps';
                      final targetVal =
                          (goal['target_value'] as num? ?? 1.0).toDouble();
                      final currentVal =
                          (goal['current_value'] as num? ?? 0.0).toDouble();
                      final targetDateStr =
                          goal['target_date']?.toString() ?? '';
                      final targetDate = targetDateStr.isNotEmpty
                          ? DateTime.tryParse(targetDateStr)
                          : null;
                      final isCompleted =
                          goal['is_completed'] as bool? ?? false;

                      final double percentage =
                          targetVal > 0 ? (currentVal / targetVal) : 0.0;
                      final int displayPercent =
                          (percentage * 100).round().clamp(0, 100);

                      final color =
                          goalColors[goalType] ?? Colors.indigo;
                      final iconData =
                          goalIcons[goalType] ?? Icons.track_changes;

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: color.withAlpha(26),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(iconData,
                                        color: color, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          typeDisplayNames[goalType] ??
                                              goalType,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15),
                                        ),
                                        if (targetDate != null)
                                          Text(
                                            'Target: ${DateFormat('MMM dd, yyyy').format(targetDate)}',
                                            style: TextStyle(
                                                color: Colors.grey.shade500,
                                                fontSize: 12),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isCompleted ||
                                      currentVal >= targetVal)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.green.shade200),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.check_circle,
                                              color: Colors.green.shade700,
                                              size: 14),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Achieved',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green.shade800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${currentVal.toStringAsFixed(0)} / ${targetVal.toStringAsFixed(0)} ${units[goalType] ?? ""}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  Text(
                                    '$displayPercent%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: color,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: percentage.clamp(0.0, 1.0),
                                  minHeight: 8,
                                  backgroundColor: color.withAlpha(26),
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(color),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () =>
                                        _confirmDeleteGoal(goalId),
                                    icon: const Icon(Icons.delete_outline,
                                        size: 16),
                                    label: const Text('Delete'),
                                    style: TextButton.styleFrom(
                                        foregroundColor:
                                            Colors.red.shade700),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        _showUpdateGoalProgressDialog(goal),
                                    icon: const Icon(Icons.add, size: 14),
                                    label: const Text('Add progress'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: color,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  // ===================== SHARED HELPERS =====================
  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F6E4A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  String _formatDateTimeString(dynamic dateTimeString) {
    if (dateTimeString == null) return '';
    try {
      final parsed = DateTime.tryParse(dateTimeString.toString());
      if (parsed == null) return dateTimeString.toString();
      final local = parsed.toLocal();
      return DateFormat('MMM dd, yyyy   h:mm a').format(local);
    } catch (_) {
      return dateTimeString.toString();
    }
  }
}

// ===================== CUSTOM WIDGETS =====================

class CircularProgressRing extends StatelessWidget {
  final double value;
  final double target;
  final String unit;
  final IconData icon;
  final Color color;
  final String label;

  const CircularProgressRing({
    super.key,
    required this.value,
    required this.target,
    required this.unit,
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final double percentage = target > 0 ? (value / target) : 0.0;
    final int displayPercent = (percentage * 100).round();

    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(76, 76),
                  painter: ProgressRingPainter(
                    progress: percentage,
                    progressColor: color,
                    backgroundColor: color.withAlpha(26),
                    strokeWidth: 7,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(height: 2),
                    Text(
                      '$displayPercent%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${value.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            Text(
              unit,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

class ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color progressColor;
  final Color backgroundColor;
  final double strokeWidth;

  const ProgressRingPainter({
    required this.progress,
    required this.progressColor,
    required this.backgroundColor,
    this.strokeWidth = 8,
  });

  static const double _twoPi = 2 * 3.141592653589793;
  static const double _startAngle = -3.141592653589793 / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    final double sweepAngle = _twoPi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
