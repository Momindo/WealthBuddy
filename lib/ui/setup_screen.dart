// "Set up your month": salary, home and regular costs. Every step can be skipped.
// Entries become repeating rules tagged with a setup key, so re-running setup replaces them.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/basics.dart';
import '../domain/finance.dart';
import '../domain/models.dart';
import '../domain/recurring.dart';
import 'widgets.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key, this.initialStep = 0});
  final int initialStep;
  @override
  ConsumerState<SetupScreen> createState() => _SetupState();
}

class _CostDraft {
  bool on;
  final TextEditingController amount, balance;
  _CostDraft(this.on, String a) : amount = TextEditingController(text: a), balance = TextEditingController();
}

class _SetupState extends ConsumerState<SetupScreen> {
  late int step = widget.initialStep;
  final salary = TextEditingController(), payday = TextEditingController(text: '25');
  final rent = TextEditingController(), mortBal = TextEditingController(), mortRate = TextEditingController();
  String housing = 'rent', rentFreq = 'yearly', rentMethod = 'cheque';
  int cheques = 4;
  final costs = <String, _CostDraft>{};
  String? err;

  @override
  void initState() {
    super.initState();
    final s = ref.read(appProvider).data!;
    RecurringRule? find(String k) {
      for (final r in s.recurring) {
        if (r.setupKey == k) return r;
      }
      return null;
    }

    final sal = find('salary'), home = find('home');
    if (sal != null) {
      salary.text = fmtPlain(sal.amount);
      payday.text = sal.start.substring(8, 10);
    }
    if (home != null) {
      housing = home.merchant.toLowerCase().contains('mortgage') ? 'mortgage' : 'rent';
      rent.text = fmtPlain(home.amount);
      rentFreq = home.freq;
      rentMethod = home.method;
      cheques = home.cheques ?? 4;
    }
    for (final c in setupCosts) {
      final r = find(c.key);
      costs[c.key] = _CostDraft(r != null || (c.key == 'school' && (s.profile.kids ?? 0) > 0), r == null ? '' : fmtPlain(r.amount));
    }
  }

  String fmtPlain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  double? parseNum(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim());

  void _finish() => ref.read(showSetupProvider.notifier).state = null;

  bool _save() {
    final ctl = ref.read(appProvider.notifier), today = todayIso();
    if (step == 0) {
      final a = parseNum(salary);
      if (a == null || a <= 0) return _fail('Enter your monthly take-home pay, or skip this step.');
      final day = (int.tryParse(payday.text) ?? 1).clamp(1, 31);
      ctl.update((s) {
        upsertRule(s, 'salary', RecurringRule(id: 0, merchant: 'Salary', cat: 'Income', amount: a, sign: 1, method: 'transfer', freq: 'monthly', start: monthStart(today, day)));
        s.setup['salary'] = 'done';
      });
    } else if (step == 1) {
      if (housing == 'free') {
        ctl.update((s) {
          upsertRule(s, 'home', null);
          upsertDebt(s, 'home', null);
          s.setup['housing'] = 'done';
        });
      } else {
        final a = parseNum(rent);
        if (a == null || a <= 0) return _fail(housing == 'rent' ? 'Enter what you pay in rent, or skip this step.' : 'Enter your monthly mortgage instalment, or skip this step.');
        ctl.update((s) {
          if (housing == 'rent') {
            upsertRule(s, 'home', RecurringRule(id: 0, merchant: 'Rent', cat: 'Rent', amount: a, sign: -1, method: rentMethod, freq: rentFreq,
                cheques: rentFreq == 'yearly' ? cheques : null, start: monthStart(today)));
            upsertDebt(s, 'home', null);
          } else {
            upsertRule(s, 'home', RecurringRule(id: 0, merchant: 'Mortgage instalment', cat: 'Rent', amount: a, sign: -1, method: 'transfer', freq: 'monthly', start: monthStart(today)));
            final bal = parseNum(mortBal);
            upsertDebt(s, 'home', bal != null && bal > 0 ? Liability(id: 0, name: 'Mortgage', type: 'loan', amount: bal, rate: parseNum(mortRate) ?? 0, monthly: a) : null);
          }
          s.setup['housing'] = 'done';
        });
      }
    } else if (step == 2) {
      for (final c in setupCosts) {
        final d = costs[c.key]!;
        if (d.on && ((parseNum(d.amount) ?? 0) <= 0)) return _fail('Enter an amount for ${c.label.toLowerCase()}, or untick it.');
      }
      ctl.update((s) {
        for (final c in setupCosts) {
          final d = costs[c.key]!;
          if (!d.on) {
            upsertRule(s, c.key, null);
            if (c.debt) upsertDebt(s, c.key, null);
            continue;
          }
          final a = parseNum(d.amount)!;
          upsertRule(s, c.key, RecurringRule(id: 0, merchant: c.label, cat: c.cat, amount: a, sign: -1, method: c.method, freq: c.freq,
              cheques: c.freq == 'yearly' ? c.cheques : null, start: monthStart(today)));
          if (c.debt) {
            final bal = parseNum(d.balance);
            upsertDebt(s, c.key, bal != null && bal > 0 ? Liability(id: 0, name: 'Car loan', type: 'loan', amount: bal, monthly: a) : null);
          }
        }
        s.setup['costs'] = 'done';
      });
    }
    err = null;
    return true;
  }

  bool _fail(String m) {
    setState(() => err = m);
    return false;
  }

  void _skip() {
    const keys = ['salary', 'housing', 'costs'];
    ref.read(appProvider.notifier).update((s) => s.setup[keys[step]] ??= 'skipped');
    setState(() {
      err = null;
      step++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(financeProvider)!;
    final t = Theme.of(context).textTheme;
    const steps = ['Salary', 'Home', 'Regular costs', 'Done'];
    final dots = Row(children: [
      for (var i = 0; i < 4; i++)
        Container(
            margin: const EdgeInsets.only(right: 6),
            height: 6,
            width: i == step ? 28 : 14,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: i <= step ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant)),
      const SizedBox(width: 4),
      Text(steps[step], style: t.bodySmall),
      const Spacer(),
      if (step < 3) TextButton(onPressed: _finish, child: const Text('Finish later')),
    ]);

    Widget nav([String primary = 'Save and continue']) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(err!, style: TextStyle(color: toneColor(context, Tone.bad)))),
          FilledButton(onPressed: () {
            if (_save()) setState(() => step++);
          }, child: Padding(padding: const EdgeInsets.all(12), child: Text(primary))),
          Row(children: [
            if (step > 0) TextButton(onPressed: () => setState(() {
                  err = null;
                  step--;
                }), child: const Text('Back')),
            const Spacer(),
            TextButton(onPressed: _skip, child: const Text('Skip this step')),
          ]),
        ]);

    final inc = f.income?.v ?? parseNum(salary);
    final body = <Widget>[];
    if (step == 0) {
      body.addAll([
        Text('What lands in your account each month?', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const Text('Your take-home pay, after any deductions. It drives your budget, investing amount and project checks.'),
        Row(children: [
          Expanded(flex: 3, child: TextField(controller: salary, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Monthly salary (AED)'))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: TextField(controller: payday, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Paid on day'))),
        ]),
        note(context, "Only the amount is kept, on this phone. If you'd rather not say, skip it: a salary SMS or statement sets it later."),
        nav(),
      ]);
    } else if (step == 1) {
      final r = f.benchRange('Rent');
      final mult = rentFreq == 'yearly' ? 12 : 1;
      body.addAll([
        Text('How do you pay for your home?', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'rent', label: Text('I rent')), ButtonSegment(value: 'mortgage', label: Text('Mortgage')), ButtonSegment(value: 'free', label: Text('No cost'))],
          selected: {housing},
          onSelectionChanged: (v) => setState(() {
            housing = v.first;
            if (housing == 'mortgage') rentFreq = 'monthly';
            err = null;
          }),
        ),
        if (housing == 'rent') ...[
          SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'yearly', label: Text('Yearly')), ButtonSegment(value: 'monthly', label: Text('Monthly'))],
              selected: {rentFreq},
              onSelectionChanged: (v) => setState(() => rentFreq = v.first)),
          TextField(controller: rent, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: '${rentFreq == 'yearly' ? 'Yearly' : 'Monthly'} rent (AED)')),
          if (inc != null && r != null) note(context, 'Typical for your household: ${aed(inc * r.lo / 100 * mult)}–${fmt(inc * r.hi / 100 * mult)} ${rentFreq == 'yearly' ? 'a year' : 'a month'}.'),
          if (rentFreq == 'yearly') ...[
            const Text('Paid in how many cheques?'),
            Choice<int>(options: const [1, 2, 4, 6, 12], selected: cheques, onSelected: (v) => setState(() => cheques = v)),
          ],
          const Text('Paid with'),
          Choice<String>(options: paymentMethods.keys.toList(), selected: rentMethod, labels: (k) => paymentMethods[k]!, onSelected: (v) => setState(() => rentMethod = v)),
        ],
        if (housing == 'mortgage') ...[
          TextField(controller: rent, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Monthly instalment (AED)')),
          Row(children: [
            Expanded(child: TextField(controller: mortBal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount left (optional)'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: mortRate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Rate % (optional)'))),
          ]),
          note(context, 'The balance goes into your debts, so net worth and the debt-burden check include it.'),
        ],
        if (housing == 'free') note(context, 'Company or family housing. Nothing to add.'),
        nav(),
      ]);
    } else if (step == 2) {
      body.addAll([
        Text('Any other regular costs?', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const Text('Tick what applies. Rough amounts are fine; you can change them later.'),
        for (final c in setupCosts) _costRow(context, f, c, inc),
        nav('Save and finish'),
      ]);
    } else {
      final fixed = -f.txIn(f.latestMonth).where((x) => x.rid != null && x.amount < 0).fold<double>(0, (a, x) => a + x.amount);
      final income = f.income;
      body.addAll([
        Text('Your month is set up', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        Section(children: [
          Row2('Income', income == null ? 'Not set' : aed(income.v)),
          Row2('Fixed costs', '− ${fmt(fixed)}'),
          if (income != null) Row2('Left for everything else', aed(income.v - fixed), bold: true),
        ]),
        const Text('These repeat every month automatically. Next, add what you spend day to day: import a statement, paste bank SMS, or add cash spending by hand.'),
        FilledButton(onPressed: () {
          ref.read(tabProvider.notifier).state = 1;
          _finish();
        }, child: const Padding(padding: EdgeInsets.all(12), child: Text('Add day-to-day spending'))),
        OutlinedButton(onPressed: () {
          ref.read(tabProvider.notifier).state = 0;
          _finish();
        }, child: const Padding(padding: EdgeInsets.all(12), child: Text('Go to overview'))),
      ]);
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
          dots,
          const SizedBox(height: 12),
          for (final w in body) Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
        ]),
      ),
    );
  }

  Widget _costRow(BuildContext context, Finance f, SetupCost c, double? inc) {
    final d = costs[c.key]!;
    String? typical;
    if (inc != null && c.bench != null) {
      final r = f.benchRange(c.bench!);
      if (r != null) {
        final lo = inc * r.lo / 100 * c.share, hi = inc * r.hi / 100 * c.share;
        typical = c.freq == 'yearly' ? 'Typical for your household: ${aed(lo * 12)}–${fmt(hi * 12)} a year' : 'Typical for your household: ${aed(lo)}–${fmt(hi)} a month';
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: d.on,
        onChanged: (v) => setState(() {
          d.on = v ?? false;
          err = null;
        }),
        title: Text(c.label),
        secondary: Text(c.freq == 'yearly' ? 'Yearly' : 'Monthly', style: Theme.of(context).textTheme.bodySmall),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      if (d.on) ...[
        Row(children: [
          Expanded(child: TextField(controller: d.amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: '${c.hint} (AED)'))),
          if (c.debt) ...[
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: d.balance, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Left on loan (optional)'))),
          ],
        ]),
        if (typical != null) Padding(padding: const EdgeInsets.only(top: 4), child: note(context, typical)),
      ],
    ]);
  }
}
