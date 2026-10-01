// Payday reminders: on each payday at 3 pm, one message saying what to do with this month's spare money,
// written from the plan. The phone can't see the bank, so the messages say what to do and where that
// puts you, never "you have saved X".
import 'dart:math' as math;

import 'assess.dart';
import 'format.dart';
import 'models.dart';

class PaydayReminder {
  final String date; // yyyy-mm-dd, delivered at 15:00 local time
  final String title, body;
  final int projectId;
  const PaydayReminder(this.date, this.title, this.body, this.projectId);
}

int daysInMonth(String ym) => DateTime(int.parse(ym.substring(0, 4)), int.parse(ym.substring(5, 7)) + 1, 0).day;

double _at(List<double> l, int i) => l.isEmpty ? 0 : l[math.min(i, l.length - 1)];

/// The next [count] payday reminders from [today], or none if payday or the money answers are missing.
List<PaydayReminder> paydayReminders(AppData d, {required String today, int count = 3}) {
  final m = d.money, day = m.payday;
  if (day == null || day <= 0 || !m.complete || d.projects.isEmpty) return [];
  final evals = [
    for (final p in d.projects) (p, assessIn(d, p, today: today)),
  ].where((e) => e.$2.readyIn != null && e.$2.surplus > 0 && e.$2.verdict != 'rethink').toList();
  if (evals.isEmpty) return [];

  // When each project is due on its plan: paced projects follow the target date, others the fastest path.
  // Linked projects come one after another, so the earliest due is the one being saved for.
  int due(Assessment a) => math.max(1, a.buyIn!);

  final out = <PaydayReminder>[];
  final now = monthKey(today);
  var n = 0; // paydays from now: the first payday puts aside month 1's money
  for (var k = 0; out.length < count && k < count + 2; k++) {
    final ym = addMonths(now, k);
    final date = '$ym-${math.min(day, daysInMonth(ym)).toString().padLeft(2, '0')}';
    if (date.compareTo(today) < 0) continue;
    n++;

    final reached = evals.where((e) => due(e.$2) == n).toList();
    if (reached.isNotEmpty) {
      final (p, a) = reached.first;
      out.add(PaydayReminder(
          date,
          'You can afford the ${p.name}',
          a.loan
              ? 'Your down payment is ready. Open your plan for the last steps before you buy.'
              : 'Your plan says it\'s ready. Open it for the last steps before you buy.',
          p.id));
      continue;
    }
    final active = evals.where((e) => due(e.$2) > n).toList()..sort((x, y) => due(x.$2).compareTo(due(y.$2)));
    if (active.isEmpty) break;
    final (p, a) = active.first;
    out.add(_message(p, a, n, date));
  }
  return out;
}

PaydayReminder _message(Project p, Assessment a, int n, String date) {
  final noun = kindOf(p.type).noun;

  // 1. Credit card
  final cardBefore = _at(a.cardPath, n - 1);
  if (cardBefore > 0.5) {
    final after = _at(a.cardPath, n);
    final pay = math.min(a.surplus, cardBefore * (1 + cardMonthlyRate));
    return PaydayReminder(
        date,
        'Payday: clear your credit card',
        after <= 0.5
            ? 'Put ${money(roundUp(pay, 10))} toward your card today. That clears it.'
            : 'Put ${money(pay)} toward your card today. About ${money(after)} left after this.',
        p.id);
  }

  // 2. Safety cushion
  final efBefore = _at(a.efPath, n - 1);
  if (!a.small && efBefore < a.efTarget - 0.5) {
    final after = _at(a.efPath, n);
    final put = after - efBefore;
    return PaydayReminder(
        date,
        'Payday: build your safety cushion',
        after >= a.efTarget - 0.5
            ? 'Put ${money(put)} into your safety cushion today. That completes it. Next up: the ${p.name}.'
            : 'Put ${money(put)} into your safety cushion today. It\'ll be ${(after / a.efTarget * 100).floor()}% full.',
        p.id);
  }

  // 3. Saving for the project
  final onTrack = a.paced;
  final amount = onTrack ? a.pace : math.min(a.surplus, math.max(0.0, a.upfront - _at(a.potPath, n - 1)));
  final held = onTrack ? a.potStart + a.pace * math.max(0, n - a.projStart) : _at(a.potPath, n);
  final pct = a.upfront > 0 ? math.min(99, (held / a.upfront * 100).floor()) : 99;
  return PaydayReminder(
      date,
      'Payday: ${p.name}',
      'Put aside ${money(amount)} for the ${a.loan ? 'down payment' : noun} today. '
          'You\'ll be at $pct%, ${onTrack ? 'on track for ${a.targetLabel}' : 'ready ${a.readyLabel}'}.',
      p.id);
}
