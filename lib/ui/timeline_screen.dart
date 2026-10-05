// All projects on one timeline: when each saves, waits, is ready and is bought, against the date it's wanted.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/assess.dart';
import '../domain/format.dart';
import '../domain/models.dart';
import 'motion.dart';
import 'result_screen.dart';
import 'widgets.dart';

/// One row of the timeline, in months from today.
class TimelineRow {
  final Project p;
  final int? waitUntil; // saving starts after other projects (shared plans)
  final int saveFrom; // money starts going to it (after card, cushion or waiting)
  final int? ready, buy;
  final int wanted;
  const TimelineRow(this.p, {this.waitUntil, required this.saveFrom, this.ready, this.buy, required this.wanted});
}

List<TimelineRow> timelineRows(AppData d, {required String today}) {
  final all = assessAll(d, today: today);
  final rows = [
    for (final p in d.projects)
      () {
        final a = all[p.id]!;
        final sh = a.share;
        return TimelineRow(
          p,
          waitUntil: sh != null && sh.waiting && !sh.blocked ? sh.startsAt : null,
          saveFrom: a.readyIn == 0 ? 0 : a.projStart,
          ready: a.readyIn,
          buy: a.buyIn ?? a.readyIn,
          wanted: a.monthsLeft,
        );
      }(),
  ];
  rows.sort((x, y) => (x.buy ?? 9999).compareTo(y.buy ?? 9999));
  return rows;
}

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider).data;
    final today = todayIso();
    final rows = timelineRows(data, today: today);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Timeline')),
      body: SafeArea(
        child: ScreenBody(children: [
          note(context, 'Every project on one line of time. Tap a row to open its plan.'),
          LayoutBuilder(builder: (context, box) {
            const rowH = 52.0, top = 24.0;
            return GestureDetector(
              onTapUp: (e) {
                final i = ((e.localPosition.dy - top) / rowH).floor();
                if (i >= 0 && i < rows.length) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(projectId: rows[i].p.id)));
                }
              },
              child: Semantics(
                label: rows.map((r) => '${r.p.name}: ${r.ready == null ? 'not reachable' : 'ready ${monthLabel(addMonths(monthKey(today), r.ready!))}'}').join('. '),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: motion(context, 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, grow, _) => CustomPaint(
                    size: Size(box.maxWidth, top + rows.length * rowH + 8),
                    painter: _TimelinePainter(rows, today, Theme.of(context), rowH: rowH, top: top, grow: grow),
                  ),
                ),
              ),
            );
          }),
          Wrap(spacing: 16, runSpacing: 8, children: [
            _legend(context, Theme.of(context).colorScheme.outline, 'Waiting or cushion first', thin: true),
            _legend(context, Theme.of(context).colorScheme.primary, 'Saving'),
            _legend(context, toneColor(context, Tone.good), 'Bought'),
            _legend(context, toneColor(context, Tone.warn), 'Wanted by', tick: true),
          ]),
          if (rows.isEmpty) Text('No projects yet.', style: t.bodyMedium),
        ]),
      ),
    );
  }

  Widget _legend(BuildContext context, Color c, String label, {bool thin = false, bool tick = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: tick ? 3 : 18, height: tick ? 14 : (thin ? 3 : 10), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.rows, this.today, this.theme, {required this.rowH, required this.top, this.grow = 1});
  final List<TimelineRow> rows;
  final String today;
  final ThemeData theme;
  final double rowH, top;
  final double grow; // 0..1: bars grow left to right as the screen opens

  void _text(Canvas c, String s, Offset at, TextStyle? style, {double maxW = 200, bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')..layout(maxWidth: maxW);
    tp.paint(c, center ? at - Offset(tp.width / 2, 0) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;
    final cs = theme.colorScheme;
    final good = theme.brightness == Brightness.dark ? const Color(0xFF6CC48A) : const Color(0xFF2D7A4A);
    final warn = theme.brightness == Brightness.dark ? const Color(0xFFE6B450) : const Color(0xFFB7791F);
    const labelW = 96.0;
    final end = math.min(360, rows.fold<int>(12, (m, r) => math.max(m, math.max(r.wanted, r.buy ?? r.wanted))) + 3);
    final w = size.width - labelW - 8;
    double x(int m) => labelW + m.clamp(0, end) / end * w * grow;
    final small = theme.textTheme.bodySmall;

    // Year ticks
    final now = monthKey(today);
    final startYear = int.parse(now.substring(0, 4));
    final grid = Paint()
      ..color = cs.outlineVariant
      ..strokeWidth = 1;
    final yearsSpan = (end / 12).ceil();
    final step = yearsSpan > 8 ? 2 : 1;
    for (var y = startYear + 1; y <= startYear + yearsSpan; y += step) {
      final m = monthsUntil('$now-01', '$y-01');
      if (m > end) break;
      canvas.drawLine(Offset(x(m), top - 4), Offset(x(m), size.height), grid);
      _text(canvas, '$y', Offset(x(m), 2), small, center: true);
    }

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final cy = top + i * rowH + rowH / 2;
      _text(canvas, r.p.name, Offset(0, cy - 9), theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxW: labelW - 8);

      final thin = Paint()
        ..color = cs.outline
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final lead = r.waitUntil ?? r.saveFrom;
      if (lead > 0) canvas.drawLine(Offset(x(0), cy), Offset(x(lead), cy), thin);

      final readyAt = r.ready ?? end;
      if (readyAt > r.saveFrom) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x(r.saveFrom), cy - 6, x(readyAt), cy + 6), const Radius.circular(6)), Paint()..color = cs.primary);
      }
      if (r.ready == null) {
        _text(canvas, '…', Offset(x(end) - 10, cy - 10), theme.textTheme.titleMedium);
      } else {
        final buy = r.buy ?? r.ready!;
        if (buy > r.ready!) canvas.drawLine(Offset(x(r.ready!), cy), Offset(x(buy), cy), Paint()..color = good.withValues(alpha: 0.5)..strokeWidth = 3);
        canvas.drawCircle(Offset(x(buy), cy), 7, Paint()..color = good);
      }
      // Wanted by
      canvas.drawRect(Rect.fromLTWH(x(r.wanted) - 1.5, cy - 12, 3, 24), Paint()..color = warn);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => old.rows != rows || old.theme != theme || old.grow != grow;
}
