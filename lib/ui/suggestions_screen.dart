import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/basics.dart';
import '../domain/finance.dart';
import 'widgets.dart';

class SuggestionCard extends ConsumerWidget {
  const SuggestionCard(this.s, {super.key});
  final Suggestion s;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = toneColor(context, toneOf(s.sev));
    final ctl = ref.read(appProvider.notifier);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: c),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(s.title, style: Theme.of(context).textTheme.titleSmall)),
                  if (s.impact != null && s.impact! > 0) Tag('+${fmt(s.impact!)}/yr', tone: Tone.good),
                ]),
                const SizedBox(height: 4),
                Text(s.body, style: Theme.of(context).textTheme.bodyMedium),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    title: Text('Why am I seeing this?', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary)),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final w in s.why) Text('• $w', style: Theme.of(context).textTheme.bodySmall)],
                  ),
                ),
                Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  FilledButton.tonal(onPressed: () => ref.read(tabProvider.notifier).state = tabFor(s.actionTab), child: Text(s.actionLabel)),
                  TextButton(onPressed: () => ctl.update((x) => x.done.add(s.id)), child: const Text('Done')),
                  TextButton(onPressed: () => ctl.update((x) => x.dismissed.add(s.id)), child: const Text('Not for me')),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Household size picker, used here and on the Spending tab.
class HouseholdPicker extends ConsumerWidget {
  const HouseholdPicker({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(appProvider).data!.profile;
    final ctl = ref.read(appProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const SizedBox(width: 72, child: Text('Adults')),
        Expanded(
            child: Choice<int>(options: const [1, 2, 3, 4], selected: p.adults, labels: (v) => v == 4 ? '4+' : '$v', onSelected: (v) => ctl.update((s) {
                  s.profile.adults = v;
                  s.profile.kids ??= 0;
                }))),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        const SizedBox(width: 72, child: Text('Children')),
        Expanded(
            child: Choice<int>(options: const [0, 1, 2, 3, 4], selected: p.adults == null ? null : p.kids, labels: (v) => v == 4 ? '4+' : '$v', onSelected: (v) => ctl.update((s) {
                  s.profile.kids = v;
                  s.profile.adults ??= 1;
                }))),
      ]),
      if (p.adults == null) Padding(padding: const EdgeInsets.only(top: 6), child: note(context, 'Not set, so ranges assume one adult.')),
    ]);
  }
}

class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({super.key});
  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsState();
}

class _SuggestionsState extends ConsumerState<SuggestionsScreen> {
  late final basic = TextEditingController(), years = TextEditingController();
  bool _init = false;

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(financeProvider);
    if (f == null) return const SizedBox();
    final p = f.s.profile, ctl = ref.read(appProvider.notifier), sugs = f.suggestions;
    if (!_init) {
      basic.text = p.basic == null ? '' : p.basic!.toStringAsFixed(0);
      years.text = p.years == null ? '' : '${p.years}';
      _init = true;
    }
    final hidden = f.s.dismissed.length + f.s.done.length;
    final total = sugs.fold<double>(0, (a, s) => a + (s.impact ?? 0));
    return ScreenBody(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SUGGESTIONS', style: Theme.of(context).textTheme.labelSmall),
        Text('${sugs.length} for you now', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        if (total > 0) Text('Up to ${aed(total)} a year if you act on all of them', style: TextStyle(color: toneColor(context, Tone.good))),
      ]),
      if (f.income == null)
        Section(title: 'Add an income range for more suggestions', children: [
          note(context, "It stays on this phone. Or paste a salary SMS on the Spending tab and it's detected automatically."),
          const SizedBox(height: 8),
          Choice<String>(options: incomeBands.map((b) => b.key).toList(), selected: p.incomeBand, labels: (k) => incomeBands.firstWhere((b) => b.key == k).label,
              onSelected: (k) => ctl.update((s) => s.profile.incomeBand = k)),
        ]),
      if (sugs.isEmpty) note(context, 'Nothing to flag right now. Suggestions appear as your data changes.'),
      for (final s in sugs) SuggestionCard(s),
      if (hidden > 0)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => ctl.update((s) {
                  s.dismissed.clear();
                  s.done.clear();
                }), child: Text('Show $hidden hidden suggestion${hidden > 1 ? 's' : ''}'))),
      Section(title: 'Fine-tune (all optional)', children: [
        note(context, 'Ranges only. Nothing here identifies you, and it never leaves this phone.'),
        const SizedBox(height: 12),
        const Text('Household'),
        const SizedBox(height: 6),
        const HouseholdPicker(),
        const SizedBox(height: 12),
        Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: () => ref.read(showSetupProvider.notifier).state = 0, child: const Text('Update salary, rent and regular costs'))),
        const SizedBox(height: 12),
        const Text('Monthly income range'),
        const SizedBox(height: 6),
        Choice<String>(options: incomeBands.map((b) => b.key).toList(), selected: p.incomeBand, labels: (k) => incomeBands.firstWhere((b) => b.key == k).label,
            onSelected: (k) => ctl.update((s) => s.profile.incomeBand = s.profile.incomeBand == k ? null : k)),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('End-of-service gratuity'),
          children: [
            Row(children: [
              Expanded(child: TextField(controller: basic, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Basic salary (AED)'),
                  onChanged: (v) => ctl.update((s) => s.profile.basic = double.tryParse(v)))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: years, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Years with employer'),
                  onChanged: (v) => ctl.update((s) => s.profile.years = double.tryParse(v)))),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: f.plan.eos != null
                  ? Text("Owed if you left today: ${aed(f.plan.eos!)}. 21 days' basic pay per year for the first 5 years, 30 days after.")
                  : note(context, "Add both to estimate what you'd be owed if you left today."),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ]),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: toneColor(context, Tone.bad)),
          onPressed: () async {
            if (await confirm(context, 'Delete all data?', 'Everything on this phone is removed, including the encryption key. This cannot be undone.', 'Delete everything')) {
              await ctl.wipe();
            }
          },
          child: const Text('Delete all data'),
        ),
      ),
      note(context, 'Suggestions are educational guidance from fixed rules, not a recommendation to buy any product.'),
    ]);
  }
}
