// App state: one controller owns AppData (money answers, projects, settings), saved encrypted on every change.
// Every change also refreshes the payday reminders so they always match the plan.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/encrypted_store.dart';
import '../domain/format.dart';
import '../domain/history.dart';
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
    // Projects saved before prices were dated start from today, so nothing is flagged straight away.
    var dated = false;
    for (final p in d?.projects ?? <Project>[]) {
      if (p.priceDate == null) {
        p.priceDate = todayIso();
        dated = true;
      }
    }
    // Savings answers given before plans assumed they're followed count from today.
    if (d != null && d.money.complete && d.money.asOf == null) {
      d.money.asOf = todayIso();
      dated = true;
    }
    // Every project gets a first history point, so later moves have something to compare with.
    if (d != null && d.projects.any((p) => p.history.isEmpty)) {
      recordHistory(d, today: todayIso(), why: timePassed, first: 'Plan as of ${dayLabel(todayIso())}');
      dated = true;
    }
    if (dated && d != null) await _store.save(d);
    // Keep the splash up for about three seconds.
    final wait = const Duration(milliseconds: 3000) - DateTime.now().difference(started);
    if (wait > Duration.zero && _reminders != null) await Future<void>.delayed(wait);
    state = AppModel(true, d ?? AppData());
    _reminders?.reschedule(state.data);
  }

  /// Puts back a snapshot taken before a change (Undo).
  void restore(AppData snapshot) {
    final next = snapshot.copy();
    state = AppModel(true, next);
    _store.save(next);
    _reminders?.reschedule(next);
  }

  /// Every change: copy, change, publish, save, refresh reminders.
  /// [why] marks a change that can move ready dates; it's recorded in each project's history when it does.
  /// Any move found just before the change is put down to time passing.
  void update(void Function(AppData d) change, {String? why}) {
    final next = state.data.copy();
    final today = todayIso();
    if (why != null) recordHistory(next, today: today, why: timePassed);
    change(next);
    if (why != null) recordHistory(next, today: today, why: why);
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
