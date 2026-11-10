# easy_offline

[![pub package](https://img.shields.io/pub/v/easy_offline.svg)](https://pub.dev/packages/easy_offline)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Uma biblioteca **Offline-First reativa, fortemente tipada e de baixíssima verbosidade (Zero Boilerplate)** para aplicações Flutter & Dart.

Persista seus dados localmente com segurança em disco em microssegundos, forneça atualizações instantâneas para a UI via Streams reativas e deixe a sincronização bidirecional em segundo plano (PUSH & PULL) rodar de forma automática e transparente.

---

## ✨ Principais Diferenciais

- **Zero Adapters & Zero Boilerplate:** Não exige geração de código complexa, adaptadores intermediários ou schemas SQLite manuais.
- **Tudo Centralizado no Repository:** A camada de UI e os Controllers não sabem nada sobre rede, SQL, arquivos ou timers. Apenas consom o repositório.
- **Persistência Atômica Segura:** Gravação em disco usando padrão *Atomic Write* (`.tmp` + rename atômico), garantindo integridade mesmo se o app for encerrado durante o I/O.
- **I/O Debouncing Inteligente:** Agrupamento automático de escritas consecutivas em buffer (padrão 150ms) para evitar sobrecarga de CPU e disco em loops de dados.
- **Sincronização com Concurrency Lock (Mutex):** Previne múltiplos `sync()` simultâneos em paralelo, evitando registros duplicados no backend ou perda de dados em trânsito.
- **Políticas de Pull Flexíveis:** Suporte nativo a endpoints paginados com `PullPolicy.incremental` (não apaga dados locais) e modo espelho com `PullPolicy.fullMirror`.
- **Resolução de Conflitos Declarativa:** Escolha entre `newestWins` (baseado em timestamp), `clientWins`, `serverWins` ou resolução customizada.
- **Operações em Lote (Batch):** Adicione, atualize ou remova centenas de registros de uma só vez (`addAll`, `updateAll`, `deleteAll`) com apenas uma notificação de UI e uma escrita em disco.
- **100% Agnóstico a Protocolos:** Funciona perfeitamente com **Dio**, **http**, **GraphQL / Hasura**, **Firebase**, **Supabase** ou **WebSockets**.

---

## 🏛️ Fluxo Arquitetural

```mermaid
flowchart TD
    subgraph UI & State
        Page[Widgets & Pages Dumb] <--> |Consome Estado & Dispara Eventos| Controller[ChangeNotifier / Bloc / Cubit]
    end

    subgraph Repositories Layer (Toda a Inteligência Centralizada)
        Controller <--> |watchAll / getAll / add / update / delete| Repo[EasyOfflineRepository]
        
        subgraph Engine de Armazenamento Local
            Repo <--> Cache[In-Memory Cache Instantâneo]
            Cache --> Debounce[Debounce Buffer 150ms]
            Debounce --> AtomicWriter[Atomic Write *.tmp -> rename]
            AtomicWriter --> Disk[(JSON Seguro no Disco)]
        end
        
        subgraph Engine de Sincronização
            Repo --> Mutex[Sync Mutex & Loop Reentrante]
            Mutex --> Pull[PULL: Baixa Novidades & Resolve Conflitos]
            Mutex --> Push[PUSH: Envia Pendências Locais]
            Push --> ErrorClassifier{Falha de Conexão ou Lógica?}
            ErrorClassifier -->|Transitória| Pending[Mantém Pending]
            ErrorClassifier -->|Lógica/400| Failed[Marca Failed + armazena lastError]
        end
    end

    subgraph Backend
        Pull & Push <--> Service[RemoteService REST / GraphQL / Supabase]
    end
```

---

## 🚀 Guia Rápido (Quickstart em 4 Passos)

### 1. Defina a Entidade (estendendo `SyncModel`)
Herde de `SyncModel` para ganhar suporte a ID (UUID v4) e controle de ciclo de vida (`createdAt` e `updatedAt`):

```dart
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

  TaskEntity copyWith({String? title, bool? done}) => TaskEntity(
        id: id,
        title: title ?? this.title,
        done: done ?? this.done,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
```

---

### 2. Implemente o Serviço Remoto (`RemoteService<T>`)
Implemente apenas os 4 métodos da interface conectando ao seu backend:

```dart
import 'package:easy_offline/easy_offline.dart';
import 'package:dio/dio.dart';

class TaskRemoteService implements RemoteService<TaskEntity> {
  final Dio dio;

  TaskRemoteService({required this.dio});

  @override
  Future<void> create(TaskEntity item) async {
    await dio.post('/tasks', data: item.toJson());
  }

  @override
  Future<List<TaskEntity>> read() async {
    final response = await dio.get('/tasks');
    final List list = response.data;
    return list.map((json) => TaskEntity.fromJson(json)).toList();
  }

  @override
  Future<void> update(TaskEntity item) async {
    await dio.put('/tasks/${item.id}', data: item.toJson());
  }

  @override
  Future<void> delete(String id) async {
    await dio.delete('/tasks/$id');
  }
}
```

---

### 3. Crie o Repositório (`EasyOfflineRepository<T>`)
Estenda `EasyOfflineRepository<T>`. É aqui que toda a mágica acontece:

```dart
import 'package:easy_offline/easy_offline.dart';

class TaskRepository extends EasyOfflineRepository<TaskEntity> {
  TaskRepository({required TaskRemoteService remoteService})
      : super(
          tableName: 'tasks',
          fromJson: TaskEntity.fromJson,
          remoteService: remoteService,
          // Opcional: define estratégia de pull (incremental ou fullMirror)
          pullPolicy: PullPolicy.incremental,
          // Opcional: define resolução de conflitos (newestWins, clientWins, serverWins, custom)
          conflictPolicy: ConflictPolicy.newestWins,
        );
}
```

---

### 4. Consuma na sua UI ou Controller
Utilize o repositório diretamente na sua camada de apresentação ou gerenciador de estado (ChangeNotifier, Bloc, Riverpod):

```dart
class TaskController extends ChangeNotifier {
  final TaskRepository repository;
  StreamSubscription? _subscription;
  List<SyncWrapper<TaskEntity>> tasks = [];

  TaskController({required this.repository}) {
    _init();
  }

  Future<void> _init() async {
    // 1. Carrega dados do disco instantaneamente (< 5ms)
    await repository.initialize();

    // 2. Escuta mudanças em tempo real (reativo)
    _subscription = repository.watchAll().listen((items) {
      tasks = items;
      notifyListeners();
    });

    // 3. Sincroniza novidades com o servidor em segundo plano
    repository.sync();
  }

  // Operações instantâneas
  Future<void> addTask(String title) =>
      repository.add(TaskEntity(title: title));

  Future<void> toggleDone(TaskEntity task) =>
      repository.update(task.copyWith(done: !task.done));

  Future<void> removeTask(String id) =>
      repository.delete(id);

  Future<void> syncNow() =>
      repository.sync();

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
```

---

## ⚙️ Recursos Avançados

### 1. Estratégias de Pull (`PullPolicy`)
Por padrão, o `easy_offline` utiliza `PullPolicy.incremental`.

* **`PullPolicy.incremental` (Recomendado):** Adiciona novos itens do servidor e atualiza os existentes. **Nunca apaga registros locais pré-existentes.** Ideal para endpoints que usam paginação, filtros por data ou consultas parciais.
* **`PullPolicy.fullMirror`:** Compara os dados do servidor com os do disco local e remove registros locais sincronizados que não estejam mais na resposta da nuvem (espelhamento estrito).

```dart
class TaskRepository extends EasyOfflineRepository<TaskEntity> {
  TaskRepository({required super.remoteService})
      : super(
          tableName: 'tasks',
          fromJson: TaskEntity.fromJson,
          pullPolicy: PullPolicy.incremental,
        );
}
```

---

### 2. Resolução de Conflitos (`ConflictPolicy`)
Quando um item é alterado localmente enquanto offline e também foi modificado no servidor, o `easy_offline` resolve o conflito automaticamente com base na política configurada:

* **`ConflictPolicy.newestWins` (Padrão):** Compara `updatedAt` entre a versão local e a remota; a mais recente prevalece.
* **`ConflictPolicy.clientWins`:** A alteração local sempre tem prioridade e será reenviada ao servidor.
* **`ConflictPolicy.serverWins`:** A versão do servidor sempre sobrescreve a alteração local pendente.
* **`ConflictPolicy.custom`:** Permite definir uma função customizada:

```dart
class TaskRepository extends EasyOfflineRepository<TaskEntity> {
  TaskRepository({required super.remoteService})
      : super(
          tableName: 'tasks',
          fromJson: TaskEntity.fromJson,
          conflictPolicy: ConflictPolicy.custom,
          customConflictResolver: (local, remote) {
            // Regra customizada: preserva o título local mas aceita o status remoto
            return local.copyWith(done: remote.done);
          },
        );
}
```

---

### 3. Operações em Lote (Batch)
Para processar múltiplos itens com performance máxima (apenas uma escrita em disco e uma emissão de stream):

```dart
// Adicionar múltiplos registros
await repository.addAll([task1, task2, task3]);

// Atualizar múltiplos registros
await repository.updateAll([updatedTask1, updatedTask2]);

// Deletar múltiplos registros por ID
await repository.deleteAll(['id-1', 'id-2']);
```

---

### 4. Monitoramento de Status e Falhas (`SyncWrapper`)
A lista emitida por `watchAll()` e `getAll()` fornece o objeto encapsulado em `SyncWrapper<T>`:

```dart
final wrapper = tasks.first;

print(wrapper.item.title);     // O modelo T original
print(wrapper.isPending);       // true se aguarda envio para a nuvem
print(wrapper.isSynced);        // true se está 100% sincronizado com a nuvem
print(wrapper.isFailed);        // true se a última tentativa falhou por erro de negócio/lógico
print(wrapper.lastError);       // Mensagem detalhada da falha (ex: HTTP 400 ou validação)
```

---

### 5. Isolamento por Usuário ou Empresa (Multi-Tenant)
Você pode particionar o armazenamento local dinamicamente no nome da tabela:

```dart
class ProjectRepository extends EasyOfflineRepository<ProjectEntity> {
  ProjectRepository({
    required String enterpriseId,
    required super.remoteService,
  }) : super(
          // Cada empresa possui seu arquivo JSON e cache totalmente isolados
          tableName: 'projects_$enterpriseId',
          fromJson: ProjectEntity.fromJson,
        );
}
```

---

### 6. Testes Unitários Simples
Você pode inicializar o repositório apontando para diretórios temporários (`Directory.systemTemp`) para testes de unidade rápidos sem necessidade de mocks de plugins nativos:

```dart
test('Repository salva e recupera dados em teste unitário', () async {
  final tempDir = await Directory.systemTemp.createTemp('repo_test_');
  final repository = TaskRepository(remoteService: mockService);
  
  await repository.initialize(customPath: tempDir.path);
  await repository.add(TaskEntity(title: 'Test'));
  
  final items = await repository.getAll();
  expect(items.length, 1);
  
  await tempDir.delete(recursive: true);
});
```

---

## 📚 Tabela de Métodos do `EasyOfflineRepository<T>`

| Método | Retorno | Descrição |
| :--- | :--- | :--- |
| `initialize({String? customPath})` | `Future<void>` | Carrega o arquivo JSON do disco para a memória no startup. |
| `getAll()` | `Future<List<SyncWrapper<T>>>` | Retorna todos os itens locais não deletados. |
| `getById(String id)` | `Future<SyncWrapper<T>?>` | Retorna o wrapper de um item pelo seu ID. |
| `watchAll()` | `Stream<List<SyncWrapper<T>>>` | Stream reativa emitida a cada inclusão, edição, deleção ou sync. |
| `add(T item)` | `Future<void>` | Salva localmente em microssegundos e dispara auto-sync em background. |
| `addAll(List<T> items)` | `Future<void>` | Inclusão em lote com persistência e notificação única. |
| `update(T item)` | `Future<void>` | Atualiza localmente e dispara auto-sync em background. |
| `updateAll(List<T> items)` | `Future<void>` | Atualização em lote com persistência e notificação única. |
| `delete(String id)` | `Future<void>` | Marca para remoção e sincroniza deleção no servidor. |
| `deleteAll(List<String> ids)` | `Future<void>` | Remoção em lote. |
| `sync()` | `Future<void>` | Executa ciclo completo de PULL + PUSH com proteção contra reentrância. |
| `clearLocal()` | `Future<void>` | Limpa a tabela em memória e exclui o arquivo do disco. |
| `dispose()` | `void` | Fecha os controllers de Stream e libera recursos da tabela. |

---

## 📄 Licença

Distribuído sob a licença MIT. Consulte `LICENSE` para obter mais informações.
