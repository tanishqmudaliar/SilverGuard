import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/sms_message.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('silverguard.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    // Main SMS table - raw storage from device
    await db.execute('''
      CREATE TABLE sms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT NOT NULL,
        body TEXT NOT NULL,
        date INTEGER NOT NULL,
        type INTEGER NOT NULL,
        read INTEGER NOT NULL,
        service_center TEXT,
        created_at INTEGER NOT NULL,
        UNIQUE(address, date, body)
      )
    ''');

    // Unread SMS table - received + unread, has threat_score for ML
    await db.execute('''
      CREATE TABLE unread (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT NOT NULL,
        contact_name TEXT,
        body TEXT NOT NULL,
        date INTEGER NOT NULL,
        service_center TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        threat_score REAL,
        UNIQUE(address, date, body)
      )
    ''');

    // Read SMS table - received + read, has threat_score for ML
    await db.execute('''
      CREATE TABLE read (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT NOT NULL,
        contact_name TEXT,
        body TEXT NOT NULL,
        date INTEGER NOT NULL,
        service_center TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        threat_score REAL,
        UNIQUE(address, date, body)
      )
    ''');

    // Sent SMS table - sent messages, NO is_scam
    await db.execute('''
      CREATE TABLE sent (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT NOT NULL,
        contact_name TEXT,
        body TEXT NOT NULL,
        date INTEGER NOT NULL,
        service_center TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(address, date, body)
      )
    ''');

    // Create indexes for faster queries
    await db.execute('CREATE INDEX idx_sms_address ON sms(address)');
    await db.execute('CREATE INDEX idx_sms_date ON sms(date)');
    await db.execute('CREATE INDEX idx_unread_address ON unread(address)');
    await db.execute('CREATE INDEX idx_unread_date ON unread(date)');
    await db.execute('CREATE INDEX idx_read_address ON read(address)');
    await db.execute('CREATE INDEX idx_read_date ON read(date)');
    await db.execute('CREATE INDEX idx_sent_address ON sent(address)');
    await db.execute('CREATE INDEX idx_sent_date ON sent(date)');
  }

  // ==================== SMS TABLE OPERATIONS ====================

  /// Insert SMS into main table (duplicates ignored)
  Future<int> insertSms(SmsMessage sms) async {
    final db = await database;
    return await db.insert(
      'sms',
      sms.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Insert multiple SMS messages into main table
  Future<void> insertMultipleSms(List<SmsMessage> smsList) async {
    final db = await database;
    final batch = db.batch();

    for (final sms in smsList) {
      batch.insert(
        'sms',
        sms.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Get all SMS from main table
  Future<List<SmsMessage>> getAllSms() async {
    final db = await database;
    final result = await db.query('sms', orderBy: 'date DESC');
    return result.map((map) => SmsMessage.fromMap(map)).toList();
  }

  /// Get SMS count from main table
  Future<int> getSmsCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM sms');
    return result.first['count'] as int;
  }

  // ==================== UNREAD TABLE OPERATIONS ====================

  /// Insert into unread table (duplicates ignored)
  Future<int> insertUnread(UnreadSms sms) async {
    final db = await database;
    return await db.insert(
      'unread',
      sms.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Insert multiple unread SMS
  Future<void> insertMultipleUnread(List<UnreadSms> smsList) async {
    final db = await database;
    final batch = db.batch();

    for (final sms in smsList) {
      batch.insert(
        'unread',
        sms.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Get all unread SMS
  Future<List<UnreadSms>> getAllUnread() async {
    final db = await database;
    final result = await db.query('unread', orderBy: 'date DESC');
    return result.map((map) => UnreadSms.fromMap(map)).toList();
  }

  /// Get unread count
  Future<int> getUnreadCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM unread');
    return result.first['count'] as int;
  }

  /// Update threat_score in unread table
  Future<int> updateUnreadThreatScore(int id, double threatScore) async {
    final db = await database;
    return await db.update(
      'unread',
      {
        'threat_score': threatScore,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get unchecked unread SMS (threat_score IS NULL)
  Future<List<UnreadSms>> getUncheckedUnread() async {
    final db = await database;
    final result = await db.query(
      'unread',
      where: 'threat_score IS NULL',
      orderBy: 'date ASC', // Oldest first so newest ends up on top of stack
    );
    return result.map((map) => UnreadSms.fromMap(map)).toList();
  }

  // ==================== READ TABLE OPERATIONS ====================

  /// Insert into read table (duplicates ignored)
  Future<int> insertRead(ReadSms sms) async {
    final db = await database;
    return await db.insert(
      'read',
      sms.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Insert multiple read SMS
  Future<void> insertMultipleRead(List<ReadSms> smsList) async {
    final db = await database;
    final batch = db.batch();

    for (final sms in smsList) {
      batch.insert(
        'read',
        sms.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Get all read SMS
  Future<List<ReadSms>> getAllRead() async {
    final db = await database;
    final result = await db.query('read', orderBy: 'date DESC');
    return result.map((map) => ReadSms.fromMap(map)).toList();
  }

  /// Get read count
  Future<int> getReadCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM read');
    return result.first['count'] as int;
  }

  /// Update threat_score in read table
  Future<int> updateReadThreatScore(int id, double threatScore) async {
    final db = await database;
    return await db.update(
      'read',
      {
        'threat_score': threatScore,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get unchecked read SMS (threat_score IS NULL)
  Future<List<ReadSms>> getUncheckedRead() async {
    final db = await database;
    final result = await db.query(
      'read',
      where: 'threat_score IS NULL',
      orderBy: 'date ASC', // Oldest first so newest ends up on top of stack
    );
    return result.map((map) => ReadSms.fromMap(map)).toList();
  }

  // ==================== SENT TABLE OPERATIONS ====================

  /// Insert into sent table (duplicates ignored)
  Future<int> insertSent(SentSms sms) async {
    final db = await database;
    return await db.insert(
      'sent',
      sms.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Insert multiple sent SMS
  Future<void> insertMultipleSent(List<SentSms> smsList) async {
    final db = await database;
    final batch = db.batch();

    for (final sms in smsList) {
      batch.insert(
        'sent',
        sms.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Get all sent SMS
  Future<List<SentSms>> getAllSent() async {
    final db = await database;
    final result = await db.query('sent', orderBy: 'date DESC');
    return result.map((map) => SentSms.fromMap(map)).toList();
  }

  /// Get sent count
  Future<int> getSentCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM sent');
    return result.first['count'] as int;
  }

  // ==================== STATISTICS ====================

  /// Get database statistics with all threat levels
  Future<Map<String, int>> getStats() async {
    final db = await database;

    final smsCount = await db.rawQuery('SELECT COUNT(*) as count FROM sms');
    final unreadCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM unread',
    );
    final readCount = await db.rawQuery('SELECT COUNT(*) as count FROM read');
    final sentCount = await db.rawQuery('SELECT COUNT(*) as count FROM sent');

    // Threat level counts from both unread and read tables
    // UNCHECKED: threat_score IS NULL
    final uncheckedUnread = await db.rawQuery(
      'SELECT COUNT(*) as count FROM unread WHERE threat_score IS NULL',
    );
    final uncheckedRead = await db.rawQuery(
      'SELECT COUNT(*) as count FROM read WHERE threat_score IS NULL',
    );

    // SAFE: threat_score < 0.30
    final safeUnread = await db.rawQuery(
      'SELECT COUNT(*) as count FROM unread WHERE threat_score IS NOT NULL AND threat_score < 0.30',
    );
    final safeRead = await db.rawQuery(
      'SELECT COUNT(*) as count FROM read WHERE threat_score IS NOT NULL AND threat_score < 0.30',
    );

    // UNCERTAIN: 0.30 <= threat_score < 0.50
    final uncertainUnread = await db.rawQuery(
      'SELECT COUNT(*) as count FROM unread WHERE threat_score >= 0.30 AND threat_score < 0.50',
    );
    final uncertainRead = await db.rawQuery(
      'SELECT COUNT(*) as count FROM read WHERE threat_score >= 0.30 AND threat_score < 0.50',
    );

    // SUSPICIOUS: 0.50 <= threat_score < 0.70
    final suspiciousUnread = await db.rawQuery(
      'SELECT COUNT(*) as count FROM unread WHERE threat_score >= 0.50 AND threat_score < 0.70',
    );
    final suspiciousRead = await db.rawQuery(
      'SELECT COUNT(*) as count FROM read WHERE threat_score >= 0.50 AND threat_score < 0.70',
    );

    // SCAM: threat_score >= 0.70
    final scamUnread = await db.rawQuery(
      'SELECT COUNT(*) as count FROM unread WHERE threat_score >= 0.70',
    );
    final scamRead = await db.rawQuery(
      'SELECT COUNT(*) as count FROM read WHERE threat_score >= 0.70',
    );

    return {
      'total': smsCount.first['count'] as int,
      'unread': unreadCount.first['count'] as int,
      'read': readCount.first['count'] as int,
      'sent': sentCount.first['count'] as int,
      'unchecked':
          (uncheckedUnread.first['count'] as int) +
          (uncheckedRead.first['count'] as int),
      'safe':
          (safeUnread.first['count'] as int) + (safeRead.first['count'] as int),
      'uncertain':
          (uncertainUnread.first['count'] as int) +
          (uncertainRead.first['count'] as int),
      'suspicious':
          (suspiciousUnread.first['count'] as int) +
          (suspiciousRead.first['count'] as int),
      'scam':
          (scamUnread.first['count'] as int) + (scamRead.first['count'] as int),
    };
  }

  /// Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  /// Delete database and reset
  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'silverguard.db');
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }
}
