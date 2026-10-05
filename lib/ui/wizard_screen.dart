// One question per screen. Project questions first, then the user's money (asked once and reused).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/format.dart';
import '../domain/impact.dart';
import '../domain/models.dart';
import '../domain/whatif.dart';
import 'result_screen.dart';
import 'widgets.dart';

enum WizardMode { create, edit, money }

const startSource = 'Set aside at start';

class WizardScreen extends ConsumerStatefulWidget {
  const WizardScreen.newProject(this.type, {super.key})
      : mode = WizardMode.create,
        projectId = null;
  const WizardScreen.edit(int this.projectId, {super.key})
      : mode = WizardMode.edit,
        type = null;
  const WizardScreen.money({super.key})
      : mode = WizardMode.money,
        type = null,
        projectId = null;

  final WizardMode mode;
  final String? type;
  final int? projectId;

  @override
  ConsumerState<WizardScreen> createState() => _WizardState();
}

class _WizardState extends ConsumerState<WizardScreen> {
  final today = todayIso();
  late Project p;
  late Money m;
  late bool moneyWasComplete;
  bool editMoney = false;
  int i = 0;
  String? err;
  int? whenMonths;
  bool? carriesCard;
  bool? hasSetAside;
  Impact? impact; // what this does to the other projects, shown as a last step when something moves
  String? harmless; // the earliest want-by date that keeps the others on time

  final name = TextEditingController(), cost = TextEditingController(), rate = TextEditingController(), rent = TextEditingController();
  final income = TextEditingController(), spending = TextEditingController(), savings = TextEditingController();
  final repayments = TextEditingController(), card = TextEditingController(), investments = TextEditingController();
  final setAside = TextEditingController();

  String _amt(double? v) => v == null ? '' : fmt(v);
  String _plain(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim());

  @override
  void initState() {
    super.initState();
    final data = ref.read(appProvider).data;
    m = data.money.copy();
    moneyWasComplete = m.complete;
    if (widget.mode == WizardMode.edit) {
      p = data.projects.firstWhere((x) => x.id == widget.projectId).copy();
      whenMonths = monthsUntil(today, p.target).clamp(1, 600);
      name.text = p.name;
      cost.text = _amt(p.cost);
    } else {
      final type = widget.type ?? 'other';
      final k = kindOf(type);
      p = Project(id: data.nextProjectId(), type: type, name: k.label, cost: 0, target: addMonths(monthKey(today), 12),
          downPct: k.minDown > 0 ? k.minDown : 20, rate: k.rate, term: k.term);
    }
    rate.text = _plain(p.rate);
    rent.text = _amt(p.rent);
    income.text = _amt(m.income);
    spending.text = _amt(m.spending);
    savings.text = _amt(m.savings);
    repayments.text = _amt(m.repayments);
    investments.text = _amt(m.investments);
    if (m.cardDebt != null) {
      carriesCard = m.cardDebt! > 0;
      if (carriesCard!) card.text = _amt(m.cardDebt);
    }
  }

  @override
  void dispose() {
    for (final c in [name, cost, rate, rent, income, spending, savings, repayments, card, investments, setAside]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Q> get flow {
    if (widget.mode == WizardMode.money) return moneyQuestions;
    return [
      ...projectQuestions(p, isNew: widget.mode == WizardMode.create),
      ...(moneyWasComplete && !editMoney ? [Q.moneyCheck] : moneyQuestions),
    ];
  }

  ProjectKind get k => kindOf(p.type);

  void _fail(String message) => setState(() => err = message);

  /// Checks and stores one answer. Returns what's wrong, or null.
  String? _apply(Q q) {
    switch (q) {
      case Q.cost:
        final c = _num(cost);
        if (c == null || c <= 0) return 'Enter the cost in AED.';
        p.cost = c;
        p.name = name.text.trim().isEmpty ? k.label : name.text.trim();
      case Q.when:
        if (whenMonths == null) return 'Pick when you want it.';
        p.target = addMonths(monthKey(today), whenMonths!);
      case Q.pay:
        break;
      case Q.loan:
        final r = _num(rate);
        if (r == null || r < 0 || r > 30) return 'Enter the interest rate, for example 3.5.';
        p.rate = r;
      case Q.rent:
        final r = _num(rent);
        if (r == null || r < 0) return 'Enter your monthly rent, or tap "I don\'t pay rent".';
        p.rent = r;
      case Q.setAside:
        if (hasSetAside == null) return 'Choose one.';
        p.contributions.removeWhere((c) => c.source == startSource);
        if (hasSetAside!) {
          final v = _num(setAside);
          if (v == null || v <= 0) return 'Enter how much you\'ve set aside, or choose "Not yet".';
          p.contributions.add(Contribution(amount: v, source: startSource, date: today));
        }
      case Q.income:
        final v = _num(income);
        if (v == null || v <= 0) return 'Enter your monthly take-home pay.';
        m.income = v;
      case Q.payday:
        if (m.payday == null) return 'Pick a day, or "It varies".';
        if (m.payday! > 0 && ref.read(appProvider).data.settings.reminders) ref.read(reminderProvider)?.requestPermission();
      case Q.spending:
        final v = _num(spending);
        if (v == null || v < 0) return 'Enter a rough monthly figure, or tap one of the estimates.';
        m.spending = v;
      case Q.savings:
        final v = _num(savings);
        if (v == null || v < 0) return 'Enter your savings, or tap "None".';
        m.savings = v;
        m.asOf = today; // plans assume they're followed from here
      case Q.repayments:
        final v = _num(repayments);
        if (v == null || v < 0) return 'Enter your monthly loan repayments, or tap "No loans".';
        m.repayments = v;
      case Q.card:
        if (carriesCard == null) return 'Choose one.';
        if (carriesCard!) {
          final v = _num(card);
          if (v == null || v <= 0) return 'Enter roughly how much you owe on cards.';
          m.cardDebt = v;
        } else {
          m.cardDebt = 0;
        }
        m.asOf = today;
      case Q.situation:
        if (m.family == null || m.variable == null) return 'Answer both questions.';
      case Q.investments:
        final v = _num(investments);
        m.investments = (v == null || v <= 0) ? null : v;
      case Q.moneyCheck:
      case Q.payGroup:
      case Q.monthGroup:
      case Q.lifeGroup:
        break;
    }
    return null;
  }

  void _next() {
    final q = flow[i];
    for (final sub in moneyGroups[q] ?? [q]) {
      final e = _apply(sub);
      if (e != null) return _fail(e);
    }
    err = null;
    if (i >= flow.length - 1) {
      if (widget.mode != WizardMode.money && impact == null && _checkImpact()) return;
      _finish();
    } else {
      setState(() => i++);
    }
  }

  void _back() {
    if (i == 0) {
      Navigator.pop(context);
    } else {
      setState(() {
        err = null;
        i--;
      });
    }
  }

  /// Works out what the change does to the other projects. True when something moves, so the impact step shows.
  bool _checkImpact() {
    final saved = ref.read(appProvider).data;
    if (!saved.projects.any((x) => x.id != p.id)) return false;
    final im = impactOf(saved, m, p, today: today);
    if (!im.anyMoves) return false;
    setState(() {
      impact = im;
      harmless = harmlessTarget(saved, m, p, today: today);
    });
    return true;
  }

  void _useDate(String target) {
    final saved = ref.read(appProvider).data;
    setState(() {
      p.target = target;
      whenMonths = monthsUntil(today, target);
      impact = impactOf(saved, m, p, today: today);
      harmless = null;
    });
  }

  Widget _impactView(BuildContext context) {
    final im = impact!;
    final t = Theme.of(context).textTheme;
    final adding = widget.mode == WizardMode.create;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
        title: Text(p.name),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text('YOUR PROJECT · LAST STEP', style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Text('What ${adding ? 'adding' : 'changing'} the ${p.name} does to your other plans', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            for (final o in im.others)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(kindIcon(o.p.type), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o.p.name, style: t.titleSmall),
                      Text('${o.before.readyLabel} → ${o.after.readyLabel} · ${readyChange(o.before, o.after)}',
                          style: t.bodyMedium?.copyWith(color: o.later ? toneColor(context, Tone.warn) : null)),
                      if (o.nowMisses)
                        Text('⚠ misses ${o.after.targetLabel}', style: t.bodySmall?.copyWith(color: toneColor(context, Tone.bad))),
                    ]),
                  ),
                  if (o.before.verdict != o.after.verdict) ...[
                    Tag(verdictLabel(o.before.verdict), tone: Tone.plain),
                    const Icon(Icons.arrow_right_alt, size: 18),
                    Tag(verdictLabel(o.after.verdict), tone: verdictTone(o.after.verdict)),
                  ],
                ]),
              ),
            const Divider(),
            Row(children: [
              Icon(kindIcon(p.type), size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text('${p.name} · ${timingLabel(im.mine)}', style: t.titleSmall)),
            ]),
            if (im.why.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(im.why, style: t.bodyMedium)),
            if (!im.anyMoves)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  Icon(Icons.check_circle_outline, color: toneColor(context, Tone.good)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Nothing else moves now.', style: t.bodyMedium)),
                ]),
              ),
            if (harmless != null)
              Card(
                margin: const EdgeInsets.only(top: 16),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    richBold(context, '**Want the ${p.name} by ${monthLabel(harmless!)} instead?** Then everything else still makes its date.'),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: () => _useDate(harmless!), child: Text('Use ${monthLabel(harmless!)}')),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            TextButton(onPressed: () => setState(() => impact = null), child: const Text('Back')),
            const Spacer(),
            FilledButton(
              onPressed: _finish,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), child: Text(adding ? 'Add it' : 'Save changes')),
            ),
          ]),
        ),
      ),
    );
  }

  void _finish() {
    final moneyOnly = widget.mode == WizardMode.money;
    if (!moneyOnly) {
      // The price is dated when it's first set and whenever the cost or loan terms change.
      final old = ref.read(appProvider).data.projects.where((x) => x.id == p.id).firstOrNull;
      if (old == null || old.cost != p.cost || old.rate != p.rate || old.pay != p.pay || p.priceDate == null) p.priceDate = today;
    }
    ref.read(appProvider.notifier).update((d) {
      d.money = m.copy();
      if (!moneyOnly) {
        final idx = d.projects.indexWhere((x) => x.id == p.id);
        if (idx >= 0) {
          d.projects[idx] = p.copy();
        } else {
          d.projects.add(p.copy());
        }
      }
    },
        why: switch (widget.mode) {
          WizardMode.create => '${p.name} added',
          WizardMode.edit => '${p.name}: answers changed',
          WizardMode.money => 'Money answers updated',
        });
    if (widget.mode == WizardMode.create) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultScreen(projectId: p.id)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (impact != null) return _impactView(context);
    final f = flow;
    if (i >= f.length) i = f.length - 1;
    final q = f[i];
    final inMoney = moneyQuestions.contains(q) || q == Q.moneyCheck;
    final last = i == f.length - 1;
    final t = Theme.of(context).textTheme;
    final (title, sub) = _text(q);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
        title: Text(widget.mode == WizardMode.money ? 'Your money' : p.name),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(4), child: LinearProgressIndicator(value: (i + 1) / f.length)),
      ),
      body: SafeArea(
        child: ListView(
          key: ValueKey(q),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text('${inMoney ? 'YOUR MONEY' : 'YOUR PROJECT'} · ${i + 1} OF ${f.length}', style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(sub, style: t.bodyMedium)),
            const SizedBox(height: 20),
            ..._input(q),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err!, style: TextStyle(color: toneColor(context, Tone.bad)))),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            TextButton(onPressed: _back, child: Text(i == 0 ? 'Cancel' : 'Back')),
            const Spacer(),
            if (q == Q.investments) TextButton(onPressed: () {
              investments.clear();
              _next();
            }, child: const Text('Skip')),
            FilledButton(
              onPressed: _next,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text(last ? (widget.mode == WizardMode.money ? 'Save' : 'See my plan') : 'Next'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  (String, String) _text(Q q) => switch (q) {
        Q.cost => (k.costTitle.isNotEmpty ? k.costTitle : (p.type == 'other' ? 'How much will it cost?' : 'How much will the ${k.noun} cost?'), k.costHint),
        Q.when => (p.type == 'build' ? 'When do you want to start?' : 'When do you want it?', ''),
        Q.pay => ('How do you want to pay?', 'Not sure? Pick savings. The plan will tell you if a ${k.loanName} would help.'),
        Q.loan => ('About the ${k.loanName}', 'Typical values are filled in. Change them if you have a quote.'),
        Q.rent => ('How much rent do you pay now?', 'Per month. It stops once you move in, so it counts in favour of buying.'),
        Q.setAside => (
            'Have you already put money aside for this?',
            'Cash kept just for this ${k.noun}. Leave it out of your general savings so it isn\'t counted twice.'
          ),
        Q.income => ('What do you take home each month?', 'After deductions. Include any regular extra income.'),
        Q.payday => ('Which day is your salary paid?', 'On payday at 3 pm you\'ll get a reminder to put money aside. You can turn it off in Settings.'),
        Q.spending => ('How much do you spend in a month?', 'Rent, bills, food, school fees: everything except loan repayments. A rough figure is fine.'),
        Q.savings => (
            'How much do you have in savings?',
            'Cash you could reach within a few days, in current and savings accounts. Leave out money set aside for a project.'
          ),
        Q.repayments => ('Do you pay any loans each month?', 'Car loan, personal loan or mortgage instalments. Leave out credit cards.'),
        Q.card => ('Do you carry a credit card balance?', 'Money you owe on cards that you don\'t clear in full each month.'),
        Q.situation => ('A bit about your situation', 'This sets how big your safety cushion should be.'),
        Q.investments => ('Any investments you could sell?', 'Optional. Shares, funds, gold or crypto. Only used to suggest options; the plan never relies on them.'),
        Q.moneyCheck => ('Are your money details still right?', 'They\'re shared by all your projects.'),
        Q.payGroup => ('Your pay', 'What arrives each month, and when. Rough figures are fine; you can change them any time.'),
        Q.monthGroup => ('Your month', 'What goes out, and what you have saved. Estimates are fine.'),
        Q.lifeGroup => ('Debts and your situation', 'This sets how big your safety cushion should be.'),
      };

  List<Widget> _input(Q q) {
    switch (q) {
      case Q.cost:
        return [
          _amount(cost, label: 'Cost', autofocus: true),
          const SizedBox(height: 16),
          TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: 'Name (optional)', hintText: k.label)),
        ];
      case Q.when:
        final now = monthKey(today);
        return [
          for (final n in [3, 6, 12, 24, 36, 60])
            _option('In ${durationLabel(n)}', monthLabel(addMonths(now, n)), whenMonths == n, () => setState(() {
                  whenMonths = n;
                  err = null;
                })),
          _option(
              whenMonths != null && ![3, 6, 12, 24, 36, 60].contains(whenMonths) ? monthLabel(addMonths(now, whenMonths!)) : 'Pick a month…',
              'Any month up to 30 years ahead',
              whenMonths != null && ![3, 6, 12, 24, 36, 60].contains(whenMonths),
              _pickMonth),
        ];
      case Q.pay:
        return [
          _option('From my savings', 'Save up and pay in full', p.pay == 'savings', () => setState(() => p.pay = 'savings')),
          _option('With a ${k.loanName}', 'Pay part upfront and the rest monthly', p.pay == 'loan', () => setState(() => p.pay = 'loan')),
        ];
      case Q.loan:
        final downs = <double>[10, 20, 25, 30, 40, 50].where((d) => d >= k.minDown).toList();
        if (p.downPct < k.minDown) p.downPct = k.minDown;
        return [
          if (k.minDown > 0 || p.type != 'other') ...[
            Text('Down payment', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in downs)
                ChoiceChip(label: Text('${num1(d)}%'), selected: p.downPct == d, onSelected: (_) => setState(() => p.downPct = d)),
            ]),
            if (k.minDown > 0) Padding(padding: const EdgeInsets.only(top: 6), child: note(context, 'UAE rules require at least ${num1(k.minDown)}% down.')),
            const SizedBox(height: 20),
          ],
          TextField(
              controller: rate,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Interest rate', suffixText: '% a year')),
          if (k.rateChips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in k.rateChips)
                ChoiceChip(
                    label: Text(r == 0 ? '0% offer' : '${num1(r)}%'),
                    selected: _num(rate) == r,
                    onSelected: (_) => setState(() => rate.text = _plain(r))),
            ]),
            if (p.type == 'car') Padding(padding: const EdgeInsets.only(top: 6), child: note(context, 'Some dealers offer 0% finance. Pick it if you have that offer.')),
          ],
          const SizedBox(height: 20),
          Text('Repay over', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final n in k.terms) ChoiceChip(label: Text(durationLabel(n)), selected: p.term == n, onSelected: (_) => setState(() => p.term = n)),
          ]),
        ];
      case Q.rent:
        return [_amount(rent, label: 'Monthly rent', quick: [('I don\'t pay rent', 0)])];
      case Q.setAside:
        return [
          _option('Not yet', null, hasSetAside == false, () => setState(() {
                hasSetAside = false;
                err = null;
              })),
          _option('Yes, I have some set aside', null, hasSetAside == true, () => setState(() {
                hasSetAside = true;
                err = null;
              })),
          if (hasSetAside == true) ...[const SizedBox(height: 12), _amount(setAside, label: 'Set aside for this')],
        ];
      case Q.income:
        return [_amount(income, label: 'Monthly take-home', autofocus: true, quick: [for (final v in <double>[8000, 12000, 15000, 20000, 25000, 35000, 50000]) (fmt(v), v)])];
      case Q.payday:
        return [
          PaydayPicker(
              selected: m.payday,
              onSelected: (d) => setState(() {
                    m.payday = d;
                    err = null;
                  })),
        ];
      case Q.spending:
        final inc = m.income ?? 0;
        return [
          _amount(spending, label: 'Monthly spending', quick: [
            if (inc > 0) for (final (l, f) in [('About half', 0.5), ('About 60%', 0.6), ('About 75%', 0.75), ('Almost all', 0.9)]) ('$l · ${fmt(roundUp(inc * f, 100))}', roundUp(inc * f, 100)),
          ]),
        ];
      case Q.savings:
        return [_amount(savings, label: 'Savings', quick: [('None', 0)])];
      case Q.repayments:
        return [_amount(repayments, label: 'Monthly loan repayments', quick: [('No loans', 0)])];
      case Q.card:
        return [
          _option('No', 'I pay it in full each month, or don\'t have one', carriesCard == false, () => setState(() {
                carriesCard = false;
                err = null;
              })),
          _option('Yes, I carry a balance', null, carriesCard == true, () => setState(() {
                carriesCard = true;
                err = null;
              })),
          if (carriesCard == true) ...[const SizedBox(height: 12), _amount(card, label: 'Total owed on cards')],
        ];
      case Q.situation:
        return [
          Text('Who relies on your income?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _option('Just me', null, m.family == false, () => setState(() => m.family = false)),
          _option('Me and my family', 'A partner, children or parents depend on it', m.family == true, () => setState(() => m.family = true)),
          const SizedBox(height: 16),
          Text('How steady is your income?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _option('Fixed salary', null, m.variable == false, () => setState(() => m.variable = false)),
          _option('It varies', 'Commission, contract or self-employed', m.variable == true, () => setState(() => m.variable = true)),
        ];
      case Q.investments:
        return [_amount(investments, label: 'Investments (optional)', autofocus: false, quick: [('None', 0)])];
      case Q.payGroup:
      case Q.monthGroup:
      case Q.lifeGroup:
        final subs = moneyGroups[q]!;
        return [
          for (var n = 0; n < subs.length; n++) ...[
            if (n > 0) const SizedBox(height: 24),
            Text(_text(subs[n]).$1, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (_text(subs[n]).$2.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: note(context, _text(subs[n]).$2)),
            const SizedBox(height: 10),
            ..._input(subs[n]),
          ],
        ];
      case Q.moneyCheck:
        return [
          Section(children: [
            Row2('Take-home pay', '${money(m.income ?? 0)} / month'),
            Row2('Payday', paydayLabel(m.payday)),
            Row2('Spending', '${money(m.spending ?? 0)} / month'),
            Row2('Savings', money(m.savings ?? 0)),
            Row2('Loan repayments', '${money(m.repayments ?? 0)} / month'),
            Row2('Card balance', money(m.cardDebt ?? 0)),
            Row2('Relying on your income', m.family == true ? 'You and family' : 'Just you'),
            Row2('Income', m.variable == true ? 'Varies' : 'Fixed salary'),
          ]),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => setState(() => editMoney = true), child: const Text('Update my answers')),
        ];
    }
  }

  /// Month and year picker for "When do you want it?".
  Future<void> _pickMonth() async {
    final now = monthKey(today);
    final start = whenMonths != null ? addMonths(now, whenMonths!) : addMonths(now, 12);
    var year = int.parse(start.substring(0, 4));
    final firstYear = int.parse(now.substring(0, 4));
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Row(children: [
            IconButton(tooltip: 'Previous year', onPressed: year > firstYear ? () => set(() => year--) : null, icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text('$year', textAlign: TextAlign.center)),
            IconButton(tooltip: 'Next year', onPressed: year < firstYear + 30 ? () => set(() => year++) : null, icon: const Icon(Icons.chevron_right)),
          ]),
          content: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var mo = 1; mo <= 12; mo++)
              Builder(builder: (_) {
                final ym = '$year-${mo.toString().padLeft(2, '0')}';
                final ok = ym.compareTo(now) > 0;
                return ChoiceChip(
                  label: SizedBox(width: 36, child: Text(monthLabel(ym).substring(0, 3), textAlign: TextAlign.center)),
                  selected: ym == start,
                  onSelected: ok ? (_) => Navigator.pop(ctx, ym) : null,
                );
              }),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        whenMonths = monthsUntil(today, picked);
        err = null;
      });
    }
  }

  Widget _amount(TextEditingController c, {required String label, List<(String, double)> quick = const [], bool autofocus = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: c,
            autofocus: autofocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [AmountFormatter()],
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: InputDecoration(labelText: label, prefixText: 'AED '),
            onChanged: (_) {
              if (err != null) setState(() => err = null);
            },
            onSubmitted: (_) => _next(),
          ),
          if (quick.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (l, v) in quick)
                ActionChip(
                    label: Text(l),
                    onPressed: () => setState(() {
                          c.text = fmt(v);
                          err = null;
                        })),
            ]),
          ],
        ],
      );

  Widget _option(String title, String? sub, bool selected, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: selected ? cs.primary.withValues(alpha: 0.10) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1)),
        child: ListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub == null ? null : Text(sub),
          trailing: selected ? Icon(Icons.check_circle, color: cs.primary) : null,
          onTap: onTap,
        ),
      ),
    );
  }
}
