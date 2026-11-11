import 'dart:isolate';

Future<T> runBackground<T>(T Function() encode) => Isolate.run(encode);
