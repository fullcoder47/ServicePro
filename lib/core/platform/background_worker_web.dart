// Dart web does not support dart:isolate. Yield before encoding large exports.
Future<T> runBackground<T>(T Function() encode) async {
  await Future<void>.delayed(Duration.zero);
  return encode();
}
