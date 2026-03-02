import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart' as sms_inbox;
import 'package:another_telephony/telephony.dart' as telephony;
import '../models/sms_message.dart';
import 'database_helper.dart';
import 'contacts_service.dart';
import 'scam_processor_service.dart';

/// Background message handler - MUST be top-level function
/// Called by Android when SMS arrives while app is in background
@pragma('vm:entry-point')
void backgroundMessageHandler(telephony.SmsMessage message) async {
  debugPrint('>>> BACKGROUND SMS RECEIVED: ${message.address}');
  debugPrint('>>> BACKGROUND SMS BODY: ${message.body}');
  // Note: Can't access SmsService.instance here reliably
  // The foreground handler will pick it up when app resumes
}

class SmsService {
  static final SmsService instance = SmsService._init();
  final sms_inbox.SmsQuery _smsQuery = sms_inbox.SmsQuery();
  final telephony.Telephony _telephony = telephony.Telephony.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ContactsService _contactsService = ContactsService.instance;
  final ScamProcessorService _scamProcessor = ScamProcessorService.instance;

  /// Callback for when new SMS is received (for UI updates)
  Function(telephony.SmsMessage)? onNewSmsReceived;

  SmsService._init();

  /// Initialize contacts before fetching SMS
  Future<void> initializeContacts() async {
    await _contactsService.loadContacts();
  }

  /// Fetch all SMS from inbox and store in all tables (sms, unread, read, sent)
  Future<Map<String, int>> fetchAndStoreAllSms() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Ensure contacts are loaded
    if (!_contactsService.isLoaded) {
      await initializeContacts();
    }

    // Lists for each table
    final List<SmsMessage> allSms = [];
    final List<UnreadSms> unreadList = [];
    final List<ReadSms> readList = [];
    final List<SentSms> sentList = [];

    // Fetch all SMS using flutter_sms_inbox
    final List<sms_inbox.SmsMessage> messages = await _smsQuery.getAllSms;

    for (final msg in messages) {
      final address = msg.address ?? '';
      final body = msg.body ?? '';
      final date = msg.date?.millisecondsSinceEpoch ?? now;
      final type = _convertSmsKindToType(msg.kind);
      final isRead = msg.read ?? false;

      // Lookup contact name
      final contactName = _contactsService.getContactName(address);

      // Add to main sms table
      allSms.add(
        SmsMessage(
          address: address,
          body: body,
          date: date,
          type: type,
          read: isRead ? 1 : 0,
          serviceCenter: null,
          createdAt: now,
        ),
      );

      // Distribute to appropriate table based on type and read status
      if (type == 2) {
        // Sent message
        sentList.add(
          SentSms(
            address: address,
            contactName: contactName,
            body: body,
            date: date,
            serviceCenter: null,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else if (isRead) {
        // Received + Read
        readList.add(
          ReadSms(
            address: address,
            contactName: contactName,
            body: body,
            date: date,
            serviceCenter: null,
            createdAt: now,
            updatedAt: now,
            threatScore: null, // Not classified yet
          ),
        );
      } else {
        // Received + Unread
        unreadList.add(
          UnreadSms(
            address: address,
            contactName: contactName,
            body: body,
            date: date,
            serviceCenter: null,
            createdAt: now,
            updatedAt: now,
            threatScore: null, // Not classified yet
          ),
        );
      }
    }

    // Insert into all tables (duplicates are ignored)
    await _dbHelper.insertMultipleSms(allSms);
    await _dbHelper.insertMultipleUnread(unreadList);
    await _dbHelper.insertMultipleRead(readList);
    await _dbHelper.insertMultipleSent(sentList);

    return {
      'total': allSms.length,
      'unread': unreadList.length,
      'read': readList.length,
      'sent': sentList.length,
    };
  }

  /// Start listening for incoming SMS using another_telephony
  void startListeningForIncomingSms() {
    debugPrint('SmsService: Starting SMS listener...');
    _telephony.listenIncomingSms(
      onNewMessage: _onNewSmsReceived,
      onBackgroundMessage: backgroundMessageHandler,
      listenInBackground: true,
    );
    debugPrint('SmsService: SMS listener registered successfully');
  }

  /// Handle new incoming SMS - adds to sms and unread tables
  Future<void> _onNewSmsReceived(telephony.SmsMessage message) async {
    debugPrint('>>> SMS RECEIVED: ${message.address}');
    debugPrint('>>> SMS BODY: ${message.body}');

    final now = DateTime.now().millisecondsSinceEpoch;
    final address = message.address ?? '';
    final body = message.body ?? '';
    final date = message.date ?? now;
    final serviceCenter = message.serviceCenterAddress;

    // Ensure contacts are loaded for name lookup
    if (!_contactsService.isLoaded) {
      await _contactsService.loadContacts();
    }

    // Lookup contact name
    final contactName = _contactsService.getContactName(address);
    debugPrint('>>> CONTACT NAME: $contactName');

    // Add to main sms table
    final sms = SmsMessage(
      address: address,
      body: body,
      date: date,
      type: 1, // Received
      read: 0, // Unread
      serviceCenter: serviceCenter,
      createdAt: now,
    );
    await _dbHelper.insertSms(sms);
    debugPrint('SmsService: Saved to main sms table');

    // Add to unread table (new SMS is always unread)
    final unread = UnreadSms(
      address: address,
      contactName: contactName,
      body: body,
      date: date,
      serviceCenter: serviceCenter,
      createdAt: now,
      updatedAt: now,
      threatScore: null, // Not classified yet
    );
    final insertedId = await _dbHelper.insertUnread(unread);
    debugPrint('SmsService: Saved to unread table (id: $insertedId)');

    // Push to scam processor for AI classification (highest priority)
    if (insertedId > 0 && _scamProcessor.isInitialized) {
      final unreadWithId = UnreadSms(
        id: insertedId,
        address: address,
        contactName: contactName,
        body: body,
        date: date,
        serviceCenter: serviceCenter,
        createdAt: now,
        updatedAt: now,
        threatScore: null,
      );
      _scamProcessor.pushIncoming(unreadWithId);
      debugPrint('SmsService: Pushed to scam processor');
    }

    // Notify UI callback if set
    onNewSmsReceived?.call(message);
    debugPrint('SmsService: Callback triggered');
  }

  /// Convert SmsMessageKind to type integer
  int _convertSmsKindToType(sms_inbox.SmsMessageKind? kind) {
    switch (kind) {
      case sms_inbox.SmsMessageKind.sent:
        return 2;
      case sms_inbox.SmsMessageKind.received:
      default:
        return 1;
    }
  }

  // ==================== GETTERS ====================

  /// Get all unread SMS
  Future<List<UnreadSms>> getUnreadSms() async {
    return await _dbHelper.getAllUnread();
  }

  /// Get all read SMS
  Future<List<ReadSms>> getReadSms() async {
    return await _dbHelper.getAllRead();
  }

  /// Get all sent SMS
  Future<List<SentSms>> getSentSms() async {
    return await _dbHelper.getAllSent();
  }

  /// Get database statistics
  Future<Map<String, int>> getStats() async {
    return await _dbHelper.getStats();
  }

  /// Get counts for each table
  Future<Map<String, int>> getCounts() async {
    return {
      'total': await _dbHelper.getSmsCount(),
      'unread': await _dbHelper.getUnreadCount(),
      'read': await _dbHelper.getReadCount(),
      'sent': await _dbHelper.getSentCount(),
    };
  }
}
