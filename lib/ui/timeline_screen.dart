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
          note(context, 'Every project on one line of time, from today. Tap a lane to open its plan.'),
          TimelineLanes(
            rows: rows,
            today: today,
            onTapRow: (r) => Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(projectId: r.p.id))),
          ),
          const TimelineLegend(),
          if (rows.isEmpty) Text('No projects yet.', style: t.bodyMedium),
        ]),
      ),
    );
  }
}

/// The compact timeline on home: always visible when there are projects; tap for the full view.
class HomeTimeline extends ConsumerWidget {
  const HomeTimeline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider).data;
    final today = todayIso();
    final rows = timelineRows(data, today: today);
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TimelineScreen())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Timeline', style: t.titleSmall)),
              Text('See details', style: t.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
              Icon(Icons.chevron_right, size: 18, color: Theme.of(context).colorScheme.primary),
            ]),
            const SizedBox(height: 6),
            TimelineLanes(rows: rows, today: today, compact: true),
          ]),
        ),
      ),
    );
  }
}

class TimelineLegend extends StatelessWidget {
  const TimelineLegend({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget item(Widget mark, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          mark,
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]);
    Widget box(Color c, double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)));
    return Wrap(spacing: 16, runSpacing: 8, children: [
      item(box(cs.outline.withValues(alpha: 0.5), 18, 4), 'Waiting or cushion first'),
      item(box(_saveColor(context), 18, 10), 'Saving'),
      item(CircleAvatar(radius: 6, backgroundColor: toneColor(context, Tone.good)), 'Bought'),
      item(box(toneColor(context, Tone.warn), 3, 14), 'Want by'),
    ]);
  }
}

Color _saveColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF1D9E75) : const Color(0xFF5DCAA5);

/// One lane per project on a shared month axis. A playhead sweeps from today to the last goal once
/// (again whenever the plan changes): saving bars grow behind it and a ✓ pin pops in on each buy date.
class TimelineLanes extends StatefulWidget {
  const TimelineLanes({super.key, required this.rows, required this.today, this.compact = false, this.onTapRow});
  final List<TimelineRow> rows;
  final String today;
  final bool compact;
  final void Function(TimelineRow)? onTapRow;
  @override
  State<TimelineLanes> createState() => _TimelineLanesState();
}

class _TimelineLanesState extends State<TimelineLanes> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this);

  String _sig(List<TimelineRow> rows) => rows.map((r) => '${r.p.id}:${r.saveFrom}:${r.ready}:${r.buy}:${r.wanted}').join('|');

  void _play() {
    final reduce = reduceMotion(context);
    c.duration = Duration(milliseconds: widget.compact ? 1800 : 2600);
    if (reduce) {
      c.value = 1;
    } else {
      c.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (c.value == 0 && !c.isAnimating) _play();
  }

  @override
  void didUpdateWidget(TimelineLanes old) {
    super.didUpdateWidget(old);
    if (_sig(old.rows) != _sig(widget.rows)) _play();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  double get laneH => widget.compact ? 30 : 56;
  double get top => widget.compact ? 20 : 26;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    final height = top + rows.length * laneH + 22;
    return LayoutBuilder(builder: (context, box) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: widget.onTapRow == null
            ? null
            : (e) {
                final i = ((e.localPosition.dy - top) / laneH).floor();
                if (i >= 0 && i < rows.length) widget.onTapRow!(rows[i]);
              },
        child: Semantics(
          label: 'Timeline. ${rows.map((r) => '${r.p.name}: ${r.ready == null ? 'not reachable yet' : 'ready ${monthLabel(addMonths(monthKey(widget.today), r.ready!))}'}').join('. ')}',
          child: AnimatedBuilder(
            animation: c,
            builder: (context, _) => CustomPaint(
              size: Size(box.maxWidth, height),
              painter: _LanesPainter(rows, widget.today, Theme.of(context), _saveColor(context),
                  t: Curves.easeOutCubic.transform(c.value), compact: widget.compact, laneH: laneH, top: top),
            ),
          ),
        ),
      );
    });
  }
}

class _LanesPainter extends CustomPainter {
  _LanesPainter(this.rows, this.today, this.theme, this.save, {required this.t, required this.compact, required this.laneH, required this.top});
  final List<TimelineRow> rows;
  final String today;
  final ThemeData theme;
  final Color save;
  final double t; // 0..1: where the playhead is
  final bool compact;
  final double laneH, top;

  void _text(Canvas c, String s, Offset at, TextStyle? style, {double maxW = 200, bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')..layout(maxWidth: maxW);
    tp.paint(c, center ? at - Offset(tp.width / 2, 0) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final good = dark ? const Color(0xFF6CC48A) : const Color(0xFF2D7A4A);
    final warn = dark ? const Color(0xFFE0A24F) : const Color(0xFFB06A12);
    final play = dark ? const Color(0xFFAFA9EC) : const Color(0xFF534AB7);
    final labelW = compact ? 70.0 : 86.0;
    final end = math.min(360, rows.fold<int>(12, (m, r) => math.max(m, math.max(r.wanted, r.buy ?? r.wanted))) + 2);
    final w = size.width - labelW - 8;
    double x(num m) => labelW + m.clamp(0, end) / end * w;
    final bottom = top + rows.length * laneH;
    final small = theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    final now = t * end;

    // Years across the top
    final ym = monthKey(today);
    final y0 = int.parse(ym.substring(0, 4));
    final years = (end / 12).ceil() + 1;
    final step = years > (compact ? 6 : 9) ? 2 : 1;
    final grid = Paint()
      ..color = cs.outlineVariant
      ..strokeWidth = 1;
    for (var y = y0 + 1; y <= y0 + years; y += step) {
      final m = monthsUntil('$ym-01', '$y-01');
      if (m > end) break;
      canvas.drawLine(Offset(x(m), top - 4), Offset(x(m), bottom), grid);
      _text(canvas, compact ? "'${'$y'.substring(2)}" : '$y', Offset(x(m), 0), small, center: true);
    }

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final cy = top + i * laneH + laneH / 2;
      _text(canvas, r.p.name, Offset(0, cy - 8), (compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)?.copyWith(fontWeight: FontWeight.w600),
          maxW: labelW - 6);

      // Waiting (or cushion and card first): a thin grey lane
      if (r.saveFrom > 0) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x(0), cy - 2, x(r.saveFrom), cy + 2), const Radius.circular(2)),
            Paint()..color = cs.outline.withValues(alpha: 0.5));
      }
      // Saving: grows behind the playhead
      final saveEnd = math.min(now, (r.ready ?? end).toDouble());
      if (saveEnd > r.saveFrom) {
        final h = compact ? 5.0 : 7.0;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x(r.saveFrom), cy - h, x(saveEnd), cy + h), Radius.circular(h)), Paint()..color = save);
      }
      // Want by
      final th = compact ? 9.0 : 14.0;
      canvas.drawRect(Rect.fromLTWH(x(r.wanted) - 1.5, cy - th, 3, th * 2), Paint()..color = warn);

      // Bought: a pin pops in on the buy date
      if (r.ready != null) {
        final buy = r.buy ?? r.ready!;
        if (now >= buy) {
          final pop = ((now - buy) / (end * 0.06) + 0.35).clamp(0.0, 1.0);
          final rad = (compact ? 7.0 : 11.0) * Curves.easeOutBack.transform(pop);
          final at = Offset(x(buy), cy);
          canvas.drawCircle(at, rad, Paint()..color = good);
          final tick = Path()
            ..moveTo(at.dx - rad * 0.45, at.dy)
            ..lineTo(at.dx - rad * 0.1, at.dy + rad * 0.35)
            ..lineTo(at.dx + rad * 0.5, at.dy - rad * 0.35);
          canvas.drawPath(
              tick,
              Paint()
                ..color = Colors.white
                ..style = PaintingStyle.stroke
                ..strokeWidth = compact ? 1.6 : 2.2
                ..strokeCap = StrokeCap.round);
          if (!compact) {
            final diff = r.wanted - buy;
            _text(canvas, '${monthLabel(addMonths(ym, buy))} · ${diff > 0 ? 'early' : diff == 0 ? 'on time' : 'late'}',
                Offset(math.min(math.max(x(buy), labelW + 40), size.width - 50), cy + 13), small?.copyWith(color: diff >= 0 ? good : warn), center: true);
          }
        }
      } else if (t >= 1) {
        _text(canvas, 'out of reach', Offset(size.width - 70, cy + (compact ? 6 : 12)), small?.copyWith(color: warn), maxW: 70);
      }
    }

    // The playhead, with the year it's passing; it fades once it reaches the end
    if (t < 1) {
      final px = x(now);
      final fade = t > 0.9 ? (1 - t) / 0.1 : 1.0;
      canvas.drawLine(Offset(px, top - 6), Offset(px, bottom), Paint()
        ..color = play.withValues(alpha: fade)
        ..strokeWidth = 2);
      final year = y0 + ((int.parse(ym.substring(5, 7)) - 1 + now) / 12).floor();
      final pill = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(px, bottom + 10), width: 34, height: 16), const Radius.circular(8));
      canvas.drawRRect(pill, Paint()..color = play.withValues(alpha: fade));
      _text(canvas, "'${'$year'.substring(2)}", Offset(px, bottom + 3), small?.copyWith(color: (dark ? Colors.black : Colors.white).withValues(alpha: fade)), center: true);
    }
  }

  @override
  bool shouldRepaint(covariant _LanesPainter old) => old.t != t || old.rows != rows || old.theme != theme;
}
