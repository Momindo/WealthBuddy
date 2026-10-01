// App state: one controller owns AppData (money answers, projects, settings), saved encrypted on every change.
// Every change also refreshes the payday reminders so they always match the plan.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/encrypted_store.dart';
import '../domain/models.dart';
import '../services/lock_service.dart';
import '../services/reminder_service.dart';

class AppModel {
  final bool loaded;
  final AppData data;
  const AppModel(this.loaded, this.data);
}

class AppController extends StateNotifier<AppModel> {
  AppController(this._store, this._reminders) : super(AppModel(false, AppData())) {
    _load();
  }
  final EncryptedStore _store;
  final ReminderService? _reminders;

  Future<void> _load() async {
    final started = DateTime.now();
    AppData? d;
    try {
      d = await _store.load();
    } catch (_) {
      d = null; // unreadable file (e.g. key lost after a restore): start fresh rather than crash
    }
    // Keep the splash up for about a second so it doesn't flash.
    final wait = const Duration(milliseconds: 3000) - DateTime.now().difference(started);
    if (wait > Duration.zero && _reminders != null) await Future<void>.delayed(wait);
    state = AppModel(true, d ?? AppData());
    _reminders?.reschedule(state.data);
  }

  /// Every change: copy, change, publish, save, refresh reminders.
  void update(void Function(AppData d) change) {
    final next = state.data.copy();
    change(next);
    state = AppModel(true, next);
    _store.save(next);
    _reminders?.reschedule(next);
  }

  Future<void> wipe() async {
    await _store.wipe();
    state = AppModel(true, AppData());
    _reminders?.reschedule(state.data); // cancels everything
  }
}

final storeProvider = Provider<EncryptedStore>((ref) => EncryptedStore());
final reminderProvider = Provider<ReminderService?>((ref) => ReminderService());
final lockProvider = Provider<LockService?>((ref) => LockService());
final appProvider = StateNotifierProvider<AppController, AppModel>((ref) => AppController(ref.watch(storeProvider), ref.watch(reminderProvider)));
