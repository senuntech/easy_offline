import 'dart:async';
import 'sync_model.dart';
import 'remote_service.dart';
import 'local_store.dart';

abstract class EasyOfflineRepository<T extends SyncModel> {
  final String tableName;
  final T Function(Map<String, dynamic> json) fromJson;
  final RemoteService<T> remoteService;
  final EasyLocalStore _store = EasyLocalStore();

  EasyOfflineRepository({
    required this.tableName,
    required this.fromJson,
    required this.remoteService,
  });

  /// Inicializa o repositório carregando os dados persistidos em disco
  Future<void> initialize({String? customPath}) async {
    await _store.initTable(tableName, customPath: customPath);
  }

  SyncWrapper<T> _wrapperFromMap(Map<String, dynamic> map) {
    final statusIndex = map['_sync_status'] as int? ?? SyncStatus.synced.index;
    final opIndex = map['_sync_operation'] as int? ?? SyncOperation.insert.index;

    final itemJson = Map<String, dynamic>.from(map)
      ..remove('_sync_status')
      ..remove('_sync_operation');

    return SyncWrapper<T>(
      item: fromJson(itemJson),
      status: SyncStatus.values[statusIndex],
      operation: SyncOperation.values[opIndex],
    );
  }

  Map<String, dynamic> _wrapperToMap(T item, SyncStatus status, SyncOperation op) {
    return {
      ...item.toJson(),
      '_sync_status': status.index,
      '_sync_operation': op.index,
    };
  }

  /// Retorna todos os itens não deletados da memória local
  Future<List<SyncWrapper<T>>> getAll() async {
    final rawList = _store.getAll(tableName);
    return rawList
        .map(_wrapperFromMap)
        .where((w) => !w.isDeleted)
        .toList();
  }

  /// Retorna uma Stream reativa dos itens locais não deletados
  Stream<List<SyncWrapper<T>>> watchAll() {
    return Stream.multi((controller) {
      getAll().then((initial) {
        if (!controller.isClosed) {
          controller.add(initial);
        }
      });

      final sub = _store.watch(tableName).listen((_) async {
        if (!controller.isClosed) {
          final items = await getAll();
          controller.add(items);
        }
      });

      controller.onCancel = () {
        sub.cancel();
      };
    });
  }

  /// Adiciona um novo item localmente e tenta sincronizar
  Future<void> add(T item) async {
    final map = _wrapperToMap(item, SyncStatus.pending, SyncOperation.insert);
    _store.saveRaw(tableName, item.id, map);
    await sync();
  }

  /// Atualiza um item localmente e tenta sincronizar
  Future<void> update(T item) async {
    final existing = _store.getById(tableName, item.id);
    final op = (existing != null && existing['_sync_operation'] == SyncOperation.insert.index)
        ? SyncOperation.insert
        : SyncOperation.update;

    final map = _wrapperToMap(item, SyncStatus.pending, op);
    _store.saveRaw(tableName, item.id, map);
    await sync();
  }

  /// Deleta um item localmente e tenta sincronizar
  Future<void> delete(String id) async {
    final existing = _store.getById(tableName, id);
    if (existing == null) return;

    final wrapper = _wrapperFromMap(existing);
    if (wrapper.isPending && wrapper.operation == SyncOperation.insert) {
      _store.deleteRaw(tableName, id);
      return;
    }

    final map = _wrapperToMap(wrapper.item, SyncStatus.pending, SyncOperation.delete);
    _store.saveRaw(tableName, id, map);
    await sync();
  }

  /// Executa o ciclo completo de sincronização (PUSH + PULL).
  /// Trata exceções de rede silenciosamente para manter o comportamento offline consistente.
  Future<void> sync() async {
    try {
      await _push();
      await _pull();
    } catch (_) {
      // Exceções de rede (SocketException, Failed host lookup) são esperadas quando offline
    }
  }

  Future<void> _push() async {
    final allRaw = _store.getAll(tableName);
    final pendingWrappers = allRaw
        .map(_wrapperFromMap)
        .where((w) => w.isPending)
        .toList();

    for (var wrapper in pendingWrappers) {
      try {
        switch (wrapper.operation) {
          case SyncOperation.insert:
            await remoteService.create(wrapper.item);
            _store.saveRaw(
              tableName,
              wrapper.item.id,
              _wrapperToMap(wrapper.item, SyncStatus.synced, SyncOperation.insert),
            );
            break;
          case SyncOperation.update:
            await remoteService.update(wrapper.item);
            _store.saveRaw(
              tableName,
              wrapper.item.id,
              _wrapperToMap(wrapper.item, SyncStatus.synced, SyncOperation.update),
            );
            break;
          case SyncOperation.delete:
            await remoteService.delete(wrapper.item.id);
            _store.deleteRaw(tableName, wrapper.item.id);
            break;
        }
      } catch (_) {
        // Mantém o item marcado como pending em caso de erro de rede
        _store.saveRaw(
          tableName,
          wrapper.item.id,
          _wrapperToMap(wrapper.item, SyncStatus.pending, wrapper.operation),
        );
      }
    }
  }

  Future<void> _pull() async {
    final remoteItems = await remoteService.read();
    final remoteIds = remoteItems.map((e) => e.id).toSet();

    for (var remoteItem in remoteItems) {
      final localRaw = _store.getById(tableName, remoteItem.id);
      if (localRaw == null) {
        _store.saveRaw(
          tableName,
          remoteItem.id,
          _wrapperToMap(remoteItem, SyncStatus.synced, SyncOperation.insert),
        );
      } else {
        final wrapper = _wrapperFromMap(localRaw);
        if (!wrapper.isPending) {
          _store.saveRaw(
            tableName,
            remoteItem.id,
            _wrapperToMap(remoteItem, SyncStatus.synced, wrapper.operation),
          );
        }
      }
    }

    final allRaw = _store.getAll(tableName);
    for (var map in allRaw) {
      final wrapper = _wrapperFromMap(map);
      if (!wrapper.isPending && !remoteIds.contains(wrapper.item.id)) {
        _store.deleteRaw(tableName, wrapper.item.id);
      }
    }
  }
}
