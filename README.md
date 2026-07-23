# `easy_offline`

Uma biblioteca **Offline-First reativa, fortemente tipada e de baixíssima verbosidade (Zero Boilerplate)** para aplicações Flutter & Dart.

---

## ✨ Principais Recursos

- **100% Agnostic à API**: Funciona com qualquer cliente HTTP ou protocolo (**Dio**, **http**, **GraphQL**, **Firebase**, **Supabase**, **gRPC**).
- **Zero Adapters**: Não exige a criação de classes conversoras manuais (`OfflineAdapter`). Basta estender `SyncModel`.
- **Interface Limpa de API**: Conecte qualquer API implementando a interface `RemoteService<T>`.
- **Repositório em 1 Linha**: Crie repositórios offline completos estendendo `EasyOfflineRepository<T>`.
- **Totalmente Reativo**: Método `watchAll()` emitindo `Stream<List<SyncWrapper<T>>>` para atualização em tempo real da UI.
- **Auto-Sync e Fila Offline**: Armazena inserções, edições e exclusões localmente quando offline e sincroniza automaticamente quando online.

---

## 📁 Estrutura do Repositório

- `lib/`: Código-fonte da biblioteca `easy_offline`.
- `example/`: Projeto de exemplo completo Flutter demonstrando a utilização da biblioteca. Nota: a pasta `example` faz parte do mesmo repositório do pacote.

---

## 🚀 Guia Rápido de Uso

### 1. Defina o seu Modelo (estendendo `SyncModel`)

```dart
import 'package:easy_offline/easy_offline.dart';

class UserModel extends SyncModel {
  final String name;
  final String email;

  UserModel({
    super.id,
    required this.name,
    required this.email,
    super.createdAt,
    super.updatedAt,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        name: json['name'],
        email: json['email'],
        createdAt: DateTime.parse(json['created_at']),
        updatedAt: DateTime.parse(json['updated_at']),
      );
}
```

---

### 2. Implemente o Serviço de API (`RemoteService<T>`)

O `easy_offline` **não se importa** se você usa Dio, http ou GraphQL. Basta implementar os 4 métodos da interface `RemoteService<T>`:

```dart
import 'package:easy_offline/easy_offline.dart';
import 'package:dio/dio.dart';

class UserDioService implements RemoteService<UserModel> {
  final Dio _dio;

  UserDioService({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://api.exemplo.com'));

  @override
  Future<void> create(UserModel item) async {
    await _dio.post('/users', data: item.toJson());
  }

  @override
  Future<List<UserModel>> read() async {
    final response = await _dio.get('/users');
    final List list = response.data;
    return list.map((json) => UserModel.fromJson(json)).toList();
  }

  @override
  Future<void> update(UserModel item) async {
    await _dio.put('/users/${item.id}', data: item.toJson());
  }

  @override
  Future<void> delete(String id) async {
    await _dio.delete('/users/$id');
  }
}
```

---

### 3. Crie o seu Repositório (`EasyOfflineRepository<T>`)

```dart
import 'package:easy_offline/easy_offline.dart';

class UserRepository extends EasyOfflineRepository<UserModel> {
  UserRepository({UserDioService? dioService})
      : super(
          tableName: 'users',
          fromJson: UserModel.fromJson,
          remoteService: dioService ?? UserDioService(),
        );
}
```

---

### 4. Utilize no seu ViewModel / UI

```dart
final userRepository = UserRepository();
await userRepository.initialize(); // Carrega cache local persistido no dispositivo

// 🟢 Adicionar (salva local instantaneamente + sincroniza se online)
await userRepository.add(user);

// 🟡 Atualizar
await userRepository.update(user.copyWith(name: 'Novo Nome'));

// 🔴 Deletar
await userRepository.delete(user.id);

// 📖 Consulta local instantânea
List<SyncWrapper<UserModel>> users = await userRepository.getAll();

// ⚡ Escuta reativa em tempo real (Stream)
userRepository.watchAll().listen((usersList) {
  print('Usuários atualizados: ${usersList.length}');
});

// 🔄 Disparar sincronização manual
await userRepository.sync();
```

---

## 📖 Referência da API

### `SyncModel`
Classe base para todas as entidades persistidas. Garante a presença dos campos `id`, `createdAt` e `updatedAt`.

### `SyncWrapper<T>`
Encapsula o modelo com os metadados de sincronização:
- `wrapper.item`: O objeto `T`.
- `wrapper.status`: `SyncStatus.pending` | `SyncStatus.synced` | `SyncStatus.failed`.
- `wrapper.isPending`: Retorna `true` se houver alteração pendente de envio.

### `EasyOfflineRepository<T>`
Classe abstrata principal fornecendo o CRUD reativo offline-first.

| Método | Descrição |
| :--- | :--- |
| `initialize({String? customPath})` | Carrega os dados persistidos do armazenamento local. |
| `getAll()` | Retorna a lista local atual de objetos `SyncWrapper<T>`. |
| `watchAll()` | Retorna uma `Stream<List<SyncWrapper<T>>>` reativa em tempo real. |
| `add(T item)` | Salva localmente como pendente de inclusão e sincroniza. |
| `update(T item)` | Salva localmente como pendente de edição e sincroniza. |
| `delete(String id)` | Marca como deletado e sincroniza a remoção no servidor. |
| `sync()` | Processa a fila de pendências (PUSH) e busca atualizações (PULL). |
