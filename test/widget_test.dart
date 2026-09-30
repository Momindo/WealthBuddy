// Smoke test: the app starts on the welcome screen when there's no saved data,
// and "Explore with example data" opens the tabs with the example household.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_buddy/app/state.dart';
import 'package:wealth_buddy/data/encrypted_store.dart';
import 'package:wealth_buddy/domain/models.dart';
import 'package:wealth_buddy/main.dart';

class MemoryStore extends EncryptedStore {
  AppState? saved;
  @override
  Future<AppState?> load() async => saved;
  @override
  Future<void> save(AppState s) async => saved = s.copy();
  @override
  Future<void> wipe() async => saved = null;
}

void main() {
  testWidgets('first launch shows the welcome screen, then the example opens the tabs', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [storeProvider.overrideWithValue(MemoryStore())], child: const WealthBuddyApp()));
    await tester.pumpAndSettle();
    expect(find.text('Start tracking'), findsOneWidget);

    final explore = find.text('Explore with example data');
    await tester.scrollUntilVisible(explore, 200);
    await tester.tap(explore);
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Example data'), findsOneWidget);
  });
}
