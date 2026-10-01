// App state: one controller owns AppData (money answers + projects), saved encrypted on every change.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/encrypted_store.dart';
import '../domain/models.dart';

class AppModel {
  final bool loaded;
  final AppData data;
  const AppModel(this.loaded, this.data);
}

class AppController extends StateNotifier<AppModel> {
  AppController(this._store) : super(AppModel(false, AppData())) {
    _load();
  }
  final EncryptedStore _store;

  Future<void> _load() async {
    AppData? d;
    try {
      d = await _store.load();
    } catch (_) {
      d = null; // unreadable file (e.g. key lost after a restore): start fresh rather than crash
    }
    state = AppModel(true, d ?? AppData());
  }

  /// Every change: copy, change, publish, save.
  void update(void Function(AppData d) change) {
    final next = state.data.copy();
    change(next);
    state = AppModel(true, next);
    _store.save(next);
  }

  Future<void> wipe() async {
    await _store.wipe();
    state = AppModel(true, AppData());
  }
}

final storeProvider = Provider<EncryptedStore>((ref) => EncryptedStore());
final appProvider = StateNotifierProvider<AppController, AppModel>((ref) => AppController(ref.watch(storeProvider)));
