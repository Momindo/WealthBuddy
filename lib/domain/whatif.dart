// What if: try a different take-home pay, monthly spending or target dates without saving anything.
// The whole plan is re-run (shared plans included), so moving one project's date can move the others.
import 'dart:math' as math;

import 'assess.dart';
import 'format.dart';
import 'models.dart';

/// A copy of [d] with the what-if changes applied. [targets] maps project id to a new yyyy-mm.
AppData applyWhatIf(AppData d, {double? income, double? spending, bool? cushion, Map<int, String> targets = const {}}) {
  final c = d.copy();
  if (income != null) c.money.income = income;
  if (cushion != null) c.money.cushion = cushion;
  if (spending != null) c.money.spending = spending;
  for (final p in c.projects) {
    final t = targets[p.id];
    if (t != null) p.target = t;
  }
  return c;
}

Map<int, Assessment> whatIf(AppData d, {required String today, double? income, double? spending, bool? cushion, Map<int, String> targets = const {}}) =>
    assessAll(applyWhatIf(d, income: income, spending: spending, cushion: cushion, targets: targets), today: today);

/// Every project can be reached and is ready by the date it's wanted.
bool allOnTime(Map<int, Assessment> all) => all.values.every((a) => a.readyIn != null && a.readyIn! <= a.monthsLeft);

/// The smallest change, in AED 50 steps and up to [maxShare] of today's figure, that puts every project
/// on time: a cut in spending, or a rise in take-home pay. Null when that change alone can't do it,
/// and both null when everything is already on time.
({double? spendCut, double? payRise}) smallestFix(AppData d, {required String today, Map<int, String> targets = const {}, double maxShare = 0.3}) {
  final m = d.money;
  if (!m.complete || d.projects.isEmpty) return (spendCut: null, payRise: null);
  if (allOnTime(whatIf(d, today: today, targets: targets))) return (spendCut: null, payRise: null);

  // Smallest k (in steps of 50) where [ok] holds, assuming more always helps.
  double? search(double limit, bool Function(double) ok) {
    final hi = (limit / 50).floor();
    if (hi < 1 || !ok(hi * 50.0)) return null;
    var lo = 0, top = hi; // ok(lo * 50) is false, ok(top * 50) is true
    while (top - lo > 1) {
      final mid = (lo + top) ~/ 2;
      if (ok(mid * 50.0)) {
        top = mid;
      } else {
        lo = mid;
      }
    }
    return top * 50.0;
  }

  final spend = m.spending!, pay = m.income!;
  return (
    spendCut: search(math.min(spend, spend * maxShare), (x) => allOnTime(whatIf(d, today: today, spending: spend - x, targets: targets))),
    payRise: search(pay * maxShare, (x) => allOnTime(whatIf(d, today: today, income: pay + x, targets: targets))),
  );
}

/// "4 months sooner", "2 months later", "same date", or how reachability changed.
String readyChange(Assessment before, Assessment after) {
  final b = before.readyIn, a = after.readyIn;
  if (b == null && a == null) return 'still out of reach';
  if (b == null) return 'now within reach';
  if (a == null) return 'out of reach';
  if (a == b) return 'same date';
  return a < b ? '${durationLabel(b - a)} sooner' : '${durationLabel(a - b)} later';
}

/// The earliest month a target can be set to.
String earliestTarget(String today) => addMonths(monthKey(today), 1);

/// The smallest amount to put aside each month (in AED 10 steps) that gets every project to its date,
/// counting the card, the safety cushion and the costs each purchase adds. Null when no amount does,
/// or there's nothing to plan.
double? neededMonthly(AppData d, {required String today}) {
  final m = d.money;
  if (!m.complete || d.projects.isEmpty) return null;
  final base = (m.spending ?? 0) + (m.repayments ?? 0);
  bool ok(double spare) => allOnTime(whatIf(d, today: today, income: base + spare));
  final cap = math.max(10000.0, (m.income ?? 0) * 3);
  if (!ok(cap)) return null;
  if (ok(0)) return 0;
  var lo = 0, hi = (cap / 10).ceil(); // ok(lo * 10) is false, ok(hi * 10) is true
  while (hi - lo > 1) {
    final mid = (lo + hi) ~/ 2;
    if (ok(mid * 10.0)) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return hi * 10.0;
}
