import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/platform/upload_from_path.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

class WorkItem {
  WorkItem(Map<String, dynamic> row)
      : id = '${row['id']}', companyId = '${row['company_id']}',
        workerId = row['worker_id'] as String?, kind = '${row['kind']}',
        category = '${row['category']}', title = '${row['title']}',
        description = '${row['description']}',
        location = '${row['location_text'] ?? ''}',
        priority = '${row['priority']}', status = '${row['status']}',
        reportText = '${row['report_text'] ?? ''}',
        reviewNote = '${row['review_note'] ?? ''}',
        dueOn = DateTime.tryParse('${row['due_on'] ?? ''}'),
        workDate = DateTime.tryParse('${row['work_date'] ?? ''}'),
        createdAt = DateTime.tryParse('${row['created_at']}') ?? DateTime(2000),
        archivedAt = DateTime.tryParse('${row['archived_at'] ?? ''}'),
        instructionPaths = _strings(row['instruction_media']),
        evidencePaths = _strings(row['evidence_media']);

  final String id, companyId, kind, category, title, description;
  final String? workerId;
  final String location, priority, status, reportText, reviewNote;
  final DateTime? dueOn, workDate;
  final DateTime createdAt;
  final DateTime? archivedAt;
  final List<String> instructionPaths, evidencePaths;
  bool get isTask => kind == 'assignment';
  bool get pendingReview => status == 'submitted';
  bool get canStart => isTask && (status == 'assigned' || status == 'rework');
  bool get canSubmit => isTask &&
    (status == 'assigned' || status == 'in_progress' || status == 'rework');
  static List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => '$e').toList() : [];
}

class WorkItemEvent {
  WorkItemEvent(Map<String, dynamic> row)
      : action = '${row['action']}', note = '${row['note'] ?? ''}',
        actorId = row['actor_id'] as String?,
        createdAt = DateTime.tryParse('${row['created_at']}') ?? DateTime(2000),
        mediaPaths = WorkItem._strings(row['media_paths']);
  final String action, note;
  final String? actorId;
  final DateTime createdAt;
  final List<String> mediaPaths;
}

class WorkActivityRepository {
  WorkActivityRepository(this.appState);
  final AppState appState;
  SupabaseClient get db => appState.client;
  String get companyId => appState.currentProfile?.companyId ??
    (throw StateError('Tashkilot topilmadi.'));
  String get profileId => appState.currentProfile?.id ??
    (throw StateError('Avval tizimga kiring.'));

  Future<List<WorkItem>> fetchItems({int offset = 0, int limit = 100,
    String? companyFilter, bool archived = false}) async {
    final isSuperAdmin = appState.currentProfile?.role == UserRole.superAdmin;
    var query = db.from('work_items').select();
    if (!isSuperAdmin) {
      query = query.eq('company_id', companyId);
    } else if (companyFilter != null) {
      query = query.eq('company_id', companyFilter);
    }
    query = archived ? query.not('archived_at', 'is', null)
        : query.isFilter('archived_at', null);
    if (appState.currentProfile?.role == UserRole.worker) {
      query = query.eq('worker_id', profileId);
    }
    final rows = await query.order('created_at', ascending: false)
      .range(offset, offset + limit - 1);
    return (rows as List).map((e) =>
      WorkItem(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<WorkItemEvent>> fetchEvents(String itemId) async {
    final rows = await db.from('work_item_events').select()
      .eq('item_id', itemId).order('created_at', ascending: false).limit(100);
    return (rows as List).map((e) =>
      WorkItemEvent(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<String>> uploadMedia(List<PickedAttachment> files,
      {String? forCompanyId}) async {
    if (files.length > 8) throw const FormatException('Ko‘pi bilan 8 ta media yuklang.');
    if (files.fold<double>(0, (sum, file) => sum + file.sizeInMb) > 120) {
      throw const FormatException('Jami media hajmi 120 MB dan oshmasin.');
    }
    final paths = <String>[];
    final random = Random.secure();
    for (final file in files) {
      final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase() : '';
      const types = {
        'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
        'gif': 'image/gif', 'webp': 'image/webp',
        'mp4': 'video/mp4', 'mov': 'video/quicktime',
        'webm': 'video/webm',
      };
      final type = types[ext];
      if (type == null || (file.bytes.isEmpty && file.localPath == null)) {
        throw FormatException('${file.name}: fayl formati qabul qilinmaydi.');
      }
      final maxMb = file.isVideo ? 80 : 10;
      if (file.sizeInMb > maxMb) {
        throw FormatException('${file.name}: maksimal $maxMb MB.');
      }
      final nonce = random.nextInt(1 << 32).toRadixString(16);
      final targetCompanyId = forCompanyId ?? companyId;
      final path = '$targetCompanyId/$profileId/'
        '${DateTime.now().microsecondsSinceEpoch}_$nonce.$ext';
      final options = FileOptions(contentType: type, upsert: false);
      if (file.localPath != null) {
        await uploadStorageFileFromPath(db, 'work-evidence', path,
          file.localPath!, options);
      } else {
        await db.storage.from('work-evidence').uploadBinary(
          path, file.bytes, fileOptions: options);
      }
      paths.add(path);
    }
    return paths;
  }

  Future<List<String>> signedUrls(List<String> paths) async {
    final urls = <String>[];
    for (final path in paths) {
      urls.add(await db.storage.from('work-evidence')
        .createSignedUrl(path, 15 * 60));
    }
    return urls;
  }

  List<String> mediaTypes(List<String> paths) => paths.map((p) {
    final suffix = p.toLowerCase().split('?').first;
    return suffix.endsWith('.mp4') || suffix.endsWith('.mov') ||
      suffix.endsWith('.webm') ? 'video' :
      suffix.endsWith('.gif') ? 'gif' : 'image';
  }).toList();

  Future<void> createAssignment({
    required String workerId, required String title,
    required String description, required String location,
    required String category, required String priority,
    required DateTime? dueOn, required List<PickedAttachment> files,
  }) async {
    final paths = await uploadMedia(files);
    await db.rpc('work_create_assignment', params: {
      'p_worker_id': workerId, 'p_title': title.trim(),
      'p_description': description.trim(), 'p_location': location.trim(),
      'p_category': category, 'p_priority': priority,
      'p_due_on': dueOn == null ? null : asDate(dueOn), 'p_media': paths,
    });
  }

  Future<void> createDaily({
    required String title, required String description,
    required String location, required String category,
    required DateTime workDate, required List<PickedAttachment> files,
  }) async {
    if (files.isEmpty) {
      throw const FormatException('Hisobotga rasm yoki video majburiy.');
    }
    final paths = await uploadMedia(files);
    await db.rpc('work_create_daily', params: {
      'p_title': title.trim(), 'p_description': description.trim(),
      'p_location': location.trim(), 'p_category': category,
      'p_work_date': asDate(workDate), 'p_media': paths,
    });
  }

  Future<void> startAssignment(WorkItem item) async {
    await db.rpc('work_start_assignment', params: {'p_item_id': item.id});
  }

  Future<void> submitAssignment(WorkItem item, {
    required String description, required DateTime workDate,
    required List<PickedAttachment> files,
  }) async {
    if (files.isEmpty) {
      throw const FormatException('Ish natijasiga rasm yoki video biriktiring.');
    }
    final paths = await uploadMedia(files);
    await db.rpc('work_submit_assignment', params: {
      'p_item_id': item.id, 'p_report': description.trim(),
      'p_work_date': asDate(workDate), 'p_media': paths,
    });
  }

  Future<void> resubmitDaily(WorkItem item, {
    required String description, required DateTime workDate,
    required List<PickedAttachment> files,
  }) async {
    if (files.isEmpty) {
      throw const FormatException('Qayta yuborishda yangi rasm/video majburiy.');
    }
    final paths = await uploadMedia(files);
    await db.rpc('work_resubmit_daily', params: {
      'p_item_id': item.id, 'p_report': description.trim(),
      'p_work_date': asDate(workDate), 'p_media': paths,
    });
  }

  Future<void> review(WorkItem item, {
    required bool approved, required String note,
  }) async {
    await db.rpc('work_review_item', params: {
      'p_item_id': item.id, 'p_approved': approved, 'p_note': note.trim(),
    });
  }

  Future<void> cancel(WorkItem item, String reason) async {
    await db.rpc('work_cancel_assignment', params: {
      'p_item_id': item.id, 'p_reason': reason.trim(),
    });
  }

  Future<void> adminSave({WorkItem? item, required String targetCompanyId,
    required String workerId, required String kind, required String title,
    required String description, required String location,
    required List<PickedAttachment> files}) async {
    final paths = await uploadMedia(files, forCompanyId: targetCompanyId);
    await db.rpc('servicepro_admin_work_save', params: {
      'p_item_id': item?.id, 'p_company_id': targetCompanyId,
      'p_worker_id': workerId, 'p_kind': kind,
      'p_title': title.trim(), 'p_description': description.trim(),
      'p_location': location.trim(), 'p_media': paths,
    });
  }

  Future<void> adminArchive(WorkItem item, {required bool archive}) async {
    await db.rpc('servicepro_admin_work_archive', params: {
      'p_item_id': item.id, 'p_archive': archive,
    });
  }

  Future<void> adminReview(WorkItem item, {required bool approved,
    required String note}) async {
    await db.rpc('servicepro_admin_work_review', params: {
      'p_item_id': item.id, 'p_approved': approved, 'p_note': note.trim(),
    });
  }

  static String asDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
