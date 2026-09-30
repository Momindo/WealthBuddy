// Repeating costs and income, and the guided setup that creates them.
import 'dart:math' as math;

import 'basics.dart';
import 'models.dart';

/// Expands every repeating rule into one transaction per month, up to [today]'s month.
/// Never adds a second entry for a month that already has one, so it's safe to run on every launch.
void syncRecurring(AppState s, String today) {
  final end = monthKey(today);
  for (final r in s.recurring) {
    final stop = r.until ?? end;
    final day = math.min(int.parse(r.start.substring(8, 10)), 28).toString().padLeft(2, '0');
    for (var k = monthKey(r.start); k.compareTo(stop) <= 0 && k.compareTo(end) <= 0; k = nextMonth(k)) {
      if (r.skip.contains(k) || s.tx.any((t) => t.rid == r.id && monthKey(t.date) == k)) continue;
      final each = r.freq == 'yearly' ? r.amount / 12 : r.amount;
      s.tx.add(Tx(id: nextId(s.tx.map((e) => e.id)), date: '$k-$day', merchant: r.merchant, cat: r.cat, amount: round2(r.sign * each), method: r.method, rid: r.id));
    }
  }
}

/// Replaces the rule created by a setup step, and its transactions, so setup can be re-run without duplicates.
void upsertRule(AppState s, String key, RecurringRule? rule) {
  final old = s.recurring.where((r) => r.setupKey == key).toList();
  for (final o in old) {
    s.tx.removeWhere((t) => t.rid == o.id);
    s.recurring.remove(o);
  }
  if (rule != null) {
    rule.id = nextId(s.recurring.map((e) => e.id));
    rule.setupKey = key;
    s.recurring.add(rule);
  }
}

void upsertDebt(AppState s, String key, Liability? debt) {
  s.liabilities.removeWhere((l) => l.setupKey == key);
  if (debt != null) {
    debt.id = nextId(s.liabilities.map((e) => e.id));
    debt.setupKey = key;
    s.liabilities.add(debt);
  }
}

/// Deletes one month of a repeating rule (the user removed that entry).
void skipMonth(AppState s, Tx t) {
  if (t.rid != null) {
    for (final r in s.recurring.where((r) => r.id == t.rid)) {
      r.skip.add(monthKey(t.date));
    }
  }
  s.tx.removeWhere((x) => x.id == t.id);
}

/// Stops a rule from the month of [from]: that entry and later ones go, earlier months stay.
void stopRepeating(AppState s, Tx from) {
  final k = monthKey(from.date), y = int.parse(k.substring(0, 4)), mo = int.parse(k.substring(5));
  for (final r in s.recurring.where((r) => r.id == from.rid)) {
    r.until = mo == 1 ? '${y - 1}-12' : '$y-${(mo - 1).toString().padLeft(2, '0')}';
  }
  s.tx.removeWhere((x) => x.rid == from.rid && monthKey(x.date).compareTo(k) >= 0);
}

String recurringNote(AppState s, Tx t) {
  RecurringRule? r;
  for (final x in s.recurring) {
    if (x.id == t.rid) r = x;
  }
  if (r == null) return '';
  if (r.freq == 'yearly') {
    final many = (r.cheques ?? 1) > 1 ? ' in ${r.cheques} ${r.method == 'cheque' ? 'cheques' : 'payments'}' : '';
    return 'Yearly ${money(r.amount)}$many, counted monthly';
  }
  return 'Repeats monthly${r.until != null ? ' (stopped)' : ''}';
}

/// The regular costs offered in setup step 3.
class SetupCost {
  final String key, label, cat, method, freq, hint;
  final int? cheques;
  final String? bench;
  final double share;
  final bool debt;
  const SetupCost(this.key, this.label, this.cat, this.method, this.freq, this.hint, {this.cheques, this.bench, this.share = 1, this.debt = false});
}

const List<SetupCost> setupCosts = [
  SetupCost('school', 'School fees', 'Education', 'transfer', 'yearly', 'Yearly total for all children', cheques: 3, bench: 'Education'),
  SetupCost('help', 'Home help', 'Home help', 'cash', 'monthly', 'Monthly salary for a maid, nanny or driver'),
  SetupCost('car', 'Car loan instalment', 'Transport', 'transfer', 'monthly', 'Monthly instalment', debt: true),
  SetupCost('util', 'Electricity & water', 'Bills', 'card', 'monthly', 'DEWA, ADDC or SEWA, monthly average', bench: 'Bills', share: 0.6),
  SetupCost('phone', 'Phone & internet', 'Bills', 'card', 'monthly', 'Mobile and home internet together', bench: 'Bills', share: 0.4),
  SetupCost('gym', 'Gym & subscriptions', 'Subscriptions', 'card', 'monthly', 'Gym, streaming, apps', bench: 'Subscriptions'),
];

String monthStart(String today, [int day = 1]) => '${monthKey(today)}-${math.min(day, 28).toString().padLeft(2, '0')}';
