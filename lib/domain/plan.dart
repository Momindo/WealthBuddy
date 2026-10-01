// Planning several projects together.
//
// Spare money can only be spent once, so projects share one month-by-month plan:
//   1. The credit card, then the safety cushion, come first for everyone.
//   2. Projects save in "turns". Each turn is the largest group, nearest date first, whose monthly needs
//      (what's left to save ÷ months left to its date) fit in spare money and all make their dates.
//      Each one gets its need; anything left over goes to the nearest date.
//   3. A project that doesn't fit waits for the next turn, which starts once everyone in this turn has saved enough.
//   4. Each project is bought on its date (or when ready, if late). From then on its loan, running costs,
//      minus any rent it stops, change spare money and the cushion target for everyone after it.
// "Save for this now too" pins a project into the first turn even if that makes others wait.
import 'dart:math' as math;

import 'assess.dart';
import 'format.dart';
import 'models.dart';

const int planHorizon = 360; // months

/// One project's share of a plan.
class Sched {
  final int id;
  final int turn; // 0 = saving now, 1+ = waits for earlier projects
  final int startsAt; // month its turn starts (0 = today)
  final int? readyIn, buyIn;
  final bool blocked; // waits on a project that can't be reached
  final bool pinned;
  final double pot0; // held toward it when its turn starts
  final double need; // a month, from its start, to make its date
  final List<double> alloc; // put aside for it each month (index = month)
  final List<double> potPath; // held toward it each month
  final List<double> cardPath, efPath, efTargetPath; // shared by the whole plan
  final int? cardDone; // month the card is clear
  final int? efDone; // month the cushion is full (again) at or after its start
  final List<String> withNames; // saving at the same time
  final List<String> afterNames; // projects it waits for
  final double extraSpendAtStart, extraRepayAtStart; // costs of projects bought before its turn starts
  final double extraSpendAtBuy, extraRepayAtBuy; // costs of projects bought before it's bought
  final double efAtStart;

  const Sched({
    required this.id,
    required this.turn,
    required this.startsAt,
    required this.readyIn,
    required this.buyIn,
    required this.blocked,
    required this.pinned,
    required this.pot0,
    required this.need,
    required this.alloc,
    required this.potPath,
    required this.cardPath,
    required this.efPath,
    required this.efTargetPath,
    required this.cardDone,
    required this.efDone,
    required this.withNames,
    required this.afterNames,
    required this.extraSpendAtStart,
    required this.extraRepayAtStart,
    required this.extraSpendAtBuy,
    required this.extraRepayAtBuy,
    required this.efAtStart,
  });

  bool get waiting => turn > 0;
  String get after => joinNames(afterNames);

  static double _at(List<double> l, int i) => l.isEmpty ? 0 : l[math.min(math.max(i, 0), l.length - 1)];
  double potAt(int m) => _at(potPath, m);
  double allocAt(int m) => m >= 0 && m < alloc.length ? alloc[m] : 0;

  /// The first month money goes to it.
  int get firstMoney {
    for (var i = startsAt + 1; i < alloc.length; i++) {
      if (alloc[i] > 0.5) return i;
    }
    return startsAt;
  }

  /// Monthly amounts as (from month, amount, months) runs. They change as other projects finish.
  /// One-month blips (the month the cushion fills, the last top-up) are left out when there are longer runs.
  List<(int, double, int)> get runs {
    final all = <(int, double, int)>[];
    final end = math.min(readyIn ?? alloc.length - 1, alloc.length - 1);
    for (var i = startsAt + 1; i <= end; i++) {
      if (alloc[i] < 0.5) continue;
      final a = roundUp(alloc[i], 10);
      if (all.isNotEmpty && (all.last.$2 - a).abs() <= 10 && all.last.$1 + all.last.$3 == i) {
        all[all.length - 1] = (all.last.$1, all.last.$2, all.last.$3 + 1);
      } else {
        all.add((i, a, 1));
      }
    }
    final steady = all.where((r) => r.$3 >= 2).toList();
    return steady.isNotEmpty ? steady : all;
  }

  /// The usual monthly amount: its first steady run.
  double get mainAmount => runs.isEmpty ? 0 : runs.first.$2;

  /// "Put aside AED 5,970 a month from Feb 2027, then AED 8,000 from Oct 2027".
  String amountsText(String Function(int) at) {
    final r = runs.take(3).toList();
    if (r.isEmpty) return 'Put money aside';
    final b = StringBuffer('Put aside ${money(r.first.$2)} a month from ${at(r.first.$1)}');
    for (final x in r.skip(1)) {
      b.write(', then ${money(x.$2)} from ${at(x.$1)}');
    }
    return b.toString();
  }
}

/// The whole plan.
class Plan {
  final Map<int, Sched> byId;
  final double spare; // spare money a month today
  final double needAll; // what saving for every project at once would need a month, once the cushion is full
  const Plan(this.byId, this.spare, this.needAll);
  Sched? operator [](int id) => byId[id];
  bool get anyWaiting => byId.values.any((s) => s.waiting);
}

class _Item {
  final Project p;
  final double up, emi, running, rentSaved;
  final bool small;
  final int target; // months from now
  double pot;
  int? ready, bought;
  _Item(this.p, this.up, this.emi, this.running, this.rentSaved, this.small, this.target, this.pot);
  _Item clone() => _Item(p, up, emi, running, rentSaved, small, target, pot)
    ..ready = ready
    ..bought = bought;
  double get rem => math.max(0.0, up - pot);
  double needIn(int m) => rem / math.max(1, target - m + 1);
}

int _byDate(_Item a, _Item b) => a.target != b.target ? a.target.compareTo(b.target) : a.p.id.compareTo(b.p.id);

class _State {
  int m = 0;
  double card, ef, extraSpend = 0, extraRepay = 0;
  final Map<int, _Item> items;
  _State(this.card, this.ef, this.items);
  _State clone() => _State(card, ef, {for (final e in items.entries) e.key: e.value.clone()})
    ..m = m
    ..extraSpend = extraSpend
    ..extraRepay = extraRepay;
}

class _Ctx {
  final double income, base;
  final int efMonths;
  const _Ctx(this.income, this.base, this.efMonths);
  double essentials(_State s) => base + s.extraSpend + s.extraRepay;
  double efTarget(_State s) => essentials(s) * efMonths;
  double surplus(_State s) => income - essentials(s);
}

/// Marks projects ready (enough saved, card clear, cushion full unless small) and buys them on their date.
void _settle(_Ctx c, _State s) {
  final efFull = s.ef >= c.efTarget(s) - 0.5;
  for (final x in s.items.values.toList()..sort(_byDate)) {
    if (x.ready == null && x.rem <= 0.5 && s.card <= 0.5 && (x.small || efFull)) x.ready = s.m;
    if (x.ready != null && x.bought == null && (x.ready == 0 || s.m >= x.target)) {
      x.bought = s.m;
      s.extraSpend += x.running - x.rentSaved;
      s.extraRepay += x.emi;
    }
  }
}

/// One month. Returns what each project in [turn] got.
Map<int, double> _step(_Ctx c, _State s, List<int> turn) {
  s.m++;
  final efTarget = c.efTarget(s);
  var avail = c.surplus(s);
  final give = <int, double>{};
  if (s.card > 0.5) {
    s.card += s.card * cardMonthlyRate;
    final pay = math.min(math.max(avail, 0.0), s.card);
    s.card -= pay;
    avail -= pay;
  }
  if (avail > 0 && s.card <= 0.5) {
    final saving = [for (final id in turn) s.items[id]!].where((x) => x.ready == null && x.rem > 0.5).toList()..sort(_byDate);
    final need = {for (final x in saving) x.p.id: x.needIn(s.m)};
    void put(_Item x, double amount) {
      final g = math.min(amount, math.min(avail, x.rem));
      if (g <= 0) return;
      x.pot += g;
      avail -= g;
      give[x.p.id] = (give[x.p.id] ?? 0) + g;
    }

    if (s.ef < efTarget - 0.5) {
      for (final x in saving.where((x) => x.small)) {
        put(x, need[x.p.id]!); // small purchases don't wait for the cushion
      }
      final e = math.min(avail, efTarget - s.ef);
      s.ef += e;
      avail -= e;
    }
    if (s.ef >= efTarget - 0.5) {
      for (final x in saving) {
        put(x, need[x.p.id]! - (give[x.p.id] ?? 0));
      }
      for (final x in saving) {
        put(x, avail); // leftover: nearest date first
      }
    }
  }
  _settle(c, s);
  return give;
}

/// Whether [turn] can save together: once the card and cushion are done, their monthly needs fit in
/// spare money, and every member that isn't pinned makes its date.
bool _fits(_Ctx c, _State s0, List<int> turn, Set<int> pinned) {
  final s = s0.clone();
  bool? needsFit;
  while (s.m < planHorizon && !turn.every((id) => s.items[id]!.ready != null)) {
    if (needsFit == null && s.card <= 0.5 && s.ef >= c.efTarget(s) - 0.5) {
      final need = turn.map((id) => s.items[id]!).where((x) => x.ready == null).fold<double>(0, (a, x) => a + x.needIn(s.m + 1));
      needsFit = need <= c.surplus(s) + 0.5;
    }
    _step(c, s, turn);
  }
  if (needsFit == false) return false;
  return turn.where((id) => !pinned.contains(id)).every((id) {
    final x = s.items[id]!;
    return x.ready != null && x.ready! <= x.target;
  });
}

/// The next turn: pinned projects, plus the largest group of the rest (nearest date first) that fits.
List<int> _chooseTurn(_Ctx c, _State s, Set<int> pinned) {
  final open = s.items.values.where((x) => x.ready == null).toList()..sort(_byDate);
  final pins = [for (final x in open) if (pinned.contains(x.p.id)) x.p.id];
  final others = [for (final x in open) if (!pinned.contains(x.p.id)) x.p.id];
  for (var k = others.length; k >= 1; k--) {
    final turn = [...pins, ...others.take(k)];
    if (_fits(c, s, turn, pinned)) return turn;
  }
  return pins.isNotEmpty ? pins : [others.first];
}

/// Plans [projects] together. [pinned] projects save from the start whatever it costs the others.
Plan planAll(Money mo, List<Project> projects, {required String today, Set<int> pinned = const {}}) {
  final income = mo.income ?? 0;
  final base = (mo.spending ?? 0) + (mo.repayments ?? 0);
  final efMonths = (mo.family == true ? 6 : 3) + (mo.variable == true ? 3 : 0);
  final c = _Ctx(income, base, efMonths);

  // Savings today: pay the card down (keeping a month of essentials), fill the cushion,
  // then share what's left, nearest date first. Money set aside for a project stays with it.
  var cash = mo.savings ?? 0;
  final card0 = mo.cardDebt ?? 0;
  final payNow = card0 > 0 ? math.min(card0, math.max(0.0, cash - base)) : 0.0;
  cash -= payNow;
  final ef0 = math.min(cash, base * efMonths);
  var spare = cash - ef0;

  final items = <int, _Item>{};
  final sorted = [...projects]..sort((a, b) => a.target != b.target ? a.target.compareTo(b.target) : a.id.compareTo(b.id));
  for (final p in sorted) {
    final b = projectBasics(mo, p, today: today);
    final held = math.min(b.upfront, p.saved);
    final fromSpare = math.min(spare, b.upfront - held);
    spare -= fromSpare;
    items[p.id] = _Item(p, b.upfront, b.emi, b.running, b.rentSaved, b.small, b.monthsLeft, held + fromSpare);
  }
  final names = {for (final p in projects) p.id: p.name};

  final s = _State(card0 - payNow, ef0, items);
  _settle(c, s);

  // What saving for everything at once would need, once the card and cushion are done.
  var needAll = 0.0;
  {
    final t = s.clone();
    final open = [for (final x in t.items.values) if (x.ready == null) x.p.id];
    while (t.m < planHorizon && !(t.card <= 0.5 && t.ef >= c.efTarget(t) - 0.5)) {
      _step(c, t, open);
    }
    needAll = open.map((id) => t.items[id]!).where((x) => x.ready == null).fold<double>(0, (a, x) => a + x.needIn(t.m + 1));
  }

  final cardPath = <double>[s.card], efPath = <double>[s.ef], efTargetPath = <double>[c.efTarget(s)];
  final alloc = {for (final id in items.keys) id: <double>[0]};
  final pots = {for (final id in items.keys) id: <double>[items[id]!.pot]};
  final turnOf = <int, int>{}, startOf = <int, int>{};
  final withOf = <int, List<String>>{}, afterOf = <int, List<String>>{};
  final extraStart = <int, (double, double)>{}, extraBuy = <int, (double, double)>{}, efStart = <int, double>{};
  for (final x in items.values.where((x) => x.bought == 0)) {
    turnOf[x.p.id] = 0;
    startOf[x.p.id] = 0;
    extraStart[x.p.id] = (0, 0);
    extraBuy[x.p.id] = (0, 0);
    efStart[x.p.id] = s.ef;
  }

  var turn = <int>[];
  var turnNo = -1;
  while (s.m < planHorizon && s.items.values.any((x) => x.bought == null)) {
    if (turn.every((id) => s.items[id]!.ready != null) && s.items.values.any((x) => x.ready == null)) {
      final before = [for (final x in s.items.values.toList()..sort(_byDate)) if ((turnOf[x.p.id] ?? -1) >= 0 && x.ready != 0) x.p.name];
      turn = _chooseTurn(c, s, pinned);
      turnNo++;
      for (final id in turn) {
        turnOf[id] = turnNo;
        startOf[id] = s.m;
        withOf[id] = [for (final o in turn) if (o != id) names[o]!];
        afterOf[id] = turnNo == 0 ? [] : before;
        extraStart[id] = (s.extraSpend, s.extraRepay);
        efStart[id] = s.ef;
      }
    }
    final pre = (s.extraSpend, s.extraRepay);
    final unbought = [for (final x in s.items.values) if (x.bought == null) x.p.id];
    efTargetPath.add(c.efTarget(s));
    final give = _step(c, s, turn);
    for (final id in unbought) {
      if (s.items[id]!.bought != null) extraBuy[id] = pre;
    }
    cardPath.add(s.card);
    efPath.add(s.ef);
    for (final id in items.keys) {
      alloc[id]!.add(give[id] ?? 0);
      pots[id]!.add(s.items[id]!.pot);
    }
  }

  int? firstAtOrAfter(int from, bool Function(int) ok) {
    for (var i = math.max(from, 0); i < cardPath.length; i++) {
      if (ok(i)) return i;
    }
    return null;
  }

  final cardDone = firstAtOrAfter(0, (i) => cardPath[i] <= 0.5);
  // The month the cushion is full for good before [ready]: any top-up after earlier purchases is done.
  int? efFullFrom(int start, int? ready) {
    bool full(int i) => efPath[i] >= efTargetPath[i] - 0.5;
    final end = math.min(ready ?? efPath.length - 1, efPath.length - 1);
    if (end < start) return full(math.min(start, efPath.length - 1)) ? start : null;
    if (!full(end)) return ready == null ? firstAtOrAfter(start, full) : null;
    var i = end;
    while (i > start && full(i - 1)) {
      i--;
    }
    return i;
  }

  final stuck = [for (final id in turn) if (s.items[id]!.ready == null) names[id]!];
  final out = <int, Sched>{};
  for (final x in items.values) {
    final id = x.p.id;
    final blocked = !turnOf.containsKey(id);
    final start = startOf[id] ?? 0;
    final pot0 = pots[id]![math.min(start, pots[id]!.length - 1)];
    out[id] = Sched(
      id: id,
      turn: blocked ? turnNo + 1 : turnOf[id]!,
      startsAt: start,
      readyIn: x.ready,
      buyIn: x.bought ?? (x.ready == null ? null : math.max(x.ready!, x.target)),
      blocked: blocked,
      pinned: pinned.contains(id),
      pot0: pot0,
      need: math.max(0.0, x.up - pot0) / math.max(1, x.target - start),
      alloc: alloc[id]!,
      potPath: pots[id]!,
      cardPath: cardPath,
      efPath: efPath,
      efTargetPath: efTargetPath,
      cardDone: cardDone,
      efDone: efFullFrom(start, x.ready),
      withNames: withOf[id] ?? const [],
      afterNames: blocked ? stuck : (afterOf[id] ?? const []),
      extraSpendAtStart: (extraStart[id] ?? (s.extraSpend, s.extraRepay)).$1,
      extraRepayAtStart: (extraStart[id] ?? (s.extraSpend, s.extraRepay)).$2,
      extraSpendAtBuy: (extraBuy[id] ?? (s.extraSpend, s.extraRepay)).$1,
      extraRepayAtBuy: (extraBuy[id] ?? (s.extraSpend, s.extraRepay)).$2,
      efAtStart: efStart[id] ?? s.ef,
    );
  }
  return Plan(out, income - base, needAll);
}
