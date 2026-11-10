import 'package:flutter_test/flutter_test.dart';
import 'package:easy_offline/easy_offline.dart';

class TestModel extends SyncModel {
  final String title;

  TestModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    required this.title,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory TestModel.fromJson(Map<String, dynamic> json) => TestModel(
        id: json['id'] as String?,
        title: json['title'] as String? ?? '',
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'].toString())
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'].toString())
            : null,
      );
}

void main() {
  group('SyncModel & SyncWrapper Tests', () {
    test('SyncModel generates UUID and timestamps by default', () {
      final model = TestModel(title: 'Item 1');

      expect(model.id, isNotEmpty);
      expect(model.id.length, greaterThan(20)); // UUID v4 format
      expect(model.createdAt, isNotNull);
      expect(model.updatedAt, isNotNull);
      expect(model.title, 'Item 1');
    });

    test('SyncModel preserves provided id and timestamps', () {
      final fixedDate = DateTime(2025, 1, 15, 10, 30);
      final model = TestModel(
        id: 'custom-id-123',
        createdAt: fixedDate,
        updatedAt: fixedDate,
        title: 'Fixed Item',
      );

      expect(model.id, 'custom-id-123');
      expect(model.createdAt, fixedDate);
      expect(model.updatedAt, fixedDate);
    });

    test('SyncWrapper correctly reflects status flags', () {
      final item = TestModel(id: '1', title: 'Test');

      final pendingWrapper = SyncWrapper<TestModel>(
        item: item,
        status: SyncStatus.pending,
        operation: SyncOperation.insert,
      );
      expect(pendingWrapper.isPending, isTrue);
      expect(pendingWrapper.isSynced, isFalse);
      expect(pendingWrapper.isFailed, isFalse);
      expect(pendingWrapper.isDeleted, isFalse);

      final syncedWrapper = SyncWrapper<TestModel>(
        item: item,
        status: SyncStatus.synced,
        operation: SyncOperation.update,
      );
      expect(syncedWrapper.isPending, isFalse);
      expect(syncedWrapper.isSynced, isTrue);
      expect(syncedWrapper.isFailed, isFalse);
      expect(syncedWrapper.isDeleted, isFalse);

      final failedWrapper = SyncWrapper<TestModel>(
        item: item,
        status: SyncStatus.failed,
        operation: SyncOperation.insert,
        lastError: 'HTTP 400 Bad Request',
      );
      expect(failedWrapper.isPending, isFalse);
      expect(failedWrapper.isSynced, isFalse);
      expect(failedWrapper.isFailed, isTrue);
      expect(failedWrapper.lastError, 'HTTP 400 Bad Request');

      final deletedWrapper = SyncWrapper<TestModel>(
        item: item,
        status: SyncStatus.pending,
        operation: SyncOperation.delete,
      );
      expect(deletedWrapper.isDeleted, isTrue);
    });

    test('SyncWrapper copyWith updates fields correctly', () {
      final item1 = TestModel(id: '1', title: 'Original');
      final item2 = TestModel(id: '1', title: 'Modified');

      final initial = SyncWrapper<TestModel>(
        item: item1,
        status: SyncStatus.pending,
        operation: SyncOperation.insert,
      );

      final updated = initial.copyWith(
        item: item2,
        status: SyncStatus.synced,
        operation: SyncOperation.update,
        lastError: null,
      );

      expect(updated.item.title, 'Modified');
      expect(updated.status, SyncStatus.synced);
      expect(updated.operation, SyncOperation.update);
      expect(updated.lastError, isNull);

      final failed = updated.copyWith(
        status: SyncStatus.failed,
        lastError: 'Network Error',
      );
      expect(failed.status, SyncStatus.failed);
      expect(failed.lastError, 'Network Error');
    });

    test('SyncWrapper toString provides descriptive debug information', () {
      final item = TestModel(id: 'abc', title: 'Test');
      final wrapper = SyncWrapper<TestModel>(
        item: item,
        status: SyncStatus.synced,
        operation: SyncOperation.insert,
      );

      expect(wrapper.toString(), contains('id: abc'));
      expect(wrapper.toString(), contains('SyncStatus.synced'));
      expect(wrapper.toString(), contains('SyncOperation.insert'));
    });
  });
}
