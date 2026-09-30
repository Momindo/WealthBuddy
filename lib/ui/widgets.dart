// Theme and small shared widgets.
import 'package:flutter/material.dart';

import '../domain/basics.dart';

const _ink = Color(0xFF0F5C4D);
const gold = Color(0xFFA8792A);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _ink, brightness: b, tertiary: gold);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFEEF1EE) : const Color(0xFF0C1311),
    cardTheme: CardThemeData(elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: scheme.outlineVariant))),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
  );
}

/// Semantic tones used for tags, bars and gauges.
enum Tone { good, warn, bad, plain, gold, accent }

Color toneColor(BuildContext c, Tone t) {
  final dark = Theme.of(c).brightness == Brightness.dark;
  return switch (t) {
    Tone.good => dark ? const Color(0xFF6CC48A) : const Color(0xFF2D7A4A),
    Tone.warn => dark ? const Color(0xFFE0A24F) : const Color(0xFFB06A12),
    Tone.bad => dark ? const Color(0xFFE57A70) : const Color(0xFFB3372F),
    Tone.plain => Theme.of(c).colorScheme.onSurfaceVariant,
    Tone.gold => dark ? const Color(0xFFD8AD5E) : gold,
    Tone.accent => Theme.of(c).colorScheme.primary,
  };
}

Tone toneOf(String? s) => switch (s) { 'good' => Tone.good, 'warn' => Tone.warn, 'bad' => Tone.bad, 'gold' => Tone.gold, 'accent' => Tone.accent, _ => Tone.plain };

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = Tone.accent});
  final String text;
  final Tone tone;
  @override
  Widget build(BuildContext context) {
    final c = toneColor(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

/// A titled card section.
class Section extends StatelessWidget {
  const Section({super.key, this.title, this.trailing, required this.children, this.color});
  final String? title;
  final Widget? trailing;
  final List<Widget> children;
  final Color? color;
  @override
  Widget build(BuildContext context) => Card(
        color: color,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
                  if (trailing != null) trailing!,
                ]),
              ),
            ...children,
          ]),
        ),
      );
}

class MoneyHero extends StatelessWidget {
  const MoneyHero({super.key, required this.label, required this.value, this.suffix, this.sub, this.subTone});
  final String label;
  final String value;
  final String? suffix;
  final String? sub;
  final Tone? subTone;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
      const SizedBox(height: 2),
      Text.rich(TextSpan(children: [
        TextSpan(text: 'AED ', style: t.titleMedium?.copyWith(color: t.bodySmall?.color)),
        TextSpan(text: value, style: t.displaySmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
        if (suffix != null) TextSpan(text: ' $suffix', style: t.titleMedium?.copyWith(color: t.bodySmall?.color)),
      ])),
      if (sub != null) Text(sub!, style: t.bodySmall?.copyWith(color: subTone == null ? null : toneColor(context, subTone!))),
    ]);
  }
}

class Bar extends StatelessWidget {
  const Bar(this.value, {super.key, this.tone = Tone.accent, this.height = 6});
  final double value;
  final Tone tone;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: LinearProgressIndicator(
            value: value.clamp(0, 1).toDouble(), minHeight: height, color: toneColor(context, tone), backgroundColor: Theme.of(context).colorScheme.outlineVariant),
      );
}

Tone barTone(double p) => p > 1 ? Tone.bad : p > 0.85 ? Tone.warn : Tone.accent;

/// A range gauge: shaded typical band, a solid marker for now and an optional dashed marker for "after projects".
class Gauge extends StatelessWidget {
  const Gauge({super.key, required this.lo, required this.hi, required this.value, required this.max, this.tone = Tone.plain, this.after, this.capFrom});
  final double lo, hi, value, max;
  final double? after, capFrom;
  final Tone tone;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 18,
        child: CustomPaint(
            painter: _GaugePainter(lo, hi, value, max, after, capFrom, Theme.of(context).colorScheme, toneColor(context, tone), toneColor(context, Tone.gold),
                toneColor(context, Tone.bad))),
      );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.lo, this.hi, this.v, this.max, this.after, this.capFrom, this.cs, this.mark, this.goldC, this.badC);
  final double lo, hi, v, max;
  final double? after, capFrom;
  final ColorScheme cs;
  final Color mark, goldC, badC;
  @override
  void paint(Canvas c, Size s) {
    double x(double p) => (p / max).clamp(0, 1) * s.width;
    final track = RRect.fromLTRBR(0, 4, s.width, 14, const Radius.circular(5));
    c.drawRRect(track, Paint()..color = cs.outlineVariant);
    if (capFrom != null) {
      c.drawRect(Rect.fromLTRB(x(capFrom!), 4, s.width, 14), Paint()..color = badC.withValues(alpha: 0.22));
    } else {
      c.drawRect(Rect.fromLTRB(x(lo), 4, x(hi), 14), Paint()..color = cs.primary.withValues(alpha: 0.22));
    }
    if (after != null) {
      c.drawRRect(RRect.fromLTRBR(x(after!) - 5, 0, x(after!) + 5, 18, const Radius.circular(3)),
          Paint()
            ..color = goldC
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    c.drawRRect(RRect.fromLTRBR(x(v) - 2, 0, x(v) + 2, 18, const Radius.circular(2)), Paint()..color = mark == cs.onSurfaceVariant ? cs.onSurface : mark);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter o) => o.v != v || o.lo != lo || o.hi != hi || o.after != after || o.max != max;
}

/// Renders text with **bold** lead-ins (used by project fixes).
Widget richBold(BuildContext context, String text, {TextStyle? style}) {
  final spans = <TextSpan>[];
  final parts = text.split('**');
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    spans.add(TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w600) : null));
  }
  return Text.rich(TextSpan(children: spans, style: style ?? Theme.of(context).textTheme.bodyMedium));
}

class Row2 extends StatelessWidget {
  const Row2(this.label, this.value, {super.key, this.bold = false, this.tone});
  final String label, value;
  final bool bold;
  final Tone? tone;
  @override
  Widget build(BuildContext context) {
    final st = TextStyle(fontWeight: bold ? FontWeight.w600 : null, color: tone == null ? null : toneColor(context, tone!));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: st)),
        Text(value, style: st.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

Text note(BuildContext c, String s) => Text(s, style: Theme.of(c).textTheme.bodySmall);
String aed(double v, [int dp = 0]) => money(v, dp);

/// Single-choice chips that wrap on narrow screens.
class Choice<T> extends StatelessWidget {
  const Choice({super.key, required this.options, required this.selected, required this.onSelected, this.labels});
  final List<T> options;
  final T? selected;
  final ValueChanged<T> onSelected;
  final String Function(T)? labels;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final o in options)
          ChoiceChip(label: Text(labels?.call(o) ?? '$o'), selected: o == selected, onSelected: (_) => onSelected(o), showCheckmark: false),
      ]);
}

Future<bool> confirm(BuildContext c, String title, String body, String action) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(title: Text(title), content: Text(body), actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(action)),
      ]),
    ) ??
    false;

/// Standard scrolling page body with a phone-friendly gutter.
class ScreenBody extends StatelessWidget {
  const ScreenBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 14), child: c)],
      );
}
