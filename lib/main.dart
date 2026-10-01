import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/state.dart';
import 'ui/home_screen.dart';
import 'ui/widgets.dart';

void main() => runApp(const ProviderScope(child: WealthBuddyApp()));

class WealthBuddyApp extends ConsumerWidget {
  const WealthBuddyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(appProvider.select((m) => m.loaded));
    return MaterialApp(
      title: 'Wealth Buddy',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: loaded ? const HomeScreen() : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
