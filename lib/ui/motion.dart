// Subtle motion: numbers that count, bars that fill, cards that rise in, a light press-down.
// Everything is short (200–600 ms, ease-out), nothing loops, and it all switches off with the
// phone's "reduce motion" setting.
import 'package:flutter/material.dart';

import '../domain/format.dart';

bool reduceMotion(BuildContext c) => MediaQuery.maybeOf(c)?.disableAnimations ?? false;
Duration motion(BuildContext c, int ms) => reduceMotion(c) ? Duration.zero : Duration(milliseconds: ms);

/// An AED amount that counts from its previous value (or zero, the first time) to [value].
class CountingMoney extends StatelessWidget {
  const CountingMoney(this.value, {super.key, this.style, this.prefix = 'AED '});
  final double value;
  final TextStyle? style;
  final String prefix;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: motion(context, 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text('$prefix${fmt(v)}', style: style),
      );
}

/// A progress bar that fills from its previous value to [value].
class FillingBar extends StatelessWidget {
  const FillingBar({super.key, required this.value, required this.color, required this.background, this.height = 8});
  final double value;
  final Color color, background;
  final double height;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
        duration: motion(context, 600),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: LinearProgressIndicator(value: v, minHeight: height, color: color, backgroundColor: background),
        ),
      );
}

/// Fades and rises in once when first shown; [index] staggers a list by 50 ms per item.
class RiseIn extends StatelessWidget {
  const RiseIn({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: motion(context, 280 + 50 * index.clamp(0, 8)),
        curve: Curves.easeOutCubic,
        builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child)),
        child: child,
      );
}

/// Shrinks slightly while pressed.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child});
  final Widget child;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => setState(() => down = true),
        onPointerUp: (_) => setState(() => down = false),
        onPointerCancel: (_) => setState(() => down = false),
        child: AnimatedScale(scale: down ? 0.98 : 1, duration: motion(context, 120), curve: Curves.easeOut, child: widget.child),
      );
}

/// Cross-fades when [child]'s key changes (a verdict, a date, a tab).
class FadeSwitch extends StatelessWidget {
  const FadeSwitch({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: motion(context, 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
        layoutBuilder: (current, previous) => Stack(alignment: AlignmentDirectional.topStart, children: [...previous, if (current != null) current]),
        child: child,
      );
}
