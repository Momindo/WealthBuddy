import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/format.dart';
import 'result_screen.dart';
import 'widgets.dart';
import 'wizard_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider).data;
    final today = todayIso();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text.rich(TextSpan(children: [
          TextSpan(text: 'Wealth', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: 'Buddy', style: TextStyle(fontWeight: FontWeight.w700, color: gold)),
        ])),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'money') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const WizardScreen.money()));
              } else if (v == 'wipe' &&
                  await confirm(context, 'Delete all data?', 'Your projects and answers are removed from this phone, along with the encryption key. This cannot be undone.',
                      'Delete everything')) {
                await ref.read(appProvider.notifier).wipe();
              }
            },
            itemBuilder: (_) => [
              if (data.money.complete) const PopupMenuItem(value: 'money', child: Text('Update my money')),
              const PopupMenuItem(value: 'wipe', child: Text('Delete all data')),
            ],
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
          if (data.projects.isNotEmpty) ...[
            Text('Your projects', style: t.titleMedium),
            for (final p in data.projects)
              Builder(builder: (context) {
                final a = data.money.complete ? assess(data.money, p, today: today) : null;
                return Card(
                  child: ListTile(
                    leading: Icon(kindIcon(p.type)),
                    title: Text(p.name),
                    subtitle: Text('${money(p.cost)} · by ${monthLabel(p.target)}'),
                    trailing: a == null ? null : Tag(verdictLabel(a.verdict), tone: verdictTone(a.verdict)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(projectId: p.id))),
                  ),
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
