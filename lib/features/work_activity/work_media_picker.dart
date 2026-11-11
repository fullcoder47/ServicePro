import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models.dart';
import '../tickets/picked_video_preview.dart';

class WorkMediaPicker extends StatelessWidget {
  const WorkMediaPicker({
    super.key, required this.files, required this.onChanged,
    this.requiredMedia = false,
  });

  final List<PickedAttachment> files;
  final ValueChanged<List<PickedAttachment>> onChanged;
  final bool requiredMedia;

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _gallery(BuildContext context) async {
    try {
      final selected = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif',
          'mp4', 'mov', 'webm'],
        // file_picker v13 returns List<PlatformFile> directly. Local videos
        // keep their file path so they are not loaded into memory here.
      );
      if (selected.isEmpty) return;
      final result = List<PickedAttachment>.of(files);
      for (final item in selected) {
        final extension = item.extension?.toLowerCase() ?? '';
        final video = ['mp4', 'mov', 'webm'].contains(extension);
        final path = kIsWeb ? null : item.path;
        final byteLength = item.lengthSync() ?? await item.length();
        if (byteLength == null) throw FormatException('${item.name}: fayl hajmini aniqlab bo‘lmadi.');
        final sizeMb = byteLength / (1024 * 1024);
        if (sizeMb > (video ? 80 : 10)) {
          throw FormatException('${item.name}: ${video ? 80 : 10} MB limitdan oshgan.');
        }
        if (result.length >= 8) {
          throw const FormatException('Bir hisobotga ko‘pi bilan 8 ta fayl.');
        }
        final bytes = video && path != null
            ? Uint8List(0)
            : await item.readAsBytes();
        if (bytes.isEmpty && (!video || path == null)) {
          throw FormatException('${item.name}: faylni o‘qib bo‘lmadi.');
        }
        result.add(PickedAttachment(name: item.name, bytes: bytes,
          isVideo: video, localPath: path, byteLength: byteLength));
        if (result.fold<double>(0, (sum, file) => sum + file.sizeInMb) > 120) {
          throw const FormatException('Jami media hajmi 120 MB dan oshmasin.');
        }
      }
      if (context.mounted) onChanged(result);
    } catch (e) {
      if (context.mounted) _message(context, 'Media tanlashda xato: $e');
    }
  }

  Future<void> _camera(BuildContext context) async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 85, maxWidth: 1920);
      if (file == null) return;
      if (files.length >= 8) {
        throw const FormatException('Ko‘pi bilan 8 ta fayl.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Rasm maksimal 10 MB.');
      }
      if (bytes.length / (1024 * 1024) +
          files.fold<double>(0, (sum, file) => sum + file.sizeInMb) > 120) {
        throw const FormatException('Jami media hajmi 120 MB dan oshmasin.');
      }
      if (context.mounted) {
        onChanged([...files,
          PickedAttachment(name: 'ish_${DateTime.now().millisecondsSinceEpoch}.jpg',
            bytes: bytes, isVideo: false)]);
      }
    } catch (e) {
      if (context.mounted) _message(context, 'Kamera ochilmadi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.add_photo_alternate_outlined, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(requiredMedia
          ? 'Foto yoki video dalil • majburiy'
          : 'Foto yoki video • ixtiyoriy',
          style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w800))),
        Text('${files.length}/8', style: TextStyle(color: colors.onSurfaceVariant)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: files.length >= 8 ? null : () => _gallery(context),
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('Rasm / video tanlash')),
        OutlinedButton.icon(onPressed: files.length >= 8 ? null : () => _camera(context),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Suratga olish')),
      ]),
      const SizedBox(height: 5),
      Text('Rasm 10 MB, video 80 MB gacha. JPG, PNG, GIF, WEBP, MP4, MOV, WEBM.',
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
      if (files.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (var i = 0; i < files.length; i++)
          Card(margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              onTap: files[i].isVideo && files[i].localPath != null
                ? () => showDialog<void>(context: context,
                    builder: (_) => Dialog(child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: PickedVideoPreview(path: files[i].localPath!))))
                : null,
              leading: SizedBox(width: 48, height: 48, child: files[i].isVideo
                ? const Icon(Icons.video_file_rounded, size: 32)
                : ClipRRect(borderRadius: BorderRadius.circular(8),
                    child: files[i].bytes.isNotEmpty
                      ? Image.memory(files[i].bytes, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                        const Icon(Icons.image_outlined))
                      : const Icon(Icons.image_outlined))),
              title: Text(files[i].name, maxLines: 1,
                overflow: TextOverflow.ellipsis),
              subtitle: Text('${files[i].sizeInMb.toStringAsFixed(1)} MB'),
              trailing: IconButton(
                tooltip: 'Olib tashlash',
                onPressed: () => onChanged(List.of(files)..removeAt(i)),
                icon: const Icon(Icons.close_rounded)),
            )),
      ],
    ]);
  }
}
