import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zcode_app/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ZcodeApp());

    // 等待至少一帧
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
