import 'package:easy_offline/easy_offline.dart';

class TaskModel extends SyncModel {
  final String title;
  final String description;
  final bool isCompleted;

  TaskModel({
    super.id,
    required this.title,
    required this.description,
    this.isCompleted = false,
    super.createdAt,
    super.updatedAt,
  });

  TaskModel copyWith({
    String? id,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'is_completed': isCompleted,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory TaskModel.fromJson(Map<String, dynamic> json) => TaskModel(
        id: json['id'] as String?,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        isCompleted: json['is_completed'] as bool? ?? false,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : null,
      );
}
