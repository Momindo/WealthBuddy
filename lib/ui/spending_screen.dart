import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/basics.dart';
import '../domain/finance.dart';
import '../domain/models.dart';
import '../domain/parsers.dart';
import '../domain/recurring.dart';
import 'suggestions_screen.dart' show HouseholdPicker;
import 'widgets.dart';

class SpendingScreen extends ConsumerWidget {
  const SpendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(financeProvider);
    if (f == null) return const SizedBox();
    final months = f.monthsInData;
    final vm = ref.watch(viewMonthProvider);
    final m = (vm != null && months.contains(vm)) ? vm : f.latestMonth;
    final t = f.totals(m);
    final tx = f.txIn(m)..sort((a, b) => b.date.compareTo(a.date));
    final cash = -f.txIn(m).where((x) => x.amount < 0 && (x.method == 'cash' || x.method == 'cheque')).fold<double>(0, (a, x) => a + x.amount);
    final budgetTotal = f.s.budgets.values.fold<double>(0, (a, b) => a + b);

    return ScreenBody(children: [
      MoneyHero(
          label: '${monthLong(m)} ${m.substring(0, 4)}${m != f.latestMonth ? ' · past month' : ''}',
          value: fmt(t.spent),
          sub: 'spent of ${aed(budgetTotal)} budgeted${cash > 0 ? ' · ${aed(cash)} in cash or cheques' : ''}'),
      if (months.length > 1)
        Choice<String>(
            options: months.length > 6 ? months.sublist(months.length - 6) : months,
            selected: m,
            labels: monthShort,
            onSelected: (k) => ref.read(viewMonthProvider.notifier).state = k),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: () => showExpenseSheet(context), icon: const Icon(Icons.add), label: const Text('Add expense')),
        OutlinedButton.icon(onPressed: () => _importStatement(context, ref), icon: const Icon(Icons.upload_file), label: const Text('Import statement')),
        OutlinedButton.icon(onPressed: () => _pasteSms(context, ref), icon: const Icon(Icons.sms_outlined), label: const Text('Paste SMS')),
      ]),
      _benchCard(context, f),
      Section(title: 'Budgets', trailing: Text(monthLong(m)), children: [
        for (final c in categories.where((c) => (f.s.budgets[c] ?? 0.0) > 0 || (t.byCat[c] ?? 0.0) > 0)) ...[
          Row2(c, '${fmt(t.byCat[c] ?? 0.0)} / ${(f.s.budgets[c] ?? 0.0) > 0 ? fmt(f.s.budgets[c]!) : 'no budget'}'),
          Bar((f.s.budgets[c] ?? 0.0) > 0 ? (t.byCat[c] ?? 0.0) / f.s.budgets[c]! : 0, tone: barTone((f.s.budgets[c] ?? 0.0) > 0 ? (t.byCat[c] ?? 0.0) / f.s.budgets[c]! : 0)),
          const SizedBox(height: 6),
        ],
      ]),
      Section(title: 'Transactions', children: [
        if (tx.isEmpty) note(context, 'No transactions this month.'),
        for (final x in tx)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(x.merchant, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([dayLabel(x.date), x.cat, if (x.method != null) paymentMethods[x.method] ?? x.method!, if (x.rid != null) '↻ ${recurringNote(f.s, x)}'].join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${x.amount > 0 ? '+' : '−'}${fmt(x.amount.abs(), 2)}',
                  style: TextStyle(fontFeatures: const [FontFeature.tabularFigures()], color: x.amount > 0 ? toneColor(context, Tone.good) : null)),
              IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'Delete', onPressed: () => _delete(context, ref, x)),
            ]),
          ),
      ]),
    ]);
  }

  Widget _benchCard(BuildContext context, Finance f) {
    final inc = f.income;
    if (inc == null) {
      return Section(title: 'Compare your spending with typical ranges', children: [
        note(context, 'Add your salary in setup, pick an income range on the Suggestions tab, or paste a salary SMS.'),
      ]);
    }
    final rows = f.benchmark()..sort((a, b) => (b.pct / (b.hi == 0 ? 1 : b.hi)).compareTo(a.pct / (a.hi == 0 ? 1 : a.hi)));
    final after = <String, (double, String)>{};
    for (final r in f.projects) {
      final ci = r.catImpact;
      if (ci != null) after[ci.cat] = (ci.ap, after.containsKey(ci.cat) ? '${after[ci.cat]!.$2} + ${r.pj.name}' : r.pj.name);
    }
    final flagged = rows.where((r) => r.s == 'warn' || r.s == 'bad').toList();
    final h = f.household;
    return Section(title: 'How your spending compares', trailing: const Tag('Guidelines', tone: Tone.gold), children: [
      const HouseholdPicker(),
      const SizedBox(height: 10),
      note(context,
          'Each category as a share of ${aed(inc.v)} a month, from ${inc.src}. The shaded band is typical for ${h.known ? 'a household of ${h.label}' : 'one adult'}.'
          '${flagged.isNotEmpty ? ' ${flagged.length} above typical, ${aed(flagged.fold<double>(0, (a, r) => a + r.over))} over in total.' : ' Everything is within typical ranges.'}'),
      for (final r in rows) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Text('${r.pct.toStringAsFixed(1)}%  '),
          Tag(r.status, tone: r.s == 'plain' ? Tone.plain : toneOf(r.s)),
        ]),
        const SizedBox(height: 4),
        Gauge(
            lo: r.lo,
            hi: r.hi,
            value: r.pct,
            max: [r.hi * 2, (r.pct / 5).ceil() * 5.0, if (after[r.cat] != null) (after[r.cat]!.$1 / 5).ceil() * 5.0, 4.0].reduce((a, b) => a > b ? a : b),
            tone: r.s == 'plain' ? Tone.plain : toneOf(r.s),
            after: after[r.cat]?.$1),
        note(context, 'Typical for you: ${aed(r.loAed)}–${fmt(r.hiAed)} a month · you spent ${fmt(r.spent)}'),
        if (after[r.cat] != null) Text('With ${after[r.cat]!.$2}: ${after[r.cat]!.$1.toStringAsFixed(0)}% of income', style: TextStyle(fontSize: 12, color: toneColor(context, Tone.gold), fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 10),
      note(context, 'Starter guideline ranges. Comparison with people in your income band comes once enough users opt in to share anonymised totals.'),
    ]);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Tx x) async {
    final ctl = ref.read(appProvider.notifier);
    if (x.rid == null) {
      if (await confirm(context, 'Delete this transaction?', '${x.merchant}, ${dayLabel(x.date)}', 'Delete')) ctl.update((s) => s.tx.removeWhere((t) => t.id == x.id));
      return;
    }
    if (!context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('This one repeats'),
        content: const Text('Delete this month only, or stop it repeating from this month on? Earlier months stay either way.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(d, 'one'), child: const Text('This month')),
          FilledButton(onPressed: () => Navigator.pop(d, 'stop'), child: const Text('Stop repeating')),
        ],
      ),
    );
    if (choice == 'one') ctl.update((s) => skipMonth(s, s.tx.firstWhere((t) => t.id == x.id)));
    if (choice == 'stop') ctl.update((s) => stopRepeating(s, s.tx.firstWhere((t) => t.id == x.id)));
  }

  Future<void> _pasteSms(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    String? err;
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Paste a bank SMS'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: c, maxLines: 4, decoration: const InputDecoration(hintText: 'e.g. Your card was used for AED 245.50 at CARREFOUR on 29/09/26')),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err!, style: TextStyle(color: toneColor(context, Tone.bad)))),
            const SizedBox(height: 6),
            note(context, 'On Android the app will read these automatically, on the phone. A salary credit also sets your income.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  final r = parseSms(c.text, today: todayIso());
                  if (r == null) return set(() => err = 'No amount found. The message needs a currency and amount, like "AED 245.50".');
                  final name = r.merchant == 'Salary' ? r.merchant : cleanMerchant(r.merchant);
                  ref.read(appProvider.notifier).update((s) => s.tx.add(Tx(id: nextId(s.tx.map((e) => e.id)), date: r.date, merchant: name, cat: r.cat, amount: round2(r.amount), method: 'card')));
                  Navigator.pop(d);
                },
                child: const Text('Add')),
          ],
        ),
      ),
    );
  }

  Future<void> _importStatement(BuildContext context, WidgetRef ref) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt', 'pdf', 'xlsx', 'xls'], withData: true);
    final file = res?.files.single;
    if (file == null || file.bytes == null || !context.mounted) return;
    final ext = (file.extension ?? '').toLowerCase();
    if (ext == 'pdf' || ext == 'xlsx' || ext == 'xls') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('PDF and Excel statements arrive in the next update. For now, download the CSV version from your online banking.')));
      return;
    }
    final text = utf8.decode(file.bytes!, allowMalformed: true);
    final raw = rowsToRaw(parseCsv(text)) ?? linesToRaw(text.split(RegExp(r'\r?\n')));
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No transactions found. The file needs rows with a date, a description and an amount.')));
      return;
    }
    await showModalBottomSheet(
        context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => ImportReview(name: file.name, raw: raw, kind: guessKind(text)));
  }
}

// ---------- Statement review ----------
class ImportReview extends ConsumerStatefulWidget {
  const ImportReview({super.key, required this.name, required this.raw, required this.kind});
  final String name, kind;
  final List<RawEntry> raw;
  @override
  ConsumerState<ImportReview> createState() => _ImportReviewState();
}

class _ImportReviewState extends ConsumerState<ImportReview> {
  late String kind = widget.kind;
  late List<ImportRow> rows = classify(widget.raw, kind, ref.read(appProvider).data!.tx);

  @override
  Widget build(BuildContext context) {
    final pick = rows.where((r) => r.selected).toList();
    final skipped = rows.where((r) => r.status == 'skip').length, dups = rows.where((r) => r.status == 'dup').length;
    final dates = rows.map((r) => r.date).toList()..sort();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
        Text(widget.name, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'card', label: Text('Credit card')), ButtonSegment(value: 'bank', label: Text('Bank account'))],
          selected: {kind},
          onSelectionChanged: (v) => setState(() {
            kind = v.first;
            rows = classify(widget.raw, kind, ref.read(appProvider).data!.tx);
          }),
        ),
        const SizedBox(height: 8),
        note(context,
            'Found ${rows.length} transactions from ${dayLabel(dates.first)} to ${dayLabel(dates.last)}.${skipped > 0 ? ' $skipped card payment or transfer${skipped > 1 ? 's are' : ' is'} left out so nothing is counted twice.' : ''}${dups > 0 ? ' $dups already in the app.' : ''}'),
        for (final r in rows)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: r.selected,
            onChanged: (v) => setState(() => r.selected = v ?? false),
            title: Text(r.merchant),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text([dayLabel(r.date), if (r.reason.isNotEmpty) r.reason].join(' · ')),
              if (r.amount < 0)
                DropdownButton<String>(
                    value: categories.contains(r.cat) ? r.cat : 'Other',
                    isDense: true,
                    items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setState(() => r.cat = v ?? r.cat)),
            ]),
            secondary: Text('${r.amount > 0 ? '+' : '−'}${fmt(r.amount.abs(), 2)}'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        TextButton(
            onPressed: () => setState(() {
                  for (final r in rows) {
                    r.amount = -r.amount;
                    r.cat = r.amount > 0 ? 'Income' : guessCat(r.merchant);
                  }
                }),
            child: const Text('Spending and credits look swapped')),
        FilledButton(
          onPressed: pick.isEmpty
              ? null
              : () {
                  ref.read(appProvider.notifier).update((s) {
                    for (final r in pick) {
                      s.tx.add(Tx(id: nextId(s.tx.map((e) => e.id)), date: r.date, merchant: r.merchant, cat: r.cat, amount: r.amount, method: kind == 'card' ? 'card' : 'transfer'));
                    }
                  });
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  messenger.showSnackBar(SnackBar(content: Text('Added ${pick.length} transactions. Budgets, projects and suggestions now include them.')));
                },
          child: Padding(padding: const EdgeInsets.all(12), child: Text('Add ${pick.length} transaction${pick.length == 1 ? '' : 's'}')),
        ),
      ]),
    );
  }
}

// ---------- Add an expense or income ----------
void showExpenseSheet(BuildContext context) =>
    showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const ExpenseSheet());

class _Preset {
  final String label, merchant, cat, method, freq;
  final int cheques;
  const _Preset(this.label, this.merchant, this.cat, this.method, this.freq, [this.cheques = 4]);
}

const _presets = [
  _Preset('Rent', 'Rent', 'Rent', 'cheque', 'yearly', 4),
  _Preset('Home help', 'Home help salary', 'Home help', 'cash', 'monthly'),
  _Preset('School fees', 'School fees', 'Education', 'transfer', 'yearly', 3),
  _Preset('Cash purchase', '', 'Groceries', 'cash', 'none'),
];

class ExpenseSheet extends ConsumerStatefulWidget {
  const ExpenseSheet({super.key});
  @override
  ConsumerState<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<ExpenseSheet> {
  final amount = TextEditingController(), merchant = TextEditingController();
  String type = 'expense', cat = 'Groceries', method = 'cash', freq = 'none';
  bool catTouched = false;
  int cheques = 4;
  DateTime date = DateTime.now();
  String? err;

  @override
  Widget build(BuildContext context) {
    final isExp = type == 'expense';
    final a = double.tryParse(amount.text.replaceAll(',', ''));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
        Text(isExp ? 'Add an expense' : 'Add income', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        note(context, "For anything your bank doesn't see: rent by cheque, cash at the market, home help salary."),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'expense', label: Text('Expense')), ButtonSegment(value: 'income', label: Text('Income'))],
          selected: {type},
          onSelectionChanged: (v) => setState(() {
            type = v.first;
            cat = type == 'income' ? 'Income' : 'Groceries';
            freq = 'none';
          }),
        ),
        if (isExp) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in _presets)
              ActionChip(
                  label: Text(p.label),
                  onPressed: () => setState(() {
                        cat = p.cat;
                        catTouched = true;
                        method = p.method;
                        freq = p.freq;
                        cheques = p.cheques;
                        if (merchant.text.isEmpty) merchant.text = p.merchant;
                      })),
          ]),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: '${freq == 'yearly' ? 'Yearly amount' : 'Amount'} (AED)'),
                  onChanged: (_) => setState(() => err = null))),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2035));
                if (d != null) setState(() => date = d);
              },
              child: Text('${freq == 'none' ? 'Date' : 'From'}: ${dayLabel(isoOf(date))}'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: merchant,
          decoration: InputDecoration(labelText: isExp ? 'What was it for?' : 'Where from?'),
          onChanged: (v) => setState(() {
            err = null;
            if (isExp && !catTouched) {
              final g = guessCat(v);
              if (g != 'Other') cat = g;
            }
          }),
        ),
        if (isExp) ...[
          const SizedBox(height: 12),
          Text('Category${catTouched ? '' : ' · guessed from the description'}', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Choice<String>(options: categories, selected: cat, onSelected: (v) => setState(() {
                cat = v;
                catTouched = true;
              })),
        ],
        const SizedBox(height: 12),
        Text(isExp ? 'Paid with' : 'Received as', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Choice<String>(options: paymentMethods.keys.toList(), selected: method, labels: (k) => paymentMethods[k]!, onSelected: (v) => setState(() => method = v)),
        const SizedBox(height: 12),
        Text('Repeats', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'none', label: Text('No')), ButtonSegment(value: 'monthly', label: Text('Monthly')), ButtonSegment(value: 'yearly', label: Text('Yearly'))],
          selected: {freq},
          onSelectionChanged: (v) => setState(() => freq = v.first),
        ),
        if (freq == 'yearly') ...[
          const SizedBox(height: 8),
          Row(children: [
            const Text('Paid in  '),
            Expanded(child: Choice<int>(options: const [1, 2, 4, 6, 12], selected: cheques, onSelected: (v) => setState(() => cheques = v))),
            Text(method == 'cheque' ? ' cheques' : ' payments'),
          ]),
          note(context, a != null && a > 0 ? 'Counted as ${aed(a / 12)} a month in budgets and suggestions.' : 'The yearly amount is spread evenly over 12 months.'),
        ],
        if (freq == 'monthly') note(context, 'Added automatically each month from ${dayLabel(isoOf(date))}. You can stop it any time.'),
        if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: toneColor(context, Tone.bad)))),
        const SizedBox(height: 12),
        FilledButton(onPressed: _save, child: Padding(padding: const EdgeInsets.all(12), child: Text('Save ${isExp ? 'expense' : 'income'}'))),
      ]),
    );
  }

  void _save() {
    final a = double.tryParse(amount.text.replaceAll(',', ''));
    if (a == null || a <= 0 || merchant.text.trim().isEmpty) {
      setState(() => err = 'Enter an amount above zero and what it was for.');
      return;
    }
    final sign = type == 'expense' ? -1 : 1, c = type == 'expense' ? cat : 'Income', iso = isoOf(date), name = merchant.text.trim();
    ref.read(appProvider.notifier).update((s) {
      if (freq == 'none') {
        s.tx.add(Tx(id: nextId(s.tx.map((e) => e.id)), date: iso, merchant: name, cat: c, amount: sign * a, method: method));
      } else {
        s.recurring.add(RecurringRule(
            id: nextId(s.recurring.map((e) => e.id)), merchant: name, cat: c, amount: a, sign: sign, method: method, freq: freq, cheques: freq == 'yearly' ? cheques : null, start: iso));
      }
    });
    ref.read(viewMonthProvider.notifier).state = monthKey(iso);
    Navigator.pop(context);
  }
}
