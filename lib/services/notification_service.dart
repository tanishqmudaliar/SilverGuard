import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'sms_sender_service.dart';

/// Key for storing the periodic check interval in SharedPreferences
const String _kCheckIntervalKey = 'notification_check_interval_minutes';
const int _kDefaultIntervalMinutes = 30;

/// Top-level background handler for notification actions
/// Required for actions when app is not in the foreground
@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) async {
  final action = response.actionId;
  final payloadStr = response.payload;

  if (payloadStr == null || payloadStr.isEmpty) return;

  try {
    final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
    final id = payload['id'] as int;
    final table = payload['table'] as String;
    final body = payload['body'] as String;

    final dbHelper = DatabaseHelper.instance;
    final smsSender = SmsSenderService.instance;
    final notifications = FlutterLocalNotificationsPlugin();

    // Cancel the notification explicitly
    await notifications.cancel(id: id);

    if (action == 'dismiss') {
      if (table == 'unread') {
        await dbHelper.updateUnreadDecision(id, 'dismissed');
      }
    } else if (action == 'report') {
      final guardians = await dbHelper.getAllGuardians();
      if (guardians.isEmpty) {
        // No guardians set — don't mark as reported, show info notification
        await notifications.show(
          id: 999999,
          title: 'No Guardian Contact Set',
          body:
              'Please add a guardian contact in Settings to enable scam reporting.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'info_channel',
              'Info',
              channelDescription: 'Informational notifications',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
        );
      } else {
        // Guardians exist — mark as reported and send alerts
        if (table == 'unread') {
          await dbHelper.updateUnreadDecision(id, 'reported');
        }

        final truncatedBody = body.length > 100
            ? '${body.substring(0, 100)}...'
            : body;
        final alertMessage =
            '[SilverGuard Alert] A scam SMS was reported.\n'
            'Message: $truncatedBody';

        for (final guardian in guardians) {
          await smsSender.sendSms(number: guardian.phone, body: alertMessage);
        }
      }
    }
  } catch (e) {
    // Can't use debugPrint in background isolate reliably
  }
}

/// Notification Service - handles local notifications for scam alerts
/// Shows notifications with Dismiss/Report actions for suspicious SMS
class NotificationService {
  static final NotificationService instance = NotificationService._init();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final SmsSenderService _smsSender = SmsSenderService.instance;

  bool _isInitialized = false;
  Timer? _periodicTimer;
  int _checkIntervalMinutes = _kDefaultIntervalMinutes;

  NotificationService._init();

  bool get isInitialized => _isInitialized;
  int get checkIntervalMinutes => _checkIntervalMinutes;

  /// Initialize the notification plugin
  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    // Check if notification channel was created
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      final areEnabled = await androidPlugin.areNotificationsEnabled();
      debugPrint(
        'NotificationService: Notifications enabled on device: $areEnabled',
      );
    }

    // Load saved check interval
    await _loadCheckInterval();

    _isInitialized = true;
    debugPrint('NotificationService: Initialized');
  }

  /// Load the saved check interval from SharedPreferences
  Future<void> _loadCheckInterval() async {
    final prefs = await SharedPreferences.getInstance();
    _checkIntervalMinutes =
        prefs.getInt(_kCheckIntervalKey) ?? _kDefaultIntervalMinutes;
  }

  /// Update the check interval and restart the periodic timer
  Future<void> setCheckInterval(int minutes) async {
    _checkIntervalMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCheckIntervalKey, minutes);
    // Restart the periodic check with the new interval
    if (_periodicTimer != null) {
      startPeriodicCheck();
    }
    debugPrint('NotificationService: Check interval updated to $minutes min');
  }

  /// Start the periodic check for pending scam alerts
  void startPeriodicCheck() {
    _periodicTimer?.cancel();
    // Run immediately on start, then at the configured interval
    _checkPendingAlerts();
    _periodicTimer = Timer.periodic(
      Duration(minutes: _checkIntervalMinutes),
      (_) => _checkPendingAlerts(),
    );
    debugPrint(
      'NotificationService: Periodic check started (every $_checkIntervalMinutes min)',
    );
  }

  /// Stop the periodic check
  void stopPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    debugPrint('NotificationService: Periodic check stopped');
  }

  /// Check unread table for pending alerts (decision IS NULL, threat_score >= 0.50)
  Future<void> _checkPendingAlerts() async {
    if (!_isInitialized) return;

    try {
      final pendingAlerts = await _dbHelper.getPendingUnreadAlerts();

      if (pendingAlerts.isEmpty) {
        debugPrint('NotificationService: No pending alerts');
        return;
      }

      debugPrint(
        'NotificationService: Found ${pendingAlerts.length} pending alert(s)',
      );

      for (final sms in pendingAlerts) {
        if (sms.id == null || sms.threatScore == null) continue;
        await showScamAlert(
          id: sms.id!,
          table: 'unread',
          address: sms.address,
          body: sms.body,
          threatScore: sms.threatScore!,
        );
      }
    } catch (e) {
      debugPrint('NotificationService: Error checking pending alerts: $e');
    }
  }

  /// Show a scam alert notification with Dismiss and Report actions
  /// [id] - SMS id in the unread table
  /// [table] - always 'unread'
  /// [address] - sender address
  /// [body] - SMS body
  /// [threatScore] - AI threat score
  Future<void> showScamAlert({
    required int id,
    required String table,
    required String address,
    required String body,
    required double threatScore,
  }) async {
    if (!_isInitialized) {
      debugPrint('NotificationService: Not initialized, skipping notification');
      return;
    }

    final scorePercent = (threatScore * 100).toStringAsFixed(0);
    final isScam = threatScore >= 0.70;
    final label = isScam ? 'SCAM DETECTED' : 'SUSPICIOUS SMS';

    // Encode payload as JSON so we can identify the SMS on action
    final payload = jsonEncode({
      'id': id,
      'table': table,
      'address': address,
      'body': body,
      'threatScore': threatScore,
    });

    // Only show Report button if guardians are configured
    final guardians = await _dbHelper.getAllGuardians();
    final hasGuardians = guardians.isNotEmpty;

    final actions = <AndroidNotificationAction>[
      const AndroidNotificationAction(
        'dismiss',
        'Dismiss',
        showsUserInterface: true,
        cancelNotification: true,
      ),
      if (hasGuardians)
        const AndroidNotificationAction(
          'report',
          'Report',
          showsUserInterface: true,
          cancelNotification: true,
        ),
    ];

    final androidDetails = AndroidNotificationDetails(
      'scam_alerts',
      'Scam Alerts',
      channelDescription: 'Notifications for suspicious or scam SMS messages',
      importance: Importance.high,
      priority: Priority.high,
      color: isScam ? const Color(0xFFF44336) : const Color(0xFFFF9800),
      styleInformation: BigTextStyleInformation(
        'From: $address\n$body',
        contentTitle: '$label ($scorePercent% threat)',
        summaryText: 'Tap to open app',
      ),
      actions: actions,
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      await _notifications.show(
        id: id,
        title: label,
        body:
            'From $address: ${body.length > 80 ? '${body.substring(0, 80)}...' : body}',
        notificationDetails: details,
        payload: payload,
      );

      debugPrint(
        'NotificationService: Showed $label for $table id=$id (score: $scorePercent%)',
      );
    } catch (e, stack) {
      debugPrint('NotificationService: ERROR showing notification: $e');
      debugPrint('NotificationService: Stack: $stack');
    }
  }

  /// Handle notification action responses (foreground)
  void _onNotificationResponse(NotificationResponse response) async {
    debugPrint(
      'NotificationService: Response received - actionId: "${response.actionId}", '
      'notificationResponseType: ${response.notificationResponseType}',
    );
    final action = response.actionId;
    final payloadStr = response.payload;

    if (payloadStr == null || payloadStr.isEmpty) return;

    try {
      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
      final id = payload['id'] as int;
      final table = payload['table'] as String;
      final address = payload['address'] as String;
      final body = payload['body'] as String;

      // Explicitly cancel the notification
      await _notifications.cancel(id: id);

      if (action == 'dismiss') {
        await _handleDismiss(id, table);
      } else if (action == 'report') {
        await _handleReport(id, table, address, body);
      }
    } catch (e) {
      debugPrint('NotificationService: Error handling response: $e');
    }
  }

  /// Handle dismiss action - mark as dismissed in DB
  Future<void> _handleDismiss(int id, String table) async {
    debugPrint('NotificationService: Dismissing $table id=$id');

    if (table == 'unread') {
      await _dbHelper.updateUnreadDecision(id, 'dismissed');
    }

    debugPrint('NotificationService: $table id=$id marked as dismissed');
  }

  /// Handle report action - mark as reported + send SMS to guardians
  Future<void> _handleReport(
    int id,
    String table,
    String address,
    String body,
  ) async {
    debugPrint('NotificationService: Reporting $table id=$id');

    // Send alert SMS to all guardians
    final guardians = await _dbHelper.getAllGuardians();
    if (guardians.isEmpty) {
      debugPrint(
        'NotificationService: No guardians to alert - showing info notification',
      );
      await _showNoGuardianNotification();
      return;
    }

    // Guardians exist — mark as reported in DB
    if (table == 'unread') {
      await _dbHelper.updateUnreadDecision(id, 'reported');
    }

    final truncatedBody = body.length > 100
        ? '${body.substring(0, 100)}...'
        : body;
    final alertMessage =
        '[SilverGuard Alert] A scam SMS was reported.\n'
        'Message: $truncatedBody';

    for (final guardian in guardians) {
      await _smsSender.sendSms(number: guardian.phone, body: alertMessage);
    }

    debugPrint(
      'NotificationService: Reported $table id=$id, alerted ${guardians.length} guardian(s)',
    );
  }

  /// Show a notification informing the user that no guardian contact is set
  Future<void> _showNoGuardianNotification() async {
    if (!_isInitialized) return;

    const androidDetails = AndroidNotificationDetails(
      'info_channel',
      'Info',
      channelDescription: 'Informational notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      id: 999999,
      title: 'No Guardian Contact Set',
      body:
          'Please add a guardian contact in Settings to enable scam reporting.',
      notificationDetails: details,
    );
  }
}
