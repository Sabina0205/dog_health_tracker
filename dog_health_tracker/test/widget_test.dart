// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:dog_health_tracker/main.dart';

void main() {
  testWidgets('Shows onboarding choices on first start', (
    WidgetTester tester,
  ) async {
    const storageChannel = MethodChannel('pet_health/storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async {
      if (call.method == 'loadState') {
        return null;
      }
      return true;
    });

    await tester.pumpWidget(const DogHealthTrackerApp());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Mám šteniatko'), findsOneWidget);
    expect(find.text('Mám dospelého psa'), findsOneWidget);
  });
}
