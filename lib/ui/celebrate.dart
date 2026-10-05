// A small celebration the first time a project becomes affordable.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/format.dart';
import 'widgets.dart';

/// Wraps the home screen: after each build, celebrates any project that has just become affordable, once.
class CelebrationWatcher extends ConsumerStatefulWidget {
  const CelebrationWatcher({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<CelebrationWatcher> createState() => _CelebrationWatcherState();
}

class _CelebrationWatcherState extends ConsumerState<CelebrationWatcher> {
  bool showing = false;

  Future<void> _check() async {
    if (showing || !mounted) return;
    final d = ref.read(appProvider).data;
    if (!d.money.complete || d.projects.isEmpty) return;
    final all = assessAll(d, today: todayIso());
    for (final p in d.projects) {
      final a = all[p.id]!;
      if (a.readyIn != 0 || a.verdict == 'rethink' || d.settings.celebrated.contains(p.id)) continue;
      showing = true;
      ref.read(appProvider.notifier).update((x) => x.settings.celebrated.add(p.id));
      await showCelebration(context, p.name, a.loan);
      showing = false;
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    return widget.child;
  }
}

Future<void> showCelebration(BuildContext context, String name, bool loan) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    pageBuilder: (ctx, _, __) => _Celebration(name: name, loan: loan),
  );
}

class _Celebration extends StatefulWidget {
  const _Celebration({required this.name, required this.loan});
  final String name;
  final bool loan;
  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Stack(children: [
      Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: c, builder: (_, __) => CustomPaint(painter: _Confetti(c.value))))),
      Center(
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(radius: 32, backgroundColor: toneColor(context, Tone.good), child: const Icon(Icons.celebration_outlined, color: Colors.white, size: 34)),
                const SizedBox(height: 14),
                Text('You can afford the ${widget.name}', textAlign: TextAlign.center, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  widget.loan
                      ? 'Your down payment is ready and your safety cushion is in place. Open the plan for the last steps.'
                      : 'The money is there and your safety cushion is in place. Open the plan for the last steps.',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium,
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Nice')),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Confetti extends CustomPainter {
  _Confetti(this.t);
  final double t; // 0..1
  static final _pieces = List.generate(70, (i) {
    final r = math.Random(i * 7919);
    return (r.nextDouble(), r.nextDouble() * 0.4, 0.6 + r.nextDouble() * 0.8, r.nextDouble() * math.pi, r.nextInt(5));
  });
  static const _colors = [Color(0xFF0F5C4D), Color(0xFFE0B23A), Color(0xFF2D7A4A), Color(0xFFE07A5F), Color(0xFF3D85C6)];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (x, delay, speed, spin, color) in _pieces) {
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final y = -20 + p * speed * size.height;
      final dx = math.sin(p * 6 + spin) * 18;
      canvas.save();
      canvas.translate(x * size.width + dx, y);
      canvas.rotate(spin + p * 8);
      canvas.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), Paint()..color = _colors[color].withValues(alpha: 1 - p * 0.6));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _Confetti old) => old.t != t;
}
