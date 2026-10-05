// Widget tests: first launch (privacy pop-up, picking a project) and adding money from the projects list.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_buddy/app/state.dart';
import 'package:wealth_buddy/data/encrypted_store.dart';
import 'package:wealth_buddy/domain/format.dart';
import 'package:wealth_buddy/domain/models.dart';
import 'package:wealth_buddy/main.dart';
import 'package:wealth_buddy/ui/widgets.dart';

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
    final store = MemoryStore();
    await tester.pumpWidget(ProviderScope(overrides: [storeProvider.overrideWithValue(store), reminderProvider.overrideWithValue(null), lockProvider.overrideWithValue(null)], child: const WealthBuddyApp()));
    await tester.pumpAndSettle();
    expect(find.text('Your money stays yours'), findsOneWidget); // first-launch privacy pop-up
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Can I afford it?'), findsOneWidget); // the feature tour follows the privacy pop-up
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(store.saved!.settings.tourSeen, isTrue);
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
        settings: Settings(privacySeen: true, tourSeen: true),
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

  testWidgets('what if: try the smallest fix', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final store = MemoryStore()
      ..saved = AppData(
        money: Money(income: 20000, spending: 12000, savings: 5000, repayments: 0, cardDebt: 0, family: false, variable: false),
        projects: [Project(id: 1, type: 'car', name: 'Family SUV', cost: 120000, target: addMonths(monthKey(todayIso()), 12))],
        settings: Settings(privacySeen: true, tourSeen: true),
      );
    await tester.pumpWidget(ProviderScope(overrides: [storeProvider.overrideWithValue(store), reminderProvider.overrideWithValue(null), lockProvider.overrideWithValue(null)], child: const WealthBuddyApp()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('What if…'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('What if…'));
    await tester.pumpAndSettle();
    expect(find.text('Take-home pay'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Try it').first, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Try it').first);
    await tester.pumpAndSettle();
    expect(find.text('Everything is on time.'), findsOneWidget);
    expect(store.saved!.money.spending, 12000); // nothing saved until "Keep"
  });

  testWidgets('home: payday card and a new project from the sheet', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final today = todayIso();
    final store = MemoryStore()
      ..saved = AppData(
        money: Money(income: 20000, spending: 12000, savings: 5000, repayments: 0, cardDebt: 0, family: false, variable: false, payday: int.parse(today.substring(8, 10))),
        projects: [Project(id: 1, type: 'car', name: 'Family SUV', cost: 120000, target: addMonths(monthKey(today), 24))],
        settings: Settings(privacySeen: true, tourSeen: true),
      );
    await tester.pumpWidget(ProviderScope(overrides: [storeProvider.overrideWithValue(store), reminderProvider.overrideWithValue(null), lockProvider.overrideWithValue(null)], child: const WealthBuddyApp()));
    await tester.pumpAndSettle();
    expect(find.text('Payday today'), findsOneWidget);
    await tester.tap(find.text('Done ✓'));
    await tester.pumpAndSettle();
    expect(find.text('Payday today'), findsNothing);
    expect(store.saved!.settings.paydayDone, today);

    await tester.scrollUntilVisible(find.text('New project'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Car').last);
    await tester.pumpAndSettle();
    expect(find.text('How much will the car cost?'), findsOneWidget);
  });

  test('amounts format as you type', () {
    String f(String old, String typed) => AmountFormatter().formatEditUpdate(TextEditingValue(text: old), TextEditingValue(text: typed)).text;
    expect(f('', '120000'), '120,000');
    expect(f('', '120k'), '120,000');
    expect(f('', '1.5m'), '1,500,000');
    expect(f('12', '12a'), '12');
    expect(f('', '2500.5'), '2,500.5');
  });

  testWidgets('plan tabs, timeline, and delete with undo', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final store = MemoryStore()
      ..saved = AppData(
        money: Money(income: 20000, spending: 12000, savings: 5000, repayments: 0, cardDebt: 0, family: false, variable: false),
        projects: [Project(id: 1, type: 'car', name: 'Family SUV', cost: 120000, target: addMonths(monthKey(todayIso()), 24))],
        settings: Settings(privacySeen: true, tourSeen: true),
      );
    await tester.pumpWidget(ProviderScope(overrides: [storeProvider.overrideWithValue(store), reminderProvider.overrideWithValue(null), lockProvider.overrideWithValue(null)], child: const WealthBuddyApp()));
    await tester.pumpAndSettle();

    expect(find.text('See details'), findsOneWidget); // the timeline is on home by default
    await tester.tap(find.text('See details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Every project on one line of time'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Family SUV'));
    await tester.pumpAndSettle();
    expect(find.text('Your plan'), findsOneWidget);
    await tester.tap(find.text('Money'));
    await tester.pumpAndSettle();
    expect(find.text('Money set aside'), findsOneWidget);
    expect(find.text('Your plan'), findsNothing);

    await tester.tap(find.byTooltip('Delete project'));
    await tester.pumpAndSettle();
    expect(store.saved!.projects, isEmpty);
    expect(find.text('Family SUV deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.saved!.projects.length, 1);
  });
}
