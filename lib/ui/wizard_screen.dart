// One question per screen. Project questions first, then the user's money (asked once and reused).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/format.dart';
import '../domain/models.dart';
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
  bool? linkTogether; // plan this new project with the existing ones
  int? linkAt; // its place in the linked plan (0 = first)

  final name = TextEditingController(), cost = TextEditingController(), rate = TextEditingController(), rent = TextEditingController();
  final income = TextEditingController(), spending = TextEditingController(), savings = TextEditingController();
  final repayments = TextEditingController(), card = TextEditingController(), investments = TextEditingController();
  final setAside = TextEditingController();

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
      cost.text = _plain(p.cost);
    } else {
      final type = widget.type ?? 'other';
      final k = kindOf(type);
      p = Project(id: data.nextProjectId(), type: type, name: k.label, cost: 0, target: addMonths(monthKey(today), 12),
          downPct: k.minDown > 0 ? k.minDown : 20, rate: k.rate, term: k.term);
    }
    rate.text = _plain(p.rate);
    rent.text = _plain(p.rent);
    income.text = _plain(m.income);
    spending.text = _plain(m.spending);
    savings.text = _plain(m.savings);
    repayments.text = _plain(m.repayments);
    investments.text = _plain(m.investments);
    if (m.cardDebt != null) {
      carriesCard = m.cardDebt! > 0;
      if (carriesCard!) card.text = _plain(m.cardDebt);
    }
  }

  @override
  void dispose() {
    for (final c in [name, cost, rate, rent, income, spending, savings, repayments, card, investments, setAside]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Projects this one could be planned with, in their current order: the linked plan if there is one,
  /// otherwise every other project by the date it's wanted.
  List<Project> get _others {
    final d = ref.read(appProvider).data;
    final linked = d.linkedProjects();
    if (linked.isNotEmpty) return linked;
    return [...d.projects.where((x) => x.id != p.id)]..sort((a, b) => a.target.compareTo(b.target));
  }

  /// Default place: before the first project wanted later than this one.
  int get _defaultAt {
    final o = _others;
    final i = o.indexWhere((x) => x.target.compareTo(p.target) > 0);
    return i < 0 ? o.length : i;
  }

  List<Q> get flow {
    if (widget.mode == WizardMode.money) return moneyQuestions;
    final create = widget.mode == WizardMode.create;
    return [
      ...projectQuestions(p, isNew: create),
      if (create && _others.isNotEmpty) Q.link,
      ...(moneyWasComplete && !editMoney ? [Q.moneyCheck] : moneyQuestions),
    ];
  }

  ProjectKind get k => kindOf(p.type);

  void _fail(String message) => setState(() => err = message);

  void _next() {
    final q = flow[i];
    switch (q) {
      case Q.cost:
        final c = _num(cost);
        if (c == null || c <= 0) return _fail('Enter the cost in AED.');
        p.cost = c;
        p.name = name.text.trim().isEmpty ? k.label : name.text.trim();
      case Q.when:
        if (whenMonths == null) return _fail('Pick when you want it.');
        p.target = addMonths(monthKey(today), whenMonths!);
      case Q.pay:
        break;
      case Q.loan:
        final r = _num(rate);
        if (r == null || r < 0 || r > 30) return _fail('Enter the interest rate, for example 3.5.');
        p.rate = r;
      case Q.rent:
        final r = _num(rent);
        if (r == null || r < 0) return _fail('Enter your monthly rent, or tap "I don\'t pay rent".');
        p.rent = r;
      case Q.setAside:
        if (hasSetAside == null) return _fail('Choose one.');
        p.contributions.removeWhere((c) => c.source == startSource);
        if (hasSetAside!) {
          final v = _num(setAside);
          if (v == null || v <= 0) return _fail('Enter how much you\'ve set aside, or choose "Not yet".');
          p.contributions.add(Contribution(amount: v, source: startSource, date: today));
        }
      case Q.income:
        final v = _num(income);
        if (v == null || v <= 0) return _fail('Enter your monthly take-home pay.');
        m.income = v;
      case Q.payday:
        if (m.payday == null) return _fail('Pick a day, or "It varies".');
        if (m.payday! > 0 && ref.read(appProvider).data.settings.reminders) ref.read(reminderProvider)?.requestPermission();
      case Q.spending:
        final v = _num(spending);
        if (v == null || v < 0) return _fail('Enter a rough monthly figure, or tap one of the estimates.');
        m.spending = v;
      case Q.savings:
        final v = _num(savings);
        if (v == null || v < 0) return _fail('Enter your savings, or tap "None".');
        m.savings = v;
      case Q.repayments:
        final v = _num(repayments);
        if (v == null || v < 0) return _fail('Enter your monthly loan repayments, or tap "No loans".');
        m.repayments = v;
      case Q.card:
        if (carriesCard == null) return _fail('Choose one.');
        if (carriesCard!) {
          final v = _num(card);
          if (v == null || v <= 0) return _fail('Enter roughly how much you owe on cards.');
          m.cardDebt = v;
        } else {
          m.cardDebt = 0;
        }
      case Q.situation:
        if (m.family == null || m.variable == null) return _fail('Answer both questions.');
      case Q.investments:
        final v = _num(investments);
        m.investments = (v == null || v <= 0) ? null : v;
      case Q.link:
        if (linkTogether == null) return _fail('Choose one.');
      case Q.moneyCheck:
        break;
    }
    err = null;
    if (i >= flow.length - 1) {
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

  void _finish() {
    final moneyOnly = widget.mode == WizardMode.money;
    ref.read(appProvider.notifier).update((d) {
      d.money = m.copy();
      if (!moneyOnly) {
        final idx = d.projects.indexWhere((x) => x.id == p.id);
        if (idx >= 0) {
          d.projects[idx] = p.copy();
        } else {
          d.projects.add(p.copy());
          if (linkTogether == true) d.link(p.id, at: linkAt ?? _defaultAt);
        }
      }
    });
    if (widget.mode == WizardMode.create) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultScreen(projectId: p.id)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        Q.link => (
            'Plan this together with your other projects?',
            'Your spare money can only go to one thing at a time. Together, it goes to each project in turn, '
                'and each one\'s new monthly costs, like a loan or running costs, are counted in the next.'
          ),
      };

  List<Widget> _input(Q q) {
    switch (q) {
      case Q.cost:
        return [
          _amount(cost, label: 'Cost'),
          const SizedBox(height: 16),
          TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: 'Name (optional)', hintText: k.label)),
        ];
      case Q.when:
        final now = monthKey(today);
        return [
          for (final n in [1, 3, 6, 12, 18, 24, 36, 60])
            _option('In ${durationLabel(n)}', monthLabel(addMonths(now, n)), whenMonths == n, () => setState(() {
                  whenMonths = n;
                  err = null;
                })),
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
        return [_amount(income, label: 'Monthly take-home', quick: [for (final v in <double>[8000, 12000, 15000, 20000, 25000, 35000, 50000]) (fmt(v), v)])];
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
      case Q.link:
        final o = _others;
        final at = linkAt ?? _defaultAt;
        final names = o.map((x) => x.name).join(', ');
        return [
          _option('Plan them together', 'Recommended. Counts $names in this plan', linkTogether == true, () => setState(() {
                linkTogether = true;
                err = null;
              })),
          _option('Plan this on its own', 'As if the others didn\'t exist. Both plans may count on the same spare money.', linkTogether == false, () => setState(() {
                linkTogether = false;
                err = null;
              })),
          if (linkTogether == true) ...[
            const SizedBox(height: 12),
            Text('Which comes first?', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            note(context, 'Set by when you want each one. You can change the order later from the plan.'),
            const SizedBox(height: 8),
            for (var j = 0; j <= o.length; j++)
              _option(
                  j == 0 ? 'First, before the ${o.first.name}' : (j == o.length ? 'After the ${o.last.name}' : 'Between the ${o[j - 1].name} and the ${o[j].name}'),
                  null,
                  at == j,
                  () => setState(() => linkAt = j)),
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

  Widget _amount(TextEditingController c, {required String label, List<(String, double)> quick = const [], bool autofocus = true}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: c,
            autofocus: autofocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                          c.text = _plain(v);
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
