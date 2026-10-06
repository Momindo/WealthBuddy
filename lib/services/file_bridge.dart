// Save and open files through Android's own file dialogs (Storage Access Framework), so backups stay offline:
// the user picks where the file goes (phone storage, SD card, USB) and nothing is uploaded anywhere.
// The native side lives in MainActivity (written by tool/patch_platforms.py). Not available on iOS yet.
import 'package:flutter/services.dart';

class FileBridge {
  static const _channel = MethodChannel('wealthbuddy/files');

  /// Asks where to save [bytes]; true when saved, false when the user cancelled.
  static Future<bool> save(String name, Uint8List bytes) async =>
      (await _channel.invokeMethod<bool>('save', {'name': name, 'bytes': bytes})) ?? false;

  /// Asks for a file and returns its bytes, or null when the user cancelled.
  static Future<Uint8List?> open() => _channel.invokeMethod<Uint8List>('open');
}
