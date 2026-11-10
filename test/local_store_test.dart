import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_offline/easy_offline.dart';

void main() {
  late Directory tempDir;
  late EasyLocalStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('easy_offline_test_');
    store = EasyLocalStore();
    store.resetForTesting();
    store.debounceDuration = const Duration(milliseconds: 50);
  });

  tearDown(() async {
    store.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('EasyLocalStore Tests', () {
    test('initTable loads empty state if file does not exist', () async {
      await store.initTable('test_table', customPath: tempDir.path);

      final all = store.getAll('test_table');
      expect(all, isEmpty);
    });

    test('saveRaw stores data in memory and retrieves by id and all', () async {
      await store.initTable('test_table', customPath: tempDir.path);

      store.saveRaw('test_table', 'id-1', {'id': 'id-1', 'name': 'First Item'});
      store.saveRaw('test_table', 'id-2', {'id': 'id-2', 'name': 'Second Item'});

      final item1 = store.getById('test_table', 'id-1');
      expect(item1, isNotNull);
      expect(item1!['name'], 'First Item');

      final all = store.getAll('test_table');
      expect(all.length, 2);
    });

    test('deleteRaw removes item from memory', () async {
      await store.initTable('test_table', customPath: tempDir.path);

      store.saveRaw('test_table', 'id-1', {'id': 'id-1', 'name': 'Item'});
      expect(store.getById('test_table', 'id-1'), isNotNull);

      store.deleteRaw('test_table', 'id-1');
      expect(store.getById('test_table', 'id-1'), isNull);
      expect(store.getAll('test_table'), isEmpty);
    });

    test('saveRawBatch and deleteRawBatch operate efficiently in batch', () async {
      await store.initTable('test_batch', customPath: tempDir.path);

      final batchData = {
        'b-1': {'id': 'b-1', 'val': 10},
        'b-2': {'id': 'b-2', 'val': 20},
        'b-3': {'id': 'b-3', 'val': 30},
      };

      store.saveRawBatch('test_batch', batchData);
      expect(store.getAll('test_batch').length, 3);

      store.deleteRawBatch('test_batch', ['b-1', 'b-3']);
      final remaining = store.getAll('test_batch');
      expect(remaining.length, 1);
      expect(remaining.first['id'], 'b-2');
    });

    test('watch emits updates when data changes', () async {
      await store.initTable('test_stream', customPath: tempDir.path);

      final stream = store.watch('test_stream');
      final emissions = <List<Map<String, dynamic>>>[];
      final sub = stream.listen(emissions.add);

      store.saveRaw('test_stream', 's-1', {'title': 'A'});
      store.saveRaw('test_stream', 's-2', {'title': 'B'});
      store.deleteRaw('test_stream', 's-1');

      await Future.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last.length, 1);
      expect(emissions.last.first['title'], 'B');
    });

    test('atomic persistence and flush writes valid JSON to disk', () async {
      await store.initTable('test_disk', customPath: tempDir.path);

      store.saveRaw('test_disk', 'd-1', {'title': 'Disk Item 1'});
      store.saveRaw('test_disk', 'd-2', {'title': 'Disk Item 2'});

      // Força a escrita imediata em disco
      await store.flush(tableName: 'test_disk');

      final file = File('${tempDir.path}/easy_offline_test_disk.json');
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      expect(decoded.containsKey('d-1'), isTrue);
      expect(decoded.containsKey('d-2'), isTrue);
      expect(decoded['d-1']['title'], 'Disk Item 1');
    });

    test('recovery from orphaned .tmp file if main file is missing', () async {
      final tmpFile = File('${tempDir.path}/easy_offline_test_recovery.json.tmp');
      final sampleData = {
        'rec-1': {'id': 'rec-1', 'title': 'Recovered Data'},
      };
      await tmpFile.writeAsString(jsonEncode(sampleData));

      // Inicializa tabela: deve detectar o .tmp, restaurar e renomear
      await store.initTable('test_recovery', customPath: tempDir.path);

      final item = store.getById('test_recovery', 'rec-1');
      expect(item, isNotNull);
      expect(item!['title'], 'Recovered Data');

      final mainFile = File('${tempDir.path}/easy_offline_test_recovery.json');
      expect(await mainFile.exists(), isTrue);
    });

    test('clearTable wipes memory and deletes disk file', () async {
      await store.initTable('test_clear', customPath: tempDir.path);
      store.saveRaw('test_clear', 'c-1', {'title': 'Clear Item'});
      await store.flush(tableName: 'test_clear');

      final file = File('${tempDir.path}/easy_offline_test_clear.json');
      expect(await file.exists(), isTrue);

      await store.clearTable('test_clear');

      expect(store.getAll('test_clear'), isEmpty);
      expect(await file.exists(), isFalse);
    });

    test('disposeTable closes controllers and removes table from memory', () async {
      await store.initTable('test_dispose', customPath: tempDir.path);
      store.saveRaw('test_dispose', 'dp-1', {'title': 'Dispose Item'});

      store.disposeTable('test_dispose');

      // Tabela deve ter sido removida do storage interno
      expect(store.getById('test_dispose', 'dp-1'), isNull);
    });
  });
}
