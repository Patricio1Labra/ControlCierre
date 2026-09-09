import 'package:flutter_test/flutter_test.dart';

import 'package:control_cierre/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ControlCierreApp());

    // Verify that the app title is displayed
    expect(find.text('Control de Cierre'), findsOneWidget);
  });
}
