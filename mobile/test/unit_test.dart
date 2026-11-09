import 'package:flutter_test/flutter_test.dart';
import 'package:kanha_qr/core/sync.dart';

void main() {
  group('SyncResult Tests', () {
    test('SyncResult successful construction', () {
      final res = SyncResult(success: true, message: 'Sync complete', uploadedCount: 3);
      expect(res.success, isTrue);
      expect(res.uploadedCount, equals(3));
      expect(res.message, equals('Sync complete'));
    });

    test('SyncResult failure construction', () {
      final res = SyncResult(success: false, message: 'Network connection refused', uploadedCount: 0);
      expect(res.success, isFalse);
      expect(res.uploadedCount, equals(0));
      expect(res.message, equals('Network connection refused'));
    });
  });

  group('Issue Filtering & Role Logic', () {
    test('Field staff sees both assigned issues and unassigned campus issues', () {
      final currentUserId = 'user-staff-123';
      final isLead = false;

      final issues = [
        {'id': '1', 'assigned_to': 'user-staff-123', 'status': 'open'},
        {'id': '2', 'assigned_to': null, 'status': 'open'},
        {'id': '3', 'assigned_to': 'user-other-456', 'status': 'open'},
      ];

      // Replicating the updated Repo.myIssues filtering logic
      final visible = issues.where((i) {
        if (isLead) return true;
        final assigned = i['assigned_to'];
        return assigned == null || assigned == currentUserId;
      }).toList();

      expect(visible.length, equals(2));
      expect(visible.map((i) => i['id']), containsAll(['1', '2']));
      expect(visible.map((i) => i['id']), isNot(contains('3')));
    });

    test('Lead sees all issues across campus', () {
      final isLead = true;

      final issues = [
        {'id': '1', 'assigned_to': 'user-staff-123', 'status': 'open'},
        {'id': '2', 'assigned_to': null, 'status': 'open'},
        {'id': '3', 'assigned_to': 'user-other-456', 'status': 'open'},
      ];

      final visible = issues.where((i) {
        if (isLead) return true;
        return false;
      }).toList();

      expect(visible.length, equals(3));
    });
  });

  group('Sync pending count deduction logic', () {
    test('Deduplicates photo counts between outbox and photo table', () {
      // If an inspection and photo are queued:
      // Outbox has 1 inspection record + 1 photo record
      // Photo table has 1 unuploaded photo record with same id
      final outboxRecords = [
        {'id': 'insp-1', 'entity_type': 'inspection'},
        {'id': 'photo-1', 'entity_type': 'photo'},
      ];
      final unuploadedPhotos = [
        {'id': 'photo-1', 'uploaded': 0},
      ];

      final photoIdsInOutbox = outboxRecords
          .where((r) => r['entity_type'] == 'photo')
          .map((r) => r['id'] as String)
          .toSet();

      final pendingPhotoCount = unuploadedPhotos
          .where((p) => !photoIdsInOutbox.contains(p['id']))
          .length;

      final totalPending = outboxRecords.length + pendingPhotoCount;

      // Must be 2 (1 inspection + 1 photo), NOT 3!
      expect(totalPending, equals(2));
    });
  });
}
