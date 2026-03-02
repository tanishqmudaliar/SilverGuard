import 'package:flutter/foundation.dart';
import 'package:another_telephony/telephony.dart';

/// Service for sending SMS messages silently in the background
class SmsSenderService {
  static final SmsSenderService instance = SmsSenderService._init();

  final Telephony _telephony = Telephony.instance;

  SmsSenderService._init();

  /// Send an SMS silently (without opening the default SMS app)
  /// [number] - recipient phone number
  /// [body] - message body text
  /// Returns true if sent successfully, false otherwise
  Future<bool> sendSms({required String number, required String body}) async {
    if (number.trim().isEmpty || body.trim().isEmpty) {
      debugPrint('SmsSender: Cannot send - number or body is empty');
      return false;
    }

    try {
      await _telephony.sendSms(
        to: number,
        message: body,
        isMultipart: body.length > 160,
      );
      debugPrint('SmsSender: SMS sent to $number');
      return true;
    } catch (e) {
      debugPrint('SmsSender: Failed to send SMS to $number: $e');
      return false;
    }
  }
}
