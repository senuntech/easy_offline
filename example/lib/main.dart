import 'package:flutter/material.dart';
import 'task_repository.dart';
import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final taskRepository = TaskRepository();
  await taskRepository.initialize();

  runApp(EasyOfflineExampleApp(repository: taskRepository));
}

class EasyOfflineExampleApp extends StatelessWidget {
  final TaskRepository repository;

  const EasyOfflineExampleApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Offline Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: HomePage(repository: repository),
    );
  }
}
