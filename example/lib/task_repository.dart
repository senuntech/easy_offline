import 'package:easy_offline/easy_offline.dart';
import 'task_model.dart';
import 'mock_remote_service.dart';

class TaskRepository extends EasyOfflineRepository<TaskModel> {
  final MockRemoteService mockRemoteService;

  TaskRepository({MockRemoteService? remoteService})
      : mockRemoteService = remoteService ?? MockRemoteService(),
        super(
          tableName: 'tasks',
          fromJson: TaskModel.fromJson,
          remoteService: remoteService ?? MockRemoteService(),
        );

  bool get isOnline => mockRemoteService.isOnline;

  void toggleOnlineState(bool online) {
    mockRemoteService.isOnline = online;
    if (online) {
      sync();
    }
  }
}
