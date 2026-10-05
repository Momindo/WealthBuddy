// Monthly check-in. Plans assume you've followed them since your savings answers (see projectedToday).
// A check-in compares that with what you actually have, resets the plan to the real numbers, and when
// you're consistently behind or ahead, suggests the spending figure that would explain it.
import 'dart:math' as math;

import 'assess.dart';
import 'format.dart';
import 'models.dart';

/// What the plan expects you to have today.
class Expected {
  final int months; // since the savings answers
  final double total; // savings plus money set aside for projects
  final double card; // card balance
  const Expected(this.months, this.total, this.card);
}

/// Money set aside for projects that you actually recorded (not the assumed planned saving).
double recordedSetAside(AppData d) => d.projects.fold<double>(0, (a, p) => a + p.saved);

Expected expectedNow(AppData d, {required String today}) {
  final asOf = d.money.asOf ?? today;
  final months = math.max(0, monthsUntil(asOf, monthKey(today)));
  final c = projectedToday(d, today: today);
  return Expected(months, (c.money.savings ?? 0) + recordedSetAside(c), c.money.cardDebt ?? 0);
}

/// A check-in is due when the savings answers are a month or more old and there hasn't been one in 25 days.
bool checkInDue(AppData d, {required String today}) {
  final m = d.money;
  if (!m.complete || d.projects.isEmpty || m.asOf == null) return false;
  if (monthsUntil(m.asOf!, monthKey(today)) < 1) return false;
  return m.lastCheckIn == null || daysBetween(m.lastCheckIn!, today) >= 25;
}

/// The result of a check-in: how far from the plan, and a monthly figure when there's a pattern.
class CheckInResult {
  final double gap; // positive = behind the plan, negative = ahead
  final int months;
  const CheckInResult(this.gap, this.months);
  double get perMonth => months > 0 ? gap / months : gap;
  bool get onPlan => gap.abs() < 500;
  String get label => onPlan ? 'Check-in: on plan' : 'Check-in: ${money(roundUp(gap.abs(), 100))} ${gap > 0 ? 'behind' : 'ahead of'} plan';
}

/// Records what you actually have now. [actual] is savings plus money set aside; [card] the card balance, if asked.
/// Savings become [actual] minus what's recorded as set aside for projects; the plan restarts from today.
CheckInResult applyCheckIn(AppData d, {required String today, required double actual, double? card}) {
  final e = expectedNow(d, today: today);
  final realCard = card ?? e.card;
  final gap = (e.total - actual) + (realCard - e.card);
  d.money.savings = math.max(0.0, actual - recordedSetAside(d));
  d.money.cardDebt = realCard;
  d.money.asOf = today;
  d.money.lastCheckIn = today;
  return CheckInResult(gap, e.months);
}

/// When the gap is more than a small slip, the monthly spending that would explain it.
/// Null when it's within AED 250 or 10% of spare money a month.
double? suggestedSpending(Money m, CheckInResult r) {
  if (r.months < 1) return null;
  final spare = (m.income ?? 0) - (m.spending ?? 0) - (m.repayments ?? 0);
  if (r.perMonth.abs() < math.max(250, spare * 0.1)) return null;
  final s = (m.spending ?? 0) + r.perMonth;
  return s <= 0 ? null : roundUp(s, 50);
}
