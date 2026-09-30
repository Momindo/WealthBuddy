// The shared plan: every tab reads from one Finance object built from the current state.
// Ported from the prototype; test/parity_test.dart checks the numbers match it.
import 'dart:math' as math;

import 'basics.dart';
import 'models.dart';

// ---------- Result types ----------
class Totals {
  final double assets, debts, net, cash, spent, received;
  final Map<String, double> byCat;
  const Totals(this.assets, this.debts, this.net, this.cash, this.spent, this.received, this.byCat);
}

class IncomeInfo {
  final double v;
  final String src;
  const IncomeInfo(this.v, this.src);
}

class AgeInfo {
  final double v;
  final String src;
  final bool known;
  const AgeInfo(this.v, this.src, this.known);
}

class Household {
  final int adults, kids;
  final double scale;
  final bool known;
  const Household(this.adults, this.kids, this.scale, this.known);
  String get label => '$adults adult${adults > 1 ? 's' : ''}${kids > 0 ? ', $kids child${kids > 1 ? 'ren' : ''}' : ''}';
}

class Range {
  final double lo, hi;
  final String label;
  const Range(this.lo, this.hi, this.label);
}

class BenchRow {
  final String cat, label, status, s; // s: good | plain | warn | bad
  final double spent, pct, lo, hi, over, loAed, hiAed;
  const BenchRow(this.cat, this.label, this.spent, this.pct, this.lo, this.hi, this.status, this.s, this.over, this.loAed, this.hiAed);
}

class DebtBurden {
  final double loans, cards, total, pct, income;
  final String s;
  const DebtBurden(this.loans, this.cards, this.total, this.pct, this.s, this.income);
}

class MixPart {
  final String label, kind; // kind: equity | bonds | gold
  final int v;
  const MixPart(this.label, this.kind, this.v);
}

class Plan {
  final double? surplus;
  final double toDebt, toEF, toInvestBase, projReserve, toInvest;
  final List<MixPart> mix;
  final double? eos;
  final AgeInfo age;
  final IncomeInfo? inc;
  const Plan(this.surplus, this.toDebt, this.toEF, this.toInvestBase, this.projReserve, this.toInvest, this.mix, this.eos, this.age, this.inc);
}

class Check {
  final String k, s, d;
  const Check(this.k, this.s, this.d);
}

class CatImpact {
  final String cat, label, s;
  final double bp, ap, lo, hi, before, after;
  const CatImpact(this.cat, this.label, this.bp, this.ap, this.lo, this.hi, this.before, this.after, this.s);
}

class ProjectEval {
  final Project pj;
  final String? verdict; // good | warn | bad, null when income is unknown
  final int months, term;
  final bool loan;
  final double dp, need, fromCash, canSave, emi, running, rentSaved, freeAfter;
  final double? dbr;
  final List<Check> checks;
  final List<String> fixes; // may contain **bold** lead-ins
  final List<String> impacts;
  final CatImpact? catImpact;
  const ProjectEval({required this.pj, this.verdict, this.months = 0, this.term = 0, this.loan = false, this.dp = 0, this.need = 0, this.fromCash = 0,
      this.canSave = 0, this.emi = 0, this.running = 0, this.rentSaved = 0, this.freeAfter = 0, this.dbr, this.checks = const [], this.fixes = const [],
      this.impacts = const [], this.catImpact});
}

class Suggestion {
  final String id, sev, title, body, actionLabel, actionTab;
  final double? impact; // AED a year
  final List<String> why;
  const Suggestion(this.id, this.sev, this.title, this.body, this.impact, this.why, this.actionLabel, this.actionTab);
}

class ProjectType {
  final String label, note;
  final double fees, runPct, minDp, maxTerm, rate, term;
  const ProjectType(this.label, this.fees, this.runPct, this.minDp, this.maxTerm, this.rate, this.term, this.note);
}

const Map<String, ProjectType> projectTypes = {
  'car': ProjectType('Car', 0, 12, 20, 48, 3.5, 48, 'UAE car loans need at least 20% down and run up to 48 months.'),
  'home': ProjectType('Home in the UAE', 5, 1.5, 20, 300, 4.5, 300, 'Expat mortgages usually need at least 20% down, plus about 4–7% in transfer and agent fees.'),
  'build': ProjectType('Build a house back home', 0, 0, 0, 240, 8, 120, "Building is paid in stages, so you don't need the full amount on day one."),
  'other': ProjectType('Other goal', 0, 0, 0, 60, 6, 36, ''),
};

class _Bench {
  final double lo, hi, e, cap;
  final bool perChild;
  final String label;
  const _Bench(this.lo, this.hi, this.e, this.cap, this.label, {this.perChild = false});
}

/// Starter ranges as % of monthly income, for one adult. Bigger households scale them.
const Map<String, _Bench> _bench = {
  'Rent': _Bench(25, 35, 0.2, 45, 'Rent'),
  'Transport': _Bench(8, 15, 0.2, 20, 'Car & transport'),
  'Groceries': _Bench(8, 12, 0.8, 25, 'Groceries'),
  'Dining': _Bench(3, 6, 0.2, 10, 'Dining out'),
  'Bills': _Bench(4, 7, 0.4, 12, 'Bills & utilities'),
  'Education': _Bench(5, 15, 0, 35, 'School & childcare', perChild: true),
  'Subscriptions': _Bench(0, 2, 0, 2, 'Subscriptions & gym'),
  'Shopping': _Bench(3, 8, 0.3, 12, 'Shopping'),
  'Health': _Bench(1, 4, 0.7, 8, 'Health'),
};

const Map<String, double> assumedReturns = {'equity': 7, 'bonds': 4, 'gold': 3}; // illustration only

double instalment(double principal, double annualRate, int months) {
  final i = annualRate / 1200;
  return i != 0 ? principal * i / (1 - math.pow(1 + i, -months)) : principal / months;
}

double maxPrincipal(double emi, double annualRate, int months) {
  final i = annualRate / 1200;
  return i != 0 ? emi * (1 - math.pow(1 + i, -months)) / i : emi * months;
}

/// UAE end-of-service gratuity: 21 days' basic per year for the first 5 years, 30 days after; capped at 2 years' wage.
double eosb(double basic, double years) {
  final daily = basic / 30;
  final first = math.min(years, 5.0) * 21 * daily, rest = math.max(years - 5, 0.0) * 30 * daily;
  return math.min(first + rest, basic * 24);
}

class ProjectionPoint {
  final int y;
  final double paid, value;
  const ProjectionPoint(this.y, this.paid, this.value);
}

List<ProjectionPoint> projection(double monthly, int years, double rate) {
  final i = rate / 100 / 12;
  return [
    for (var y = 0; y <= years; y++)
      ProjectionPoint(y, monthly * y * 12, i != 0 ? monthly * ((math.pow(1 + i, y * 12) - 1) / i) : monthly * y * 12),
  ];
}

class Finance {
  final AppState s;
  final String today; // yyyy-mm-dd
  Finance(this.s, {String? today}) : today = today ?? isoOf(DateTime.now());

  // ---------- Months ----------
  List<String> get monthsInData => (s.tx.map((t) => monthKey(t.date)).toSet().toList()..sort());
  String get latestMonth => monthsInData.isEmpty ? monthKey(today) : monthsInData.last;
  List<Tx> txIn(String m) => s.tx.where((t) => monthKey(t.date) == m).toList();

  // ---------- Totals ----------
  Totals totals([String? month]) {
    final mt = txIn(month ?? latestMonth);
    final assets = s.assets.fold<double>(0, (a, x) => a + toAed(x.amount, x.cur));
    final debts = s.liabilities.fold<double>(0, (a, x) => a + toAed(x.amount, x.cur));
    final cash = s.assets.where((a) => a.type == 'cash').fold<double>(0, (a, x) => a + toAed(x.amount, x.cur));
    final spent = -mt.where((t) => t.amount < 0).fold<double>(0, (a, t) => a + t.amount);
    final received = mt.where((t) => t.amount > 0).fold<double>(0, (a, t) => a + t.amount);
    final byCat = {for (final c in categories) c: 0.0};
    for (final t in mt.where((t) => t.amount < 0)) {
      byCat[t.cat] = (byCat[t.cat] ?? 0.0) - t.amount;
    }
    return Totals(assets, debts, assets - debts, cash, spent, received, byCat);
  }

  late final Totals t = totals();

  // ---------- Income, age, household ----------
  static final _salaryRx = RegExp(r'salary|payroll|wps', caseSensitive: false);

  IncomeInfo? get income {
    final p = s.profile;
    if (p.income != null && p.income! > 0) return IncomeInfo(p.income!, 'the figure you entered');
    final sal = txIn(latestMonth).where((t) => t.amount > 0 && _salaryRx.hasMatch(t.merchant)).fold<double>(0, (a, t) => a + t.amount);
    if (sal > 0) return IncomeInfo(sal, 'your salary this month');
    for (final b in incomeBands) {
      if (b.key == p.incomeBand) return IncomeInfo(b.mid, 'the middle of your ${b.label} range');
    }
    return null;
  }

  AgeInfo get age {
    for (final b in ageBands) {
      if (b.key == s.profile.ageBand) return AgeInfo(b.mid, 'your ${b.label} range', true);
    }
    return const AgeInfo(35, 'a default of 35', false);
  }

  Household get household {
    final p = s.profile;
    final adults = p.adults ?? 1, kids = p.kids ?? 0;
    return Household(adults, kids, 1 + 0.5 * (adults - 1) + 0.3 * kids, p.adults != null);
  }

  int get efMonths => s.profile.efMonths > 0 ? s.profile.efMonths : 6;
  String get invStyle => s.profile.invStyle ?? 'grow';
  double get fdRate => s.profile.fdRate ?? 4.0;

  // ---------- Benchmarks ----------
  Range? benchRange(String cat) {
    final b = _bench[cat]!, h = household;
    if (b.perChild) {
      return h.kids > 0 ? Range(math.min(b.lo * h.kids, b.cap), math.min(b.hi * h.kids, b.cap), b.label) : null;
    }
    final f = 1 + b.e * (h.scale - 1);
    double r(double x) => jsRound(math.min(x * f, b.cap) * 2) / 2;
    return Range(r(b.lo), math.max(r(b.hi), r(b.lo) + 0.5), b.label);
  }

  List<BenchRow> benchmark() {
    final inc = income;
    if (inc == null) return [];
    final out = <BenchRow>[];
    for (final cat in _bench.keys) {
      final b = benchRange(cat);
      if (b == null) continue;
      final spent = t.byCat[cat] ?? 0.0, pct = spent / inc.v * 100;
      String status, sv;
      if (pct < b.lo) {
        status = 'Below typical'; sv = 'good';
      } else if (pct <= b.hi) {
        status = 'Typical'; sv = 'plain';
      } else if (pct <= b.hi * 1.3) {
        status = 'High'; sv = 'warn';
      } else {
        status = 'Very high'; sv = 'bad';
      }
      final over = math.max(0.0, spent - inc.v * b.hi / 100);
      out.add(BenchRow(cat, b.label, spent, pct, b.lo, b.hi, status, sv, over, inc.v * b.lo / 100, inc.v * b.hi / 100));
    }
    return out;
  }

  // ---------- Debt burden (UAE lenders cap repayments at 50% of salary) ----------
  DebtBurden? get debtBurden {
    final inc = income;
    if (inc == null) return null;
    final loans = s.liabilities.where((l) => l.type != 'card').fold<double>(0, (a, l) => a + (l.monthly ?? 0.0));
    final cards = s.liabilities.where((l) => l.type == 'card').fold<double>(0, (a, l) => a + toAed(l.amount, l.cur) * 0.05);
    final total = loans + cards, pct = total / inc.v * 100;
    return DebtBurden(loans, cards, total, pct, pct >= 50 ? 'bad' : pct >= 35 ? 'warn' : 'good', inc.v);
  }

  double get costlyDebt => s.liabilities.where((l) => l.rate >= 10).fold<double>(0, (a, l) => a + toAed(l.amount, l.cur));
  double get efTarget => t.spent * efMonths;
  double get efGap => math.max(efTarget - t.cash, 0.0);

  // ---------- Monthly plan ----------
  double projectDp(Project pj) => pj.method == 'loan' ? math.max(pj.dp, projectTypes[pj.type]!.minDp) : 100;
  double projectNeed(Project pj) => math.max(pj.cost * (projectDp(pj) + projectTypes[pj.type]!.fees) / 100 - pj.saved, 0.0);

  late final Plan plan = _plan();
  Plan _plan() {
    final inc = income, p = s.profile, ag = age;
    final surplus = inc == null ? null : inc.v - t.spent;
    double toDebt = 0, toEF = 0, pool = math.max(surplus ?? 0.0, 0.0);
    if (costlyDebt > 0) {
      toDebt = math.min(pool * 0.7, costlyDebt);
      pool -= toDebt;
    }
    if (efGap > 0) {
      toEF = math.min(pool * 0.6, efGap);
      pool -= toEF;
    }
    final base = pool;
    final reserve = math.min(pool, s.projects.fold<double>(0, (a, pj) => a + projectNeed(pj) / math.max(pj.months, 1)));
    final shift = {'cautious': -20, 'balanced': 0, 'growth': 15}[p.risk] ?? 0;
    final equity = math.max(20, math.min(90, (110 - ag.v).round() + shift)).toInt();
    final mix = [
      MixPart(p.sharia ? 'Sharia-screened global equity' : 'Global equity index', 'equity', equity),
      MixPart(p.sharia ? 'Sukuk' : 'Bonds / fixed income', 'bonds', 100 - equity - 10),
      const MixPart('Gold', 'gold', 10),
    ];
    final eos = (p.basic != null && p.basic! > 0 && p.years != null) ? eosb(p.basic!, p.years!) : null;
    return Plan(surplus, toDebt, toEF, base, reserve, pool - reserve, mix, eos, ag, inc);
  }

  double growthRate([List<MixPart>? mix]) {
    final m = mix ?? plan.mix;
    return (m[0].v * assumedReturns['equity']! + m[1].v * assumedReturns['bonds']! + m[2].v * assumedReturns['gold']!) / 100;
  }

  // ---------- Projects ----------
  late final List<ProjectEval> projects = _evaluateProjects();
  List<ProjectEval> _evaluateProjects() {
    final list = s.projects, pl = plan, inc = income;
    if (inc == null || pl.surplus == null) return [for (final pj in list) ProjectEval(pj: pj)];
    final full = math.max(pl.surplus!, 0.0), base = pl.toInvestBase;
    final costly = costlyDebt;
    final ready = full > 0 ? ((costly + efGap) / full).ceil() : 9999;
    const h = 480;
    final stream = List<double>.generate(h + 1, (m) => m == 0 ? 0 : (m <= ready ? base : full));
    final obligations0 = debtBurden?.total ?? 0.0;
    final overspend = benchmark().fold<double>(0, (a, r) => a + r.over);
    var spareCash = math.max(t.cash - efTarget, 0.0);
    final investHeld = s.assets.where((a) => a.type == 'investment').fold<double>(0, (a, x) => a + toAed(x.amount, x.cur));
    final carRx = RegExp(r'car|auto|vehicle', caseSensitive: false);
    Liability? carLoan;
    for (final l in s.liabilities) {
      if (l.type != 'card' && carRx.hasMatch(l.name) && (l.monthly ?? 0) != 0) {
        carLoan = l;
        break;
      }
    }
    final catLoad = <String, double>{};
    double extraObl = 0, afterLoad = 0;
    final out = <ProjectEval>[];

    for (final pj in list) {
      final T = projectTypes[pj.type]!;
      final M = math.max(1, pj.months);
      final loan = pj.method == 'loan', dp = projectDp(pj);
      final need = projectNeed(pj);
      final fromCash = math.min(spareCash, need);
      spareCash -= fromCash;
      final needStream = need - fromCash;
      var canSave = fromCash;
      for (var m = 1; m <= M && m <= h; m++) {
        canSave += math.max(stream[m], 0.0);
      }
      final term = loan ? math.min(pj.term > 0 ? pj.term : T.term.toInt(), T.maxTerm.toInt()) : 0;
      final principal = loan ? pj.cost * (1 - dp / 100) : 0.0;
      final emi = loan ? instalment(principal, pj.rate, term) : 0.0;
      final running = pj.cost * T.runPct / 100 / 12;
      final rentSaved = pj.type == 'home' ? (t.byCat['Rent'] ?? 0.0) : 0.0;
      final monthlyAfter = emi + running - rentSaved;
      final dbr = loan ? (obligations0 + extraObl + emi) / inc.v * 100 : null;
      final freeAfter = full - afterLoad - monthlyAfter;
      final due = monthsAhead(monthKey(today), M);

      final checks = <Check>[];
      final saveOK = canSave >= need, spare = need != 0 ? (canSave - need) / need : 1.0;
      checks.add(Check(
          'Upfront by $due',
          saveOK ? (spare < 0.1 ? 'warn' : 'good') : 'bad',
          (saveOK
                  ? 'You can set aside ${money(canSave)}, and need ${money(need)}.'
                  : 'You can set aside about ${money(canSave)} by then, but need ${money(need)}. Short by ${money(need - canSave)}.') +
              (fromCash > 0 ? ' Includes ${money(fromCash)} of savings above your safety cushion.' : '')));
      if (loan) {
        final d = dbr!;
        checks.add(Check('Loan fits lending caps', d <= 35 ? 'good' : d <= 50 ? 'warn' : 'bad',
            'Repayments would be ${d.toStringAsFixed(0)}% of income. Banks cap total repayments at 50%; under 35% is comfortable.'));
      }
      final parts = [
        if (emi > 0) 'instalment ${money(emi)}',
        if (running > 0) 'running costs about ${money(running)}',
        if (rentSaved > 0) 'minus ${money(rentSaved)} rent you stop paying',
      ];
      checks.add(Check(
          'Affordable afterwards',
          freeAfter >= full * 0.25 ? 'good' : freeAfter >= 0 ? 'warn' : 'bad',
          monthlyAfter > 0
              ? 'Adds ${money(monthlyAfter)} a month (${parts.join(', ')}). You\'d have ${money(freeAfter)} a month left over.'
              : 'No new monthly costs${rentSaved > 0 ? '; it replaces ${money(rentSaved)} of rent' : ''}. You\'d have ${money(freeAfter)} a month left over.'));

      final cat = pj.type == 'car' ? 'Transport' : pj.type == 'home' ? 'Rent' : null;
      CatImpact? ci;
      if (cat != null) {
        final b = benchRange(cat)!, before = (t.byCat[cat] ?? 0.0) + (catLoad[cat] ?? 0.0);
        final after = cat == 'Rent' ? before - rentSaved + emi + running : before + emi + running;
        final bp = before / inc.v * 100, ap = after / inc.v * 100;
        ci = CatImpact(cat, b.label, bp, ap, b.lo, b.hi, before, after, ap <= b.hi ? 'good' : 'warn');
        catLoad[cat] = (catLoad[cat] ?? 0.0) + (after - before);
        checks.add(Check('${b.label} stays in a healthy range', ci.s,
            'Goes from ${bp.toStringAsFixed(0)}% to ${ap.toStringAsFixed(0)}% of income. Typical is ${_n(b.lo)}–${_n(b.hi)}%.'));
      }
      final verdict = checks.any((c) => c.s == 'bad') ? 'bad' : checks.any((c) => c.s == 'warn') ? 'warn' : 'good';

      final impacts = <String>[
        if (monthlyAfter > 0)
          'Your safety cushion target rises from ${money(efTarget)} to ${money((t.spent + afterLoad + monthlyAfter) * efMonths)}, because $efMonths months of spending costs more.',
        if (loan) 'Your debts grow by ${money(principal)}, and repayments reach ${dbr!.toStringAsFixed(0)}% of income.',
        if (pj.type == 'car') 'Cars typically lose around 15–20% of their value a year, so count this as spending, not an asset.',
      ];

      final fixes = <String>[];
      if (verdict != 'good') {
        double cum = 0;
        int? mE;
        for (var m = 1; m <= h; m++) {
          cum += math.max(stream[m], 0.0);
          if (cum >= need) {
            mE = m;
            break;
          }
        }
        if (!saveOK && mE != null) {
          fixes.add('**Move the date to ${monthsAhead(monthKey(today), mE)}.** That\'s ${mE - M} month${mE - M > 1 ? 's' : ''} later, and you\'d have the ${loan ? 'down payment' : 'full amount'} saved.');
        }
        final upPct = (dp + T.fees) / 100;
        var maxCost = (canSave + pj.saved) / upPct;
        if (loan) {
          final room = inc.v * 0.35 - obligations0 - extraObl;
          maxCost = math.min(maxCost, room > 0 ? maxPrincipal(room, pj.rate, term) / (1 - dp / 100) : 0.0);
        }
        if (maxCost < pj.cost && maxCost > pj.cost * 0.2) {
          fixes.add('**Aim for about ${money((maxCost / 5000).floorToDouble() * 5000)} instead.** That fits your $due date with what you can save.');
        }
        if (!saveOK) {
          final extra = (need - canSave) / M;
          final src = [
            if (overspend > 0) 'bringing spending back to typical ranges frees ${money(overspend)}',
            if (costly > 0) 'clearing your credit card first unlocks your full ${money(full)} surplus from ${monthsAhead(monthKey(today), ready)}',
          ];
          final joined = src.join('; ');
          fixes.add('**Find ${money(extra)} more a month.** ${src.isNotEmpty ? '${joined[0].toUpperCase()}${joined.substring(1)}.' : 'That means cutting spending or raising income.'}');
        }
        if (loan && dbr! > 35 && term < T.maxTerm) {
          fixes.add('**Stretch the loan to ${T.maxTerm.toInt()} months.** The instalment drops to ${money(instalment(principal, pj.rate, T.maxTerm.toInt()))}, but you pay more interest overall.');
        }
        if (!loan && pj.type != 'build' && T.minDp > 0) {
          fixes.add('**Consider financing.** With ${_n(T.minDp)}% down you\'d need ${money(pj.cost * (T.minDp + T.fees) / 100)} upfront instead of ${money(pj.cost * (100 + T.fees) / 100)}. Check the instalment fits first.');
        }
        if (ci != null && ci.s == 'warn' && pj.type == 'car') {
          final perAed = (loan ? (1 - dp / 100) * instalment(1, pj.rate, term) : 0.0) + T.runPct / 1200;
          final roomC = inc.v * ci.hi / 100 - ci.before, maxP = roomC / perAed;
          fixes.add(maxP > 10000
              ? '**Look at cars around ${money((maxP / 5000).floorToDouble() * 5000)}.** That keeps car & transport under ${_n(ci.hi)}% of income, including the loan and running costs.'
              : '**Transport is already ${ci.bp.toStringAsFixed(0)}% of income before this car.** Bring current costs down first.');
        }
        if (pj.type == 'car' && carLoan != null && ci != null) {
          final z = (ci.after - carLoan.monthly!) / inc.v * 100;
          fixes.add('**If it replaces your current car:** selling it and clearing the ${money(toAed(carLoan.amount, carLoan.cur))} ${carLoan.name.toLowerCase()} frees ${money(carLoan.monthly!)} a month and brings transport to ${z.toStringAsFixed(0)}% of income.');
        }
        if (!saveOK && investHeld > 0) {
          final use = math.min(investHeld, need - canSave), r = growthRate() / 100;
          final lost = use * (math.pow(1 + r, M / 12).toDouble() - 1), gapLeft = need - canSave - use;
          fixes.add('**Use part of your investments.** You hold ${money(investHeld)}. Using ${money(use)} ${gapLeft > 0 ? 'cuts the gap to ${money(gapLeft)}' : 'closes the gap'}, but that money stops growing: about ${money(lost)} less by $due at the assumed rate.');
        }
        if (pj.type == 'build') {
          fixes.add('**Build in stages.** Land and foundations first, then structure, then finishing. Each stage becomes a smaller, nearer goal.');
        }
        if (freeAfter < 0) {
          fixes.add('**Plan for the running costs.** After buying, costs would exceed your surplus by ${money(-freeAfter)} a month. A cheaper option or a bigger down payment closes that.');
        }
      }

      // Reserve this project's money from the stream, earliest months first.
      var left = needStream;
      for (var m = 1; m <= M && m <= h && left > 0; m++) {
        final take = math.min(math.max(stream[m], 0.0), left);
        stream[m] -= take;
        left -= take;
      }
      for (var m = M + 1; m <= h; m++) {
        stream[m] -= running - rentSaved + (m <= M + term ? emi : 0.0);
      }
      extraObl += emi;
      afterLoad += monthlyAfter;

      out.add(ProjectEval(pj: pj, verdict: verdict, months: M, term: term, loan: loan, dp: dp, need: need, fromCash: fromCash, canSave: canSave,
          emi: emi, running: running, rentSaved: rentSaved, freeAfter: freeAfter, dbr: dbr, checks: checks, fixes: fixes, impacts: impacts, catImpact: ci));
    }
    return out;
  }

  // ---------- Suggestions ----------
  late final List<Suggestion> suggestions = _suggestions();
  List<Suggestion> _suggestions() {
    final inc = income, out = <Suggestion>[];
    final monthlyExp = t.spent, efM = efMonths, target = monthlyExp * efM;

    for (final l in s.liabilities.where((l) => l.rate >= 10)) {
      final bal = toAed(l.amount, l.cur), interest = bal * l.rate / 100;
      out.add(Suggestion('debt-${l.id}', 'bad', 'Pay off your ${l.name.toLowerCase()} first',
          'At ${_n(l.rate)}% a year, carrying ${money(bal)} costs about ${money(interest)} a year in interest. No investment reliably beats that.', interest,
          ['Balance ${money(bal)} at ${_n(l.rate)}% a year', 'Interest if the balance stays: ${money(interest)} a year', 'Rule: any debt at 10% or more comes before investing'],
          'See debts', 'wealth'));
    }

    final db = debtBurden;
    if (db != null && db.pct >= 35) {
      out.add(Suggestion('dbr', db.s, 'Loan repayments take ${db.pct.toStringAsFixed(0)}% of income',
          db.pct >= 50 ? "That's at the 50% cap UAE lenders use, so new credit is likely to be refused." : "You're approaching the 50% cap UAE lenders use. Avoid new loans until this drops.",
          null, ['Instalments ${money(db.loans)} + card minimums ${money(db.cards)} a month', 'Income ${money(db.income)}', 'Warning from 35%, cap at 50%'], 'See debts', 'wealth'));
    }

    if (monthlyExp > 0) {
      if (t.cash < target) {
        final gap = target - t.cash;
        out.add(Suggestion('ef', t.cash < monthlyExp * 3 ? 'bad' : 'warn', 'Build your safety cushion to ${money(target)}',
            'You have ${money(t.cash)} in cash, about ${(t.cash / monthlyExp).toStringAsFixed(1)} months of spending. Aim for $efM months, since losing a job in the UAE also puts your visa on a clock.',
            null, ['Monthly spending ${money(monthlyExp)}', 'Target: $efM × spending = ${money(target)}', 'Short by ${money(gap)}'], 'See your fund', 'invest'));
      } else {
        final idle = t.cash - target, gain = idle * 0.04;
        if (idle > 5000) {
          out.add(Suggestion('idle', 'warn', '${money(idle)} is sitting idle',
              "That's above your $efM-month cushion. Invested or in a savings account, it could earn around ${money(gain)} a year.", gain,
              ['Cash ${money(t.cash)}, cushion needs ${money(target)}', 'Estimate uses an assumed 4% a year'], 'Open Invest', 'invest'));
        }
      }
    }

    final hh = household;
    for (final r in benchmark().where((r) => r.over > 0)) {
      out.add(Suggestion('bench-${r.cat}', r.s == 'bad' ? 'bad' : 'warn', '${r.label} is ${r.pct.toStringAsFixed(0)}% of your income',
          'Typical is ${_n(r.lo)}–${_n(r.hi)}%. Bringing it to ${_n(r.hi)}% frees ${money(r.over)} a month.', r.over * 12,
          ['Spent ${money(r.spent)} this month', 'Income ${money(inc!.v)} (from ${inc!.src})', 'Typical range ${_n(r.lo)}–${_n(r.hi)}% of income for ${hh.label}${hh.known ? '' : ' (assumed)'}'],
          'See spending', 'spend'));
    }

    final subs = txIn(latestMonth).where((x) => x.cat == 'Subscriptions').toList();
    if (subs.length >= 2) {
      final m = subs.fold<double>(0, (a, x) => a - x.amount);
      out.add(Suggestion('subs', 'warn', '${subs.length} subscriptions cost ${money(m * 12)} a year',
          '${subs.map((x) => x.merchant).join(', ')}. Cancelling one you rarely use is the easiest saving on this list.',
          subs.map((x) => -x.amount).reduce(math.min) * 12, ['Monthly total ${money(m, 2)}', 'Impact shows the cheapest one cancelled'], 'See spending', 'spend'));
    }

    s.budgets.forEach((c, b) {
      final v = t.byCat[c] ?? 0.0;
      final covered = out.any((o) => o.id == 'bench-$c') || (c == 'Subscriptions' && out.any((o) => o.id == 'subs'));
      if (b > 0 && v > b && !covered) {
        out.add(Suggestion('budget-$c', 'warn', '$c is ${money(v - b)} over budget', '${money(v)} spent against a ${money(b)} budget this month.', null,
            ['Budget ${money(b)}', 'Spent ${money(v)}'], 'See spending', 'spend'));
      }
    });

    for (final r in projects.where((r) => r.verdict == 'bad' || r.verdict == 'warn')) {
      final due = monthsAhead(monthKey(today), r.months);
      final title = r.verdict == 'bad'
          ? "${r.pj.name} isn't affordable by $due yet"
          : (r.catImpact != null && r.catImpact!.s == 'warn')
              ? '${r.pj.name} would push ${r.catImpact!.label.toLowerCase()} to ${r.catImpact!.ap.toStringAsFixed(0)}% of income'
              : '${r.pj.name} is tight';
      out.add(Suggestion('proj-${r.pj.id}', 'warn', title,
          r.fixes.isNotEmpty ? r.fixes.first.replaceAll('**', '') : 'Open the project to see what would make it work.', null,
          r.checks.where((c) => c.s != 'good').map((c) => c.d).toList(), 'Open project', 'projects'));
    }

    if (inc != null) {
      final surplus = inc.v - monthlyExp;
      if (surplus > 500) {
        out.add(Suggestion('auto', 'good', 'Move ${money((surplus * 0.8 / 100).floorToDouble() * 100)} on salary day',
            'You have about ${money(surplus)} left each month. A standing transfer on the day your salary lands saves it before it gets spent.', null,
            ['Income ${money(inc.v)} (from ${inc.src})', 'Spending ${money(monthlyExp)}', 'Suggests 80% of the gap, keeping a buffer'], 'Open Invest', 'invest'));
      }
    }

    const sev = {'bad': 0, 'warn': 1, 'good': 2};
    final visible = out.where((o) => !s.dismissed.contains(o.id) && !s.done.contains(o.id)).toList();
    final indexed = [for (var i = 0; i < visible.length; i++) (i, visible[i])];
    indexed.sort((a, b) {
      final c = sev[a.$2.sev]!.compareTo(sev[b.$2.sev]!);
      if (c != 0) return c;
      final d = (b.$2.impact ?? 0).compareTo(a.$2.impact ?? 0);
      return d != 0 ? d : a.$1.compareTo(b.$1); // stable, like the prototype
    });
    return [for (final e in indexed) e.$2];
  }
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
