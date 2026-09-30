// Encrypted local storage. The whole app state is one AES-256-GCM encrypted file in the app's
// private directory; the key lives in the iOS Keychain / Android Keystore via flutter_secure_storage.
// Nothing is sent anywhere. When data grows, this can move to SQLCipher without changing callers.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';

class EncryptedStore {
  static const _keyName = 'wealthbuddy.data-key.v1';
  static const _fileName = 'wealthbuddy.bin';

  // resetOnError is off: a transient Keystore error must never silently replace the key,
  // because that would make the saved data unreadable.
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  final AesGcm _algo = AesGcm.with256bits();

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/$_fileName');

  Future<SecretKey> _key() async {
    var b64 = await _secure.read(key: _keyName);
    if (b64 == null) {
      final key = await _algo.newSecretKey();
      b64 = base64Encode(await key.extractBytes());
      await _secure.write(key: _keyName, value: b64);
    }
    return SecretKey(base64Decode(b64));
  }

  Future<AppState?> load() async {
    final f = await _file();
    if (!await f.exists()) return null;
    final box = SecretBox.fromConcatenation(await f.readAsBytes(), nonceLength: _algo.nonceLength, macLength: _algo.macAlgorithm.macLength);
    final clear = await _algo.decrypt(box, secretKey: await _key());
    return AppState.fromJson((jsonDecode(utf8.decode(clear)) as Map).cast<String, dynamic>());
  }

  Future<void> save(AppState s) async {
    final box = await _algo.encrypt(utf8.encode(jsonEncode(s.toJson())), secretKey: await _key());
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(box.concatenation(), flush: true);
    await tmp.rename(f.path); // atomic replace, so a crash mid-write never corrupts the data
  }

  /// "Delete all data": removes the file and the key.
  Future<void> wipe() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
    await _secure.delete(key: _keyName);
  }
}
