import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/state.dart';
import 'ui/invest_screen.dart';
import 'ui/overview_screen.dart';
import 'ui/setup_screen.dart';
import 'ui/spending_screen.dart';
import 'ui/suggestions_screen.dart';
import 'ui/wealth_screen.dart';
import 'ui/welcome_screen.dart';
import 'ui/widgets.dart';

void main() => runApp(const ProviderScope(child: WealthBuddyApp()));

class WealthBuddyApp extends StatelessWidget {
  const WealthBuddyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Wealth Buddy',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const _Root(),
      );
}

class _Root extends ConsumerWidget {
  const _Root();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(appProvider);
    if (!model.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (model.data == null) return const WelcomeScreen();
    final setupStep = ref.watch(showSetupProvider);
    if (setupStep != null) return SetupScreen(initialStep: setupStep);
    return const Shell();
  }
}

class Shell extends ConsumerWidget {
  const Shell({super.key});
  static const _pages = [OverviewScreen(), SpendingScreen(), WealthScreen(), InvestScreen(), SuggestionsScreen()];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = ref.watch(tabProvider);
    final f = ref.watch(financeProvider);
    final urgent = f?.suggestions.where((s) => s.sev == 'bad').length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text.rich(TextSpan(children: [
          TextSpan(text: 'Wealth', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: 'Buddy', style: TextStyle(fontWeight: FontWeight.w700, color: gold)),
        ])),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tag(f?.s.example == true ? 'Example data' : 'On this phone only', tone: f?.s.example == true ? Tone.gold : Tone.accent),
          ),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: i, children: _pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => ref.read(tabProvider.notifier).state = v,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Overview'),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Spending'),
          const NavigationDestination(icon: Icon(Icons.account_balance_outlined), selectedIcon: Icon(Icons.account_balance), label: 'Wealth'),
          const NavigationDestination(icon: Icon(Icons.trending_up), label: 'Invest'),
          NavigationDestination(
            icon: Badge(isLabelVisible: urgent > 0, label: Text('$urgent'), child: const Icon(Icons.lightbulb_outline)),
            selectedIcon: const Icon(Icons.lightbulb),
            label: 'Suggestions',
          ),
        ],
      ),
    );
  }
}
