import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_accessibility_assistant/main.dart';
import 'package:ava_accessibility_assistant/ava_theme.dart';

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
}
