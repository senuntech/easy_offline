import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_offline/easy_offline.dart';

class TaskEntity extends SyncModel {
  final String title;
  final bool done;

  TaskEntity({
    super.id,
    super.createdAt,
    super.updatedAt,
    required this.title,
    this.done = false,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'done': done,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory TaskEntity.fromJson(Map<String, dynamic> json) => TaskEntity(
        id: json['id'] as String?,
        title: json['title'] as String? ?? '',
        done: json['done'] == true,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'].toString())
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'].toString())
            : null,
      );

  TaskEntity copyWith({
    String? id,
    String? title,
    bool? done,
    DateTime? updatedAt,
  }) {
    return TaskEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      done: done ?? this.done,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class MockRemoteService implements RemoteService<TaskEntity> {
  final List<TaskEntity> serverDatabase = [];
  int createCalls = 0;
  int readCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;

  bool shouldThrowNetworkError = false;
  bool shouldThrowBusinessError = false;

  @override
  Future<void> create(TaskEntity item) async {
    createCalls++;
    if (shouldThrowNetworkError) {
      throw const SocketException('No Internet Connection');
    }
    if (shouldThrowBusinessError) {
      throw StateError('Invalid title: validation failed');
    }
    serverDatabase.removeWhere((e) => e.id == item.id);
    serverDatabase.add(item);
  }

  @override
  Future<List<TaskEntity>> read() async {
    readCalls++;
    if (shouldThrowNetworkError) {
      throw const SocketException('No Internet Connection');
    }
    return List.from(serverDatabase);
  }

  @override
  Future<void> update(TaskEntity item) async {
    updateCalls++;
    if (shouldThrowNetworkError) {
      throw const SocketException('No Internet Connection');
    }
    if (shouldThrowBusinessError) {
      throw StateError('Invalid update payload');
    }
    serverDatabase.removeWhere((e) => e.id == item.id);
    serverDatabase.add(item);
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls++;
    if (shouldThrowNetworkError) {
      throw const SocketException('No Internet Connection');
    }
    serverDatabase.removeWhere((e) => e.id == id);
  }
}

class TaskRepository extends EasyOfflineRepository<TaskEntity> {
  TaskRepository({
    required super.tableName,
    required super.remoteService,
    super.pullPolicy,
    super.conflictPolicy,
    super.customConflictResolver,
  }) : super(fromJson: TaskEntity.fromJson);
}

void main() {
  late Directory tempDir;
  late MockRemoteService remoteService;
  late TaskRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('easy_offline_repo_test_');
    EasyLocalStore().resetForTesting();
    EasyLocalStore().debounceDuration = const Duration(milliseconds: 20);
    remoteService = MockRemoteService();
    repository = TaskRepository(
      tableName: 'tasks_test',
      remoteService: remoteService,
    );
    await repository.initialize(customPath: tempDir.path);
  });

  tearDown(() async {
    repository.dispose();
    EasyLocalStore().resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('EasyOfflineRepository CRUD & Lifecycle Tests', () {
    test('add stores item locally and triggers sync to remote service', () async {
      final task = TaskEntity(id: 'task-1', title: 'Buy groceries');

      await repository.add(task);

      // Aguarda o ciclo de sync assíncrono
      await repository.sync();

      final localList = await repository.getAll();
      expect(localList.length, 1);
      expect(localList.first.item.title, 'Buy groceries');
      expect(localList.first.isSynced, isTrue);

      expect(remoteService.createCalls, 1);
      expect(remoteService.serverDatabase.length, 1);
      expect(remoteService.serverDatabase.first.id, 'task-1');
    });

    test('getById returns valid wrapper or null if not found', () async {
      final task = TaskEntity(id: 't-1', title: 'Single task');
      await repository.add(task);

      final found = await repository.getById('t-1');
      expect(found, isNotNull);
      expect(found!.item.title, 'Single task');

      final notFound = await repository.getById('non-existent');
      expect(notFound, isNull);
    });

    test('update modifies local item and syncs with remote service', () async {
      final task = TaskEntity(id: 'task-1', title: 'Original Title');
      await repository.add(task);
      await repository.sync();

      final updatedTask = task.copyWith(title: 'Updated Title', done: true);
      await repository.update(updatedTask);
      await repository.sync();

      final localList = await repository.getAll();
      expect(localList.first.item.title, 'Updated Title');
      expect(localList.first.item.done, isTrue);

      expect(remoteService.updateCalls, 1);
      expect(remoteService.serverDatabase.first.title, 'Updated Title');
    });

    test('delete marks as deleted, sends delete to remote service, and removes from getAll', () async {
      final task = TaskEntity(id: 'task-del', title: 'To Delete');
      await repository.add(task);
      await repository.sync();

      expect((await repository.getAll()).length, 1);
      expect(remoteService.serverDatabase.length, 1);

      await repository.delete('task-del');
      await repository.sync();

      final localList = await repository.getAll();
      expect(localList, isEmpty);
      expect(remoteService.deleteCalls, 1);
      expect(remoteService.serverDatabase, isEmpty);
    });

    test('deleting an un-synced pending insert removes immediately without remote call', () async {
      remoteService.shouldThrowNetworkError = true;
      final task = TaskEntity(id: 'never-synced', title: 'Offline created');
      await repository.add(task);
      await repository.sync();

      // Foi salvo localmente, mas falhou ao enviar por estar offline
      expect((await repository.getAll()).length, 1);
      expect(remoteService.createCalls, greaterThanOrEqualTo(1));

      // Agora deleta enquanto ainda está pendente de insert
      await repository.delete('never-synced');

      final localList = await repository.getAll();
      expect(localList, isEmpty);
      // Nenhuma chamada a delete no servidor foi necessária
      expect(remoteService.deleteCalls, 0);
    });

    test('watchAll emits real-time updates on add, update, and delete', () async {
      final stream = repository.watchAll();
      final history = <List<SyncWrapper<TaskEntity>>>[];
      final sub = stream.listen(history.add);

      await repository.add(TaskEntity(id: 'w-1', title: 'Task 1'));
      await repository.add(TaskEntity(id: 'w-2', title: 'Task 2'));
      await repository.update(TaskEntity(id: 'w-1', title: 'Task 1 Updated'));
      await repository.delete('w-2');

      await repository.sync();
      await Future.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(history.length, greaterThanOrEqualTo(4));
      expect(history.last.length, 1);
      expect(history.last.first.item.title, 'Task 1 Updated');
    });
  });

  group('Concurrency, Mutex & Error Handling Tests', () {
    test('sync Mutex prevents concurrent duplicate executions', () async {
      final task1 = TaskEntity(id: 'par-1', title: 'Parallel 1');
      await repository.add(task1);

      // Dispara 5 syncs concorrentes simultâneos
      await Future.wait([
        repository.sync(),
        repository.sync(),
        repository.sync(),
        repository.sync(),
        repository.sync(),
      ]);

      // Somente uma chamada ao create deve ter ocorrido
      expect(remoteService.createCalls, 1);
    });

    test('transient network error keeps item in pending status for future retry', () async {
      remoteService.shouldThrowNetworkError = true;
      final task = TaskEntity(id: 'net-err', title: 'Offline Task');

      await repository.add(task);
      await repository.sync();

      final items = await repository.getAll();
      expect(items.length, 1);
      expect(items.first.isPending, isTrue);
      expect(items.first.isFailed, isFalse);

      // Quando a internet voltar:
      remoteService.shouldThrowNetworkError = false;
      await repository.sync();

      final syncedItems = await repository.getAll();
      expect(syncedItems.first.isSynced, isTrue);
    });

    test('business logic error marks item as failed with lastError recorded', () async {
      remoteService.shouldThrowBusinessError = true;
      final task = TaskEntity(id: 'fail-task', title: 'Bad payload');

      await repository.add(task);
      await repository.sync();

      final items = await repository.getAll();
      expect(items.length, 1);
      expect(items.first.isFailed, isTrue);
      expect(items.first.lastError, contains('Invalid title: validation failed'));
    });
  });

  group('Pull Policy & Conflict Resolution Tests', () {
    test('incremental pull preserves local items not present in remote subset', () async {
      // Cria item 1 que já foi sincronizado
      final task1 = TaskEntity(id: 't-1', title: 'Old Local Task');
      await repository.add(task1);
      await repository.sync();

      // Simula o servidor retornando apenas itens novos/paginados
      remoteService.serverDatabase.clear();
      remoteService.serverDatabase.add(TaskEntity(id: 't-2', title: 'New Remote Task'));

      await repository.sync();

      final all = await repository.getAll();
      // Incremental pull mantém tanto t-1 quanto t-2
      expect(all.length, 2);
      expect(all.any((e) => e.item.id == 't-1'), isTrue);
      expect(all.any((e) => e.item.id == 't-2'), isTrue);
    });

    test('fullMirror pull deletes local items that are absent from remote', () async {
      final mirrorRepo = TaskRepository(
        tableName: 'tasks_mirror_test',
        remoteService: remoteService,
        pullPolicy: PullPolicy.fullMirror,
      );
      await mirrorRepo.initialize(customPath: tempDir.path);

      await mirrorRepo.add(TaskEntity(id: 'm-1', title: 'Mirror 1'));
      await mirrorRepo.add(TaskEntity(id: 'm-2', title: 'Mirror 2'));
      await mirrorRepo.sync();

      expect((await mirrorRepo.getAll()).length, 2);

      // Simula o servidor sem o item m-1
      remoteService.serverDatabase.removeWhere((e) => e.id == 'm-1');

      await mirrorRepo.sync();

      final remaining = await mirrorRepo.getAll();
      expect(remaining.length, 1);
      expect(remaining.first.item.id, 'm-2');
    });

    test('conflict newestWins: remote item with newer timestamp overwrites local', () async {
      final baseDate = DateTime(2025, 1, 1, 10, 0);
      final localDate = DateTime(2025, 1, 1, 11, 0);
      final remoteNewerDate = DateTime(2025, 1, 1, 12, 0);

      final task = TaskEntity(
        id: 'conf-1',
        title: 'Initial',
        createdAt: baseDate,
        updatedAt: baseDate,
      );
      await repository.add(task);
      await repository.sync();

      // Desliga rede
      remoteService.shouldThrowNetworkError = true;

      // Usuário altera localmente às 11:00
      await repository.update(task.copyWith(title: 'Local Edit', updatedAt: localDate));

      // No servidor outro usuário alterou às 12:00
      remoteService.serverDatabase.clear();
      remoteService.serverDatabase.add(
        task.copyWith(title: 'Server Wins Edit', updatedAt: remoteNewerDate),
      );

      // Rede volta
      remoteService.shouldThrowNetworkError = false;
      await repository.sync();

      final all = await repository.getAll();
      expect(all.first.item.title, 'Server Wins Edit');
    });
  });

  group('Batch Operations Tests', () {
    test('addAll, updateAll and deleteAll execute cleanly in batch', () async {
      final items = [
        TaskEntity(id: 'b-1', title: 'Batch 1'),
        TaskEntity(id: 'b-2', title: 'Batch 2'),
        TaskEntity(id: 'b-3', title: 'Batch 3'),
      ];

      await repository.addAll(items);
      await repository.sync();

      var all = await repository.getAll();
      expect(all.length, 3);
      expect(remoteService.serverDatabase.length, 3);

      final updatedItems = [
        items[0].copyWith(title: 'Batch 1 Updated'),
        items[1].copyWith(title: 'Batch 2 Updated'),
      ];
      await repository.updateAll(updatedItems);
      await repository.sync();

      all = await repository.getAll();
      expect(all.firstWhere((e) => e.item.id == 'b-1').item.title, 'Batch 1 Updated');

      await repository.deleteAll(['b-1', 'b-3']);
      await repository.sync();

      all = await repository.getAll();
      expect(all.length, 1);
      expect(all.first.item.id, 'b-2');
    });

    test('clearLocal wipes data from local store', () async {
      await repository.add(TaskEntity(id: 'c-1', title: 'Item'));
      expect((await repository.getAll()).length, 1);

      await repository.clearLocal();
      expect((await repository.getAll()), isEmpty);
    });
  });
}
