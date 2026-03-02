import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/sms_message.dart';
import 'database_helper.dart';
import 'scam_detector_service.dart';
import 'notification_service.dart';

/// Priority levels for processing queue
enum ProcessingPriority {
  incoming, // New SMS - highest priority, 50ms delay
  unread, // Unread messages - medium priority, 150ms delay
  read, // Read messages - lowest priority, 400ms delay
}

/// Item in the processing stack
class _ProcessingItem {
  final int id;
  final String address;
  final String body;
  final String table; // 'unread' or 'read'
  final ProcessingPriority priority;

  _ProcessingItem({
    required this.id,
    required this.address,
    required this.body,
    required this.table,
    required this.priority,
  });

  @override
  String toString() =>
      '_ProcessingItem(id: $id, table: $table, priority: $priority)';
}

/// Scam Processor Service - manages background scam detection processing
/// Uses a LIFO stack: Read (bottom) -> Unread (middle) -> Incoming (top)
class ScamProcessorService {
  static final ScamProcessorService instance = ScamProcessorService._init();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ScamDetectorService _detector = ScamDetectorService.instance;
  final NotificationService _notificationService = NotificationService.instance;

  final List<_ProcessingItem> _stack = [];
  bool _isRunning = false;
  bool _isInitialized = false;
  Completer<void>? _itemAvailable;

  // Callbacks for UI updates
  VoidCallback? onProcessingComplete;
  void Function(int id, String table, double threatScore)? onItemProcessed;

  ScamProcessorService._init();

  bool get isRunning => _isRunning;
  bool get isInitialized => _isInitialized;
  int get pendingCount => _stack.length;

  /// Initialize the processor and scam detector
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('ScamProcessor: Initializing...');

    // Initialize the AI detector first
    await _detector.initialize();

    _isInitialized = true;
    debugPrint('ScamProcessor: Initialized successfully');
  }

  /// Load unchecked messages from database and start processing
  Future<void> startProcessing() async {
    if (!_isInitialized) {
      throw StateError(
        'ScamProcessorService not initialized. Call initialize() first.',
      );
    }

    if (_isRunning) {
      debugPrint('ScamProcessor: Already running');
      return;
    }

    debugPrint('ScamProcessor: Starting processing...');

    // Load unchecked messages into stack
    // Order: Read first (bottom), then Unread (top)
    await _loadUncheckedMessages();

    // Start background processing loop
    _isRunning = true;
    _processLoop();

    debugPrint('ScamProcessor: Processing loop started');
  }

  /// Load unchecked messages from database into the stack
  Future<void> _loadUncheckedMessages() async {
    _stack.clear();

    // Load READ messages first (they go to bottom of stack)
    final uncheckedRead = await _dbHelper.getUncheckedRead();
    for (final sms in uncheckedRead) {
      _stack.add(
        _ProcessingItem(
          id: sms.id!,
          address: sms.address,
          body: sms.body,
          table: 'read',
          priority: ProcessingPriority.read,
        ),
      );
    }
    debugPrint(
      'ScamProcessor: Loaded ${uncheckedRead.length} unchecked read messages',
    );

    // Load UNREAD messages second (they go on top of read)
    final uncheckedUnread = await _dbHelper.getUncheckedUnread();
    for (final sms in uncheckedUnread) {
      _stack.add(
        _ProcessingItem(
          id: sms.id!,
          address: sms.address,
          body: sms.body,
          table: 'unread',
          priority: ProcessingPriority.unread,
        ),
      );
    }
    debugPrint(
      'ScamProcessor: Loaded ${uncheckedUnread.length} unchecked unread messages',
    );

    debugPrint('ScamProcessor: Total stack size: ${_stack.length}');
  }

  /// Push a new incoming SMS to the top of the stack (highest priority)
  void pushIncoming(UnreadSms sms) {
    if (sms.id == null) {
      debugPrint('ScamProcessor: Cannot push SMS without ID');
      return;
    }

    final item = _ProcessingItem(
      id: sms.id!,
      address: sms.address,
      body: sms.body,
      table: 'unread',
      priority: ProcessingPriority.incoming,
    );

    _stack.add(item);
    debugPrint('ScamProcessor: Pushed incoming SMS to stack (id: ${sms.id})');

    // Wake up the processing loop if it's waiting
    _itemAvailable?.complete();
    _itemAvailable = null;
  }

  /// Background processing loop
  Future<void> _processLoop() async {
    while (_isRunning) {
      if (_stack.isEmpty) {
        // Wait for new items
        _itemAvailable = Completer<void>();
        debugPrint('ScamProcessor: Stack empty, waiting for new items...');
        await _itemAvailable!.future;
        continue;
      }

      // Pop from top of stack (LIFO)
      final item = _stack.removeLast();
      debugPrint('ScamProcessor: Processing ${item.table} id=${item.id}');

      try {
        // Run scam detection
        final result = await _detector.detectScam(item.address, item.body);

        // Update database with threat score
        if (item.table == 'unread') {
          await _dbHelper.updateUnreadThreatScore(item.id, result.threatScore);
        } else {
          await _dbHelper.updateReadThreatScore(item.id, result.threatScore);
        }

        // Set decision based on threat score (unread only)
        if (result.threatScore < 0.50) {
          // Safe — auto-mark as safe (only for unread)
          if (item.table == 'unread') {
            await _dbHelper.updateUnreadDecision(item.id, 'safe');
          }
        } else if (item.table == 'unread') {
          // Suspicious/Scam unread SMS — send immediate notification
          if (_notificationService.isInitialized) {
            await _notificationService.showScamAlert(
              id: item.id,
              table: 'unread',
              address: item.address,
              body: item.body,
              threatScore: result.threatScore,
            );
          }
        }

        debugPrint(
          'ScamProcessor: ${item.table} id=${item.id} -> ${result.verdict} '
          '(score: ${result.threatScore.toStringAsFixed(3)})',
        );

        // Notify callback with threat score
        onItemProcessed?.call(item.id, item.table, result.threatScore);
      } catch (e) {
        debugPrint(
          'ScamProcessor: Error processing ${item.table} id=${item.id}: $e',
        );
        // Don't update status - leave as NULL so it can be retried later
      }

      // Apply rate limiting based on priority
      final delay = _getDelayForPriority(item.priority);
      await Future.delayed(Duration(milliseconds: delay));
    }

    debugPrint('ScamProcessor: Processing loop stopped');
    onProcessingComplete?.call();
  }

  /// Get delay in milliseconds for rate limiting
  int _getDelayForPriority(ProcessingPriority priority) {
    switch (priority) {
      case ProcessingPriority.incoming:
        return 50; // Fastest - new SMS needs quick classification
      case ProcessingPriority.unread:
        return 150; // Medium - user might be looking at these
      case ProcessingPriority.read:
        return 400; // Slowest - already read, less urgent
    }
  }

  /// Reload unchecked messages from database (call after fetching new SMS)
  Future<void> reloadUncheckedMessages() async {
    if (!_isInitialized || !_isRunning) return;

    await _loadUncheckedMessages();

    // Wake up the loop if it was waiting
    _itemAvailable?.complete();
    _itemAvailable = null;
  }

  /// Stop the processing loop
  void stopProcessing() {
    if (!_isRunning) return;

    debugPrint('ScamProcessor: Stopping processing...');
    _isRunning = false;

    // Wake up the loop if it's waiting so it can exit
    _itemAvailable?.complete();
    _itemAvailable = null;
  }

  /// Dispose resources
  Future<void> dispose() async {
    stopProcessing();
    _stack.clear();
    _isInitialized = false;
    debugPrint('ScamProcessor: Disposed');
  }
}
