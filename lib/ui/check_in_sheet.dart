// Monthly check-in: what the plan expects you to have, what you actually have, and what that says about spending.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/checkin.dart';
import '../domain/format.dart';
import 'widgets.dart';

Future<void> showCheckIn(BuildContext context) =>
    showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const CheckInSheet());

class CheckInSheet extends ConsumerStatefulWidget {
  const CheckInSheet({super.key});
  @override
  ConsumerState<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends ConsumerState<CheckInSheet> {
  final today = todayIso();
  final have = TextEditingController(), card = TextEditingController();
  String? err;
  CheckInResult? result; // after saving: the gap, and maybe a spending suggestion
  double? suggestion;

  @override
  void dispose() {
    have.dispose();
    card.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim());

  void _save(Expected e, bool askCard) {
    final actual = _num(have);
    final c = askCard ? _num(card) : null;
    if (actual == null || actual < 0) return setState(() => err = 'Enter what you have now, or tap "About right".');
    if (askCard && (c == null || c < 0)) return setState(() => err = 'Enter your card balance (0 if it\'s clear).');
    late CheckInResult r;
    double? s;
    ref.read(appProvider.notifier).update((d) {
      r = applyCheckIn(d, today: today, actual: actual, card: c);
      s = suggestedSpending(d.money, r);
    }, why: _label(actual, e));
    setState(() {
      result = r;
      suggestion = s;
      err = null;
    });
  }

  String _label(double actual, Expected e) {
    final gap = e.total - actual;
    return gap.abs() < 500 ? 'Check-in: on plan' : 'Check-in: ${money(roundUp(gap.abs(), 100))} ${gap > 0 ? 'behind' : 'ahead of'} plan';
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appProvider).data;
    final t = Theme.of(context).textTheme;
    final e = expectedNow(data, today: today);
    final askCard = e.card > 0.5 || (data.money.cardDebt ?? 0) > 0.5;
    final since = data.money.asOf == null ? 'your last update' : monthLabel(monthKey(data.money.asOf!));

    final r = result;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Check in', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (r == null) ...[
            richBold(
                context,
                'If you followed the plan since $since, you\'d have about **${money(roundDown(e.total, 100))}** in savings and money set aside'
                '${askCard ? ', and owe about **${money(roundUp(e.card, 100))}** on cards' : ''}.'),
            const SizedBox(height: 16),
            TextField(
              controller: have,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [AmountFormatter()],
              decoration: const InputDecoration(labelText: 'What you have now', helperText: 'Savings plus money set aside for projects', prefixText: 'AED '),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  have.text = fmt(roundDown(e.total, 100));
                  if (askCard) card.text = fmt(roundUp(e.card, 100));
                }),
                child: const Text('About right'),
              ),
            ),
            if (askCard)
              TextField(
                controller: card,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [AmountFormatter()],
                decoration: const InputDecoration(labelText: 'Card balance now', prefixText: 'AED '),
              ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: toneColor(context, Tone.bad)))),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => _save(e, askCard), child: const Padding(padding: EdgeInsets.all(12), child: Text('Save'))),
            const SizedBox(height: 8),
            note(context, 'The phone can\'t see your bank, so plans assume you follow them. A monthly check-in keeps the dates honest.'),
          ] else ...[
            Row(children: [
              Icon(r.onPlan || r.gap < 0 ? Icons.check_circle_outline : Icons.info_outline,
                  color: toneColor(context, r.onPlan || r.gap < 0 ? Tone.good : Tone.warn)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.onPlan
                      ? 'You\'re on plan. Nice.'
                      : r.gap > 0
                          ? 'You\'re ${money(roundUp(r.gap, 100))} behind the plan${r.months > 0 ? ', about ${money(roundUp(r.perMonth, 50))} a month' : ''}.'
                          : 'You\'re ${money(roundUp(-r.gap, 100))} ahead of the plan. Nice.',
                  style: t.titleSmall,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text('Your plan now starts from what you actually have.', style: t.bodyMedium),
            if (suggestion != null) ...[
              const SizedBox(height: 12),
              Text(
                r.gap > 0
                    ? 'If that\'s regular, your spending is closer to ${money(suggestion!)} a month than ${money(data.money.spending ?? 0)}.'
                    : 'If that\'s regular, you spend less than you said: closer to ${money(suggestion!)} a month.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () {
                  final s = suggestion!;
                  ref.read(appProvider.notifier).update((d) => d.money.spending = s, why: 'Spending updated after check-in');
                  Navigator.pop(context);
                },
                child: Text('Update spending to ${money(suggestion!)}'),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('It was a one-off')),
            ] else
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ]),
      ),
    );
  }
}
