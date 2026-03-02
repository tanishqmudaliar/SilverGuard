import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// List of all required permissions for the app
  static final List<Permission> requiredPermissions = [
    Permission.sms,
    Permission.phone,
    Permission.contacts,
    Permission.notification,
  ];

  /// Check if all required permissions are granted
  static Future<bool> areAllPermissionsGranted() async {
    for (final permission in requiredPermissions) {
      if (!await permission.isGranted) {
        return false;
      }
    }
    return true;
  }

  /// Get status of each permission
  static Future<Map<Permission, PermissionStatus>>
  getPermissionStatuses() async {
    final Map<Permission, PermissionStatus> statuses = {};
    for (final permission in requiredPermissions) {
      statuses[permission] = await permission.status;
    }
    return statuses;
  }

  /// Request all required permissions
  static Future<bool> requestAllPermissions() async {
    final statuses = await requiredPermissions.request();

    // Check if all permissions are granted
    for (final status in statuses.values) {
      if (!status.isGranted) {
        return false;
      }
    }
    return true;
  }

  /// Check if any permission is permanently denied
  static Future<bool> isAnyPermissionPermanentlyDenied() async {
    for (final permission in requiredPermissions) {
      if (await permission.isPermanentlyDenied) {
        return true;
      }
    }
    return false;
  }

  /// Open app settings (for when permissions are permanently denied)
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
