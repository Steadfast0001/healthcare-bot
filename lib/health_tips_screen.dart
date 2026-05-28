import 'package:flutter/material.dart';

import 'auth_service.dart';

class HealthTipsScreen extends StatefulWidget {
  const HealthTipsScreen({super.key});

  @override
  State<HealthTipsScreen> createState() => _HealthTipsScreenState();
}

class _HealthTipsScreenState extends State<HealthTipsScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _tips = const [];

  @override
  void initState() {
    super.initState();
    _loadTips();
  }

  Future<void> _loadTips() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tips = await AuthService.getHealthTips();
      if (!mounted) return;
      setState(() {
        _tips = tips;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load health tips right now.';
        _isLoading = false;
      });
    }
  }

  IconData _iconForCategory(String? category) {
    switch ((category ?? '').toLowerCase()) {
      case 'malaria prevention':
      case 'prevention':
        return Icons.shield_outlined;
      case 'nutrition':
        return Icons.restaurant_menu;
      case 'mental health':
        return Icons.psychology_outlined;
      case 'hydration':
        return Icons.water_drop_outlined;
      case 'sleep':
        return Icons.bedtime_outlined;
      case 'vaccination':
        return Icons.local_hospital_outlined;
      case 'emergency preparedness':
        return Icons.warning_amber_outlined;
      case 'wellness':
        return Icons.favorite_outline;
      default:
        return Icons.lightbulb_outline;
    }
  }

  Color _colorForCategory(String? category) {
    switch ((category ?? '').toLowerCase()) {
      case 'malaria prevention':
      case 'prevention':
        return Colors.green.shade700;
      case 'nutrition':
        return Colors.orange.shade700;
      case 'mental health':
        return Colors.purple.shade700;
      case 'hydration':
        return Colors.blue.shade700;
      case 'sleep':
        return Colors.indigo.shade700;
      case 'vaccination':
        return Colors.red.shade700;
      case 'emergency preparedness':
        return Colors.orange.shade900;
      case 'wellness':
        return Colors.teal.shade700;
      default:
        return Colors.blue.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Tips'),
        backgroundColor: const Color(0xFF1F6E4A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadTips,
            tooltip: 'Refresh tips',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _buildErrorState()
            : _buildTipsList(),
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
            Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadTips,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsList() {
    if (_tips.isEmpty) {
      return const Center(child: Text('No health tips are available yet.'));
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      itemCount: _tips.length,
      itemBuilder: (context, index) {
        final tip = _tips[index];
        final category = tip['category']?.toString();
        final color = _colorForCategory(category);

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showTipDialog(context, tip),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withAlpha(31),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _iconForCategory(category),
                      size: 28,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (category != null && category.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              category.toUpperCase(),
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        Text(
                          tip['title']?.toString() ?? 'Untitled tip',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tip['content']?.toString() ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade800,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Read more',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 14,
                              color: color,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTipDialog(BuildContext context, Map<String, dynamic> tip) {
    final category = tip['category']?.toString();
    final color = _colorForCategory(category);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(_iconForCategory(category), color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(tip['title']?.toString() ?? 'Health tip')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (category != null && category.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      category,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Text(
                  tip['content']?.toString() ?? '',
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
