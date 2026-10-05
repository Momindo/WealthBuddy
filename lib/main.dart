import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/state.dart';
import 'ui/home_screen.dart';
import 'ui/logo.dart';
import 'ui/tour_screen.dart';
import 'ui/widgets.dart';

void main() => runApp(const ProviderScope(child: WealthBuddyApp()));

class WealthBuddyApp extends ConsumerWidget {
  const WealthBuddyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(appProvider);
    final mode = switch (model.data.settings.theme) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
    return MaterialApp(
      title: 'WealthBuddy',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      home: model.loaded ? const LockGate(child: PrivacyGate(child: HomeScreen())) : const SplashView(),
    );
  }
}

/// Shows the privacy promise once, the first time the app opens.
class PrivacyGate extends ConsumerStatefulWidget {
  const PrivacyGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends ConsumerState<PrivacyGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final s = ref.read(appProvider).data.settings;
      if (!s.privacySeen) {
        await showPrivacy(context);
        ref.read(appProvider.notifier).update((d) => d.settings.privacySeen = true);
      }
      // The feature tour follows the privacy promise, once.
      if (mounted && !ref.read(appProvider).data.settings.tourSeen) {
        await Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const TourScreen()));
        ref.read(appProvider.notifier).update((d) => d.settings.tourSeen = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// When app lock is on: asks for fingerprint, face or PIN on launch and whenever the app comes back from the background.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> with WidgetsBindingObserver {
  late bool locked;
  bool prompting = false;

  bool get _enabled => ref.read(appProvider).data.settings.appLock && ref.read(lockProvider) != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    locked = _enabled;
    if (locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused && _enabled && !prompting) setState(() => locked = true);
    if (s == AppLifecycleState.resumed && locked && !prompting) _unlock();
  }

  Future<void> _unlock() async {
    if (prompting) return;
    prompting = true;
    final ok = await ref.read(lockProvider)?.unlock() ?? true;
    prompting = false;
    if (ok && mounted) setState(() => locked = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!locked) return widget.child;
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const LogoMark(size: 72),
          const SizedBox(height: 16),
          Text('WealthBuddy is locked', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _unlock, icon: const Icon(Icons.fingerprint), label: const Text('Unlock')),
        ]),
      ),
    );
  }
}
