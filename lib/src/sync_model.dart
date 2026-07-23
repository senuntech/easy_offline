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

  bool get isPending => status != SyncStatus.synced;
  bool get isDeleted => operation == SyncOperation.delete;

  SyncWrapper({
    required this.item,
    required this.status,
    required this.operation,
  });

  SyncWrapper<T> copyWith({
    T? item,
    SyncStatus? status,
    SyncOperation? operation,
  }) {
    return SyncWrapper<T>(
      item: item ?? this.item,
      status: status ?? this.status,
      operation: operation ?? this.operation,
    );
  }
}
