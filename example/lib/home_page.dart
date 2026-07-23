import 'package:flutter/material.dart';
import 'package:easy_offline/easy_offline.dart';
import 'task_model.dart';
import 'task_repository.dart';

class HomePage extends StatefulWidget {
  final TaskRepository repository;

  const HomePage({super.key, required this.repository});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late bool _isOnline;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _isOnline = widget.repository.isOnline;
  }

  Future<void> _handleManualSync() async {
    setState(() => _isSyncing = true);
    await widget.repository.sync();
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sincronização executada com sucesso!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _toggleNetwork(bool value) {
    setState(() {
      _isOnline = value;
    });
    widget.repository.toggleOnlineState(value);
  }

  void _showAddTaskDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Nova Tarefa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.trim().isNotEmpty) {
                  final task = TaskModel(
                    title: titleController.text.trim(),
                    description: descController.text.trim(),
                  );
                  Navigator.pop(context);
                  await widget.repository.add(task);
                }
              },
              child: const Text('Adicionar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Easy Offline Example'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sincronizar Manualmente',
            onPressed: _isSyncing ? null : _handleManualSync,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de controle da simulação de rede
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _isOnline ? Colors.green.shade50 : Colors.orange.shade50,
            child: Row(
              children: [
                Icon(
                  _isOnline ? Icons.wifi : Icons.wifi_off,
                  color: _isOnline ? Colors.green : Colors.orange.shade800,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isOnline ? 'Conexão Online' : 'Modo Offline Simulado',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _isOnline ? Colors.green.shade900 : Colors.orange.shade900,
                        ),
                      ),
                      Text(
                        _isOnline
                            ? 'Operações serão salvas localmente e enviadas à API.'
                            : 'Operações serão retidas na fila offline (pending).',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isOnline,
                  activeThumbColor: Colors.green,
                  onChanged: _toggleNetwork,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // StreamBuilder reativo ouvindo watchAll()
          Expanded(
            child: StreamBuilder<List<SyncWrapper<TaskModel>>>(
              stream: widget.repository.watchAll(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final wrappers = snapshot.data ?? [];
                final totalCount = wrappers.length;
                final pendingCount = wrappers.where((w) => w.isPending).length;
                final syncedCount = totalCount - pendingCount;

                return Column(
                  children: [
                    // Cards de métricas
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          _buildMetricCard(
                            'Total',
                            totalCount.toString(),
                            Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          _buildMetricCard(
                            'Sincronizados',
                            syncedCount.toString(),
                            Colors.green,
                          ),
                          const SizedBox(width: 8),
                          _buildMetricCard(
                            'Pendentes',
                            pendingCount.toString(),
                            Colors.orange,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Lista de Tarefas
                    Expanded(
                      child: wrappers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.inbox, size: 64, color: Colors.grey),
                                  SizedBox(height: 12),
                                  Text(
                                    'Nenhuma tarefa cadastrada.\nClique no botão + para adicionar.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: wrappers.length,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemBuilder: (context, index) {
                                final wrapper = wrappers[index];
                                final task = wrapper.item;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  child: ListTile(
                                    leading: Checkbox(
                                      value: task.isCompleted,
                                      onChanged: (val) async {
                                        final updated = task.copyWith(
                                          isCompleted: val ?? false,
                                        );
                                        await widget.repository.update(updated);
                                      },
                                    ),
                                    title: Text(
                                      task.title,
                                      style: TextStyle(
                                        decoration: task.isCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (task.description.isNotEmpty)
                                          Text(task.description),
                                        const SizedBox(height: 4),
                                        _buildStatusBadge(wrapper.status),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      onPressed: () async {
                                        await widget.repository.delete(task.id);
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTaskDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nova Tarefa'),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(SyncStatus status) {
    final isSynced = status == SyncStatus.synced;
    final color = isSynced ? Colors.green : Colors.orange;
    final text = isSynced ? 'Sincronizado' : 'Pendente de envio';
    final icon = isSynced ? Icons.cloud_done : Icons.cloud_upload_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
