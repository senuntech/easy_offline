# CHANGELOG

## 1.1.0

- **Persistência Atômica (Atomic File Write):** Implementada gravação atômica em disco via arquivo temporário (`.tmp`) e renomeação atômica, eliminando riscos de arquivos JSON corrompidos caso o app feche durante I/O.
- **I/O Debouncing:** Agrupamento de escritas consecutivas no disco em buffer com temporizador configurável (`debounceDuration`, padrão 150ms), prevenindo tempestade de I/O em loops de inserção e edição.
- **Mutex de Sincronização & Fila Reentrante:** Proteção completa contra chamadas concorrentes a `sync()`, garantindo que múltiplos disparos paralelos aguardem a finalização do ciclo atual e processem novidades em fila sequencial.
- **Estratégias de Pull (`PullPolicy`):**
  - `PullPolicy.incremental` (novo padrão seguro): atualiza existentes e insere novos registros sem apagar registros locais não contidos no payload (totalmente compatível com paginação e endpoints delta).
  - `PullPolicy.fullMirror`: espelho estrito que remove registros locais ausentes no servidor.
- **Resolução de Conflitos (`ConflictPolicy`):**
  - `ConflictPolicy.newestWins` (padrão): o registro com `updatedAt` mais recente prevalece.
  - `ConflictPolicy.clientWins`, `ConflictPolicy.serverWins` e `ConflictPolicy.custom` com `ConflictResolver<T>`.
- **Operações em Lote (Batch):** Adicionados os métodos `addAll()`, `updateAll()` e `deleteAll()`, notificando a UI e persistindo uma única vez.
- **Classificação Robusta de Falhas:** Distinção entre erros de rede transitórios (offline, timeouts) que permanecem `SyncStatus.pending` e erros de negócio/lógicos (HTTP 4xx, validações de payload) que são marcados como `SyncStatus.failed` com a mensagem em `SyncWrapper.lastError`.
- **Prevenção de Race Conditions:** Proteção estrita contra sobrescrita de exclusões locais em trânsito e recuperação automática de `.tmp` órfão na inicialização.
- **Gestão de Ciclo de Vida e Testes:** Adicionados métodos `clearTable()`, `disposeTable()`, `clearLocal()`, `dispose()` e suporte completo a testes unitários via diretórios temporários.
- **Suite de Testes Automatizados:** 28 testes unitários abrangentes cobrindo integridade de I/O, concorrência, recuperação de falhas, batch operations e resolução de conflitos.

## 1.0.0

- Versão inicial do pacote `easy_offline`.
- Adicionada a abstração `EasyOfflineRepository<T, ID>` para gerenciamento reativo e transparente de dados locais e remotos (Offline-First).
- Adicionada a classe `LocalStore<T, ID>` com suporte a persistência chave-valor JSON assíncrona baseada em arquivos (`path_provider`).
- Suporte a sincronização bidirecional, operações pontuais (`save`, `getById`, `getAll`, `delete`) e fluxos em tempo real (`watchAll`, `watchById`).
- Suporte a gerenciamento de dependências com desacoplamento através de `RemoteService<T, ID>`.
- Adicionado projeto de exemplo completo (`example/`) demonstrando integração em tela Flutter com CRUD e simulação de instabilidade de rede.
