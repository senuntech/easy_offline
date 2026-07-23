import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';
import 'package:example/mock_remote_service.dart';
import 'package:example/task_repository.dart';

void main() {
  testWidgets('Renders Easy Offline TodoList smoke test', (WidgetTester tester) async {
    final mockService = MockRemoteService();
    final repository = TaskRepository(mockService: mockService);
    await repository.initialize();

    await tester.pumpWidget(MyApp(repository: repository));

    expect(find.text('Easy Offline TodoList'), findsOneWidget);
  });
}
