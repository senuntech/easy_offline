import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'sync_model.dart';
import 'remote_service.dart';
import 'local_store.dart';

/// Define a estratégia de sincronização de dados vindos do servidor no método `pull`.
enum PullPolicy {
  /// Modo seguro (recomendado): adiciona novos e atualiza existentes sem apagar
  /// registros locais pré-existentes. Essencial para endpoints paginados ou filtrados.
  incremental,

  /// Modo espelho estrito: apaga registros locais já sincronizados que não
  /// estejam presentes na lista retornada pelo servidor.
  fullMirror,
}

/// Define a política de resolução de conflitos entre dados locais e remotos.
enum ConflictPolicy {
  /// O registro com o `updatedAt` mais recente prevalece.
  newestWins,

  /// A alteração local sempre prevalece sobre a versão remota.
  clientWins,

  /// A versão remota sempre sobrescreve a alteração local pendente.
  serverWins,

  /// Utiliza um resolvedor customizado fornecido pelo desenvolvedor.
  custom,
}

typedef ConflictResolver<T> = T Function(T local, T remote);

/// Repositório Offline-First reativo que centraliza 100% da lógica de persistência,
/// cache em disco, reatividade e sincronização em segundo plano.
abstract class EasyOfflineRepository<T extends SyncModel> {
  final String tableName;
  final T Function(Map<String, dynamic> json) fromJson;
  final RemoteService<T> remoteService;
  final PullPolicy pullPolicy;
  final ConflictPolicy conflictPolicy;
  final ConflictResolver<T>? customConflictResolver;

  final EasyLocalStore _store = EasyLocalStore();

  bool _isSyncing = false;
  bool _hasPendingSync = false;
  Completer<void>? _activeSyncCompleter;

  /// Indica se há uma sincronização em andamento para esta tabela.
  bool get isSyncing => _isSyncing;

  EasyOfflineRepository({
    required this.tableName,
    required this.fromJson,
    required this.remoteService,
    this.pullPolicy = PullPolicy.incremental,
    this.conflictPolicy = ConflictPolicy.newestWins,
    this.customConflictResolver,
  });

  /// Inicializa o repositório carregando os dados persistidos em disco.
  Future<void> initialize({String? customPath}) async {
    await _store.initTable(tableName, customPath: customPath);
  }

  SyncWrapper<T> _wrapperFromMap(Map<String, dynamic> map) {
    final statusIndex = map['_sync_status'] as int? ?? SyncStatus.synced.index;
    final opIndex = map['_sync_operation'] as int? ?? SyncOperation.insert.index;
    final lastError = map['_sync_error'] as String?;

    final itemJson = Map<String, dynamic>.from(map)
      ..remove('_sync_status')
      ..remove('_sync_operation')
      ..remove('_sync_error');

    return SyncWrapper<T>(
      item: fromJson(itemJson),
      status: SyncStatus.values[statusIndex],
      operation: SyncOperation.values[opIndex],
      lastError: lastError,
    );
  }

  Map<String, dynamic> _wrapperToMap(
    T item,
    SyncStatus status,
    SyncOperation op, {
    String? lastError,
  }) {
    return {
      ...item.toJson(),
      '_sync_status': status.index,
      '_sync_operation': op.index,
      if (lastError != null) '_sync_error': lastError,
    };
  }

  /// Retorna todos os itens não deletados da memória local.
  Future<List<SyncWrapper<T>>> getAll() async {
    final rawList = _store.getAll(tableName);
    return rawList
        .map(_wrapperFromMap)
        .where((w) => !w.isDeleted)
        .toList();
  }

  /// Retorna um item pelo ID ou `null` se não existir ou estiver deletado.
  Future<SyncWrapper<T>?> getById(String id) async {
    final raw = _store.getById(tableName, id);
    if (raw == null) return null;
    final wrapper = _wrapperFromMap(raw);
    return wrapper.isDeleted ? null : wrapper;
  }

  /// Retorna uma Stream reativa dos itens locais não deletados.
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

  /// Adiciona um novo item localmente e agenda a sincronização.
  Future<void> add(T item) async {
    final map = _wrapperToMap(item, SyncStatus.pending, SyncOperation.insert);
    _store.saveRaw(tableName, item.id, map);
    unawaited(sync());
  }

  /// Adiciona múltiplos itens em lote localmente e agenda a sincronização.
  Future<void> addAll(List<T> items) async {
    if (items.isEmpty) return;
    final batchMap = <String, Map<String, dynamic>>{};
    for (final item in items) {
      batchMap[item.id] = _wrapperToMap(item, SyncStatus.pending, SyncOperation.insert);
    }
    _store.saveRawBatch(tableName, batchMap);
    unawaited(sync());
  }

  /// Atualiza um item localmente e agenda a sincronização.
  Future<void> update(T item) async {
    final existing = _store.getById(tableName, item.id);
    final isPendingInsert = existing != null &&
        existing['_sync_operation'] == SyncOperation.insert.index &&
        existing['_sync_status'] == SyncStatus.pending.index;

    final op = isPendingInsert ? SyncOperation.insert : SyncOperation.update;

    final map = _wrapperToMap(item, SyncStatus.pending, op);
    _store.saveRaw(tableName, item.id, map);
    unawaited(sync());
  }

  /// Atualiza múltiplos itens em lote localmente e agenda a sincronização.
  Future<void> updateAll(List<T> items) async {
    if (items.isEmpty) return;
    final batchMap = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final existing = _store.getById(tableName, item.id);
      final isPendingInsert = existing != null &&
          existing['_sync_operation'] == SyncOperation.insert.index &&
          existing['_sync_status'] == SyncStatus.pending.index;
      final op = isPendingInsert ? SyncOperation.insert : SyncOperation.update;
      batchMap[item.id] = _wrapperToMap(item, SyncStatus.pending, op);
    }
    _store.saveRawBatch(tableName, batchMap);
    unawaited(sync());
  }

  /// Deleta um item localmente e agenda a sincronização.
  Future<void> delete(String id) async {
    final existing = _store.getById(tableName, id);
    if (existing == null) return;

    final wrapper = _wrapperFromMap(existing);
    if (wrapper.isPending && wrapper.operation == SyncOperation.insert) {
      // Se nunca foi enviado ao servidor (insert pendente), remove imediatamente do disco local
      _store.deleteRaw(tableName, id);
      return;
    }

    final map = _wrapperToMap(wrapper.item, SyncStatus.pending, SyncOperation.delete);
    _store.saveRaw(tableName, id, map);
    unawaited(sync());
  }

  /// Deleta múltiplos itens em lote localmente e agenda a sincronização.
  Future<void> deleteAll(List<String> ids) async {
    if (ids.isEmpty) return;
    final deleteBatchMap = <String, Map<String, dynamic>>{};
    final immediateDeleteIds = <String>[];

    for (final id in ids) {
      final existing = _store.getById(tableName, id);
      if (existing == null) continue;

      final wrapper = _wrapperFromMap(existing);
      if (wrapper.isPending && wrapper.operation == SyncOperation.insert) {
        immediateDeleteIds.add(id);
      } else {
        deleteBatchMap[id] = _wrapperToMap(
          wrapper.item,
          SyncStatus.pending,
          SyncOperation.delete,
        );
      }
    }

    if (immediateDeleteIds.isNotEmpty) {
      _store.deleteRawBatch(tableName, immediateDeleteIds);
    }
    if (deleteBatchMap.isNotEmpty) {
      _store.saveRawBatch(tableName, deleteBatchMap);
      unawaited(sync());
    }
  }

  /// Executa o ciclo completo de sincronização com proteção contra reentrância.
  /// A reconciliação executa `_pull()` primeiro para detectar novidades/conflitos,
  /// seguido por `_push()` para enviar as alterações locais consolidadas.
  Future<void> sync() async {
    if (_isSyncing) {
      _hasPendingSync = true;
      return _activeSyncCompleter?.future ?? Future.value();
    }

    _isSyncing = true;
    final completer = Completer<void>();
    _activeSyncCompleter = completer;

    try {
      do {
        _hasPendingSync = false;

        try {
          await _pull();
        } catch (e) {
          debugPrint('[EasyOfflineRepository] Erro durante pull na tabela $tableName: $e');
        }

        try {
          await _push();
        } catch (e) {
          debugPrint('[EasyOfflineRepository] Erro durante push na tabela $tableName: $e');
        }
      } while (_hasPendingSync);
    } finally {
      _isSyncing = false;
      _activeSyncCompleter = null;
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  /// Verifica se uma exceção é transitória de conectividade ou falha definitiva de negócio.
  bool _isNetworkTransientError(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException) {
      return true;
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection timed out') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('socketexception');
  }

  Future<void> _push() async {
    final allRaw = _store.getAll(tableName);
    final pendingWrappers = allRaw
        .map(_wrapperFromMap)
        .where((w) => w.isPending)
        .toList();

    for (final wrapper in pendingWrappers) {
      try {
        switch (wrapper.operation) {
          case SyncOperation.insert:
            await remoteService.create(wrapper.item);
            final currentAfterInsert = _store.getById(tableName, wrapper.item.id);
            if (currentAfterInsert == null) {
              try {
                await remoteService.delete(wrapper.item.id);
              } catch (_) {}
              break;
            }
            final current = _wrapperFromMap(currentAfterInsert);
            if (current.isDeleted || current.item.updatedAt.isAfter(wrapper.item.updatedAt)) {
              break;
            }
            _store.saveRaw(
              tableName,
              wrapper.item.id,
              _wrapperToMap(wrapper.item, SyncStatus.synced, SyncOperation.update),
            );
            break;
          case SyncOperation.update:
            await remoteService.update(wrapper.item);
            final currentAfterUpdate = _store.getById(tableName, wrapper.item.id);
            if (currentAfterUpdate != null) {
              final current = _wrapperFromMap(currentAfterUpdate);
              if (current.isDeleted || current.item.updatedAt.isAfter(wrapper.item.updatedAt)) {
                break;
              }
            }
            _store.saveRaw(
              tableName,
              wrapper.item.id,
              _wrapperToMap(wrapper.item, SyncStatus.synced, SyncOperation.update),
            );
            break;
          case SyncOperation.delete:
            await remoteService.delete(wrapper.item.id);
            final currentAfterDelete = _store.getById(tableName, wrapper.item.id);
            if (currentAfterDelete != null) {
              final current = _wrapperFromMap(currentAfterDelete);
              if (!current.isDeleted) {
                break;
              }
            }
            _store.deleteRaw(tableName, wrapper.item.id);
            break;
        }
      } catch (e) {
        if (_isNetworkTransientError(e)) {
          // Erro de rede temporário: mantém pending para tentar no próximo ciclo
          _store.saveRaw(
            tableName,
            wrapper.item.id,
            _wrapperToMap(
              wrapper.item,
              SyncStatus.pending,
              wrapper.operation,
            ),
          );
        } else {
          // Erro permanente ou de negócio: marca como failed e armazena mensagem de erro
          _store.saveRaw(
            tableName,
            wrapper.item.id,
            _wrapperToMap(
              wrapper.item,
              SyncStatus.failed,
              wrapper.operation,
              lastError: e.toString(),
            ),
          );
        }
      }
    }
  }

  Future<void> _pull() async {
    final remoteItems = await remoteService.read();
    final remoteIds = remoteItems.map((e) => e.id).toSet();

    for (final remoteItem in remoteItems) {
      final localRaw = _store.getById(tableName, remoteItem.id);
      if (localRaw == null) {
        // Novo item vindo do servidor
        _store.saveRaw(
          tableName,
          remoteItem.id,
          _wrapperToMap(remoteItem, SyncStatus.synced, SyncOperation.update),
        );
      } else {
        final localWrapper = _wrapperFromMap(localRaw);

        // Se o item local foi deletado e aguarda push, não ressuscitá-lo no pull
        if (localWrapper.isDeleted) {
          continue;
        }

        if (!localWrapper.isPending) {
          // Item local já estava sincronizado: atualiza com os dados do servidor
          _store.saveRaw(
            tableName,
            remoteItem.id,
            _wrapperToMap(remoteItem, SyncStatus.synced, SyncOperation.update),
          );
        } else {
          // Conflito: item local possui alterações pendentes não enviadas
          _resolveConflict(localWrapper, remoteItem);
        }
      }
    }

    // Modo espelho estrito: apaga locais que não existem mais remotamente
    if (pullPolicy == PullPolicy.fullMirror) {
      final allRaw = _store.getAll(tableName);
      for (final map in allRaw) {
        final wrapper = _wrapperFromMap(map);
        if (!wrapper.isPending && !remoteIds.contains(wrapper.item.id)) {
          _store.deleteRaw(tableName, wrapper.item.id);
        }
      }
    }
  }

  void _resolveConflict(SyncWrapper<T> localWrapper, T remoteItem) {
    switch (conflictPolicy) {
      case ConflictPolicy.newestWins:
        if (remoteItem.updatedAt.isAfter(localWrapper.item.updatedAt)) {
          // Versão remota é mais recente: sobrescreve local e marca como sincronizado
          _store.saveRaw(
            tableName,
            remoteItem.id,
            _wrapperToMap(remoteItem, SyncStatus.synced, SyncOperation.update),
          );
        }
        // Se a local for mais recente ou igual, mantém a alteração local pendente
        break;

      case ConflictPolicy.serverWins:
        _store.saveRaw(
          tableName,
          remoteItem.id,
          _wrapperToMap(remoteItem, SyncStatus.synced, SyncOperation.update),
        );
        break;

      case ConflictPolicy.clientWins:
        // Mantém a versão local pendente para ser enviada no _push()
        break;

      case ConflictPolicy.custom:
        if (customConflictResolver != null) {
          final resolvedItem = customConflictResolver!(localWrapper.item, remoteItem);
          _store.saveRaw(
            tableName,
            resolvedItem.id,
            _wrapperToMap(resolvedItem, SyncStatus.pending, localWrapper.operation),
          );
        }
        break;
    }
  }

  /// Limpa os dados em disco e memória da tabela do repositório.
  Future<void> clearLocal() async {
    await _store.clearTable(tableName);
  }

  /// Libera recursos e fecha os streams associados à tabela.
  void dispose() {
    _store.disposeTable(tableName);
  }
}
