import 'sync_model.dart';

abstract class RemoteService<T extends SyncModel> {
  Future<void> create(T item);
  Future<List<T>> read();
  Future<void> update(T item);
  Future<void> delete(String id);
}
