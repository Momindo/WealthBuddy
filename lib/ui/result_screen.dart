// The answer: verdict, the numbers behind it, the plan in order, and ways to make it work.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/format.dart';
import '../domain/models.dart';
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

    final a = assessIn(data, p, today: todayIso());
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
                ref.read(appProvider.notifier).update((d) => d.removeProject(p.id));
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

          if (data.projects.length >= 2) LinkedPlanSection(projectId: p.id),

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

/// How this project fits with the others: the order they're saved for, each one's ready date,
/// moving it up or down, and a suggestion when another order gets everything done sooner.
class LinkedPlanSection extends ConsumerWidget {
  const LinkedPlanSection({super.key, required this.projectId});
  final int projectId;

  /// Months until every project in [order] could be ready, or null if one can't be.
  static int? _allDone(Money m, List<Project> order, String today) {
    var last = 0;
    for (final (_, a) in assessChain(m, order, today: today)) {
      if (a.readyIn == null) return null;
      if (a.readyIn! > last) last = a.readyIn!;
    }
    return last;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider).data;
    final today = todayIso();
    final t = Theme.of(context).textTheme;
    final ctl = ref.read(appProvider.notifier);
    final order = data.linkedProjects();
    final p = data.projects.firstWhere((x) => x.id == projectId);

    if (!order.any((x) => x.id == projectId)) {
      final others = data.projects.where((x) => x.id != projectId).map((x) => x.name).join(', ');
      return Section(title: 'Your other projects', children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: toneColor(context, Tone.warn)),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Planned on its own. $others count on the same spare money, so these dates may be too hopeful.', style: t.bodyMedium)),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.link),
            label: const Text('Plan it with the others'),
            onPressed: () => ctl.update((d) {
              final current = d.linkedProjects().isNotEmpty
                  ? d.linkedProjects()
                  : ([...d.projects.where((x) => x.id != projectId)]..sort((a, b) => a.target.compareTo(b.target)));
              final i = current.indexWhere((x) => x.target.compareTo(p.target) > 0);
              d.link(projectId, at: i < 0 ? current.length : i);
            }),
          ),
        ),
      ]);
    }

    final chain = assessChain(data.money, order, today: today);
    final now = _allDone(data.money, order, today);
    String at(int n) => n <= 0 ? 'now' : monthLabel(addMonths(monthKey(today), n));

    // Would swapping two neighbours get everything done sooner?
    (int, int, List<(Project, Assessment)>)? best; // swap index, months saved, the plan after swapping
    for (var i = 0; i < order.length - 1; i++) {
      final alt = [...order]..[i] = order[i + 1]..[i + 1] = order[i];
      final done = _allDone(data.money, alt, today);
      if (done == null) continue;
      final saved = now == null ? 1000 : now - done;
      if (saved >= 1 && (best == null || saved > best.$2)) best = (i, saved, assessChain(data.money, alt, today: today));
    }

    return Section(title: 'Planned with your other projects', children: [
      note(context, 'Spare money goes to each in turn. Once one is bought, its monthly costs are counted in the next.'),
      const SizedBox(height: 8),
      for (var i = 0; i < chain.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 10),
            Icon(kindIcon(chain[i].$1.type), size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(chain[i].$1.name,
                  style: chain[i].$1.id == projectId ? t.bodyMedium?.copyWith(fontWeight: FontWeight.w700) : t.bodyMedium),
            ),
            Text(chain[i].$2.readyLabel == 'Now' ? 'Ready now' : chain[i].$2.readyLabel, style: t.bodySmall),
            if (chain[i].$1.id == projectId) ...[
              IconButton(
                  tooltip: 'Earlier',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: i == 0 ? null : () => ctl.update((d) => d.move(projectId, -1))),
              IconButton(
                  tooltip: 'Later',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: i == chain.length - 1 ? null : () => ctl.update((d) => d.move(projectId, 1))),
            ],
          ]),
        ),
      if (best != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: toneColor(context, Tone.good).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            richBold(
                context,
                '**Tip: do the ${order[best.$1 + 1].name} before the ${order[best.$1].name}.** '
                '${now == null ? 'That makes every project reachable' : 'Everything is done by ${at(now - best.$2)}, ${durationLabel(best.$2)} sooner'}: '
                '${best.$3.map((e) => '${e.$1.name} ${e.$2.readyLabel == 'Now' ? 'now' : e.$2.readyLabel}').join(', ')}.'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  final swapId = order[best!.$1 + 1].id;
                  ctl.update((d) => d.move(swapId, -1));
                },
                child: const Text('Swap the order'),
              ),
            ),
          ]),
        ),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.link_off),
          label: const Text('Plan this on its own'),
          onPressed: () async {
            if (await confirm(context, 'Plan ${p.name} on its own?',
                'Its plan will ignore your other projects, so both may count on the same spare money.', 'Plan on its own')) {
              ctl.update((d) => d.unlink(projectId));
            }
          },
        ),
      ),
    ]);
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
