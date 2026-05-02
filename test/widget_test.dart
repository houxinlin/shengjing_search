import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shengjing_search/main.dart';

void main() {
  testWidgets('Search page smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('圣经搜索'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
  });
}
