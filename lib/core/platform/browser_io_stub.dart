// Only compiled by the browser target. Native builds use dart:io directly.
// Browser pickers provide bytes, so filesystem paths must never be accessed.
import 'dart:typed_data';

class File {
  File(this.path);
  final String path;

  Future<bool> exists() async => false;
  Future<Uint8List> readAsBytes() async =>
      throw UnsupportedError('Brauzer fayl yo‘lini o‘qiy olmaydi.');
  Future<File> writeAsString(String contents) async =>
      throw UnsupportedError('Brauzer fayl tizimiga yoza olmaydi.');
}

class Directory {
  const Directory(this.path);
  final String path;
  static const systemTemp = Directory('');
}
