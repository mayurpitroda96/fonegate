import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('Frontend smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FoneGateDashboardApp());
    expect(find.textContaining('FoneGate'), findsWidgets);
  });
}
