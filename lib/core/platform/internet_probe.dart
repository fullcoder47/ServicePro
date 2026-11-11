// The DNS lookup API exists on native Dart runtimes, not inside web browsers.
export 'internet_probe_web.dart'
    if (dart.library.io) 'internet_probe_io.dart';
