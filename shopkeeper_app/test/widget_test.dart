// Basic Flutter widget smoke test for shopkeeper app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shopkeeper_app/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const QPrintApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
