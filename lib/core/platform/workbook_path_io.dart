import 'dart:io';
import 'dart:typed_data';

Future<String?> writeWorkbook(String filename, Uint8List bytes) async {
  final file = File('${Directory.systemTemp.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
