import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import 'widgets.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeState();
}

class _WelcomeState extends ConsumerState<WelcomeScreen> {
  int? adults, kids;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget promise(String a, String b) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a, style: t.titleSmall), Text(b, style: t.bodySmall)])),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 32), children: [
          Text('WELCOME', style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Text('See where your money goes. No sign-up.', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Start tracking in seconds. The app learns what it needs from your transactions instead of asking.', style: t.bodyLarge),
          const SizedBox(height: 20),
          promise('No account, no name, no phone number', "Nothing identifies you. There's nothing to log in to."),
          promise('Your data stays on this phone', 'Encrypted on the device. Nothing is uploaded.'),
          promise('Income is detected, not asked', 'From your salary SMS or statement. You can type it in setup, or skip.'),
          const SizedBox(height: 8),
          note(context, "Optional: who's in your household? It sharpens spending comparisons. Just counts, no names."),
          const SizedBox(height: 8),
          Row(children: [const SizedBox(width: 64, child: Text('Adults')), Expanded(child: Choice<int>(options: const [1, 2, 3, 4], selected: adults, onSelected: (v) => setState(() {
                    adults = v;
                    kids ??= 0;
                  }), labels: (v) => v == 4 ? '4+' : '$v'))]),
          const SizedBox(height: 6),
          Row(children: [const SizedBox(width: 64, child: Text('Children')), Expanded(child: Choice<int>(options: const [0, 1, 2, 3, 4], selected: kids, onSelected: (v) => setState(() {
                    kids = v;
                    adults ??= 1;
                  }), labels: (v) => v == 4 ? '4+' : '$v'))]),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              await ref.read(appProvider.notifier).startFresh(adults: adults, kids: kids);
              ref.read(showSetupProvider.notifier).state = 0;
            },
            child: const Padding(padding: EdgeInsets.all(12), child: Text('Start tracking')),
          ),
          const SizedBox(height: 6),
          Center(child: note(context, 'Next: salary, rent and regular costs. About a minute, and every step can be skipped.')),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.read(appProvider.notifier).startExample(),
            child: const Padding(padding: EdgeInsets.all(12), child: Text('Explore with example data')),
          ),
          const SizedBox(height: 16),
          note(context, 'Suggestions are educational and come from fixed rules you can inspect on every card.'),
        ]),
      ),
    );
  }
}
