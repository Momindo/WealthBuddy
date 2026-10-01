// The answer: verdict, the numbers behind it, the plan in order, and ways to make it work.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/format.dart';
import 'add_money_sheet.dart';
import 'widgets.dart';
import 'wizard_screen.dart';

class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.projectId});
  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider).data;
    final matches = data.projects.where((x) => x.id == projectId);
    if (matches.isEmpty) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This project was removed.')));
    final p = matches.first;
    final t = Theme.of(context).textTheme;

    if (!data.money.complete) {
      return Scaffold(
        appBar: AppBar(title: Text(p.name)),
        body: ScreenBody(children: [
          const Text('A few answers about your money are missing.'),
          FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WizardScreen.money())), child: const Text('Answer them')),
        ]),
      );
    }

    final a = assess(data.money, p, today: todayIso());
    final k = kindOf(p.type);
    final tone = verdictTone(a.verdict);
    final c = toneColor(context, tone);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            tooltip: 'Change answers',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WizardScreen.edit(p.id))),
          ),
          IconButton(
            tooltip: 'Delete project',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(context, 'Delete ${p.name}?', 'This removes the project from this phone.', 'Delete')) {
                ref.read(appProvider.notifier).update((d) => d.projects.removeWhere((x) => x.id == p.id));
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ScreenBody(children: [
          // What it is
          Row(children: [
            CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), child: Icon(kindIcon(p.type))),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${k.label} · ${money(p.cost)} · by ${monthLabel(p.target)}${a.loan ? ' · with a ${k.loanName}' : ''}', style: t.bodyMedium),
            ),
          ]),

          // The verdict
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.5))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Tag(verdictLabel(a.verdict), tone: tone),
              const SizedBox(height: 8),
              Text(a.headline, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(a.summary, style: t.bodyMedium),
            ]),
          ),

          // Money set aside
          Section(title: 'Money set aside', children: [
            Row2('For this project', '${money(a.earmarked)} of ${money(a.upfront)}', bold: true),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: a.upfront > 0 ? (a.earmarked / a.upfront).clamp(0, 1).toDouble() : 0,
                minHeight: 8,
                color: toneColor(context, Tone.good),
                backgroundColor: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final c in p.contributions.reversed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      '${c.source} · ${_day(c.date)}${c.to == 'cushion' ? ' · to safety cushion' : c.to == 'card' ? ' · to credit card' : ''}',
                      style: t.bodySmall,
                    ),
                  ),
                  Text('+${fmt(c.amount)}', style: t.bodySmall?.copyWith(color: toneColor(context, Tone.good))),
                ]),
              ),
            if (p.contributions.isEmpty) note(context, 'Nothing set aside yet. Add a bonus or gift when one comes in.'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => showAddMoney(context, p.id), icon: const Icon(Icons.add), label: const Text('Add money')),
            ),
          ]),

          // The numbers behind it
          Section(title: 'The numbers', children: [
            Row2('Spare each month', money(a.surplus), tone: a.surplus > 0 ? null : Tone.bad),
            Row2(a.loan ? (k.fees > 0 ? 'Down payment and fees' : 'Down payment') : 'Needed', money(a.upfront)),
            Row2('Safety cushion', a.small ? 'Not needed first' : '${money(a.efHave)} of ${money(a.efTarget)}'),
            if (a.loan) Row2('Loan instalment', '${money(a.emi)} / month'),
            if (a.dbr != null) Row2('Loan repayments after', '${a.dbr!.toStringAsFixed(0)}% of pay', tone: a.dbr! > 50 ? Tone.bad : (a.dbr! > 35 ? Tone.warn : null)),
            if (a.running > 0) Row2('Running costs', '${money(a.running)} / month'),
            if (a.emi > 0 || a.running > 0) Row2('Spare after buying', '${money(a.afterSurplus)} / month', tone: a.afterSurplus < 0 ? Tone.bad : null),
            Row2('Could be ready', a.readyLabel, bold: true),
          ]),

          // The plan, in order
          Section(title: 'Your plan', children: [
            for (var n = 0; n < a.steps.length; n++) _StepTile(number: n + 1, step: a.steps[n], last: n == a.steps.length - 1),
          ]),

          if (a.options.isNotEmpty)
            Section(title: 'Ways to make it work', children: [
              for (final o in a.options) Padding(padding: const EdgeInsets.only(bottom: 10), child: richBold(context, o)),
            ]),

          if (a.watchouts.isNotEmpty)
            Section(title: 'Good to know', children: [
              for (final w in a.watchouts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(child: Text(w, style: t.bodyMedium)),
                  ]),
                ),
            ]),

          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WizardScreen.edit(p.id))),
            icon: const Icon(Icons.tune),
            label: const Text('Change answers'),
          ),
          note(context,
              'Guidance from fixed rules for planning, not financial advice. Lending rules and costs are estimates; check them with your bank before you commit.'),
        ]),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.number, required this.step, required this.last});
  final int number;
  final PlanStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: step.done ? toneColor(context, Tone.good) : cs.primary),
            child: step.done
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text('$number', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          if (!last) Expanded(child: Container(width: 2, color: cs.outlineVariant)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 18, top: 3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(step.title, style: t.titleSmall),
                if (step.when.isNotEmpty) Tag(step.when, tone: Tone.plain),
              ]),
              const SizedBox(height: 4),
              Text(step.body, style: t.bodyMedium),
            ]),
          ),
        ),
      ]),
    );
  }
}

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _day(String iso) => '${int.parse(iso.substring(8, 10))} ${_mon[int.parse(iso.substring(5, 7)) - 1]} ${iso.substring(0, 4)}';
