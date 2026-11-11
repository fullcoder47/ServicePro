import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicepro/data/models.dart';
import 'package:servicepro/features/work_activity/work_activity_repository.dart';

void main() {
  Map<String, dynamic> row({
    String kind = 'assignment',
    String status = 'assigned',
    String? workerId = 'worker-1',
    List<String> evidence = const [],
  }) => {
    'id': 'task-1',
    'company_id': 'company-1',
    'worker_id': workerId,
    'kind': kind,
    'category': 'cleaning',
    'title': 'Hududni tozalash',
    'description': 'Bino oldini tozalash',
    'location_text': 'Ipak yo‘li 50',
    'priority': 'normal',
    'status': status,
    'evidence_media': evidence,
    'instruction_media': <String>[],
    'created_at': '2026-10-28T10:00:00Z',
  };

  test('new assignments can start and be submitted', () {
    final item = WorkItem(row());
    expect(item.isTask, isTrue);
    expect(item.canStart, isTrue);
    expect(item.canSubmit, isTrue);
    expect(item.pendingReview, isFalse);
  });

  test('submitted reports are reviewable and historical evidence is parsed', () {
    final item = WorkItem(row(kind: 'daily', status: 'submitted',
      evidence: ['company/worker/old.jpg']));
    expect(item.isTask, isFalse);
    expect(item.pendingReview, isTrue);
    expect(item.evidencePaths, hasLength(1));
    expect(item.canSubmit, isFalse);
  });

  test('deleted worker profile does not prevent reading historical work', () {
    final item = WorkItem(row(workerId: null, status: 'approved',
      evidence: ['company/worker/proof.mp4']));
    expect(item.workerId, isNull);
    expect(item.status, 'approved');
    expect(item.evidencePaths.single, endsWith('proof.mp4'));
  });

  test('large picked videos keep their size without loading all bytes', () {
    final video = PickedAttachment(
      name: 'ish.mp4',
      bytes: Uint8List(0),
      isVideo: true,
      localPath: '/temporary/ish.mp4',
      byteLength: 40 * 1024 * 1024,
    );
    expect(video.bytes, isEmpty);
    expect(video.sizeInMb, 40);
  });
}
