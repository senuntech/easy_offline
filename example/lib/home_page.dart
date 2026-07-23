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
  final TextEditingController _taskController = TextEditingController();
  bool _isSyncing = false;

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  void _addTask() async {
    final text = _taskController.text.trim();
    if (text.isEmpty) return;

    _taskController.clear();
    final newTask = TaskModel(title: text);
    await widget.repository.add(newTask);
  }

  void _toggleTask(TaskModel task) async {
    final updated = task.copyWith(isCompleted: !task.isCompleted);
    await widget.repository.update(updated);
  }

  void _deleteTask(String id) async {
    await widget.repository.delete(id);
  }

  void _manualSync() async {
    setState(() => _isSyncing = true);
    await widget.repository.sync();
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sincronização concluída!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _toggleOnlineState() {
    setState(() {
      widget.repository.mockService.toggleOnlineState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = widget.repository.mockService.isOnline;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Easy Offline TodoList'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sincronizar Manualmente',
            onPressed: _isSyncing ? null : _manualSync,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de Status da Conexão Simulada
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isOnline ? Colors.green.shade100 : Colors.orange.shade100,
            child: Row(
              children: [
                Icon(
                  isOnline ? Icons.wifi : Icons.wifi_off,
                  color: isOnline ? Colors.green.shade800 : Colors.orange.shade800,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isOnline ? 'Modo Online (Sincroniza com servidor)' : 'Modo Offline (Salva localmente)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOnline ? Colors.green.shade900 : Colors.orange.shade900,
                    ),
                  ),
                ),
                Switch(
                  value: isOnline,
                  onChanged: (_) => _toggleOnlineState(),
                  activeThumbColor: Colors.green,
                ),
              ],
            ),
          ),
          
          // Form para adicionar nova tarefa
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taskController,
                    decoration: const InputDecoration(
                      hintText: 'Digite o título da tarefa...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addTask(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _addTask,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Lista Reativa em Tempo Real via Stream
          Expanded(
            child: StreamBuilder<List<SyncWrapper<TaskModel>>>(
              stream: widget.repository.watchAll(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items = snapshot.data ?? [];

                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nenhuma tarefa cadastrada.\nAdicione uma tarefa acima!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final wrapper = items[index];
                    final task = wrapper.item;

                    return ListTile(
                      leading: Checkbox(
                        value: task.isCompleted,
                        onChanged: (_) => _toggleTask(task),
                      ),
                      title: Text(
                        task.title,
                        style: TextStyle(
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        'ID: ${task.id.substring(0, 8)}... | Op: ${wrapper.operation.name}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Chip(
                            avatar: Icon(
                              wrapper.isPending ? Icons.cloud_upload : Icons.cloud_done,
                              size: 14,
                              color: wrapper.isPending ? Colors.orange.shade800 : Colors.green.shade800,
                            ),
                            label: Text(
                              wrapper.isPending ? 'Pendente' : 'Sincronizado',
                              style: TextStyle(
                                fontSize: 11,
                                color: wrapper.isPending ? Colors.orange.shade900 : Colors.green.shade900,
                              ),
                            ),
                            backgroundColor: wrapper.isPending ? Colors.orange.shade50 : Colors.green.shade50,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deleteTask(task.id),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
