import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../models/guardian.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Guardian> _guardians = [];
  bool _isLoading = true;
  double _checkIntervalMinutes = NotificationService.instance.checkIntervalMinutes.toDouble();

  @override
  void initState() {
    super.initState();
    _loadGuardians();
    _checkIntervalMinutes = NotificationService.instance.checkIntervalMinutes.toDouble();
  }

  Future<void> _loadGuardians() async {
    setState(() => _isLoading = true);
    try {
      final guardians = await _dbHelper.getAllGuardians();
      if (mounted) {
        setState(() {
          _guardians = guardians;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addGuardianFromContacts() async {
    try {
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;

      // Fetch full contact with properties
      final fullContact = await FlutterContacts.getContact(
        contact.id,
        withProperties: true,
      );
      if (fullContact == null || fullContact.phones.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected contact has no phone number'),
              backgroundColor: Color(0xFFFF3366),
            ),
          );
        }
        return;
      }

      String phone = fullContact.phones.first.number;
      String name = fullContact.displayName;

      // If contact has multiple numbers, let user pick
      if (fullContact.phones.length > 1) {
        final selected = await _showPhonePickerDialog(name, fullContact.phones);
        if (selected == null) return;
        phone = selected;
      }

      await _saveGuardian(name, phone);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking contact: $e'),
            backgroundColor: const Color(0xFFFF3366),
          ),
        );
      }
    }
  }

  Future<String?> _showPhonePickerDialog(
    String name,
    List<Phone> phones,
  ) async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Pick number for $name',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: phones.map((phone) {
            final label = phone.label.name;
            return ListTile(
              title: Text(
                phone.number,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              leading: const Icon(Icons.phone, color: Color(0xFF00D4FF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onTap: () => Navigator.pop(context, phone.number),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showManualEntryDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add Guardian Manually',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF333333)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF00D4FF)),
                ),
                prefixIcon: const Icon(Icons.person, color: Color(0xFF00D4FF)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF333333)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF00D4FF)),
                ),
                prefixIcon: const Icon(Icons.phone, color: Color(0xFF00D4FF)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              if (name.isEmpty || phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please fill in both fields'),
                    backgroundColor: Color(0xFFFF3366),
                  ),
                );
                return;
              }
              Navigator.pop(context);
              _saveGuardian(name, phone);
            },
            child: const Text(
              'ADD',
              style: TextStyle(color: Color(0xFF00D4FF)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveGuardian(String name, String phone) async {
    // Remove all spaces from phone number (e.g. "98765 43210" -> "9876543210")
    phone = phone.replaceAll(' ', '');

    // Check if already exists
    final exists = await _dbHelper.isGuardianExists(phone);
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This contact is already a guardian'),
            backgroundColor: Color(0xFFFF9800),
          ),
        );
      }
      return;
    }

    final guardian = Guardian(
      name: name,
      phone: phone,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _dbHelper.insertGuardian(guardian);
    await _loadGuardians();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name added as guardian'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
    }
  }

  Future<void> _deleteGuardian(Guardian guardian) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove Guardian',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove ${guardian.name} from guardian contacts?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'REMOVE',
              style: TextStyle(color: Color(0xFFFF3366)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && guardian.id != null) {
      await _dbHelper.deleteGuardian(guardian.id!);
      await _loadGuardians();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${guardian.name} removed'),
            backgroundColor: const Color(0xFF1E1E1E),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
              )
            : CustomScrollView(
                slivers: [
                  _buildAppBar(),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildSectionHeader('GUARDIAN CONTACTS'),
                        const SizedBox(height: 8),
                        const Text(
                          'Trusted contacts who can be alerted when scam messages are detected.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        _buildAddGuardianButtons(),
                        const SizedBox(height: 16),
                        if (_guardians.isEmpty)
                          _buildEmptyState()
                        else
                          ..._guardians.map((g) => _buildGuardianCard(g)),
                        const SizedBox(height: 32),
                        _buildSectionHeader('NOTIFICATION CHECK INTERVAL'),
                        const SizedBox(height: 8),
                        const Text(
                          'How often SilverGuard re-checks for pending scam alerts.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        _buildIntervalSlider(),
                      ]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: const Color(0xFF1A1A1A),
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00D4FF), Color(0xFF0099CC)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.settings, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'Guardian Contacts',
                style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildAddGuardianButtons() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _addGuardianFromContacts,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.3),
                ),
              ),
              child: const Column(
                children: [
                  Icon(Icons.contacts, color: Color(0xFF00D4FF), size: 28),
                  SizedBox(height: 8),
                  Text(
                    'From Contacts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Pick from phonebook',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: _showManualEntryDialog,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.edit, color: Color(0xFF888888), size: 28),
                  SizedBox(height: 8),
                  Text(
                    'Manual Entry',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Type name & number',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          const Text(
            'No Guardian Contacts',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add trusted contacts who will be notified when scam messages are detected.',
            style: TextStyle(color: Colors.white24, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGuardianCard(Guardian guardian) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(guardian.createdAt);
    final formattedDate = '${dateTime.day}/${dateTime.month}/${dateTime.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00D4FF).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: Color(0xFF00D4FF),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guardian.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  guardian.phone,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Added $formattedDate',
                  style: const TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _deleteGuardian(guardian),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3366).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.delete_outline,
                color: Color(0xFFFF3366),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntervalSlider() {
    // Snap points: 5, 10, 15, 30, 60
    final snapPoints = [5.0, 10.0, 15.0, 30.0, 60.0];
    final label = _checkIntervalMinutes >= 60
        ? '1 hour'
        : '${_checkIntervalMinutes.round()} min';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.timer_outlined,
                      color: Color(0xFF00D4FF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Check Interval',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF00D4FF),
              inactiveTrackColor: const Color(0xFF333333),
              thumbColor: const Color(0xFF00D4FF),
              overlayColor: const Color(0xFF00D4FF).withValues(alpha: 0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: _checkIntervalMinutes,
              min: 5,
              max: 60,
              divisions: 55,
              onChanged: (value) {
                // Snap to nearest snap point
                double snapped = snapPoints.reduce((a, b) =>
                    (a - value).abs() < (b - value).abs() ? a : b);
                setState(() {
                  _checkIntervalMinutes = snapped;
                });
              },
              onChangeEnd: (value) {
                double snapped = snapPoints.reduce((a, b) =>
                    (a - value).abs() < (b - value).abs() ? a : b);
                NotificationService.instance.setCheckInterval(snapped.round());
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('5 min', style: TextStyle(color: Colors.white38, fontSize: 11)),
              Text('15 min', style: TextStyle(color: Colors.white38, fontSize: 11)),
              Text('30 min', style: TextStyle(color: Colors.white38, fontSize: 11)),
              Text('1 hour', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
