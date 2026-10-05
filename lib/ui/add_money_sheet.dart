// Add a bonus, gift or other money to a project, with a live preview of what it changes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/format.dart';
import 'widgets.dart';

Future<void> showAddMoney(BuildContext context, int projectId) =>
    showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => AddMoneySheet(projectId: projectId));

const moneySources = ['Bonus', 'Gift', 'Sold something', 'Other'];

class AddMoneySheet extends ConsumerStatefulWidget {
  const AddMoneySheet({super.key, required this.projectId});
  final int projectId;
  @override
  ConsumerState<AddMoneySheet> createState() => _AddMoneySheetState();
}

class _AddMoneySheetState extends ConsumerState<AddMoneySheet> {
  final amount = TextEditingController();
  String source = 'Bonus', to = 'project';
  String? err;

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(amount.text.replaceAll(',', '').trim());

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appProvider).data;
    final p = data.projects.firstWhere((x) => x.id == widget.projectId);
    final today = todayIso();
    final t = Theme.of(context).textTheme;
    final k = kindOf(p.type);
    final hasCard = (data.money.cardDebt ?? 0) > 0;
    if (to == 'card' && !hasCard) to = 'project';
    final ready = data.money.complete;
    String inMonths(int? n) => n == null ? 'not within 30 years' : (n == 0 ? 'now' : monthLabel(addMonths(monthKey(today), n)));

    final a = _amount;
    String? head, body, tip;
    if (ready && a != null && a > 0) {
      final before = assessIn(data, p, today: today);
      Assessment afterFor(String dest) {
        final copy = data.copy()..addMoney(p.id, a, source, dest, today);
        return assessIn(copy, copy.projects.firstWhere((x) => x.id == p.id), today: today);
      }

      final after = afterFor(to);
      final gain = (before.readyIn != null && after.readyIn != null) ? before.readyIn! - after.readyIn! : null;
      head = after.readyIn == 0
          ? 'Ready now'
          : (gain != null && gain > 0)
              ? 'Ready ${inMonths(after.readyIn)}, ${durationLabel(gain)} sooner'
              : 'Still ready ${inMonths(after.readyIn)}';
      if (to == 'project') {
        body = '${p.name} pot goes from ${money(before.earmarked)} to ${money(after.earmarked)}.';
      } else if (to == 'cushion') {
        body = after.efHave >= after.efTarget - 0.5
            ? 'Your safety cushion would be full now.'
            : 'Safety cushion full by ${inMonths(after.efReadyIn)} instead of ${inMonths(before.efReadyIn)}.';
      } else {
        final card = data.money.cardDebt ?? 0, paid = a < card ? a : card;
        body = 'Card balance goes from ${money(card)} to ${money(card - paid)}.${a > card ? ' ${money(a - card)} left over goes to ${p.name}.' : ''}';
      }

      // Tips, only when they're true for these numbers.
      if (hasCard && to != 'card') {
        tip = 'You owe ${money(data.money.cardDebt!)} on cards at around 36% a year. Paying that first saves you the most.';
      } else if (to == 'project' && !before.small && before.efHave < before.efTarget - 0.5) {
        final alt = afterFor('cushion');
        if (alt.readyIn == after.readyIn && (alt.efReadyIn ?? 999) < (after.efReadyIn ?? 999)) {
          tip = 'Your safety cushion is ${money(before.efTarget - before.efHave)} short. Putting this there gets you the ${k.noun} on the same date, and protects you sooner.';
        }
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 16, 20, 20), children: [
        Text('Add money to ${p.name}', style: t.titleLarge),
        const SizedBox(height: 4),
        note(context, 'A bonus, a gift, or something you sold.'),
        const SizedBox(height: 16),
        TextField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountFormatter()],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(labelText: 'How much did you get?', prefixText: 'AED '),
          onChanged: (_) => setState(() => err = null),
        ),
        if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err!, style: TextStyle(color: toneColor(context, Tone.bad)))),
        const SizedBox(height: 16),
        Text('Where\'s it from?', style: t.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in moneySources) ChoiceChip(label: Text(s), selected: source == s, onSelected: (_) => setState(() => source = s)),
        ]),
        const SizedBox(height: 16),
        Text('Put it toward', style: t.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('This project'), selected: to == 'project', onSelected: (_) => setState(() => to = 'project')),
          ChoiceChip(label: const Text('My safety cushion'), selected: to == 'cushion', onSelected: (_) => setState(() => to = 'cushion')),
          if (hasCard) ChoiceChip(label: const Text('My credit card'), selected: to == 'card', onSelected: (_) => setState(() => to = 'card')),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(head ?? (ready ? 'Enter an amount to see the effect' : 'Answer the money questions to see the effect'), style: t.titleSmall),
            if (body != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(body, style: t.bodySmall)),
          ]),
        ),
        if (tip != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_outline, size: 18, color: toneColor(context, Tone.gold)),
              const SizedBox(width: 8),
              Expanded(child: Text(tip, style: t.bodySmall)),
            ]),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final v = _amount;
            if (v == null || v <= 0) {
              setState(() => err = 'Enter an amount above zero.');
              return;
            }
            ref.read(appProvider.notifier).update((d) => d.addMoney(p.id, v, source, to, today), why: 'Added ${money(v)} (${source.toLowerCase()})');
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(context);
            messenger.showSnackBar(SnackBar(content: Text('Added ${money(v)}')));
          },
          child: Padding(padding: const EdgeInsets.all(12), child: Text(a != null && a > 0 ? 'Add ${money(a)}' : 'Add money')),
        ),
      ]),
    );
  }
}
