// Back up to a file and restore from one, from Settings. The file is encrypted with a password the user
// chooses; it's saved wherever they pick through Android's file dialog and never uploaded anywhere.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/backup.dart';
import '../domain/format.dart';
import '../domain/history.dart';
import '../domain/models.dart';
import '../services/file_bridge.dart';
import 'settings_screen.dart' show appVersion;
import 'widgets.dart';

// Key stretching is deliberately slow, so encryption runs off the main thread (plain data in, plain data out).
Future<Uint8List> _encrypt((Map<String, dynamic>, String, String) a) =>
    makeBackup(AppData.fromJson(a.$1), a.$2, today: a.$3, version: appVersion);
Future<BackupContents> _decrypt((Uint8List, String) a) => readBackup(a.$1, a.$2);

void _say(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Runs [work] behind a small "please wait" dialog.
Future<T> _busy<T>(BuildContext context, String label, Future<T> Function() work) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 20), Expanded(child: Text(label))])),
    ),
  );
  try {
    return await work();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

Future<void> backUpToFile(BuildContext context, WidgetRef ref) async {
  final password = await showDialog<String>(context: context, builder: (_) => const PasswordDialog(creating: true));
  if (password == null || !context.mounted) return;
  final data = ref.read(appProvider).data.copy();
  final today = todayIso();
  try {
    final bytes = await _busy(context, 'Encrypting your backup…',
        () => compute(_encrypt, (data.toJson(), password, today)));
    final saved = await FileBridge.save(backupFileName(today), bytes);
    if (!saved) return;
    ref.read(appProvider.notifier).update((d) => d.settings.lastBackup = today);
    if (context.mounted) _say(context, 'Backup saved. Keep the password safe: without it the file can\'t be opened.');
  } on MissingPluginException {
    if (context.mounted) _say(context, 'Backups work on Android for now.');
  } on PlatformException catch (e) {
    if (context.mounted) _say(context, 'Couldn\'t save the file (${e.message ?? e.code}).');
  }
}

Future<void> restoreFromFile(BuildContext context, WidgetRef ref) async {
  Uint8List? bytes;
  try {
    bytes = await FileBridge.open();
  } on MissingPluginException {
    if (context.mounted) _say(context, 'Backups work on Android for now.');
    return;
  } on PlatformException catch (e) {
    if (context.mounted) _say(context, 'Couldn\'t open the file (${e.message ?? e.code}).');
    return;
  }
  if (bytes == null || !context.mounted) return;
  final file = bytes;

  BackupContents? contents;
  String? error;
  while (contents == null) {
    final password = await showDialog<String>(context: context, builder: (_) => PasswordDialog(creating: false, error: error));
    if (password == null || !context.mounted) return;
    try {
      contents = await _busy(context, 'Opening the backup…', () => compute(_decrypt, (file, password)));
    } on BackupError catch (e) {
      error = e.message;
      if (!e.message.startsWith('Wrong password')) {
        if (context.mounted) _say(context, e.message);
        return;
      }
    }
    if (!context.mounted) return;
  }

  final c = contents;
  final n = c.data.projects.length;
  final ok = await confirm(
      context,
      'Restore this backup?',
      'Backup from ${c.created.isEmpty ? 'an unknown date' : dayLabel(c.created)}, with $n project${n == 1 ? '' : 's'}.\n\n'
          'This replaces everything on this phone now. Back up first if you want to keep what\'s here.',
      'Restore');
  if (!ok || !context.mounted) return;
  final current = ref.read(appProvider).data.settings;
  final restored = c.data
    ..settings.privacySeen = true
    ..settings.tourSeen = true
    ..settings.appLock = current.appLock; // the lock depends on this phone's fingerprint or face
  ref.read(appProvider.notifier).restore(restored);
  _say(context, 'Restored $n project${n == 1 ? '' : 's'} from ${c.created.isEmpty ? 'the backup' : dayLabel(c.created)}.');
}

/// Asks for the backup password. When [creating], asks twice and explains it can't be recovered.
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({super.key, required this.creating, this.error});
  final bool creating;
  final String? error;
  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final a = TextEditingController(), b = TextEditingController();
  bool hide = true;
  String? err;

  @override
  void initState() {
    super.initState();
    err = widget.error;
  }

  @override
  void dispose() {
    a.dispose();
    b.dispose();
    super.dispose();
  }

  void _ok() {
    if (a.text.length < minPasswordLength) return setState(() => err = 'Use at least $minPasswordLength characters.');
    if (widget.creating && a.text != b.text) return setState(() => err = 'The two passwords don\'t match.');
    Navigator.pop(context, a.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.creating ? 'Back up to a file' : 'Backup password'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.creating)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Choose a password for the file. You\'ll need it to restore. If you forget it, the backup can\'t be opened: nobody can recover it.',
                style: t.bodyMedium,
              ),
            ),
          TextField(
            controller: a,
            obscureText: hide,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                tooltip: hide ? 'Show password' : 'Hide password',
                icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => hide = !hide),
              ),
            ),
            onChanged: (_) => setState(() => err = null),
            onSubmitted: widget.creating ? null : (_) => _ok(),
          ),
          if (widget.creating) ...[
            const SizedBox(height: 12),
            TextField(
              controller: b,
              obscureText: hide,
              decoration: const InputDecoration(labelText: 'Same password again'),
              onChanged: (_) => setState(() => err = null),
              onSubmitted: (_) => _ok(),
            ),
          ],
          if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: TextStyle(color: toneColor(context, Tone.bad)))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _ok, child: Text(widget.creating ? 'Save backup' : 'Open')),
      ],
    );
  }
}
