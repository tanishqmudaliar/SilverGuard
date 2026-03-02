import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// Service for managing contacts and phone number lookups
class ContactsService {
  static final ContactsService instance = ContactsService._init();

  /// Map of normalized phone numbers to contact names
  /// Each contact may have multiple phone numbers, all mapped to same name
  final Map<String, String> _phoneToName = {};

  bool _isLoaded = false;
  int _contactsCount = 0;

  ContactsService._init();

  bool get isLoaded => _isLoaded;
  int get contactsCount => _contactsCount;

  /// Load all contacts into memory for fast lookup
  Future<void> loadContacts() async {
    if (_isLoaded) return;

    try {
      // Check permission first
      if (!await FlutterContacts.requestPermission(readonly: true)) {
        debugPrint('ContactsService: Permission denied');
        return;
      }

      // Fetch contacts with phone numbers
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      _phoneToName.clear();
      _contactsCount = 0;

      for (final contact in contacts) {
        final name = contact.displayName;
        if (name.isEmpty) continue;

        _contactsCount++;

        // Map all phone numbers for this contact
        for (final phone in contact.phones) {
          final number = phone.number;
          if (number.isEmpty) continue;

          // Store multiple normalized versions for flexible matching
          final variants = _generatePhoneVariants(number);
          for (final variant in variants) {
            if (variant.length >= 7) {
              // Avoid short numbers causing false matches
              _phoneToName[variant] = name;
            }
          }
        }
      }

      _isLoaded = true;
      debugPrint(
        'ContactsService: Loaded $_contactsCount contacts, ${_phoneToName.length} phone mappings',
      );
    } catch (e) {
      debugPrint('ContactsService: Error loading contacts: $e');
    }
  }

  /// Generate multiple normalized versions of a phone number for flexible matching
  /// This handles ISD codes, leading zeros, etc.
  List<String> _generatePhoneVariants(String phone) {
    // Remove all non-digit characters except leading +
    // Also strip Unicode whitespace and zero-width characters
    phone = phone.replaceAll(RegExp(r'[\s\u00A0\u200B-\u200D\uFEFF]'), '');
    final hasPlus = phone.startsWith('+');
    final digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.isEmpty) return [];

    final variants = <String>{};

    // Full number with + (if originally had it)
    if (hasPlus) {
      variants.add('+$digitsOnly');
    }

    // Full digits
    variants.add(digitsOnly);

    // Without leading zeros
    final withoutLeadingZeros = digitsOnly.replaceFirst(RegExp(r'^0+'), '');
    if (withoutLeadingZeros.isNotEmpty) {
      variants.add(withoutLeadingZeros);
    }

    // Last 10 digits (common for India, US, etc.)
    if (digitsOnly.length >= 10) {
      variants.add(digitsOnly.substring(digitsOnly.length - 10));
    }

    // Last 11 digits (for countries with 11-digit numbers)
    if (digitsOnly.length >= 11) {
      variants.add(digitsOnly.substring(digitsOnly.length - 11));
    }

    // Without country code for common codes
    // India (+91), US (+1), UK (+44), etc.
    if (digitsOnly.startsWith('91') && digitsOnly.length > 10) {
      variants.add(digitsOnly.substring(2)); // Remove 91
    }
    if (digitsOnly.startsWith('1') && digitsOnly.length == 11) {
      variants.add(digitsOnly.substring(1)); // Remove 1
    }
    if (digitsOnly.startsWith('44') && digitsOnly.length > 10) {
      variants.add(digitsOnly.substring(2)); // Remove 44
    }

    return variants.toList();
  }

  /// Normalize a phone number for lookup
  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^\d]'), '');
  }

  /// Get contact name for a phone number
  /// Returns null if no match found
  String? getContactName(String phoneNumber) {
    if (!_isLoaded || phoneNumber.isEmpty) return null;

    // Try alphanumeric sender IDs (like "HDFCBK", "Amazon")
    // These won't be in contacts, return null early
    if (!phoneNumber.contains(RegExp(r'\d'))) {
      return null;
    }

    // Generate variants of the incoming number and try to match
    final variants = _generatePhoneVariants(phoneNumber);

    for (final variant in variants) {
      final name = _phoneToName[variant];
      if (name != null) {
        return name;
      }
    }

    // Fallback: try suffix matching (last 7-10 digits)
    final normalized = _normalizePhone(phoneNumber);
    if (normalized.length >= 7) {
      for (int len = normalized.length; len >= 7; len--) {
        final suffix = normalized.substring(normalized.length - len);
        final name = _phoneToName[suffix];
        if (name != null) {
          return name;
        }
      }
    }

    return null;
  }

  /// Reload contacts (call when user wants to refresh)
  Future<void> reloadContacts() async {
    _isLoaded = false;
    _phoneToName.clear();
    _contactsCount = 0;
    await loadContacts();
  }

  /// Clear contacts from memory
  void clear() {
    _phoneToName.clear();
    _isLoaded = false;
    _contactsCount = 0;
  }
}
