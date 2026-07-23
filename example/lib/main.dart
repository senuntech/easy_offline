import 'package:flutter/material.dart';
import 'mock_remote_service.dart';
import 'task_repository.dart';
import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final mockService = MockRemoteService();
  final repository = TaskRepository(mockService: mockService);

  // Inicializa a tabela do armazenamento local (carrega cache persistido em disco)
  await repository.initialize();

  runApp(MyApp(repository: repository));
}

class MyApp extends StatelessWidget {
  final TaskRepository repository;

  const MyApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Offline Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: HomePage(repository: repository),
    );
  }
}
