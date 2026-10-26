import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_accessibility_assistant/main.dart';
import 'package:ava_accessibility_assistant/ava_theme.dart';
import 'package:ava_accessibility_assistant/text_translation_screen.dart';

void main() {
  testWidgets('Ava opens on a clear, light sign-in screen', (tester) async {
    await tester.pumpWidget(const AvaApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Welcome to Ava'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    final context = tester.element(find.text('Welcome to Ava'));
    expect(Theme.of(context).brightness, Brightness.light);
    expect(Theme.of(context).colorScheme.primary, AvaColors.primary);
  });

  testWidgets('Create account reveals confirmation fields', (tester) async {
    await tester.pumpWidget(const AvaApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('New to Ava? Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Create your Ava account'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('Message translation offers Indian regional languages', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TextTranslationScreen()));

    expect(find.text('Translate a message'), findsOneWidget);
    expect(find.text('Message to translate'), findsOneWidget);

    final sourcePicker = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).first,
    );
    final languageCodes = sourcePicker.items!.map((item) => item.value);
    expect(languageCodes, contains('ml'));
    expect(languageCodes, contains('ta'));
    expect(languageCodes, contains('te'));
  });
}
