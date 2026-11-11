import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';

import '../platform/background_worker.dart';
import '../platform/workbook_path.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../features/work_activity/work_activity_repository.dart';

/// Genuine XLSX export with offline-embedded pictures and a separate media list.
/// Videos are referenced by filename/URL (Excel does not play video clips).
class ServiceProExcelExport {
  ServiceProExcelExport._();
  static const _pageSize = 200;

  static Future<XFile> tickets(AppState state) async {
    final tickets = <Ticket>[];
    for (var offset = 0;; offset += _pageSize) {
      var query = state.client.from('tickets').select();
      final me = state.currentProfile;
      if (me?.role != UserRole.superAdmin && me?.companyId != null) {
        query = query.eq('company_id', me!.companyId!);
      }
      final rows = await query.order('created_at', ascending: false)
          .range(offset, offset + _pageSize - 1);
      tickets.addAll((rows as List).map((row) =>
        Ticket.fromMap(Map<String, dynamic>.from(row))));
      if (rows.length < _pageSize) break;
    }
    if (tickets.isEmpty) throw StateError('Eksport uchun ariza mavjud emas.');
    final data = _ExcelData();
    data.sheets['Arizalar'] = [[
      'Ariza raqami', 'Tashkilot', 'Holat', 'Manzil', 'Xonadon',
      'Muammo', 'Yuborgan', 'Telefon', 'Qabul qilgan', 'Bajargan',
      'Natija', 'Yaratilgan vaqt', 'Biriktirmalar soni',
    ]];
    for (final ticket in tickets) {
      final creator = state.profileById(ticket.createdBy);
      data.sheets['Arizalar']!.add([
        ticket.number,
        state.companyById(ticket.companyId)?.name ?? ticket.companyId,
        ticket.status.label,
        ticket.addressLabel(state.buildingById(ticket.buildingId)),
        ticket.apartmentNumber, ticket.description,
        creator?.fullName ?? '${ticket.requesterSnapshot['first_name'] ?? ''} '
          '${ticket.requesterSnapshot['last_name'] ?? ''}'.trim(),
        creator?.phone ?? '${ticket.requesterSnapshot['phone'] ?? ''}',
        ticket.acceptedBy == null ? '' :
          (state.profileById(ticket.acceptedBy!)?.fullName ?? ''),
        ticket.completedBy == null ? '' :
          (state.profileById(ticket.completedBy!)?.fullName ?? ''),
        ticket.completionDescription ?? '', ticket.createdAt.toIso8601String(),
        '${ticket.attachments.length + ticket.completionAttachments.length}',
      ]);
      for (final source in ticket.attachments) {
        data.media.add(await _ticketMedia(state, ticket.number, 'Ariza', source));
      }
      for (final source in ticket.completionAttachments) {
        data.media.add(await _ticketMedia(state, ticket.number, 'Bajarilgan ish', source));
      }
    }
    return _save(data, 'servicepro_arizalar');
  }

  static Future<XFile> work(AppState state, {String? companyFilter}) async {
    final repo = WorkActivityRepository(state);
    final data = _ExcelData();
    const columns = ['Tashkilot', 'Ishchi', 'Ish turi', 'Holat', 'Nomi',
      'Tavsif', 'Manzil', 'Bajarilgan ish', 'Rahbar izohi', 'Yaratilgan vaqt',
      'Bajarilgan sana', 'Rasm/video soni', 'Arxivlangan', 'ID'];
    data.sheets['Vazifalar'] = [columns];
    data.sheets['Hisobotlar'] = [columns];
    data.sheets['Arxiv'] = [columns];
    for (final archived in [false, true]) {
      if (archived && state.currentProfile?.role != UserRole.superAdmin) continue;
      for (var offset = 0;; offset += _pageSize) {
        final items = await repo.fetchItems(offset: offset, limit: _pageSize,
          companyFilter: companyFilter, archived: archived);
        for (final item in items) {
          final worker = item.workerId == null ? null : state.profileById(item.workerId!);
          final row = [
            state.companyById(item.companyId)?.name ?? item.companyId,
            worker?.fullName ?? item.workerId ?? '',
            item.isTask ? 'Vazifa' : 'Kunlik hisobot', item.status,
            item.title, item.description, item.location, item.reportText,
            item.reviewNote, item.createdAt.toIso8601String(),
            item.workDate?.toIso8601String() ?? '',
            '${item.instructionPaths.length + item.evidencePaths.length}',
            archived ? 'Ha' : 'Yo‘q', item.id,
          ];
          if (archived) {
            data.sheets['Arxiv']!.add(row);
          } else {
            if (item.isTask) data.sheets['Vazifalar']!.add(row);
            if (!item.isTask || item.evidencePaths.isNotEmpty) {
              data.sheets['Hisobotlar']!.add(row);
            }
          }
          for (final path in item.instructionPaths) {
            data.media.add(await _workMedia(state, item.id, 'Vazifa rasmi', path));
          }
          for (final path in item.evidencePaths) {
            data.media.add(await _workMedia(state, item.id, 'Natija rasmi/video', path));
          }
        }
        if (items.length < _pageSize) break;
      }
    }
    if (data.sheets.values.every((sheet) => sheet.length == 1)) {
      throw StateError('Eksport uchun vazifa yoki hisobot yo‘q.');
    }
    return _save(data, 'servicepro_vazifalar_hisobotlar');
  }

  static Future<_MediaEntry> _ticketMedia(AppState state, String number,
      String section, String source) async {
    const marker = '/storage/v1/object/public/ticket-files/';
    final url = Uri.tryParse(source);
    final expected = state.client.storage.from('ticket-files')
        .getPublicUrl('__servicepro_check__')
        .split('__servicepro_check__').first;
    if (url == null || !source.startsWith(expected) || !url.path.contains(marker)) {
      return _MediaEntry(section, number, source, 'Tashqi havola');
    }
    final path = Uri.decodeFull(url.path.substring(url.path.indexOf(marker) + marker.length));
    return _loadImage(section, number, source, path,
      () => state.client.storage.from('ticket-files').download(path));
  }

  static Future<_MediaEntry> _workMedia(AppState state, String id,
      String section, String path) => _loadImage(section, id, path, path,
    () => state.client.storage.from('work-evidence').download(path));

  static Future<_MediaEntry> _loadImage(String section, String id,
      String source, String path, Future<Uint8List> Function() download) async {
    final name = path.toLowerCase().split('?').first;
    final format = name.endsWith('.jpg') || name.endsWith('.jpeg')
        ? ExcelImageType.jpeg : name.endsWith('.png') ? ExcelImageType.png
        : name.endsWith('.webp') ? ExcelImageType.webp
        : name.endsWith('.gif') ? ExcelImageType.gif : null;
    if (format == null) return _MediaEntry(section, id, source,
      name.endsWith('.mp4') || name.endsWith('.mov') || name.endsWith('.webm')
        ? 'Video (ilovada ochiladi)' : 'Fayl (ilovada ochiladi)');
    try {
      final bytes = await download().timeout(const Duration(seconds: 25));
      return _MediaEntry(section, id, source, 'Rasm',
        bytes: bytes, imageType: format);
    } catch (_) {
      return _MediaEntry(section, id, source, 'Rasmni yuklab bo‘lmadi');
    }
  }

  static Future<XFile> _save(_ExcelData data, String name) async {
    // Native: background isolate. Browser: the main isolate is the only option.
    final bytes = Uint8List.fromList(await runBackground(() => _encode(data)));
    final filename = '${name}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    const mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (kIsWeb) {
      return XFile.fromData(bytes, name: filename, mimeType: mime);
    }
    final path = await writeWorkbook(filename, bytes);
    if (path == null) throw StateError('Excel fayl saqlanmadi.');
    return XFile(path, mimeType: mime);
  }

  static List<int> _encode(_ExcelData data) {
    final book = Excel.createExcel();
    for (final entry in data.sheets.entries) {
      final sheet = book[entry.key];
      sheet.frozenRows = 1;
      for (final row in entry.value) {
        sheet.appendRow(row.map((value) => TextCellValue(value)).toList());
      }
      for (var col = 0; col < entry.value.first.length; col++) {
        sheet.setColumnWidth(col, col == 5 || col == 6 || col == 7 ? 43 : 23);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
          .cellStyle = CellStyle(bold: true);
      }
    }
    final media = book['Rasmlar'];
    media.frozenRows = 1;
    media.appendRow(['Bo‘lim', 'Ariza / ish ID', 'Manba / fayl',
      'Fayl turi', 'Rasm'].map(TextCellValue.new).toList());
    for (var col = 0; col < 5; col++) {
      media.setColumnWidth(col, col == 2 ? 65 : col == 4 ? 30 : 24);
      media.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
        .cellStyle = CellStyle(bold: true);
    }
    for (final entry in data.media) {
      final rowIndex = media.maxRows;
      media.appendRow([entry.section, entry.id, entry.source, entry.type, '']
        .map(TextCellValue.new).toList());
      if (entry.bytes != null && entry.imageType != null) {
        media.setRowHeight(rowIndex, 74);
        media.addImage(ExcelImage(imageBytes: entry.bytes!,
          imageType: entry.imageType!,
          anchor: ImageAnchor.fromPixels(column: 4, row: rowIndex,
            widthPixels: 170, heightPixels: 92)));
      }
    }
    book.delete('Sheet1');
    return book.encode() ?? (throw StateError('Excel faylni yaratib bo‘lmadi.'));
  }
}

class _ExcelData {
  final Map<String, List<List<String>>> sheets = {};
  final List<_MediaEntry> media = [];
}

class _MediaEntry {
  const _MediaEntry(this.section, this.id, this.source, this.type,
    {this.bytes, this.imageType});
  final String section, id, source, type;
  final Uint8List? bytes;
  final ExcelImageType? imageType;
}
