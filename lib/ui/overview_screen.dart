import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/basics.dart';
import '../domain/finance.dart';
import 'suggestions_screen.dart' show SuggestionCard;
import 'widgets.dart';

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(financeProvider);
    if (f == null) return const SizedBox();
    final t = f.t, inc = f.income, surplus = inc == null ? null : inc.v - t.spent;
    final top = t.byCat.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final sugs = f.suggestions;
    return ScreenBody(children: [
      MoneyHero(label: 'Net worth', value: fmt(t.net)),
      _checklist(context, ref, f),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.4,
        children: [
          _stat(context, 'Assets', fmt(t.assets)),
          _stat(context, 'Debts', fmt(t.debts), Tone.bad),
          _stat(context, 'Spent in ${monthShort(f.latestMonth)}', fmt(t.spent)),
          _stat(context, 'Left over', surplus == null ? '—' : fmt(surplus), surplus == null ? null : (surplus >= 0 ? Tone.good : Tone.bad)),
        ],
      ),
      if (sugs.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Top suggestions', style: Theme.of(context).textTheme.titleMedium)),
            TextButton(onPressed: () => ref.read(tabProvider.notifier).state = 4, child: Text('All ${sugs.length}')),
          ]),
          for (final s in sugs.take(2)) Padding(padding: const EdgeInsets.only(top: 8), child: SuggestionCard(s)),
        ]),
      if (f.s.projects.isNotEmpty && inc != null)
        Section(
          title: 'Your projects',
          trailing: TextButton(onPressed: () => ref.read(tabProvider.notifier).state = 2, child: const Text('Details')),
          children: [
            for (final r in f.projects)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.pj.name),
                subtitle: Text('${aed(r.pj.cost)} by ${monthsAhead(monthKey(f.today), r.months)}'),
                trailing: Tag(_verdictLabel(r.verdict), tone: toneOf(r.verdict)),
              ),
          ],
        ),
      if (top.isNotEmpty)
        Section(
          title: 'Where ${monthLong(f.latestMonth)} went',
          trailing: TextButton(onPressed: () => ref.read(tabProvider.notifier).state = 1, child: const Text('All spending')),
          children: [
            for (final e in top.take(4)) ...[
              Row2(e.key, '${fmt(e.value)} / ${fmt(f.s.budgets[e.key] ?? 0.0)}'),
              Bar((f.s.budgets[e.key] ?? 0.0) > 0 ? e.value / f.s.budgets[e.key]! : 0, tone: barTone((f.s.budgets[e.key] ?? 0.0) > 0 ? e.value / f.s.budgets[e.key]! : 0)),
              const SizedBox(height: 6),
            ],
          ],
        ),
    ]);
  }

  Widget _stat(BuildContext c, String label, String v, [Tone? tone]) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label.toUpperCase(), style: Theme.of(c).textTheme.labelSmall),
            Text(v, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: tone == null ? null : toneColor(c, tone), fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
      );

  Widget _checklist(BuildContext context, WidgetRef ref, Finance f) {
    final s = f.s;
    if (s.example || s.setup['dismissed'] == true) return const SizedBox.shrink();
    final items = [
      (0, 'Salary', s.setup['salary'] == 'done' || f.income != null),
      (1, 'Home costs', s.setup['housing'] == 'done'),
      (2, 'Regular costs', s.setup['costs'] == 'done'),
      (-1, 'Household size', f.household.known),
      (-2, 'Day-to-day spending', s.tx.any((t) => t.rid == null)),
    ];
    final n = items.where((i) => i.$3).length;
    if (n == items.length) return const SizedBox.shrink();
    return Section(title: 'Finish setting up', trailing: Text('$n of ${items.length}'), children: [
      Bar(n / items.length),
      for (final i in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(i.$3 ? Icons.check_circle : Icons.radio_button_unchecked, color: i.$3 ? toneColor(context, Tone.good) : null),
          title: Text(i.$2),
          trailing: i.$3
              ? const Tag('Done', tone: Tone.good)
              : TextButton(
                  onPressed: () {
                    if (i.$1 >= 0) {
                      ref.read(showSetupProvider.notifier).state = i.$1;
                    } else {
                      ref.read(tabProvider.notifier).state = i.$1 == -1 ? 4 : 1;
                    }
                  },
                  child: const Text('Add')),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: () => ref.read(appProvider.notifier).update((s) => s.setup['dismissed'] = true), child: const Text('Hide this')),
      ),
    ]);
  }
}

String _verdictLabel(String? v) => switch (v) { 'good' => 'Affordable', 'warn' => 'Tight', 'bad' => 'Not yet', _ => 'Add income' };
String verdictLabel(String? v) => _verdictLabel(v);
