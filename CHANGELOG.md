# CHANGELOG

## 1.0.0

- Versão inicial do pacote `easy_offline`.
- Adicionada a abstração `EasyOfflineRepository<T, ID>` para gerenciamento reativo e transparente de dados locais e remotos (Offline-First).
- Adicionada a classe `LocalStore<T, ID>` com suporte a persistência chave-valor JSON assíncrona baseada em arquivos (`path_provider`).
- Suporte a sincronização bidirecional, operações pontuais (`save`, `getById`, `getAll`, `delete`) e fluxos em tempo real (`watchAll`, `watchById`).
- Suporte a gerenciamento de dependências com desacoplamento através de `RemoteService<T, ID>`.
- Adicionado projeto de exemplo completo (`example/`) demonstrando integração em tela Flutter com CRUD e simulação de instabilidade de rede.
