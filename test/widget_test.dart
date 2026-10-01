// Smoke test: the home screen lists project types, and picking one starts the questions.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_buddy/app/state.dart';
import 'package:wealth_buddy/data/encrypted_store.dart';
import 'package:wealth_buddy/domain/models.dart';
import 'package:wealth_buddy/main.dart';

class MemoryStore extends EncryptedStore {
  AppData? saved;
  @override
  Future<AppData?> load() async => saved;
  @override
  Future<void> save(AppData d) async => saved = d.copy();
  @override
  Future<void> wipe() async => saved = null;
}

void main() {
  testWidgets('pick a car, answer the first question', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [storeProvider.overrideWithValue(MemoryStore())], child: const WealthBuddyApp()));
    await tester.pumpAndSettle();
    expect(find.text('What are you planning?'), findsOneWidget);

    await tester.tap(find.text('Car'));
    await tester.pumpAndSettle();
    expect(find.text('How much will the car cost?'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '60000');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('When do you want it?'), findsOneWidget);
  });
}
