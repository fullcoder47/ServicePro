import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Public session details are obtained from a server-side RPC that only returns
/// sessions belonging to auth.uid(). No auth schema tables are exposed to Flutter.
class ServiceProDeviceSession {
  const ServiceProDeviceSession({
    required this.id,
    required this.label,
    required this.platform,
    required this.appVersion,
    required this.loginAt,
    required this.lastSeenAt,
    required this.ipAddress,
    required this.userAgent,
    required this.assuranceLevel,
    required this.isCurrent,
    required this.isOnline,
  });

  final String id;
  final String label;
  final String platform;
  final String appVersion;
  final DateTime loginAt;
  final DateTime lastSeenAt;
  final String ipAddress;
  final String userAgent;
  final String assuranceLevel;
  final bool isCurrent;
  final bool isOnline;

  factory ServiceProDeviceSession.fromMap(Map<String, dynamic> row) {
    DateTime parsedDate(String key) =>
        DateTime.tryParse('${row[key] ?? ''}')?.toLocal() ?? DateTime.now();

    return ServiceProDeviceSession(
      id: '${row['session_id'] ?? ''}',
      label: '${row['device_label'] ?? 'Nomaʼlum qurilma'}',
      platform: '${row['platform'] ?? 'unknown'}',
      appVersion: '${row['app_version'] ?? ''}',
      loginAt: parsedDate('login_at'),
      lastSeenAt: parsedDate('last_seen_at'),
      ipAddress: '${row['ip_address'] ?? ''}',
      userAgent: '${row['user_agent'] ?? ''}',
      assuranceLevel: '${row['aal'] ?? 'aal1'}',
      isCurrent: row['is_current'] == true,
      isOnline: row['is_online'] == true,
    );
  }
}

class SessionDevicesRepository {
  const SessionDevicesRepository(this.client);

  final SupabaseClient client;

  static const _installationKey = 'servicepro_device_installation_v1';
  static const _localLabelKey = 'servicepro_device_label_v1';

  static String get platform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'unknown';
    }
  }

  static String get defaultLabel {
    switch (platform) {
      case 'android':
        return 'Android telefon';
      case 'ios':
        return 'iPhone yoki iPad';
      case 'windows':
        return 'Windows noutbuk yoki kompyuter';
      case 'macos':
        return 'Mac kompyuter';
      case 'linux':
        return 'Linux kompyuter';
      case 'web':
        return 'Brauzer / PWA';
      default:
        return 'ServicePro qurilmasi';
    }
  }

  /// This ID is only for recognizable device display, never for authorization.
  static Future<String> _installationId(SharedPreferences prefs) async {
    var value = prefs.getString(_installationKey);
    if (value != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) return value;
    final random = Random.secure();
    value = List<int>.generate(16, (_) => random.nextInt(256))
        .map((n) => n.toRadixString(16).padLeft(2, '0'))
        .join();
    await prefs.setString(_installationKey, value);
    return value;
  }

  /// Background-friendly; never blocks login if a new SQL migration is pending.
  Future<void> touchCurrent() async {
    if (client.auth.currentUser == null || client.auth.currentSession == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final installationId = await _installationId(prefs);
      final localLabel = prefs.getString(_localLabelKey) ?? defaultLabel;
      var version = '';
      try {
        final info = await PackageInfo.fromPlatform();
        version = '${info.version}+${info.buildNumber}';
      } catch (_) {
        // Version is informational only; not a reason to deny sign-in.
      }
      await client.rpc('servicepro_session_touch', params: {
        'p_installation_id': installationId,
        'p_platform': platform,
        'p_device_label': localLabel,
        'p_app_version': version,
      });
    } catch (_) {
      // Existing users stay signed in until the migration is deployed.
    }
  }

  Future<List<ServiceProDeviceSession>> listSessions() async {
    final rows = await client.rpc('servicepro_my_sessions');
    if (rows is! List) return const [];
    return rows.map((value) => ServiceProDeviceSession.fromMap(
      Map<String, dynamic>.from(value as Map),
    )).toList(growable: false);
  }

  Future<void> renameThisDevice(String newLabel) async {
    final label = newLabel.trim();
    if (label.length < 2 || label.length > 64) {
      throw ArgumentError('Qurilma nomi 2–64 belgi bo‘lishi kerak.');
    }
    await touchCurrent();
    final changed = await client.rpc('servicepro_session_rename', params: {
      'p_device_label': label,
    });
    if (changed != true) throw StateError('Qurilma nomi yangilanmadi.');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localLabelKey, label);
  }

  Future<void> revokeOne(String sessionId) async {
    final revoked = await client.rpc('servicepro_revoke_my_session', params: {
      'p_session_id': sessionId,
    });
    if (revoked != true) throw StateError('Sessiya topilmadi yoki allaqachon yopilgan.');
  }

  Future<void> revokeOtherDevices() async {
    await client.auth.signOut(scope: SignOutScope.others);
  }
}
