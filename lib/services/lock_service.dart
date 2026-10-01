// App lock with fingerprint, face, or the device PIN as a fallback. Uses the OS prompt; nothing is stored by the app.
import 'package:local_auth/local_auth.dart';

class LockService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Whether this phone can lock the app (biometrics or a device PIN/passcode is set up).
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Shows the OS prompt. Returns true when the user proves it's them.
  Future<bool> unlock() async {
    try {
      return await _auth.authenticate(localizedReason: 'Unlock WealthBuddy', persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    }
  }
}
