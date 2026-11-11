import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('serviceProFirebaseConfig')
external JSObject? get _webConfig;

@JS('serviceProVapidKey')
external JSString? get _publicVapidKey;

String _value(JSObject source, String name) =>
    source.getProperty<JSString?>(name.toJS)?.toDart ?? '';

Map<String, String>? readFirebaseWebConfig() {
  final config = _webConfig;
  if (config == null) return null;
  return {
    for (final field in const [
      'apiKey', 'authDomain', 'databaseURL', 'projectId', 'storageBucket',
      'messagingSenderId', 'appId', 'measurementId',
    ]) field: _value(config, field),
  };
}

String? readWebPushVapidKey() => _publicVapidKey?.toDart;
