// What if: sliders for take-home pay and spending, a want-by stepper per project, and live ready dates.
// Nothing is saved unless the user taps "Keep these changes".
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/format.dart';
import '../domain/whatif.dart';
import 'widgets.dart';

class WhatIfScreen extends ConsumerStatefulWidget {
  const WhatIfScreen({super.key});
  @override
  ConsumerState<WhatIfScreen> createState() => _WhatIfState();
}

class _WhatIfState extends ConsumerState<WhatIfScreen> {
  static const payStep = 500.0, spendStep = 250.0;
  final today = todayIso();
  late double basePay, baseSpend;
  late double pay, spend; // what the plan is run with
  late double payDrag, spendDrag; // what the sliders show while dragging
  final targets = <int, String>{};
  String? _fixKey;
  ({double? spendCut, double? payRise}) _fix = (spendCut: null, payRise: null);

  @override
  void initState() {
    super.initState();
    final m = ref.read(appProvider).data.money;
    basePay = pay = payDrag = m.income ?? 0;
    baseSpend = spend = spendDrag = m.spending ?? 0;
  }

  bool get changed => pay != basePay || spend != baseSpend || targets.isNotEmpty;

  (double, double, int) _range(double base, double step) {
    final lo = roundDown(base * 0.7, step);
    final hi = math.max(lo + step * 4, roundUp(base * 1.3, step));
    return (lo, hi, ((hi - lo) / step).round());
  }

  void _reset() => setState(() {
        pay = payDrag = basePay;
        spend = spendDrag = baseSpend;
        targets.clear();
      });

  Future<void> _keep() async {
    final data = ref.read(appProvider).data;
    final lines = [
      if (pay != basePay) 'Take-home pay ${fmt(basePay)} → ${fmt(pay)}',
      if (spend != baseSpend) 'Monthly spending ${fmt(baseSpend)} → ${fmt(spend)}',
      for (final p in data.projects)
        if (targets[p.id] != null && targets[p.id] != p.target) '${p.name} by ${monthLabel(p.target)} → ${monthLabel(targets[p.id]!)}',
    ];
    if (lines.isEmpty) return;
    if (!await confirm(context, 'Keep these changes?', lines.join('\n'), 'Keep')) return;
    ref.read(appProvider.notifier).update((d) {
      d.money.income = pay;
      d.money.spending = spend;
      for (final p in d.projects) {
        final t = targets[p.id];
        if (t != null) p.target = t;
      }
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appProvider).data;
    final t = Theme.of(context).textTheme;
    final now = assessAll(data, today: today);
    final after = whatIf(data, today: today, income: pay, spending: spend, targets: targets);

    // The smallest fix depends only on the target dates; work it out once per set of dates.
    final key = (targets.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}:${e.value}').join(',');
    if (key != _fixKey) {
      _fixKey = key;
      _fix = smallestFix(data, today: today, targets: targets);
    }

    final (payLo, payHi, payDiv) = _range(basePay, payStep);
    final (spLo, spHi, spDiv) = _range(baseSpend, spendStep);
    String delta(double v, double base) => v == base ? '' : '${v > base ? '+' : '−'}${fmt((v - base).abs())}';

    Widget slider(String label, double value, double base, double lo, double hi, int div, ValueChanged<double> onDrag, ValueChanged<double> onDone) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: t.titleSmall)),
          Text(money(value), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(width: 64, child: Text(delta(value, base), textAlign: TextAlign.end, style: t.bodySmall)),
        ]),
        Slider(value: value.clamp(lo, hi).toDouble(), min: lo, max: hi, divisions: div, label: fmt(value), onChanged: onDrag, onChangeEnd: onDone),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('What if…'),
        actions: [TextButton(onPressed: changed ? _reset : null, child: const Text('Reset'))],
      ),
      body: SafeArea(
        child: ScreenBody(children: [
          note(context, 'Try a different pay, spending or date. Nothing is saved unless you keep it.'),
          slider('Take-home pay', payDrag, basePay, payLo, payHi, payDiv, (v) => setState(() => payDrag = v), (v) => setState(() => pay = payDrag = v)),
          slider('Monthly spending', spendDrag, baseSpend, spLo, spHi, spDiv, (v) => setState(() => spendDrag = v),
              (v) => setState(() => spend = spendDrag = v)),
          Section(title: 'Your projects', children: [
            for (final p in data.projects)
              Builder(builder: (context) {
                final a0 = now[p.id]!, a1 = after[p.id]!;
                final target = targets[p.id] ?? p.target;
                final sh = a1.share;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Icon(kindIcon(p.type), size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p.name, style: t.titleSmall)),
                      Tag(verdictLabel(a1.verdict), tone: verdictTone(a1.verdict)),
                    ]),
                    const SizedBox(height: 4),
                    Text('Ready ${a0.readyLabel} → ${a1.readyLabel} · ${readyChange(a0, a1)}', style: t.bodyMedium),
                    if (sh != null)
                      Text(sh.waiting ? 'Waits for the ${sh.after}' : 'Saving now · ${money(sh.mainAmount)} a month', style: t.bodySmall),
                    Row(children: [
                      Text('Want it by', style: t.bodySmall),
                      IconButton(
                        tooltip: 'A month earlier',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: target.compareTo(earliestTarget(today)) <= 0
                            ? null
                            : () => setState(() => targets[p.id] = addMonths(target, -1)),
                      ),
                      Text(monthLabel(target), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      IconButton(
                        tooltip: 'A month later',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: () => setState(() => targets[p.id] = addMonths(target, 1)),
                      ),
                      if (targets[p.id] != null && targets[p.id] != p.target) Text('was ${monthLabel(p.target)}', style: t.bodySmall),
                    ]),
                  ]),
                );
              }),
          ]),
          if (allOnTime(after))
            Row(children: [
              Icon(Icons.check_circle_outline, color: toneColor(context, Tone.good)),
              const SizedBox(width: 8),
              Expanded(child: Text('Everything is on time.', style: t.bodyMedium)),
            ])
          else if (_fix.spendCut != null || _fix.payRise != null)
            Section(title: 'Smallest change that puts everything on time', children: [
              if (_fix.spendCut != null)
                Row(children: [
                  Expanded(child: Text('Spend ${money(_fix.spendCut!)} less a month', style: t.bodyMedium)),
                  TextButton(
                    onPressed: () => setState(() {
                      spend = spendDrag = baseSpend - _fix.spendCut!;
                      pay = payDrag = basePay;
                    }),
                    child: const Text('Try it'),
                  ),
                ]),
              if (_fix.payRise != null)
                Row(children: [
                  Expanded(child: Text('Or take home ${money(_fix.payRise!)} more', style: t.bodyMedium)),
                  TextButton(
                    onPressed: () => setState(() {
                      pay = payDrag = basePay + _fix.payRise!;
                      spend = spendDrag = baseSpend;
                    }),
                    child: const Text('Try it'),
                  ),
                ]),
              if (_fix.spendCut != null && _fix.payRise != null && _fix.spendCut! < _fix.payRise!)
                note(context, 'Spending less counts for more, because it also shrinks the safety cushion you need first.'),
            ])
          else
            note(context, 'Pay or spending alone (within 30%) can\'t put everything on time. Try moving a date.'),
          FilledButton(onPressed: changed ? _keep : null, child: const Text('Keep these changes')),
        ]),
      ),
    );
  }
}
