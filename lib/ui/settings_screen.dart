import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/whatif.dart';
import '../domain/format.dart';
import '../domain/assess.dart';
import 'check_in_sheet.dart';
import 'tour_screen.dart';
import 'widgets.dart';
import 'wizard_screen.dart';

const appVersion = '0.13.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider).data;
    final s = data.settings, ctl = ref.read(appProvider.notifier);
    final t = Theme.of(context).textTheme;
    Widget header(String text) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 6), child: Text(text.toUpperCase(), style: t.labelSmall?.copyWith(letterSpacing: 0.8)));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(children: [
          header('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Icons.brightness_auto_outlined)),
                ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {s.theme},
              onSelectionChanged: (v) => ctl.update((d) => d.settings.theme = v.first),
            ),
          ),

          header('Planning'),
          SwitchListTile(
            title: const Text('Keep a safety cushion first'),
            subtitle: Text(data.money.cushion
                ? 'Months of essentials kept aside before saving for projects. Recommended.'
                : 'Off: savings go to projects straight away. One surprise bill could undo your plans.'),
            value: data.money.cushion,
            onChanged: (on) async {
              if (on) {
                ctl.update((d) => d.money.cushion = true, why: 'Safety cushion turned on');
                return;
              }
              final today = todayIso();
              final lines = <String>[];
              if (data.money.complete && data.projects.isNotEmpty) {
                final before = assessAll(data, today: today), after = whatIf(data, today: today, cushion: false);
                for (final p in data.projects) {
                  final b = before[p.id]!, a = after[p.id]!;
                  if (b.readyIn != a.readyIn) lines.add('${p.name}: ${b.readyLabel} → ${a.readyLabel}');
                }
              }
              final ok = await confirm(
                  context,
                  'Plan without a safety cushion?',
                  '${lines.isEmpty ? 'No ready dates change.' : lines.join('\n')}\n\nSavings go to your projects straight away. One surprise bill or a month without pay could undo your plans.',
                  'Turn off');
              if (ok) ctl.update((d) => d.money.cushion = false, why: 'Safety cushion turned off');
            },
          ),

          header('Reminders'),
          SwitchListTile(
            title: const Text('Payday reminder'),
            subtitle: Text(data.money.payday == null || data.money.payday == 0
                ? 'Set your payday below to get a reminder at 3 pm'
                : 'At 3 pm on payday: what to put aside and where it gets you'),
            value: s.reminders,
            onChanged: (on) async {
              if (on && data.money.payday != null && data.money.payday! > 0) {
                final ok = await ref.read(reminderProvider)?.requestPermission() ?? false;
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Notifications are off for WealthBuddy. Turn them on in your phone\'s settings to get reminders.')));
                }
              }
              ctl.update((d) => d.settings.reminders = on);
            },
          ),
          ListTile(
            title: const Text('Payday'),
            subtitle: Text(paydayLabel(data.money.payday)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickPayday(context, ref, data.money.payday),
          ),

          header('Security'),
          SwitchListTile(
            title: const Text('Lock with fingerprint or face'),
            subtitle: const Text('Asks when you open the app. Your phone\'s PIN works too.'),
            value: s.appLock,
            onChanged: (on) async {
              final lock = ref.read(lockProvider);
              if (on) {
                if (lock == null || !await lock.available()) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Set up a fingerprint, face or screen lock on your phone first.')));
                  }
                  return;
                }
                if (!await lock.unlock()) return; // confirm it works before turning it on
              }
              ctl.update((d) => d.settings.appLock = on);
            },
          ),

          header('Your data'),
          if (data.projects.isNotEmpty && data.money.complete)
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Check in now'),
              subtitle: const Text('Tell the plan what you actually have'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showCheckIn(context),
            ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Update my money'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WizardScreen.money())),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('How it works'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const TourScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Privacy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showPrivacy(context),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: toneColor(context, Tone.bad)),
            title: Text('Delete all data', style: TextStyle(color: toneColor(context, Tone.bad))),
            onTap: () async {
              if (await confirm(context, 'Delete all data?',
                  'Your projects, answers and settings are removed from this phone, along with the encryption key. This cannot be undone.', 'Delete everything')) {
                await ctl.wipe();
                if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
              }
            },
          ),

          header('About'),
          ListTile(
            title: const Text('WealthBuddy'),
            subtitle: const Text('Version $appVersion. Guidance for planning, not financial advice.'),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Future<void> _pickPayday(BuildContext context, WidgetRef ref, int? current) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (s) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Which day is your salary paid?', style: Theme.of(s).textTheme.titleLarge),
          const SizedBox(height: 16),
          PaydayPicker(selected: current, onSelected: (d) => Navigator.pop(s, d)),
        ]),
      ),
    );
    if (picked == null) return;
    if (picked > 0 && ref.read(appProvider).data.settings.reminders) await ref.read(reminderProvider)?.requestPermission();
    ref.read(appProvider.notifier).update((d) => d.money.payday = picked);
  }
}
