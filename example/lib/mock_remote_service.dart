import 'dart:io';
import 'package:easy_offline/easy_offline.dart';
import 'task_model.dart';

class MockRemoteService implements RemoteService<TaskModel> {
  final Map<String, TaskModel> _remoteDb = {};
  bool isOnline = true;

  @override
  Future<void> create(TaskModel item) async {
    await _checkNetwork();
    _remoteDb[item.id] = item;
  }

  @override
  Future<List<TaskModel>> read() async {
    await _checkNetwork();
    return _remoteDb.values.toList();
  }

  @override
  Future<void> update(TaskModel item) async {
    await _checkNetwork();
    _remoteDb[item.id] = item;
  }

  @override
  Future<void> delete(String id) async {
    await _checkNetwork();
    _remoteDb.remove(id);
  }

  Future<void> _checkNetwork() async {
    // Simula tempo de resposta de rede
    await Future.delayed(const Duration(milliseconds: 400));
    if (!isOnline) {
      throw const SocketException('Sem conexão com a internet (Simulação)');
    }
  }
}
