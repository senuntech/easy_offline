import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Gerencia o armazenamento local em disco e em memória de cada tabela,
/// fornecendo persistência atômica, debounce de escrita e reatividade por Streams.
class EasyLocalStore {
  static final EasyLocalStore _instance = EasyLocalStore._internal();
  factory EasyLocalStore() => _instance;
  EasyLocalStore._internal();

  final Map<String, Map<String, Map<String, dynamic>>> _storage = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>> _controllers = {};
  final Set<String> _initializedTables = {};
  final Map<String, Timer> _debounceTimers = {};

  Directory? _documentsDir;
  String? _customPath;

  /// Duração do debounce para agrupamento de persistência em disco (padrão: 150ms).
  Duration debounceDuration = const Duration(milliseconds: 150);

  /// Inicializa a tabela carregando o arquivo JSON persistido em disco com recuperação atômica.
  Future<void> initTable(String tableName, {String? customPath}) async {
    if (customPath != null) {
      _customPath = customPath;
    }
    if (_initializedTables.contains(tableName)) return;
    _initializedTables.add(tableName);

    try {
      final file = await _getFile(tableName);
      if (file != null) {
        // Verifica primeiro se o arquivo principal existe
        if (await file.exists()) {
          final content = await file.readAsString();
          if (content.isNotEmpty) {
            _loadDecodedContent(tableName, content);
            return;
          }
        }

        // Recuperação: se o principal estiver vazio/ausente, tenta recuperar do .tmp
        final tempFile = File('${file.path}.tmp');
        if (await tempFile.exists()) {
          final tempContent = await tempFile.readAsString();
          if (tempContent.isNotEmpty) {
            _loadDecodedContent(tableName, tempContent);
            // Restaura o arquivo principal
            await tempFile.rename(file.path);
          }
        }
      }
    } catch (e) {
      debugPrint('[EasyLocalStore] Erro ao inicializar tabela $tableName: $e');
    }
  }

  void _loadDecodedContent(String tableName, String content) {
    try {
      final Map decoded = jsonDecode(content);
      final tableMap = <String, Map<String, dynamic>>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          tableMap[key.toString()] = Map<String, dynamic>.from(value);
        }
      });
      _storage[tableName] = tableMap;
    } catch (e) {
      debugPrint('[EasyLocalStore] Erro de decodificação JSON na tabela $tableName: $e');
    }
  }

  Future<File?> _getFile(String tableName) async {
    try {
      if (_customPath != null) {
        final dir = Directory(_customPath!);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return File('${dir.path}/easy_offline_$tableName.json');
      }

      _documentsDir ??= await getApplicationDocumentsDirectory();
      return File('${_documentsDir!.path}/easy_offline_$tableName.json');
    } catch (e) {
      debugPrint('[EasyLocalStore] Erro ao obter arquivo para $tableName: $e');
      return null;
    }
  }

  /// Escrita atômica em disco: grava primeiro em .tmp e renomeia para evitar corrupção.
  Future<void> _atomicWrite(File file, String content) async {
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(content, flush: true);
    try {
      await tempFile.rename(file.path);
    } catch (_) {
      // Fallback para cópia se rename entre partições falhar
      await tempFile.copy(file.path);
      await tempFile.delete();
    }
  }

  /// Agenda a persistência em disco com debounce para evitar tempestade de I/O.
  void _schedulePersistToDisk(String tableName) {
    _debounceTimers[tableName]?.cancel();
    _debounceTimers[tableName] = Timer(debounceDuration, () {
      _persistNow(tableName);
    });
  }

  /// Persiste imediatamente os dados da tabela em disco.
  Future<void> _persistNow(String tableName) async {
    _debounceTimers[tableName]?.cancel();
    _debounceTimers.remove(tableName);

    try {
      final file = await _getFile(tableName);
      if (file != null) {
        final tableData = _getTable(tableName);
        await _atomicWrite(file, jsonEncode(tableData));
      }
    } catch (e) {
      debugPrint('[EasyLocalStore] Erro ao persistir tabela $tableName: $e');
    }
  }

  /// Força a gravação imediata no disco de todas as tabelas ou de uma tabela específica.
  Future<void> flush({String? tableName}) async {
    if (tableName != null) {
      await _persistNow(tableName);
    } else {
      final tables = List<String>.from(_debounceTimers.keys);
      for (final table in tables) {
        await _persistNow(table);
      }
    }
  }

  StreamController<List<Map<String, dynamic>>> _getController(String tableName) {
    return _controllers.putIfAbsent(
      tableName,
      () => StreamController<List<Map<String, dynamic>>>.broadcast(),
    );
  }

  Map<String, Map<String, dynamic>> _getTable(String tableName) {
    return _storage.putIfAbsent(tableName, () => {});
  }

  void _notify(String tableName) {
    final list = getAll(tableName);
    final controller = _controllers[tableName];
    if (controller != null && !controller.isClosed) {
      controller.add(list);
    }
    _schedulePersistToDisk(tableName);
  }

  List<Map<String, dynamic>> getAll(String tableName) {
    final table = _getTable(tableName);
    return table.values.toList();
  }

  Map<String, dynamic>? getById(String tableName, String id) {
    final table = _getTable(tableName);
    return table[id];
  }

  void saveRaw(String tableName, String id, Map<String, dynamic> data) {
    final table = _getTable(tableName);
    table[id] = data;
    _notify(tableName);
  }

  void saveRawBatch(String tableName, Map<String, Map<String, dynamic>> items) {
    final table = _getTable(tableName);
    table.addAll(items);
    _notify(tableName);
  }

  void deleteRaw(String tableName, String id) {
    final table = _getTable(tableName);
    table.remove(id);
    _notify(tableName);
  }

  void deleteRawBatch(String tableName, List<String> ids) {
    final table = _getTable(tableName);
    for (final id in ids) {
      table.remove(id);
    }
    _notify(tableName);
  }

  Stream<List<Map<String, dynamic>>> watch(String tableName) {
    return _getController(tableName).stream;
  }

  /// Limpa os dados em memória e no disco para a tabela informada.
  Future<void> clearTable(String tableName) async {
    _debounceTimers[tableName]?.cancel();
    _debounceTimers.remove(tableName);

    final table = _getTable(tableName);
    table.clear();
    _notify(tableName);

    try {
      final file = await _getFile(tableName);
      if (file != null && await file.exists()) {
        await file.delete();
      }
      final tempFile = File('${file?.path}.tmp');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (_) {}
  }

  /// Fecha o StreamController e libera os recursos da tabela informada.
  void disposeTable(String tableName) {
    _debounceTimers[tableName]?.cancel();
    _debounceTimers.remove(tableName);
    final controller = _controllers.remove(tableName);
    controller?.close();
    _storage.remove(tableName);
    _initializedTables.remove(tableName);
  }

  /// Método de conveniência para reset total (útil para testes unitários).
  @visibleForTesting
  void resetForTesting() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();

    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _storage.clear();
    _initializedTables.clear();
    _documentsDir = null;
    _customPath = null;
  }
}
