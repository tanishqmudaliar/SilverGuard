/// Main SMS model for storing raw SMS from device
/// This is the source table - no ML processing, just storage
class SmsMessage {
  final int? id;
  final String address;
  final String body;
  final int date;
  final int type; // 1 = received, 2 = sent
  final int read; // 0 = unread, 1 = read
  final String? serviceCenter;
  final int createdAt;

  SmsMessage({
    this.id,
    required this.address,
    required this.body,
    required this.date,
    required this.type,
    required this.read,
    this.serviceCenter,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'address': address,
      'body': body,
      'date': date,
      'type': type,
      'read': read,
      'service_center': serviceCenter,
      'created_at': createdAt,
    };
  }

  factory SmsMessage.fromMap(Map<String, dynamic> map) {
    return SmsMessage(
      id: map['id'] as int?,
      address: map['address'] as String,
      body: map['body'] as String,
      date: map['date'] as int,
      type: map['type'] as int,
      read: map['read'] as int,
      serviceCenter: map['service_center'] as String?,
      createdAt: map['created_at'] as int,
    );
  }
}

/// Unread SMS model - received messages that haven't been read
/// Has threat_score field for ML classification
class UnreadSms {
  final int? id;
  final String address;
  final String? contactName; // Contact name if found, null otherwise
  final String body;
  final int date;
  final String? serviceCenter;
  final int createdAt;
  final int updatedAt;
  final double? threatScore; // null = not classified, 0.0-1.0 = threat level

  UnreadSms({
    this.id,
    required this.address,
    this.contactName,
    required this.body,
    required this.date,
    this.serviceCenter,
    required this.createdAt,
    required this.updatedAt,
    this.threatScore,
  });

  /// Display name: contact name if available, otherwise address
  String get displayName => contactName ?? address;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'address': address,
      'contact_name': contactName,
      'body': body,
      'date': date,
      'service_center': serviceCenter,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'threat_score': threatScore,
    };
  }

  factory UnreadSms.fromMap(Map<String, dynamic> map) {
    return UnreadSms(
      id: map['id'] as int?,
      address: map['address'] as String,
      contactName: map['contact_name'] as String?,
      body: map['body'] as String,
      date: map['date'] as int,
      serviceCenter: map['service_center'] as String?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
      threatScore: map['threat_score'] as double?,
    );
  }
}

/// Read SMS model - received messages that have been read
/// Has threat_score field for ML classification
class ReadSms {
  final int? id;
  final String address;
  final String? contactName; // Contact name if found, null otherwise
  final String body;
  final int date;
  final String? serviceCenter;
  final int createdAt;
  final int updatedAt;
  final double? threatScore; // null = not classified, 0.0-1.0 = threat level

  ReadSms({
    this.id,
    required this.address,
    this.contactName,
    required this.body,
    required this.date,
    this.serviceCenter,
    required this.createdAt,
    required this.updatedAt,
    this.threatScore,
  });

  /// Display name: contact name if available, otherwise address
  String get displayName => contactName ?? address;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'address': address,
      'contact_name': contactName,
      'body': body,
      'date': date,
      'service_center': serviceCenter,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'threat_score': threatScore,
    };
  }

  factory ReadSms.fromMap(Map<String, dynamic> map) {
    return ReadSms(
      id: map['id'] as int?,
      address: map['address'] as String,
      contactName: map['contact_name'] as String?,
      body: map['body'] as String,
      date: map['date'] as int,
      serviceCenter: map['service_center'] as String?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
      threatScore: map['threat_score'] as double?,
    );
  }
}

/// Sent SMS model - messages sent by user
/// No is_scam field - we don't run ML on sent messages
class SentSms {
  final int? id;
  final String address;
  final String? contactName; // Contact name if found, null otherwise
  final String body;
  final int date;
  final String? serviceCenter;
  final int createdAt;
  final int updatedAt;

  SentSms({
    this.id,
    required this.address,
    this.contactName,
    required this.body,
    required this.date,
    this.serviceCenter,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Display name: contact name if available, otherwise address
  String get displayName => contactName ?? address;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'address': address,
      'contact_name': contactName,
      'body': body,
      'date': date,
      'service_center': serviceCenter,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory SentSms.fromMap(Map<String, dynamic> map) {
    return SentSms(
      id: map['id'] as int?,
      address: map['address'] as String,
      contactName: map['contact_name'] as String?,
      body: map['body'] as String,
      date: map['date'] as int,
      serviceCenter: map['service_center'] as String?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }
}
