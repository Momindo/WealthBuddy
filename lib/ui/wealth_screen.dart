import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/basics.dart';
import '../domain/finance.dart';
import '../domain/models.dart';
import 'overview_screen.dart' show verdictLabel;
import 'widgets.dart';

class WealthScreen extends ConsumerWidget {
  const WealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(financeProvider);
    if (f == null) return const SizedBox();
    final ctl = ref.read(appProvider.notifier), t = f.t;
    return ScreenBody(children: [
      MoneyHero(label: 'What you own, minus what you owe', value: fmt(t.net)),
      Section(
        title: 'Assets',
        trailing: TextButton.icon(onPressed: () => _addAsset(context, ref), icon: const Icon(Icons.add), label: const Text('Add')),
        children: [
          if (f.s.assets.isEmpty) note(context, 'Add bank balances, investments, gold or property to see your net worth.'),
          for (final a in f.s.assets)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(a.name),
              subtitle: Text('${assetTypes[a.type]}${a.cur != 'AED' ? ' · ${fmt(a.amount)} ${a.cur == 'GOLD_G' ? 'g gold' : a.cur}' : ''}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(fmt(toAed(a.amount, a.cur))),
                IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'Remove', onPressed: () => ctl.update((s) => s.assets.removeWhere((x) => x.id == a.id))),
              ]),
            ),
        ],
      ),
      Section(
        title: 'Debts',
        trailing: TextButton.icon(onPressed: () => _addDebt(context, ref), icon: const Icon(Icons.add), label: const Text('Add')),
        children: [
          if (f.s.liabilities.isEmpty) note(context, 'No debts added.'),
          for (final l in f.s.liabilities)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(children: [Flexible(child: Text(l.name)), if (l.rate >= 10) const Padding(padding: EdgeInsets.only(left: 6), child: Tag('High interest', tone: Tone.bad))]),
              subtitle: Text('${l.rate}% a year${l.monthly != null ? ' · ${fmt(l.monthly!)}/mo' : ''}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('−${fmt(toAed(l.amount, l.cur))}', style: TextStyle(color: toneColor(context, Tone.bad))),
                IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'Remove', onPressed: () => ctl.update((s) => s.liabilities.removeWhere((x) => x.id == l.id))),
              ]),
            ),
        ],
      ),
      if (f.debtBurden != null && f.s.liabilities.isNotEmpty) _dbrCard(context, f),
      _projects(context, ref, f),
      note(context, 'Values in AED at fixed demo rates (USD 3.6725, INR 0.0418, gold AED 400/g). Live rates arrive with the price feed.'),
    ]);
  }

  Widget _dbrCard(BuildContext context, Finance f) {
    final d = f.debtBurden!;
    final loans = f.projects.where((r) => r.loan && r.dbr != null).toList();
    final after = loans.isEmpty ? null : loans.last.dbr;
    return Section(
      title: 'Debt burden',
      trailing: Tag(d.s == 'good' ? 'Healthy' : d.s == 'warn' ? 'Getting high' : 'At the cap', tone: toneOf(d.s)),
      children: [
        Text('${d.pct.toStringAsFixed(1)}% of income'),
        const SizedBox(height: 6),
        Gauge(lo: 0, hi: 0, value: d.pct, max: 70, capFrom: 50, tone: toneOf(d.s), after: after),
        if (after != null) Text('With ${loans.map((r) => r.pj.name).join(' + ')}: ${after.toStringAsFixed(0)}% of income', style: TextStyle(fontSize: 12, color: toneColor(context, Tone.gold), fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        note(context, '${aed(d.total)} a month: instalments ${aed(d.loans)} plus card minimums ${aed(d.cards)} (assumed 5% of the balance). Lenders cap repayments at 50%.'),
      ],
    );
  }

  Widget _projects(BuildContext context, WidgetRef ref, Finance f) {
    final pl = f.plan;
    return Section(
      title: 'Projects',
      trailing: TextButton.icon(onPressed: () => showProjectSheet(context), icon: const Icon(Icons.add), label: const Text('New')),
      children: [
        note(context, "Something you're saving for, like a car or a house. Each one is checked against your income, spending, savings, debts and investments."),
        if (pl.projReserve > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Saving for these takes ${aed(pl.projReserve)} a month, so investing drops from ${aed(pl.toInvestBase)} to ${aed(pl.toInvest)}.'),
          ),
        if (f.s.projects.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: note(context, 'No projects yet.')),
        for (final r in f.projects) _projectTile(context, ref, f, r),
      ],
    );
  }

  Widget _projectTile(BuildContext context, WidgetRef ref, Finance f, ProjectEval r) {
    final pj = r.pj, T = projectTypes[pj.type]!;
    final due = monthsAhead(monthKey(f.today), r.months == 0 ? pj.months : r.months);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ExpansionTile(
          shape: const Border(),
          title: Text(pj.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${T.label} · ${aed(pj.cost)} by $due${r.loan ? ' · ${r.dp.toStringAsFixed(0)}% down' : ' · from savings'}'),
          trailing: Tag(verdictLabel(r.verdict), tone: toneOf(r.verdict)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: r.verdict == null
              ? [note(context, 'Add your income to check this project.')]
              : [
                  Bar(r.need > 0 ? r.canSave / r.need : 1, tone: toneOf(r.verdict == 'good' ? 'accent' : r.verdict), height: 8),
                  const SizedBox(height: 8),
                  Row2(r.loan ? 'Down payment + fees' : 'Needed', aed(r.need)),
                  Row2('Save per month', aed(r.need / r.months)),
                  if (r.loan) Row2('Instalment', aed(r.emi)),
                  if (r.loan) Row2('Repayments after', '${r.dbr!.toStringAsFixed(0)}% of income', tone: r.dbr! > 50 ? Tone.bad : null),
                  const Divider(),
                  for (final c in r.checks)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(c.k, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(c.d),
                      trailing: Tag(c.s == 'good' ? 'OK' : c.s == 'warn' ? 'Tight' : 'No', tone: toneOf(c.s)),
                    ),
                  if (r.fixes.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: toneColor(context, Tone.gold).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('HOW TO MAKE IT WORK', style: TextStyle(fontSize: 11.5, color: toneColor(context, Tone.gold), fontWeight: FontWeight.w600)),
                        for (final x in r.fixes) Padding(padding: const EdgeInsets.only(top: 6), child: richBold(context, '• $x')),
                      ]),
                    ),
                  if (r.impacts.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('WHAT ELSE CHANGES', style: Theme.of(context).textTheme.labelSmall),
                    for (final x in r.impacts) Padding(padding: const EdgeInsets.only(top: 4), child: note(context, '• $x')),
                  ],
                  if (T.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: note(context, T.note)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: () => ref.read(appProvider.notifier).update((s) => s.projects.removeWhere((x) => x.id == pj.id)), child: const Text('Remove')),
                  ),
                ],
        ),
      ),
    );
  }

  Future<void> _addAsset(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController(), amount = TextEditingController();
    String type = 'cash', cur = 'AED';
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Add an asset'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name, e.g. Savings account')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [for (final e in assetTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => set(() => type = v!)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                  initialValue: cur,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [for (final c in fx.keys) DropdownMenuItem(value: c, child: Text(c == 'GOLD_G' ? 'Grams of gold' : c))],
                  onChanged: (v) => set(() => cur = v!)),
              const SizedBox(height: 10),
              TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  final a = double.tryParse(amount.text.replaceAll(',', ''));
                  if (name.text.trim().isEmpty || a == null || a <= 0) return;
                  ref.read(appProvider.notifier).update((s) => s.assets.add(Asset(id: nextId(s.assets.map((e) => e.id)), name: name.text.trim(), type: type, amount: a, cur: cur)));
                  Navigator.pop(d);
                },
                child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  Future<void> _addDebt(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController(), amount = TextEditingController(), rate = TextEditingController(text: '0'), monthly = TextEditingController();
    String type = 'loan';
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Add a debt'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name, e.g. Personal loan')),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                  segments: const [ButtonSegment(value: 'loan', label: Text('Loan')), ButtonSegment(value: 'card', label: Text('Credit card'))],
                  selected: {type},
                  onSelectionChanged: (v) => set(() => type = v.first)),
              const SizedBox(height: 10),
              TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Balance (AED)')),
              const SizedBox(height: 10),
              TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Interest % a year')),
              if (type == 'loan') ...[
                const SizedBox(height: 10),
                TextField(controller: monthly, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly instalment')),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  final a = double.tryParse(amount.text.replaceAll(',', ''));
                  if (name.text.trim().isEmpty || a == null || a <= 0) return;
                  ref.read(appProvider.notifier).update((s) => s.liabilities.add(Liability(
                      id: nextId(s.liabilities.map((e) => e.id)),
                      name: name.text.trim(),
                      type: type,
                      amount: a,
                      rate: double.tryParse(rate.text) ?? 0,
                      monthly: type == 'loan' ? double.tryParse(monthly.text) : null)));
                  Navigator.pop(d);
                },
                child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}

// ---------- New project ----------
void showProjectSheet(BuildContext context) => showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const ProjectSheet());

class ProjectSheet extends ConsumerStatefulWidget {
  const ProjectSheet({super.key});
  @override
  ConsumerState<ProjectSheet> createState() => _ProjectSheetState();
}

class _ProjectSheetState extends ConsumerState<ProjectSheet> {
  final name = TextEditingController(), cost = TextEditingController(), months = TextEditingController(text: '12'), saved = TextEditingController();
  final dp = TextEditingController(text: '20'), rate = TextEditingController(text: '3.5'), term = TextEditingController(text: '48');
  String type = 'car', method = 'cash';
  String? err;

  @override
  Widget build(BuildContext context) {
    final T = projectTypes[type]!;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
        Text('New project', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'What is it? e.g. New car')),
        const SizedBox(height: 10),
        Choice<String>(
            options: projectTypes.keys.toList(),
            selected: type,
            labels: (k) => projectTypes[k]!.label,
            onSelected: (k) => setState(() {
                  type = k;
                  final t = projectTypes[k]!;
                  dp.text = (t.minDp > 0 ? t.minDp : 20).toStringAsFixed(0);
                  rate.text = '${t.rate}';
                  term.text = t.term.toStringAsFixed(0);
                })),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost (AED)'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: months, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'In how many months?'))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: saved, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Already saved (AED, optional)')),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'cash', label: Text('From savings')), ButtonSegment(value: 'loan', label: Text('Loan or finance'))],
          selected: {method},
          onSelectionChanged: (v) => setState(() => method = v.first),
        ),
        if (method == 'loan') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: dp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Down payment %'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Rate % a year'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: term, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Term (months)'))),
          ]),
        ],
        if (T.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: note(context, T.note)),
        if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: toneColor(context, Tone.bad)))),
        const SizedBox(height: 12),
        FilledButton(onPressed: _save, child: const Padding(padding: EdgeInsets.all(12), child: Text('Check affordability'))),
      ]),
    );
  }

  void _save() {
    final c = double.tryParse(cost.text.replaceAll(',', '')), m = int.tryParse(months.text);
    if (name.text.trim().isEmpty || c == null || c <= 0 || m == null || m <= 0) {
      setState(() => err = 'Add a name, a cost above zero and a number of months.');
      return;
    }
    ref.read(appProvider.notifier).update((s) => s.projects.add(Project(
        id: nextId(s.projects.map((e) => e.id)),
        name: name.text.trim(),
        type: type,
        cost: c,
        months: m,
        method: method,
        saved: double.tryParse(saved.text) ?? 0,
        dp: double.tryParse(dp.text) ?? 0,
        rate: double.tryParse(rate.text) ?? 0,
        term: int.tryParse(term.text) ?? 36)));
    Navigator.pop(context);
  }
}
