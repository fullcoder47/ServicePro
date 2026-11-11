import 'dart:io';

/// Preserve the original connectivity check on Android, Windows and macOS.
Future<bool> probeInternet() async {
  try {
    final addresses = await InternetAddress.lookup('one.one.one.one')
        .timeout(const Duration(seconds: 2));
    return addresses.isNotEmpty && addresses.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
