import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> uploadStorageFileFromPath(
  SupabaseClient client, String bucket, String target, String localPath,
  FileOptions options,
) async {
  final file = File(localPath);
  if (!await file.exists()) throw StateError('local_media_unavailable');
  await client.storage.from(bucket).upload(target, file, fileOptions: options);
}
