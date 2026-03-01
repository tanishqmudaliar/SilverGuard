import 'dart:async';
import 'package:flutter/material.dart';
import 'services/permission_service.dart';
import 'services/sms_service.dart';
import 'services/scam_processor_service.dart';
import 'models/sms_message.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SilverGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00D4FF),
          secondary: const Color(0xFFFF3366),
          surface: const Color(0xFF121212),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  bool _permissionsGranted = false;
  bool _isLoading = true;
  bool _isFetchingSms = false;
  bool _listenerStarted = false;
  bool _aiInitialized = false;
  int _pendingScamChecks = 0;
  String _statusMessage = 'Checking permissions...';

  Map<String, int> _stats = {
    'total': 0,
    'unread': 0,
    'read': 0,
    'sent': 0,
    'unchecked': 0,
    'safe': 0,
    'uncertain': 0,
    'suspicious': 0,
    'scam': 0,
  };
  List<UnreadSms> _unreadSms = [];
  List<ReadSms> _readSms = [];
  List<SentSms> _sentSms = [];

  late TabController _tabController;
  Timer? _refreshDebounceTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkPermissions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshDebounceTimer?.cancel();
    ScamProcessorService.instance.stopProcessing();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);

    final granted = await PermissionService.areAllPermissionsGranted();

    setState(() {
      _permissionsGranted = granted;
      _isLoading = false;
      _statusMessage = granted
          ? 'Permissions granted. Ready to fetch SMS.'
          : 'Tap "Grant Permissions" to start';
    });

    if (granted) {
      await _initializeServices();
    }
  }

  Future<void> _initializeServices() async {
    if (_listenerStarted) return;
    _listenerStarted = true;

    // Initialize scam processor (loads AI model)
    setState(() {
      _statusMessage = 'Loading AI model...';
    });

    try {
      await ScamProcessorService.instance.initialize();

      setState(() {
        _aiInitialized = true;
      });

      // Set up callback for when items are processed - debounced refresh
      ScamProcessorService.instance.onItemProcessed = (id, table, threatScore) {
        if (mounted) {
          setState(() {
            _pendingScamChecks = ScamProcessorService.instance.pendingCount;
          });
          _debouncedRefreshData();
        }
      };
    } catch (e) {
      // Show visible error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI Model failed to load: $e'),
            backgroundColor: const Color(0xFFFF3366),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      // Continue anyway - SMS features still work, just no AI
    }

    // Set up callback for new SMS - refresh UI when SMS arrives
    SmsService.instance.onNewSmsReceived = (message) {
      _debouncedRefreshData();
      if (mounted) {
        setState(() {
          _pendingScamChecks = ScamProcessorService.instance.pendingCount;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New SMS from ${message.address}'),
            backgroundColor: const Color(0xFF00D4FF),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    };

    SmsService.instance.startListeningForIncomingSms();

    // Start scam processing in background
    if (ScamProcessorService.instance.isInitialized) {
      // startProcessing loads items then returns (loop runs independently)
      await ScamProcessorService.instance.startProcessing();
      if (mounted) {
        setState(() {
          _pendingScamChecks = ScamProcessorService.instance.pendingCount;
        });
      }
    }

    setState(() {
      _statusMessage = _aiInitialized
          ? 'SMS listener active. AI protection enabled.'
          : 'SMS listener active. AI failed to load.';
    });

    await _refreshData();
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Requesting permissions...';
    });

    final granted = await PermissionService.requestAllPermissions();

    if (granted) {
      setState(() {
        _permissionsGranted = true;
        _statusMessage = 'All permissions granted!';
      });
      await _initializeServices();
    } else {
      final permanentlyDenied =
          await PermissionService.isAnyPermissionPermanentlyDenied();
      if (permanentlyDenied && mounted) {
        _showSettingsDialog();
      }
      setState(() {
        _statusMessage = 'Some permissions denied. SMS features limited.';
      });
    }

    setState(() => _isLoading = false);
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Permissions Required',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'SMS permissions are permanently denied. Please enable them in app settings.',
          style: TextStyle(color: Colors.white70),
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
              Navigator.pop(context);
              PermissionService.openSettings();
            },
            child: const Text(
              'OPEN SETTINGS',
              style: TextStyle(color: Color(0xFF00D4FF)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchAllSms() async {
    setState(() {
      _isFetchingSms = true;
      _statusMessage = 'Loading SMS messages...';
    });

    try {
      final result = await SmsService.instance.fetchAndStoreAllSms();

      if (mounted) {
        setState(() {
          _statusMessage =
              'Loaded ${result['total']} messages: ${result['unread']} unread, ${result['read']} read, ${result['sent']} sent';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fetched ${result['total']} SMS messages'),
            backgroundColor: const Color(0xFF1E1E1E),
          ),
        );

        await _refreshData();

        // Tell processor to check newly fetched messages
        if (ScamProcessorService.instance.isInitialized) {
          await ScamProcessorService.instance.reloadUncheckedMessages();
          setState(() {
            _pendingScamChecks = ScamProcessorService.instance.pendingCount;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error fetching SMS: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFFF3366),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingSms = false);
      }
    }
  }

  /// Debounced refresh - ensures UI updates at most every 1 second
  void _debouncedRefreshData() {
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(
      const Duration(milliseconds: 1000),
      _refreshData,
    );
  }

  Future<void> _refreshData() async {
    try {
      final stats = await SmsService.instance.getStats();
      final unread = await SmsService.instance.getUnreadSms();
      final read = await SmsService.instance.getReadSms();
      final sent = await SmsService.instance.getSentSms();

      if (mounted) {
        setState(() {
          _stats = stats;
          _unreadSms = unread;
          _readSms = read;
          _sentSms = sent;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                        _buildProtectionStatusCard(),
                        const SizedBox(height: 16),
                        _buildPermissionCard(),
                        const SizedBox(height: 12),
                        _buildActionCard(
                          icon: Icons.download_rounded,
                          title: 'Fetch All SMS',
                          subtitle: 'Load all SMS from device into database',
                          onTap: _permissionsGranted ? _fetchAllSms : null,
                          isLoading: _isFetchingSms,
                        ),
                        const SizedBox(height: 24),
                        if (_stats['total']! > 0) ...[
                          _buildSectionHeader('DATABASE STATISTICS'),
                          const SizedBox(height: 12),
                          _buildStatsCard(),
                          const SizedBox(height: 24),
                        ],
                        _buildSectionHeader('SMS MESSAGES'),
                        const SizedBox(height: 12),
                        _buildSmsTabsCard(),
                        const SizedBox(height: 16),
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
            child: const Icon(Icons.shield, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SilverGuard',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                _aiInitialized
                    ? (_pendingScamChecks > 0
                          ? 'Checking $_pendingScamChecks messages...'
                          : 'AI Protection Active')
                    : (_listenerStarted
                          ? 'Loading AI model...'
                          : 'SMS Protection Inactive'),
                style: TextStyle(
                  fontSize: 12,
                  color: _aiInitialized
                      ? const Color(0xFF00D4FF)
                      : const Color(0xFF888888),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (_pendingScamChecks > 0)
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF00D4FF),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProtectionStatusCard() {
    final isActive = _permissionsGranted && _listenerStarted;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isActive
              ? [
                  const Color(0xFF00D4FF).withValues(alpha: 0.2),
                  const Color(0xFF0099CC).withValues(alpha: 0.1),
                ]
              : [
                  const Color(0xFFFF3366).withValues(alpha: 0.2),
                  const Color(0xFFCC0033).withValues(alpha: 0.1),
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? const Color(0xFF00D4FF).withValues(alpha: 0.5)
              : const Color(0xFFFF3366).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isActive
                    ? [const Color(0xFF00D4FF), const Color(0xFF0099CC)]
                    : [const Color(0xFFFF3366), const Color(0xFFCC0033)],
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (isActive
                              ? const Color(0xFF00D4FF)
                              : const Color(0xFFFF3366))
                          .withValues(alpha: 0.4),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              isActive ? Icons.shield : Icons.shield_outlined,
              size: 48,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isActive ? 'PROTECTION ACTIVE' : 'PROTECTION DISABLED',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isActive
                  ? const Color(0xFF00D4FF)
                  : const Color(0xFFFF3366),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listenerStarted
                      ? const Color(0xFF00FF88)
                      : const Color(0xFF666666),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _listenerStarted
                    ? 'SMS Monitoring Active'
                    : 'SMS Monitoring Inactive',
                style: TextStyle(
                  fontSize: 12,
                  color: _listenerStarted
                      ? const Color(0xFF00FF88)
                      : Colors.white38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _aiInitialized
                      ? const Color(0xFF00FF88)
                      : const Color(0xFF666666),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _aiInitialized
                    ? (_pendingScamChecks > 0
                          ? 'AI Checking $_pendingScamChecks messages...'
                          : 'AI Protection Active')
                    : 'AI Not Loaded',
                style: TextStyle(
                  fontSize: 12,
                  color: _aiInitialized
                      ? const Color(0xFF00FF88)
                      : Colors.white38,
                ),
              ),
              if (_pendingScamChecks > 0) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF00D4FF),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard() {
    return GestureDetector(
      onTap: _requestPermissions,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _permissionsGranted
                ? const Color(0xFF00D4FF).withValues(alpha: 0.3)
                : const Color(0xFF333333),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _permissionsGranted
                    ? const Color(0xFF00D4FF).withValues(alpha: 0.2)
                    : const Color(0xFF333333),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.sms,
                color: _permissionsGranted
                    ? const Color(0xFF00D4FF)
                    : Colors.white70,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SMS Permission',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Required to read and monitor SMS messages',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _permissionsGranted
                    ? const Color(0xFF00D4FF).withValues(alpha: 0.2)
                    : const Color(0xFFFF3366).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _permissionsGranted ? 'ENABLED' : 'TAP TO ENABLE',
                style: TextStyle(
                  color: _permissionsGranted
                      ? const Color(0xFF00D4FF)
                      : const Color(0xFFFF3366),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    final isEnabled = onTap != null && !isLoading;

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEnabled
                ? const Color(0xFF333333)
                : const Color(0xFF222222),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isEnabled
                    ? const Color(0xFF00D4FF).withValues(alpha: 0.1)
                    : const Color(0xFF222222),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00D4FF),
                      ),
                    )
                  : Icon(
                      icon,
                      color: isEnabled
                          ? const Color(0xFF00D4FF)
                          : Colors.white38,
                      size: 24,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isEnabled ? Colors.white : Colors.white38,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isEnabled ? Colors.white54 : Colors.white24,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: isEnabled ? Colors.white38 : Colors.white12,
              size: 16,
            ),
          ],
        ),
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

  Widget _buildStatsCard() {
    final totalReceived = _stats['unread']! + _stats['read']!;
    final checked = totalReceived - _stats['unchecked']!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        children: [
          _buildStatRow('Total SMS', '${_stats['total']}', Icons.message),
          const Divider(color: Color(0xFF333333), height: 24),
          Row(
            children: [
              Expanded(
                child: _buildStatBadge(
                  'Unread',
                  '${_stats['unread']}',
                  const Color(0xFF00D4FF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBadge(
                  'Read',
                  '${_stats['read']}',
                  const Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBadge(
                  'Sent',
                  '${_stats['sent']}',
                  const Color(0xFF888888),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF333333), height: 24),
          // AI Analysis Progress
          Row(
            children: [
              Icon(
                checked == totalReceived ? Icons.check_circle : Icons.sync,
                color: checked == totalReceived
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFF00D4FF),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'AI Analyzed: $checked / $totalReceived',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              if (_stats['unchecked']! > 0) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9E9E9E).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_stats['unchecked']} pending',
                    style: const TextStyle(
                      color: Color(0xFF9E9E9E),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // Threat Level Breakdown
          Row(
            children: [
              Expanded(
                child: _buildThreatBadge(
                  'SAFE',
                  _stats['safe']!,
                  const Color(0xFF4CAF50),
                  Icons.verified_user,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildThreatBadge(
                  'UNCERTAIN',
                  _stats['uncertain']!,
                  const Color(0xFFFFC107),
                  Icons.help_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildThreatBadge(
                  'SUSPICIOUS',
                  _stats['suspicious']!,
                  const Color(0xFFFF9800),
                  Icons.warning_amber,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildThreatBadge(
                  'SCAM',
                  _stats['scam']!,
                  const Color(0xFFF44336),
                  Icons.dangerous,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThreatBadge(
    String label,
    int count,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: count > 0 ? 0.15 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: count > 0 ? 0.4 : 0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color.withValues(alpha: count > 0 ? 1.0 : 0.4),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color.withValues(alpha: count > 0 ? 1.0 : 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    color: count > 0 ? Colors.white : Colors.white38,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00D4FF), size: 20),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildStatBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSmsTabsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF333333))),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF00D4FF),
              unselectedLabelColor: Colors.white38,
              indicatorColor: const Color(0xFF00D4FF),
              indicatorWeight: 2,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mark_email_unread, size: 16),
                      const SizedBox(width: 6),
                      Text('${_unreadSms.length}'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mark_email_read, size: 16),
                      const SizedBox(width: 6),
                      Text('${_readSms.length}'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.send, size: 16),
                      const SizedBox(width: 6),
                      Text('${_sentSms.length}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 400,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUnreadList(),
                _buildReadList(),
                _buildSentList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnreadList() {
    if (_unreadSms.isEmpty) {
      return _buildEmptyState(Icons.mark_email_unread, 'No unread messages');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _unreadSms.length,
      itemBuilder: (context, index) {
        final sms = _unreadSms[index];
        return _buildSmsItem(
          address: sms.displayName,
          body: sms.body,
          date: sms.date,
          threatScore: sms.threatScore,
          kind: 'unread',
        );
      },
    );
  }

  Widget _buildReadList() {
    if (_readSms.isEmpty) {
      return _buildEmptyState(Icons.mark_email_read, 'No read messages');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _readSms.length,
      itemBuilder: (context, index) {
        final sms = _readSms[index];
        return _buildSmsItem(
          address: sms.displayName,
          body: sms.body,
          date: sms.date,
          threatScore: sms.threatScore,
          kind: 'read',
        );
      },
    );
  }

  Widget _buildSentList() {
    if (_sentSms.isEmpty) {
      return _buildEmptyState(Icons.send, 'No sent messages');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _sentSms.length,
      itemBuilder: (context, index) {
        final sms = _sentSms[index];
        return _buildSmsItem(
          address: sms.displayName,
          body: sms.body,
          date: sms.date,
          threatScore: null, // Sent messages don't have threat score
          kind: 'sent',
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmsItem({
    required String address,
    required String body,
    required int date,
    double? threatScore,
    required String kind,
  }) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(date);
    final formattedDate =
        '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';

    Color kindColor;
    switch (kind) {
      case 'unread':
        kindColor = const Color(0xFF00D4FF);
        break;
      case 'sent':
        kindColor = const Color(0xFF4CAF50);
        break;
      default:
        kindColor = const Color(0xFF666666);
    }

    // Threat level colors based on score
    // null = UNCHECKED (gray), <0.30 = SAFE (green), 0.30-0.49 = UNCERTAIN (amber)
    // 0.50-0.69 = SUSPICIOUS (orange), >=0.70 = SCAM (red)
    Color statusBorderColor;
    String statusLabel;
    IconData statusIcon;
    bool hasWarning = false;

    if (kind == 'sent') {
      // Sent messages don't have threat score
      statusBorderColor = const Color(0xFF666666);
      statusLabel = 'SENT';
      statusIcon = Icons.send;
    } else if (threatScore == null) {
      statusBorderColor = const Color(0xFF9E9E9E);
      statusLabel = 'UNCHECKED';
      statusIcon = Icons.hourglass_empty;
    } else if (threatScore < 0.30) {
      statusBorderColor = const Color(0xFF4CAF50); // Green
      statusLabel = 'SAFE';
      statusIcon = Icons.verified_user;
    } else if (threatScore < 0.50) {
      statusBorderColor = const Color(0xFFFFC107); // Amber
      statusLabel = 'UNCERTAIN';
      statusIcon = Icons.help_outline;
      hasWarning = true;
    } else if (threatScore < 0.70) {
      statusBorderColor = const Color(0xFFFF9800); // Orange
      statusLabel = 'SUSPICIOUS';
      statusIcon = Icons.warning_amber;
      hasWarning = true;
    } else {
      statusBorderColor = const Color(0xFFF44336); // Red
      statusLabel = 'SCAM';
      statusIcon = Icons.dangerous;
      hasWarning = true;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasWarning
            ? statusBorderColor.withValues(alpha: 0.15)
            : const Color(0xFF252525),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasWarning
              ? statusBorderColor.withValues(alpha: 0.5)
              : const Color(0xFF333333),
          width: hasWarning ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasWarning ? statusBorderColor : kindColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        address,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Status tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBorderColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusBorderColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 9,
                        color: statusBorderColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            formattedDate,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
