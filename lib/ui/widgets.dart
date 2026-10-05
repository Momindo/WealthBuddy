// Theme and small shared widgets.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/assess.dart';

const _ink = Color(0xFF0F5C4D);
const gold = Color(0xFFA8792A);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _ink, brightness: b, tertiary: gold);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFEEF1EE) : const Color(0xFF0C1311),
    cardTheme: CardThemeData(
        elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: scheme.outlineVariant))),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    // One soft fade-and-rise between screens on Android; iOS keeps its swipe-back slide.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

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

Tone verdictTone(String v) => switch (v) { 'ready' || 'onTrack' => Tone.good, 'later' || 'tight' => Tone.warn, 'rethink' => Tone.bad, _ => Tone.plain };
String verdictLabel(String v) =>
    switch (v) { 'ready' => 'Ready now', 'onTrack' => 'On track', 'tight' => 'Yes, but tight', 'later' => 'Later', 'rethink' => 'Rethink', _ => '' };

IconData kindIcon(String type) => switch (type) {
      'car' => Icons.directions_car_outlined,
      'home' => Icons.home_outlined,
      'build' => Icons.foundation,
      'vacation' => Icons.flight_takeoff,
      'wedding' => Icons.favorite_border,
      'education' => Icons.school_outlined,
      'renovation' => Icons.handyman_outlined,
      'hajj' => Icons.mosque,
      'business' => Icons.storefront_outlined,
      'baby' => Icons.child_friendly_outlined,
      'gold' => Icons.diamond_outlined,
      'gadget' => Icons.phone_iphone,
      _ => Icons.flag_outlined,
    };

String kindLabel(String type) => kindOf(type).label;

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = Tone.accent});
  final String text;
  final Tone tone;
  @override
  Widget build(BuildContext context) {
    final c = toneColor(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class Section extends StatelessWidget {
  const Section({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
            ...children,
          ]),
        ),
      );
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(label)),
        Text(value, style: st.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

Text note(BuildContext c, String s) => Text(s, style: Theme.of(c).textTheme.bodySmall);

/// Renders text with **bold** lead-ins.
Widget richBold(BuildContext context, String text, {TextStyle? style}) {
  final parts = text.split('**');
  return Text.rich(TextSpan(
    style: style ?? Theme.of(context).textTheme.bodyMedium,
    children: [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty) TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w600) : null),
    ],
  ));
}

/// A column of sections with the same gaps as [ScreenBody].
Widget gapColumn(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < children.length; i++) Padding(padding: EdgeInsets.only(bottom: i == children.length - 1 ? 0 : 14), child: children[i]),
    ]);

class ScreenBody extends StatelessWidget {
  const ScreenBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 14), child: c)],
      );
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

/// Day-of-month picker for payday: 1–31 plus "It varies" (stored as 0).
class PaydayPicker extends StatelessWidget {
  const PaydayPicker({super.key, required this.selected, required this.onSelected});
  final int? selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var d = 1; d <= 31; d++)
          SizedBox(
            width: 40,
            height: 40,
            child: Material(
              color: selected == d ? cs.primary : cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelected(d),
                child: Center(child: Text('$d', style: TextStyle(color: selected == d ? cs.onPrimary : null, fontWeight: FontWeight.w600))),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      ChoiceChip(label: const Text('It varies'), selected: selected == 0, onSelected: (_) => onSelected(0)),
    ]);
  }
}

String paydayLabel(int? day) {
  if (day == null) return 'Not set';
  if (day == 0) return 'Varies';
  final suffix = (day % 100 >= 11 && day % 100 <= 13) ? 'th' : switch (day % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  return '$day$suffix of the month';
}

/// The privacy promise: shown once on first launch, and from Settings.
Future<void> showPrivacy(BuildContext context) => showDialog<void>(
      context: context,
      builder: (d) {
        final cs = Theme.of(d).colorScheme;
        Widget item(IconData icon, String text) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
              ]),
            );
        return AlertDialog(
          icon: Icon(Icons.shield_outlined, color: cs.primary),
          title: const Text('Your money stays yours'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            item(Icons.phone_android, 'Everything stays on this phone, encrypted'),
            item(Icons.cloud_off_outlined, 'No cloud and no account'),
            item(Icons.block, 'No ads and no tracking'),
            item(Icons.person_off_outlined, 'No name, email or phone number needed'),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Got it'))],
        );
      },
    );

/// Amounts as you type: 120000 shows as 120,000; "120k" becomes 120,000 and "1.2m" 1,200,000.
class AmountFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var t = newValue.text.toLowerCase().replaceAll(',', '').replaceAll(' ', '');
    if (t.isEmpty) return newValue.copyWith(text: '');
    final mult = t.endsWith('k') ? 1000 : (t.endsWith('m') ? 1000000 : 1);
    if (mult > 1) {
      final v = double.tryParse(t.substring(0, t.length - 1));
      if (v == null) return oldValue;
      t = (v * mult).round().toString();
    }
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(t)) return oldValue;
    final parts = t.split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    final text = parts.length > 1 ? '$whole.${parts[1]}' : whole;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
