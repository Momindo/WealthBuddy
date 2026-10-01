// Widget tests: first launch (privacy pop-up, picking a project) and adding money from the projects list.
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
    await tester.pumpWidget(ProviderScope(overrides: [storeProvider.overrideWithValue(MemoryStore()), reminderProvider.overrideWithValue(null), lockProvider.overrideWithValue(null)], child: const WealthBuddyApp()));
    await tester.pumpAndSettle();
    expect(find.text('Your money stays yours'), findsOneWidget); // first-launch privacy pop-up
    await tester.tap(find.text('Got it'));
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

  testWidgets('add a bonus from the projects list', (tester) async {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final store = MemoryStore()
      ..saved = AppData(
        money: Money(income: 20000, spending: 12000, savings: 5000, repayments: 0, cardDebt: 0, family: false, variable: false),
        projects: [
          Project(id: 1, type: 'car', name: 'Family SUV', cost: 120000, target: '2099-01', contributions: [
            Contribution(amount: 10000, source: 'Set aside at start', date: '2026-10-01'),
          ]),
        ],
        settings: Settings(privacySeen: true),
      );
    await tester.pumpWidget(ProviderScope(overrides: [storeProvider.overrideWithValue(store), reminderProvider.overrideWithValue(null), lockProvider.overrideWithValue(null)], child: const WealthBuddyApp()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Add money'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('AED 10,000 of AED 120,000'), findsOneWidget);

    await tester.tap(find.text('Add money'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '25000');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add AED 25,000'));
    await tester.tap(find.text('Add AED 25,000'));
    await tester.pumpAndSettle();

    expect(find.textContaining('AED 35,000 of AED 120,000'), findsOneWidget);
    expect(store.saved!.projects.first.contributions.last.source, 'Bonus');
  });
}
