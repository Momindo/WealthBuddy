// App state: one controller owns the AppState, and every screen reads a Finance built from it.
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/encrypted_store.dart';
import '../domain/basics.dart';
import '../domain/finance.dart';
import '../domain/models.dart';
import '../domain/recurring.dart';

String todayIso() => isoOf(DateTime.now());

class AppModel {
  final bool loaded;
  final AppState? data;
  const AppModel(this.loaded, this.data);
}

class AppController extends StateNotifier<AppModel> {
  AppController(this._store) : super(const AppModel(false, null)) {
    _load();
  }
  final EncryptedStore _store;

  Future<void> _load() async {
    AppState? s;
    try {
      s = await _store.load();
    } catch (_) {
      s = null; // unreadable file (e.g. key lost after a restore): start fresh rather than crash
    }
    if (s != null) syncRecurring(s, todayIso());
    state = AppModel(true, s);
  }

  AppState? get data => state.data;

  /// Every change goes through here: copy, change, expand repeating costs, save, publish.
  void update(void Function(AppState s) change) {
    final cur = state.data;
    if (cur == null) return;
    final next = cur.copy();
    change(next);
    syncRecurring(next, todayIso());
    state = AppModel(true, next);
    _store.save(next);
  }

  Future<void> startFresh({int? adults, int? kids}) async {
    final s = AppState(budgets: Map.of(defaultBudgets));
    if (adults != null) {
      s.profile
        ..adults = adults
        ..kids = kids ?? 0
        ..efMonths = (kids ?? 0) > 0 ? 9 : 6;
    }
    state = AppModel(true, s);
    await _store.save(s);
  }

  Future<void> startExample() async {
    final raw = await rootBundle.loadString('assets/sample_state.json');
    final s = AppState.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>())
      ..example = true
      ..setup = {'salary': 'done', 'housing': 'done', 'costs': 'done', 'dismissed': true};
    state = AppModel(true, s);
    await _store.save(s);
  }

  Future<void> wipe() async {
    await _store.wipe();
    state = const AppModel(true, null);
  }
}

final storeProvider = Provider<EncryptedStore>((ref) => EncryptedStore());
final appProvider = StateNotifierProvider<AppController, AppModel>((ref) => AppController(ref.watch(storeProvider)));

/// The shared plan. Rebuilt whenever the state changes, so every tab stays in step.
final financeProvider = Provider<Finance?>((ref) {
  final s = ref.watch(appProvider).data;
  return s == null ? null : Finance(s, today: todayIso());
});

/// Selected tab: 0 Overview, 1 Spending, 2 Wealth, 3 Invest, 4 Suggestions.
final tabProvider = StateProvider<int>((ref) => 0);
final showSetupProvider = StateProvider<int?>((ref) => null); // setup step to open, or null
final viewMonthProvider = StateProvider<String?>((ref) => null);

int tabFor(String action) => switch (action) { 'spend' => 1, 'wealth' || 'projects' => 2, 'invest' => 3, 'advice' => 4, _ => 0 };
