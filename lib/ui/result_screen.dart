// The answer: verdict, the numbers behind it, the plan in order, and ways to make it work.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/format.dart';
import '../domain/history.dart';
import '../domain/impact.dart';
import '../domain/models.dart';
import '../domain/whatif.dart';
import 'add_money_sheet.dart';
import 'whatif_screen.dart';
import 'widgets.dart';
import 'wizard_screen.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.projectId});
  final int projectId;
  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  int tab = 0; // 0 Plan, 1 Money, 2 More

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
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
            onPressed: () {
              // No "are you sure?": delete straight away and offer Undo.
              final ctl = ref.read(appProvider.notifier);
              final before = data.copy();
              final messenger = ScaffoldMessenger.of(context);
              ctl.update((d) => d.removeProject(p.id), why: '${p.name} removed');
              Navigator.pop(context);
              messenger.showSnackBar(SnackBar(
                content: Text('${p.name} deleted'),
                duration: const Duration(seconds: 6),
                action: SnackBarAction(label: 'Undo', onPressed: () => ctl.restore(before)),
              ));
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

          if (staleness(p, a, today: todayIso()) != null) PriceCheck(projectId: p.id),

          // The verdict
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.5))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _ProgressRing(value: a.upfront > 0 ? (a.earmarked / a.upfront).clamp(0, 1).toDouble() : 0, color: c),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Tag(verdictLabel(a.verdict), tone: tone),
                    const SizedBox(height: 6),
                    Text(a.headline, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    if (whyNotYet(a, today: todayIso()) != null)
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text(whyNotYet(a, today: todayIso())!, style: t.titleSmall?.copyWith(color: c))),
                  ]),
                ),
              ]),
              const SizedBox(height: 6),
              Text(a.summary, style: t.bodyMedium),
              if (a.wait != null) _WaitBox(wait: a.wait!),
              // The regret check: every line when it's tight, otherwise just the one that doesn't pass.
              for (final ch in a.checks.where((c) => a.verdict == 'tight' || !c.ok))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(ch.ok ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 18, color: toneColor(context, ch.ok ? Tone.good : Tone.warn)),
                    const SizedBox(width: 8),
                    Expanded(child: richBold(context, '**${ch.label}.** ${ch.detail}')),
                  ]),
                ),
            ]),
          ),

          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Plan'), icon: Icon(Icons.checklist)),
              ButtonSegment(value: 1, label: Text('Money'), icon: Icon(Icons.savings_outlined)),
              ButtonSegment(value: 2, label: Text('More'), icon: Icon(Icons.more_horiz)),
            ],
            selected: {tab},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => tab = v.first),
          ),

          if (tab == 0) ...[
          // The plan, in order
          Section(title: 'Your plan', children: [
            for (var n = 0; n < a.steps.length; n++) _StepTile(number: n + 1, step: a.steps[n], last: n == a.steps.length - 1),
          ]),
          if (a.options.isNotEmpty)
            Section(title: 'Ways to make it work', children: [
              for (final o in a.options) Padding(padding: const EdgeInsets.only(bottom: 10), child: richBold(context, o)),
            ]),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WhatIfScreen())),
            icon: const Icon(Icons.tune),
            label: const Text('What if…'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WizardScreen.edit(p.id))),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Change answers'),
          ),
          ],

          if (tab == 1) ...[
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
            if (a.earmarked - p.saved > 0.5)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Text('Planned saving since ${monthLabel(monthKey(data.money.asOf ?? todayIso()))} · assumed until you check in', style: t.bodySmall),
                  ),
                  Text('+${fmt(a.earmarked - p.saved)}', style: t.bodySmall?.copyWith(color: toneColor(context, Tone.good))),
                ]),
              ),
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
          if (data.projects.length >= 2) SplitSection(projectId: p.id),
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
          ],

          if (tab == 2) ...[
          if (p.history.length >= 2) HistorySection(project: p, assessment: a),
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
            if (p.history.length < 2 && a.watchouts.isEmpty) note(context, 'Nothing more for now. Changes to your ready date will show here.'),
          ],

          note(context,
              'Guidance from fixed rules for planning, not financial advice. Lending rules and costs are estimates; check them with your bank before you commit.'),
        ]),
      ),
    );
  }
}

/// How much of the upfront amount is held, as a ring with the percentage inside.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.value, required this.color});
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '${(value * 100).floor()}% saved',
        child: SizedBox(
          width: 64,
          height: 64,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(value: value, strokeWidth: 7, color: color, backgroundColor: Theme.of(context).colorScheme.outlineVariant),
            ),
            Text('${(value * 100).floor()}%', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

/// "On time", "3 months early", "2 months late", or why there's no date.
String timingLabel(Assessment a) {
  if (a.readyIn == null) return 'not reachable yet';
  if (a.readyIn == 0) return 'ready now';
  final d = a.monthsLeft - a.readyIn!;
  return 'ready ${a.readyLabel} · ${d == 0 ? 'on time' : d > 0 ? '${durationLabel(d)} early' : '${durationLabel(-d)} late'}';
}

/// How spare money is split between this project and the others: who's saving now and how much,
/// who waits and why, and the choice to save for a waiting project now too, or plan this one on its own.
class SplitSection extends ConsumerWidget {
  const SplitSection({super.key, required this.projectId});
  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider).data;
    final today = todayIso();
    final t = Theme.of(context).textTheme;
    final ctl = ref.read(appProvider.notifier);
    final p = data.projects.firstWhere((x) => x.id == projectId);
    final all = assessAll(data, today: today);
    String at(int n) => n <= 0 ? 'now' : monthLabel(addMonths(monthKey(today), n));

    if (!data.isPlanned(projectId)) {
      final others = joinNames([for (final x in data.projects) if (x.id != projectId) x.name]);
      return Section(title: 'Your other projects', children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: toneColor(context, Tone.warn)),
          const SizedBox(width: 8),
          Expanded(child: Text('Planned on its own. The $others count on the same spare money, so these dates may be too hopeful.', style: t.bodyMedium)),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.link),
            label: const Text('Plan it with the others'),
            onPressed: () => ctl.update((d) => d.setSolo(projectId, false), why: '${p.name} planned with the others'),
          ),
        ),
      ]);
    }

    final planned = data.plannedProjects();
    final shares = {for (final x in planned) x.id: all[x.id]!.share!};
    final turns = shares.values.map((s) => s.turn).toSet().toList()..sort();
    final me = shares[projectId]!;
    final efDone = shares.values.first.efDone;
    final spare = (data.money.income ?? 0) - (data.money.spending ?? 0) - (data.money.repayments ?? 0);
    final needAll = planAll(data.money, planned, today: today, pinned: data.pinned.toSet()).needAll;
    final waiting = [for (final x in planned) if (shares[x.id]!.waiting) x.name];

    Widget row(Project x) {
      final a = all[x.id]!, sh = shares[x.id]!;
      final mine = x.id == projectId;
      final amount = a.readyIn == 0 ? '' : (sh.waiting ? '—' : '${fmt(sh.mainAmount)}/mo');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(kindIcon(x.type), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${x.name}${sh.pinned ? ' · saving now by choice' : ''}', style: mine ? t.bodyMedium?.copyWith(fontWeight: FontWeight.w700) : t.bodyMedium),
              Text(timingLabel(a), style: t.bodySmall?.copyWith(color: a.readyIn != null && a.readyIn! > a.monthsLeft ? toneColor(context, Tone.bad) : null)),
            ]),
          ),
          Text(amount, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ]),
      );
    }

    return Section(title: 'How your spare money is split', children: [
      Row2('Spare each month', money(spare), bold: true),
      if (efDone != null && efDone > 0) note(context, 'Your safety cushion comes first, full by ${at(efDone)}.'),
      const SizedBox(height: 8),
      for (final turn in turns) ...[
        Text(
          turn == 0
              ? 'SAVING NOW'
              : 'WAITING · ${shares.values.firstWhere((s) => s.turn == turn).blocked ? 'until the ${shares.values.firstWhere((s) => s.turn == turn).after} can be reached' : 'starts ${at(shares.values.firstWhere((s) => s.turn == turn).startsAt)}, after the ${shares.values.firstWhere((s) => s.turn == turn).after}'}',
          style: t.labelSmall?.copyWith(letterSpacing: 0.8),
        ),
        for (final x in planned.where((x) => shares[x.id]!.turn == turn).toList()..sort((a, b) => a.target.compareTo(b.target))) row(x),
        const SizedBox(height: 8),
      ],
      if (waiting.isNotEmpty)
        note(
            context,
            'Saving for all of them at once needs ${money(roundUp(needAll, 10))} a month. You have ${money(spare)}, '
            'so the ${joinNames(waiting)} ${waiting.length == 1 ? 'waits' : 'wait'}. '
            '${planned.every((x) => all[x.id]!.readyIn != null && all[x.id]!.readyIn! <= all[x.id]!.monthsLeft) ? 'Everything still makes its date.' : ''}'),
      Wrap(spacing: 4, children: [
        if (me.waiting && !me.pinned)
          TextButton.icon(
            icon: const Icon(Icons.play_arrow_outlined),
            label: const Text('Save for this now too'),
            onPressed: () async {
              final after = assessAll(data.copy()..setPinned(projectId, true), today: today);
              final changes = <String>[];
              for (final x in planned) {
                final b = all[x.id]!.readyIn, c = after[x.id]!.readyIn;
                if (b == c) continue;
                changes.add('${x.name}: ${b == null ? 'not reachable' : at(b)} → ${c == null ? 'not reachable' : at(c)}');
              }
              final body = changes.isEmpty ? 'Nothing else moves.' : 'Ready dates change:\n${changes.join('\n')}';
              if (await confirm(context, 'Save for ${p.name} now too?', body, 'Save now too')) {
                ctl.update((d) => d.setPinned(projectId, true), why: 'Saving for the ${p.name} now too');
              }
            },
          ),
        if (me.pinned)
          TextButton.icon(
            icon: const Icon(Icons.auto_mode),
            label: const Text('Let the plan decide'),
            onPressed: () => ctl.update((d) => d.setPinned(projectId, false), why: 'The plan decides the order again'),
          ),
        TextButton.icon(
          icon: const Icon(Icons.link_off),
          label: const Text('Plan this on its own'),
          onPressed: () {
            final before = data.copy();
            ctl.update((d) => d.setSolo(projectId, true), why: '${p.name} planned on its own');
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${p.name} is planned on its own'),
              action: SnackBarAction(label: 'Undo', onPressed: () => ctl.restore(before)),
            ));
          },
        ),
      ]),
    ]);
  }
}

/// "Is AED 120,000 still right?" with Still right, or Update showing what the new price does before saving it.
class PriceCheck extends ConsumerStatefulWidget {
  const PriceCheck({super.key, required this.projectId});
  final int projectId;
  @override
  ConsumerState<PriceCheck> createState() => _PriceCheckState();
}

class _PriceCheckState extends ConsumerState<PriceCheck> {
  final today = todayIso();
  bool editing = false;
  final cost = TextEditingController(), rate = TextEditingController();

  @override
  void dispose() {
    cost.dispose();
    rate.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim());
  String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appProvider).data;
    final p = data.projects.firstWhere((x) => x.id == widget.projectId);
    final a = assessIn(data, p, today: today);
    final st = staleness(p, a, today: today);
    if (st == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final c = toneColor(context, Tone.warn);
    final ctl = ref.read(appProvider.notifier);
    final since = monthLabel(monthKey(p.priceDate!));

    final body = StringBuffer();
    if (st.nearBuy && !st.price) {
      body.write('You\'re close to buying. Get a fresh quote so the plan uses the real price. ');
    } else {
      body.write('You set it in $since. ${priceMoves(p.type)} ');
    }
    if (st.rate) body.write('Your ${num1(p.rate)}% ${kindOf(p.type).loanName} rate was quoted then too; bank quotes usually last about 3 months.');

    // Live preview of the new price
    Widget? preview;
    final newCost = _num(cost), newRate = a.loan ? _num(rate) : p.rate;
    if (editing && newCost != null && newCost > 0 && newRate != null) {
      final q = p.copy()
        ..cost = newCost
        ..rate = newRate;
      final im = impactOf(data, data.money, q, today: today);
      preview = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ready ${a.readyLabel} → ${im.mine.readyLabel} · ${readyChange(a, im.mine)}', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        for (final o in im.others)
          Text('${o.p.name}: ${o.changed ? '${o.before.readyLabel} → ${o.after.readyLabel}' : 'no change'}', style: t.bodySmall),
      ]);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.timer_outlined, color: c, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Is ${money(p.cost)} still right?', style: t.titleSmall)),
        ]),
        const SizedBox(height: 6),
        Text(body.toString().trim(), style: t.bodyMedium),
        if (editing) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              flex: 3,
              child: TextField(
                  controller: cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [AmountFormatter()],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'New price', prefixText: 'AED ')),
            ),
            if (a.loan) ...[
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                    controller: rate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Rate', suffixText: '%')),
              ),
            ],
          ]),
          if (preview != null) Padding(padding: const EdgeInsets.only(top: 10), child: preview),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          if (!editing)
            TextButton(onPressed: () => ctl.update((d) => d.projects.firstWhere((x) => x.id == p.id).priceDate = today), child: const Text('Still right')),
          if (!editing)
            FilledButton.tonal(
              onPressed: () => setState(() {
                editing = true;
                cost.text = fmt(p.cost);
                rate.text = _plain(p.rate);
              }),
              child: const Text('Update'),
            ),
          if (editing) TextButton(onPressed: () => setState(() => editing = false), child: const Text('Cancel')),
          if (editing)
            FilledButton(
              onPressed: newCost == null || newCost <= 0 || newRate == null || newRate < 0 || newRate > 30
                  ? null
                  : () {
                      ctl.update((d) {
                        final x = d.projects.firstWhere((x) => x.id == p.id);
                        x.cost = newCost;
                        x.rate = newRate;
                        x.priceDate = today;
                      }, why: '${p.name}: price updated to ${money(newCost)}');
                      setState(() => editing = false);
                    },
              child: const Text('Save price'),
            ),
        ]),
      ]),
    );
  }
}

/// How the ready date has moved: a summary since the start, a small chart and each change with its reason.
class HistorySection extends StatelessWidget {
  const HistorySection({super.key, required this.project, required this.assessment});
  final Project project;
  final Assessment assessment;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final h = project.history;
    final since = sinceStart(project);
    final moved = monthsMoved(h.first.ready, h.last.ready);
    final sooner = moved != null && moved < 0;
    final setback = !sooner && since != null ? biggestSetback(project) : null;
    return Section(title: 'How your date has moved', children: [
      if (since != null)
        Row(children: [
          Icon(sooner ? Icons.trending_up : Icons.trending_down, color: toneColor(context, sooner ? Tone.good : Tone.warn)),
          const SizedBox(width: 8),
          Expanded(child: Text(since[0].toUpperCase() + since.substring(1), style: t.titleSmall)),
        ])
      else
        note(context, 'Back where you started: ready ${assessment.readyLabel}.'),
      if (setback != null) Padding(padding: const EdgeInsets.only(top: 4), child: note(context, 'Biggest step back: ${setback.why} (${dayLabel(setback.date)}).')),
      const SizedBox(height: 10),
      Semantics(
        label: 'Chart of the ready date over time: ${h.map((x) => x.ready == null ? 'out of reach' : monthLabel(x.ready!)).join(', then ')}',
        child: SizedBox(height: 120, child: CustomPaint(painter: _HistoryPainter(h, project.target, Theme.of(context).colorScheme), size: Size.infinite)),
      ),
      Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: note(context, 'Higher is sooner. The dashed line is when you want it.')),
      for (var i = h.length - 1; i >= 0; i--)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 82, child: Text(dayLabel(h[i].date), style: t.bodySmall)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h[i].ready == null ? 'Out of reach' : 'Ready ${monthLabel(h[i].ready!)}', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(h[i].why, style: t.bodySmall),
              ]),
            ),
            if (i > 0) _moveTag(context, monthsMoved(h[i - 1].ready, h[i].ready), h[i].ready),
          ]),
        ),
    ]);
  }

  Widget _moveTag(BuildContext context, int? m, String? ready) {
    if (m == null) return Tag(ready == null ? 'out of reach' : 'within reach', tone: ready == null ? Tone.bad : Tone.good);
    if (m == 0) return const SizedBox.shrink();
    return Tag('${m < 0 ? '↑' : '↓'} ${durationLabel(m.abs())} ${m < 0 ? 'sooner' : 'later'}', tone: m < 0 ? Tone.good : Tone.warn);
  }
}

/// Ready month over time, as steps. Sooner is higher; the dashed line is the want-by month.
class _HistoryPainter extends CustomPainter {
  _HistoryPainter(this.points, this.target, this.cs);
  final List<HistoryPoint> points;
  final String target;
  final ColorScheme cs;

  static int _idx(String ym) => int.parse(ym.substring(0, 4)) * 12 + int.parse(ym.substring(5, 7));

  @override
  void paint(Canvas canvas, Size size) {
    final known = [for (final p in points) if (p.ready != null) _idx(p.ready!)];
    if (known.isEmpty) return;
    final tgt = _idx(target);
    var lo = [...known, tgt].reduce(math.min), hi = [...known, tgt].reduce(math.max);
    if (hi == lo) {
      lo -= 1;
      hi += 1;
    }
    const pad = 8.0;
    double y(int m) => pad + (m - lo) / (hi - lo) * (size.height - 2 * pad);
    final n = points.length;
    double x(int i) => n == 1 ? size.width / 2 : pad + i / (n - 1) * (size.width - 2 * pad);

    // Want-by line
    final dash = Paint()
      ..color = cs.outline
      ..strokeWidth = 1;
    for (var dx = 0.0; dx < size.width; dx += 8) {
      canvas.drawLine(Offset(dx, y(tgt)), Offset(math.min(dx + 4, size.width), y(tgt)), dash);
    }

    final line = Paint()
      ..color = cs.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = cs.primary;
    final path = Path();
    var started = false;
    double? lastY;
    for (var i = 0; i < n; i++) {
      final r = points[i].ready;
      if (r == null) {
        started = false;
        continue;
      }
      final px = x(i), py = y(_idx(r));
      if (!started) {
        path.moveTo(px, py);
        started = true;
      } else {
        path.lineTo(px, lastY!);
        path.lineTo(px, py);
      }
      lastY = py;
      canvas.drawCircle(Offset(px, py), 3.5, dot);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter old) => old.points != points || old.target != target || old.cs != cs;
}

/// What the delay costs, line by line.
class _WaitBox extends StatelessWidget {
  const _WaitBox({required this.wait});
  final WaitCost wait;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String signed(double v) => '${v < 0 ? '−' : '+'}${fmt(v.abs())}';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (label, amount) in wait.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [Expanded(child: Text(label, style: t.bodySmall)), Text(signed(amount), style: t.bodySmall)]),
          ),
        const Divider(height: 10),
        Row(children: [
          Expanded(child: Text(wait.saves ? 'Waiting saves you' : 'Waiting costs you', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
          Text('${money(wait.total.abs())} · ${money(wait.perMonth.abs())} a month', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      ]),
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
