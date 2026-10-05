import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/checkin.dart';
import '../domain/format.dart';
import '../domain/history.dart';
import '../domain/models.dart';
import '../domain/reminders.dart';
import 'add_money_sheet.dart';
import 'check_in_sheet.dart';
import 'logo.dart';
import 'settings_screen.dart';
import 'result_screen.dart';
import 'whatif_screen.dart';
import 'widgets.dart';
import 'wizard_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider).data;
    final today = todayIso();
    final t = Theme.of(context).textTheme;
    final all = data.money.complete ? assessAll(data, today: today) : null;
    final hasProjects = data.projects.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const BrandTitle(),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: ScreenBody(children: [
          if (!hasProjects) ...[
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('What are you planning?', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Pick one. Answer a few questions and you\'ll get a plan: whether you can afford it, by when, and what to do first.', style: t.bodyMedium),
            ]),
            const KindGrid(),
          ],
          if (hasProjects) ...[
            PaydayCard(today: today),
            Row(children: [
              Expanded(child: Text('Your projects', style: t.titleMedium)),
              if (data.money.complete)
                TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WhatIfScreen())),
                  icon: const Icon(Icons.tune),
                  label: const Text('What if…'),
                ),
            ]),
            for (final p in data.projects)
              Builder(builder: (context) {
                final a = all?[p.id];
                return ProjectCard(
                  status: a == null ? null : cardStatus(p, a, today: today),
                  projectName: p.name,
                  type: p.type,
                  assessment: a,
                  saved: a?.earmarked ?? p.saved,
                  cost: p.cost,
                  wanted: monthLabel(p.target),
                  onOpen: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(projectId: p.id))),
                  onAdd: () => showAddMoney(context, p.id),
                );
              }),
            OutlinedButton.icon(
              onPressed: () => showKindPicker(context),
              icon: const Icon(Icons.add),
              label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('New project')),
            ),
          ],
          Row(children: [
            Icon(Icons.lock_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: note(context, 'No account and no personal details. Everything stays on this phone, encrypted.')),
          ]),
        ]),
      ),
    );
  }
}

/// The one status line a project card shows, by priority: a stale price, what's holding it back,
/// then how far the date has moved. Null when there's nothing to say.
({String text, Tone tone})? cardStatus(Project p, Assessment a, {required String today}) {
  final stale = staleness(p, a, today: today);
  if (stale != null) return (text: '⏱ ${stale.chip}', tone: Tone.warn);
  final why = whyNotYet(a, today: today);
  if (why != null) return (text: why, tone: Tone.plain);
  final moved = sinceStart(p);
  if (moved != null) {
    final good = moved.contains('sooner') || moved.startsWith('Within');
    return (text: '${good ? '↑' : '↓'} $moved', tone: good ? Tone.good : Tone.warn);
  }
  return null;
}

/// Project types, two per row.
class KindGrid extends StatelessWidget {
  const KindGrid({super.key, this.onPicked});
  final VoidCallback? onPicked; // e.g. close the sheet first
  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.5,
        children: [
          for (final type in kinds.keys)
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  onPicked?.call();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => WizardScreen.newProject(type)));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Icon(kindIcon(type), color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(kindLabel(type), style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
            ),
        ],
      );
}

Future<void> showKindPicker(BuildContext context) {
  final nav = Navigator.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('What are you planning?', style: Theme.of(sheet).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Builder(builder: (_) {
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.5,
            children: [
              for (final type in kinds.keys)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(sheet);
                      nav.push(MaterialPageRoute(builder: (_) => WizardScreen.newProject(type)));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(children: [
                        Icon(kindIcon(type), color: Theme.of(sheet).colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text(kindLabel(type), style: const TextStyle(fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  ),
                ),
            ],
          );
        }),
      ]),
    ),
  );
}

/// "This payday": the one thing to do with this month's money, across all projects, plus the check-in when due.
class PaydayCard extends ConsumerWidget {
  const PaydayCard({super.key, required this.today});
  final String today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider).data;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final due = checkInDue(data, today: today);
    final next = paydayReminders(data, today: today, count: 1);
    final r = next.isNotEmpty && data.settings.paydayDone != next.first.date ? next.first : null;
    if (r == null && !due) return const SizedBox.shrink();

    final isToday = r != null && r.date == today;
    final title = r == null ? 'Monthly check-in' : (isToday ? 'Payday today' : 'Next payday · ${dayLabel(r.date)}');
    final body = r == null
        ? 'Your plans assume you\'ve followed them since ${monthLabel(monthKey(data.money.asOf!))}. Tell us what you have now to keep the dates honest.'
        : (isToday ? r.body : r.body.replaceAll(' today.', '.'));
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(r == null ? Icons.fact_check_outlined : Icons.event_available_outlined, size: 20, color: cs.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: t.titleSmall?.copyWith(color: cs.onPrimaryContainer))),
          ]),
          if (r != null && !r.title.startsWith('Payday')) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.title, style: t.titleMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700))),
          const SizedBox(height: 6),
          Text(body, style: t.bodyMedium?.copyWith(color: cs.onPrimaryContainer)),
          Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
            if (due) TextButton(onPressed: () => showCheckIn(context), child: const Text('Check in')),
            if (isToday)
              FilledButton.tonal(
                onPressed: () => ref.read(appProvider.notifier).update((d) => d.settings.paydayDone = r!.date),
                child: const Text('Done ✓'),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// A project on the home screen: verdict, progress toward the upfront amount, ready date, one status line, and Add money.
class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, this.status, required this.projectName, required this.type, required this.assessment, required this.saved, required this.cost,
      required this.wanted, required this.onOpen, required this.onAdd});
  final String projectName, type, wanted;
  final ({String text, Tone tone})? status;
  final Assessment? assessment;
  final double saved, cost;
  final VoidCallback onOpen, onAdd;

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final goal = a?.upfront ?? cost;
    final t = Theme.of(context).textTheme;
    final st = status;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(kindIcon(type)),
              const SizedBox(width: 10),
              Expanded(child: Text(projectName, style: t.titleSmall)),
              if (a != null) Tag(verdictLabel(a.verdict), tone: verdictTone(a.verdict)),
            ]),
            const SizedBox(height: 10),
            Semantics(
              label: '${money(saved)} of ${money(goal)} set aside',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: goal > 0 ? (saved / goal).clamp(0, 1).toDouble() : 0,
                  minHeight: 8,
                  color: toneColor(context, Tone.good),
                  backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text('${money(saved)} of ${money(goal)} set aside${a != null && a.loan ? ' (down payment)' : ''}', style: t.bodySmall),
            Text(a == null ? 'Wanted by $wanted' : 'Ready ${a.readyLabel == 'Now' ? 'now' : a.readyLabel} · wanted by $wanted', style: t.bodySmall),
            if (st != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(st.text,
                    style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: st.tone == Tone.plain ? null : toneColor(context, st.tone))),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add money')),
            ),
          ]),
        ),
      ),
    );
  }
}
