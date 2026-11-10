import 'package:uuid/uuid.dart';

enum SyncStatus { pending, synced, failed }

enum SyncOperation { insert, update, delete }

abstract class SyncModel {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  SyncModel({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson();
}

class SyncWrapper<T extends SyncModel> {
  final T item;
  final SyncStatus status;
  final SyncOperation operation;
  final String? lastError;

  bool get isPending => status == SyncStatus.pending;
  bool get isSynced => status == SyncStatus.synced;
  bool get isFailed => status == SyncStatus.failed;
  bool get isDeleted => operation == SyncOperation.delete;

  SyncWrapper({
    required this.item,
    required this.status,
    required this.operation,
    this.lastError,
  });

  SyncWrapper<T> copyWith({
    T? item,
    SyncStatus? status,
    SyncOperation? operation,
    String? lastError,
  }) {
    return SyncWrapper<T>(
      item: item ?? this.item,
      status: status ?? this.status,
      operation: operation ?? this.operation,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  String toString() =>
      'SyncWrapper(id: ${item.id}, status: $status, operation: $operation, error: $lastError)';
}
