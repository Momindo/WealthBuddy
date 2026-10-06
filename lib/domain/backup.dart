// Offline backup: everything in one file, encrypted with a password only the user knows.
//
// File layout (all integers big-endian):
//   "WBK1"  magic, 4 bytes
//   iterations  4 bytes   PBKDF2-HMAC-SHA256 rounds used to turn the password into the key
//   salt   16 bytes
//   nonce  12 bytes       AES-256-GCM
//   mac    16 bytes
//   ciphertext            UTF-8 JSON: {"app": "wealthbuddy", "created": yyyy-mm-dd, "version": "...", "data": AppData}
// The phone never keeps the password; without it the file can't be opened.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'models.dart';

const _magic = [0x57, 0x42, 0x4B, 0x31]; // WBK1
const int backupIterations = 120000;
const int minPasswordLength = 6;

class BackupError implements Exception {
  final String message;
  const BackupError(this.message);
  @override
  String toString() => message;
}

/// What a backup holds, shown before restoring it.
class BackupContents {
  final AppData data;
  final String created; // yyyy-mm-dd
  final String version;
  const BackupContents(this.data, this.created, this.version);
}

String backupFileName(String today) => 'wealthbuddy-backup-$today.wbk';

Future<SecretKey> _key(String password, List<int> salt, int iterations) =>
    Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256).deriveKeyFromPassword(password: password, nonce: salt);

Future<Uint8List> makeBackup(AppData d, String password,
    {required String today, required String version, int iterations = backupIterations}) async {
  if (password.length < minPasswordLength) throw const BackupError('Use at least $minPasswordLength characters.');
  final rnd = Random.secure();
  final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
  final nonce = List<int>.generate(12, (_) => rnd.nextInt(256));
  final clear = utf8.encode(jsonEncode({'app': 'wealthbuddy', 'created': today, 'version': version, 'data': d.toJson()}));
  final box = await AesGcm.with256bits().encrypt(clear, secretKey: await _key(password, salt, iterations), nonce: nonce);
  final out = BytesBuilder()
    ..add(_magic)
    ..add((ByteData(4)..setUint32(0, iterations)).buffer.asUint8List())
    ..add(salt)
    ..add(nonce)
    ..add(box.mac.bytes)
    ..add(box.cipherText);
  return out.toBytes();
}

Future<BackupContents> readBackup(Uint8List bytes, String password) async {
  if (bytes.length < 52 || !List.generate(4, (i) => bytes[i] == _magic[i]).every((x) => x)) {
    throw const BackupError('This isn\'t a WealthBuddy backup file.');
  }
  final iterations = ByteData.sublistView(bytes, 4, 8).getUint32(0);
  if (iterations < 1000 || iterations > 5000000) throw const BackupError('This backup file is damaged.');
  final salt = bytes.sublist(8, 24), nonce = bytes.sublist(24, 36), mac = bytes.sublist(36, 52), cipher = bytes.sublist(52);
  List<int> clear;
  try {
    clear = await AesGcm.with256bits().decrypt(SecretBox(cipher, nonce: nonce, mac: Mac(mac)), secretKey: await _key(password, salt, iterations));
  } on SecretBoxAuthenticationError {
    throw const BackupError('Wrong password, or the file is damaged.');
  }
  try {
    final j = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    if (j['app'] != 'wealthbuddy') throw const BackupError('This isn\'t a WealthBuddy backup file.');
    final data = AppData.fromJson((j['data'] as Map).cast<String, dynamic>());
    return BackupContents(data, (j['created'] as String?) ?? '', (j['version'] as String?) ?? '');
  } on BackupError {
    rethrow;
  } catch (_) {
    throw const BackupError('This backup file is damaged.');
  }
}
