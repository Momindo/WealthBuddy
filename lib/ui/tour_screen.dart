// The feature tour: four swipeable cards shown once after the privacy pop-up, and from Settings → How it works.
// Parallel projects are the showcase (card 2). Illustrations are built from app widgets, not screenshots.
import 'package:flutter/material.dart';

import 'widgets.dart';

class TourScreen extends StatefulWidget {
  const TourScreen({super.key});
  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  final pages = PageController();
  int page = 0;

  static const _cards = [
    (
      'Can I afford it?',
      'Pick a car, a home or a trip and answer a few questions. You get a clear answer: yes or not yet, by when, and what to do first.',
    ),
    (
      'Plan several things at once',
      'Your spare money is split between your projects so everything makes its date. What doesn\'t fit yet waits its turn.',
    ),
    (
      'Payday nudges',
      'On payday at 3 pm, a reminder says what to put aside for each project. A quick monthly check-in keeps the dates honest.',
    ),
    (
      'Try "what if"',
      'Change your pay, spending or dates and watch every plan move. Adding a project shows what it costs the others first.',
    ),
  ];

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void _next() {
    if (page == _cards.length - 1) {
      Navigator.pop(context);
    } else {
      pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final last = page == _cards.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView.builder(
              controller: pages,
              itemCount: _cards.length,
              onPageChanged: (i) => setState(() => page = i),
              itemBuilder: (context, i) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(height: 260, child: Center(child: _illustration(i))),
                  const SizedBox(height: 24),
                  Text(_cards[i].$1, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text(_cards[i].$2, style: t.bodyLarge),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 16, 16),
            child: Row(children: [
              for (var i = 0; i < _cards.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 6),
                  width: i == page ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(color: i == page ? cs.primary : cs.outlineVariant, borderRadius: BorderRadius.circular(4)),
                ),
              const Spacer(),
              if (!last) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip')),
              const SizedBox(width: 4),
              FilledButton(onPressed: _next, child: Text(last ? 'Start planning' : 'Next')),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _illustration(int i) => switch (i) {
        0 => const _AffordArt(),
        1 => const _SplitArt(),
        2 => const _PaydayArt(),
        _ => const _WhatIfArt(),
      };
}

/// A rounded panel the illustrations sit on.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: 320,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );
}

class _AffordArt extends StatelessWidget {
  const _AffordArt();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return _Panel(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          CircleAvatar(radius: 44, backgroundColor: cs.primary.withValues(alpha: 0.12), child: Icon(Icons.directions_car_outlined, size: 48, color: cs.primary)),
          Positioned(
            right: -4,
            bottom: -4,
            child: CircleAvatar(radius: 16, backgroundColor: toneColor(context, Tone.good), child: const Icon(Icons.check, color: Colors.white, size: 20)),
          ),
        ]),
        const SizedBox(height: 14),
        const Tag('On track', tone: Tone.good),
        const SizedBox(height: 8),
        Text('Yes, by Oct 2028', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final (n, s) in [(1, 'Build your safety cushion'), (2, 'Save AED 6,180 a month'), (3, 'Buy the car')])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              CircleAvatar(radius: 10, backgroundColor: cs.primary, child: Text('$n', style: TextStyle(fontSize: 11, color: cs.onPrimary))),
              const SizedBox(width: 8),
              Text(s, style: t.bodyMedium),
            ]),
          ),
      ]),
    );
  }
}

/// The showcase: one month's spare money flowing into the projects saving now, one waiting, all on time.
class _SplitArt extends StatefulWidget {
  const _SplitArt();
  @override
  State<_SplitArt> createState() => _SplitArtState();
}

class _SplitArtState extends State<_SplitArt> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final good = toneColor(context, Tone.good);
    Widget row(IconData icon, String name, String amount, double from, double to, String ready, {bool waiting = false}) => AnimatedBuilder(
          animation: c,
          builder: (context, _) {
            final p = Curves.easeInOut.transform((c.value * 1.4).clamp(0, 1).toDouble());
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(icon, size: 22, color: waiting ? cs.outline : cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                      Text(waiting ? 'waiting' : amount, style: t.bodySmall?.copyWith(color: waiting ? cs.outline : cs.primary, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: waiting ? from : from + (to - from) * p,
                        minHeight: 8,
                        color: waiting ? cs.outline : good,
                        backgroundColor: cs.outlineVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('✓ $ready', style: t.bodySmall?.copyWith(color: good)),
                  ]),
                ),
              ]),
            );
          },
        );
    return _Panel(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(20)),
            child: Text('AED 8,000 spare this month', style: t.labelLarge?.copyWith(color: cs.onPrimary)),
          ),
        ),
        const SizedBox(height: 8),
        Text('SAVING NOW', style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
        row(Icons.flight_takeoff, 'Vacation', '1,250/mo', 0.2, 0.75, 'Oct 2027'),
        row(Icons.directions_car_outlined, 'SUV', '6,180/mo', 0.1, 0.45, 'Jul 2028'),
        const SizedBox(height: 4),
        Text('WAITING · STARTS JUL 2028', style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
        row(Icons.home_outlined, 'Home', '', 0.02, 0.02, 'Jun 2031', waiting: true),
      ]),
    );
  }
}

class _PaydayArt extends StatelessWidget {
  const _PaydayArt();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return _Panel(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x22000000))]),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.notifications_active_outlined, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Payday · 25th, 3 pm', style: t.labelMedium),
                const SizedBox(height: 2),
                Text('Put AED 1,250 for the vacation and AED 6,180 for the SUV today.', style: t.bodyMedium),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Icon(Icons.fact_check_outlined, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('Monthly check-in: what do you have now?', style: t.bodyMedium)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.check_circle_outline, color: toneColor(context, Tone.good)),
          const SizedBox(width: 10),
          Expanded(child: Text('You\'re on plan. Nice.', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        ]),
      ]),
    );
  }
}

class _WhatIfArt extends StatelessWidget {
  const _WhatIfArt();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final good = toneColor(context, Tone.good), warn = toneColor(context, Tone.warn);
    return _Panel(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: Text('Monthly spending', style: t.titleSmall)), Text('AED 11,000', style: t.titleSmall)]),
        const IgnorePointer(child: Slider(value: 0.4, onChanged: null)),
        Row(children: [
          const Icon(Icons.home_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Home: Aug 2029 → Oct 2028', style: t.bodyMedium)),
          Text('↑ 10 mo', style: t.bodyMedium?.copyWith(color: good, fontWeight: FontWeight.w700)),
        ]),
        const Divider(height: 24),
        Text('Adding a wedding:', style: t.labelMedium),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.directions_car_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('SUV: Jul 2028 → May 2029', style: t.bodyMedium)),
          Text('↓ 10 mo', style: t.bodyMedium?.copyWith(color: warn, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}
