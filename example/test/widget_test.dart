import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:example/task_repository.dart';
import 'package:example/task_model.dart';

void main() {
  test('TaskRepository offline CRUD unit test', () async {
    final tempDir = await Directory.systemTemp.createTemp('easy_offline_test_');
    final repository = TaskRepository();
    await repository.initialize(customPath: tempDir.path);

    // 1. Deve iniciar com lista vazia
    final initial = await repository.getAll();
    expect(initial, isEmpty);

    // 2. Adicionar tarefa
    final task = TaskModel(title: 'Test Task', description: 'Testing offline repo');
    await repository.add(task);

    final tasks = await repository.getAll();
    expect(tasks.length, equals(1));
    expect(tasks.first.item.title, equals('Test Task'));

    // 3. Atualizar tarefa
    final updated = task.copyWith(isCompleted: true);
    await repository.update(updated);

    final tasksAfterUpdate = await repository.getAll();
    expect(tasksAfterUpdate.first.item.isCompleted, isTrue);

    // 4. Deletar tarefa
    await repository.delete(task.id);
    final finalTasks = await repository.getAll();
    expect(finalTasks, isEmpty);
  });
}
