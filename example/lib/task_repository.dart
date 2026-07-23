import 'package:easy_offline/easy_offline.dart';
import 'mock_remote_service.dart';
import 'task_model.dart';

class TaskRepository extends EasyOfflineRepository<TaskModel> {
  final MockRemoteService mockService;

  TaskRepository({required this.mockService})
      : super(
          tableName: 'example_tasks',
          fromJson: TaskModel.fromJson,
          remoteService: mockService,
        );
}
