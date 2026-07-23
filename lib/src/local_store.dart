import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class EasyLocalStore {
  static final EasyLocalStore _instance = EasyLocalStore._internal();
  factory EasyLocalStore() => _instance;
  EasyLocalStore._internal();

  final Map<String, Map<String, Map<String, dynamic>>> _storage = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>> _controllers = {};
  final Set<String> _initializedTables = {};
  Directory? _documentsDir;
  String? _customPath;

  /// Inicializa a tabela carregando o arquivo JSON persistido em disco
  Future<void> initTable(String tableName, {String? customPath}) async {
    if (customPath != null) {
      _customPath = customPath;
    }
    if (_initializedTables.contains(tableName)) return;
    _initializedTables.add(tableName);

    try {
      final file = await _getFile(tableName);
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final Map decoded = jsonDecode(content);
          final tableMap = <String, Map<String, dynamic>>{};
          decoded.forEach((key, value) {
            tableMap[key.toString()] = Map<String, dynamic>.from(value as Map);
          });
          _storage[tableName] = tableMap;
        }
      }
    } catch (_) {}
  }

  Future<File?> _getFile(String tableName) async {
    try {
      if (_customPath != null) {
        return File('$_customPath/easy_offline_$tableName.json');
      }
      _documentsDir ??= await getApplicationDocumentsDirectory().timeout(
        const Duration(milliseconds: 500),
      );
      return File('${_documentsDir!.path}/easy_offline_$tableName.json');
    } catch (_) {
      return null;
    }
  }

  void _persistToDisk(String tableName) async {
    try {
      final file = await _getFile(tableName);
      if (file != null) {
        final tableData = _getTable(tableName);
        await file.writeAsString(jsonEncode(tableData));
      }
    } catch (_) {}
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
    _getController(tableName).add(list);
    _persistToDisk(tableName);
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

  void deleteRaw(String tableName, String id) {
    final table = _getTable(tableName);
    table.remove(id);
    _notify(tableName);
  }

  Stream<List<Map<String, dynamic>>> watch(String tableName) {
    return _getController(tableName).stream;
  }
}
