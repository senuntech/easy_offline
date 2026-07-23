import 'dart:io';
import 'package:easy_offline/easy_offline.dart';
import 'task_model.dart';

class MockRemoteService implements RemoteService<TaskModel> {
  final List<TaskModel> _serverDatabase = [];
  bool isOnline = true;

  MockRemoteService();

  void toggleOnlineState() {
    isOnline = !isOnline;
  }

  void _checkConnection() {
    if (!isOnline) {
      throw const SocketException('Sem conexão com o servidor remoto (Simulação Offline).');
    }
  }

  @override
  Future<void> create(TaskModel item) async {
    _checkConnection();
    await Future.delayed(const Duration(milliseconds: 300));
    _serverDatabase.removeWhere((e) => e.id == item.id);
    _serverDatabase.add(item);
  }

  @override
  Future<List<TaskModel>> read() async {
    _checkConnection();
    await Future.delayed(const Duration(milliseconds: 300));
    return List.from(_serverDatabase);
  }

  @override
  Future<void> update(TaskModel item) async {
    _checkConnection();
    await Future.delayed(const Duration(milliseconds: 300));
    final index = _serverDatabase.indexWhere((e) => e.id == item.id);
    if (index != -1) {
      _serverDatabase[index] = item;
    } else {
      _serverDatabase.add(item);
    }
  }

  @override
  Future<void> delete(String id) async {
    _checkConnection();
    await Future.delayed(const Duration(milliseconds: 300));
    _serverDatabase.removeWhere((e) => e.id == id);
  }
}
