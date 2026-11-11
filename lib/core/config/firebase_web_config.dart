import 'package:firebase_core/firebase_core.dart';

import 'firebase_web_globals_stub.dart'
    if (dart.library.js_interop) 'firebase_web_globals_browser.dart' as browser;

/// The same public config is shared by Flutter and firebase-messaging-sw.js.
/// Never put a Firebase service-account private key in the web directory.
class FirebaseWebConfig {
  FirebaseWebConfig._();

  static Map<String, String>? get _config => browser.readFirebaseWebConfig();

  static String? get vapidKey {
    final value = browser.readWebPushVapidKey()?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static FirebaseOptions? get options {
    final data = _config;
    if (data == null) return null;
    for (final key in const ['apiKey', 'appId', 'projectId', 'messagingSenderId']) {
      if ((data[key] ?? '').trim().isEmpty) return null;
    }
    return FirebaseOptions(
      apiKey: data['apiKey']!,
      appId: data['appId']!,
      messagingSenderId: data['messagingSenderId']!,
      projectId: data['projectId']!,
      authDomain: data['authDomain'],
      databaseURL: data['databaseURL'],
      storageBucket: data['storageBucket'],
      measurementId: data['measurementId'],
    );
  }

  static bool get canRegisterPush => options != null && vapidKey != null;
}
