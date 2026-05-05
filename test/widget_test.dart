import 'package:flutter_test/flutter_test.dart';

import 'package:mimicx/main.dart';

void main() {
  testWidgets('App renders home AppBar', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartRetroHidApp());
    expect(find.text('Mimic X'), findsWidgets);
  });
}
