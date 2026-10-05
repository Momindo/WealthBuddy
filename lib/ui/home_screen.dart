import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/checkin.dart';
import '../domain/format.dart';
import '../domain/history.dart';
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
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('What are you planning?', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Pick one. Answer a few questions and you\'ll get a plan: whether you can afford it, by when, and what to do first.', style: t.bodyMedium),
          ]),
          GridView.count(
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
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WizardScreen.newProject(type))),
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
          ),
          if (checkInDue(data, today: today))
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Monthly check-in', style: t.titleSmall),
                  const SizedBox(height: 4),
                  Text('Your plans assume you\'ve followed them since ${monthLabel(monthKey(data.money.asOf!))}. Tell us what you have now to keep the dates honest.',
                      style: t.bodyMedium),
                  Align(alignment: Alignment.centerRight, child: FilledButton.tonal(onPressed: () => showCheckIn(context), child: const Text('Check in'))),
                ]),
              ),
            ),
          if (data.projects.isNotEmpty) ...[
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
                final sh = a?.share;
                final stale = a == null ? null : staleness(p, a, today: today);
                return ProjectCard(
                  moveNote: sinceStart(p),
                  staleNote: stale == null ? null : '⏱ ${stale.chip}',
                  planNote: sh == null || a!.readyIn == 0
                      ? null
                      : sh.waiting
                          ? (sh.blocked ? 'Waiting on the ${sh.after}' : 'Waiting · starts ${monthLabel(addMonths(monthKey(today), sh.startsAt))}')
                          : 'Saving now · ${money(sh.mainAmount)} a month',
                  projectName: p.name,
                  type: p.type,
                  assessment: a,
                  saved: a?.earmarked ?? p.saved,
                  why: a == null ? null : whyNotYet(a, today: today),
                  cost: p.cost,
                  wanted: monthLabel(p.target),
                  onOpen: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(projectId: p.id))),
                  onAdd: () => showAddMoney(context, p.id),
                );
              }),
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

/// A project on the home screen: verdict, progress toward the upfront amount, ready date, and Add money.
class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, this.planNote, this.staleNote, this.moveNote, this.why, required this.projectName, required this.type, required this.assessment, required this.saved, required this.cost,
      required this.wanted, required this.onOpen, required this.onAdd});
  final String projectName, type, wanted;
  final String? planNote; // saving now / waiting, when planned with other projects
  final String? staleNote; // the price is worth checking again
  final String? moveNote; // how far the ready date has moved since the start
  final String? why; // what's holding it back, in one sentence
  final Assessment? assessment;
  final double saved, cost;
  final VoidCallback onOpen, onAdd;

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final goal = a?.upfront ?? cost;
    final t = Theme.of(context).textTheme;
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
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: goal > 0 ? (saved / goal).clamp(0, 1).toDouble() : 0,
                minHeight: 8,
                color: toneColor(context, Tone.good),
                backgroundColor: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text('${money(saved)} of ${money(goal)} set aside${a != null && a.loan ? ' (down payment)' : ''}', style: t.bodySmall),
            Text(a == null ? 'Wanted by $wanted' : 'Ready ${a.readyLabel == 'Now' ? 'now' : a.readyLabel} · wanted by $wanted', style: t.bodySmall),
            if (why != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(why!, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
            if (moveNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Builder(builder: (context) {
                  final good = moveNote!.contains('sooner') || moveNote!.startsWith('Within');
                  return Text('${good ? '↑' : '↓'} $moveNote', style: t.bodySmall?.copyWith(color: toneColor(context, good ? Tone.good : Tone.warn)));
                }),
              ),
            if (staleNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(staleNote!, style: t.bodySmall?.copyWith(color: toneColor(context, Tone.warn), fontWeight: FontWeight.w600)),
              ),
            if (planNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(planNote!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
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
