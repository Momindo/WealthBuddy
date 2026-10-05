// The decision engine: given the user's money and one project, decide whether it's affordable,
// by when, and what to do in what order. Pure Dart, no Flutter, fully unit-tested.
//
// Order of priorities, from personal-finance basics:
//   1. Clear credit card debt (30–40% a year interest beats any saving).
//   2. Build a safety cushion (3–12 months of essentials, sized to the household),
//      unless the purchase is small: under one month's take-home pay.
//   3. Save the upfront amount (full price, or down payment and fees).
//   4. Buy, and check the monthly costs and any loan still fit afterwards.
import 'dart:math' as math;

import 'format.dart';
import 'models.dart';
import 'plan.dart';

export 'plan.dart';

class ProjectKind {
  final String label, noun, buyTitle, costHint;
  final bool canFinance;
  final String loanName;
  final double minDown, fees, rate, runPctYear;
  final int term, maxTerm;
  final List<int> terms;
  final List<double> rateChips; // quick picks for the loan rate
  final String costTitle; // overrides "How much will the {noun} cost?"
  final double priceRise; // % a year the price tends to rise, for the cost of waiting
  const ProjectKind({
    required this.label,
    required this.noun,
    required this.buyTitle,
    this.costHint = '',
    this.canFinance = false,
    this.loanName = 'loan',
    this.minDown = 0,
    this.fees = 0,
    this.rate = 0,
    this.runPctYear = 0,
    this.term = 36,
    this.maxTerm = 48,
    this.terms = const [12, 24, 36, 48],
    this.rateChips = const [],
    this.costTitle = '',
    this.priceRise = 0,
  });
}

/// Project types. Lending rules and cost estimates are starter values to verify before release.
const Map<String, ProjectKind> kinds = {
  'car': ProjectKind(
      label: 'Car', noun: 'car', buyTitle: 'Buy the car', costHint: 'The price, plus first-year registration and insurance.',
      canFinance: true, loanName: 'car loan', minDown: 20, rate: 3.5, term: 48, maxTerm: 60, runPctYear: 12,
      terms: [12, 24, 36, 48, 60], rateChips: [0, 2.5, 3.5, 4.5]),
  'home': ProjectKind(
      label: 'Home', noun: 'home', buyTitle: 'Buy the home', costHint: 'The property price. Transfer and agent fees are added for you.',
      canFinance: true, loanName: 'mortgage', minDown: 20, fees: 6, rate: 4.5, term: 300, maxTerm: 300, runPctYear: 1.5, terms: [120, 180, 240, 300], rateChips: [3.5, 4.5, 5.5], priceRise: 3),
  'build': ProjectKind(label: 'Build a house', noun: 'house', buyTitle: 'Start building', costHint: 'Land and construction together.', priceRise: 3),
  'vacation': ProjectKind(label: 'Vacation', noun: 'trip', buyTitle: 'Book the trip', costHint: 'Flights, hotels and spending money.', priceRise: 4),
  'wedding': ProjectKind(label: 'Wedding', noun: 'wedding', buyTitle: 'Pay for the wedding', costHint: 'Venue, catering, gifts, everything.', priceRise: 4),
  'education': ProjectKind(label: 'Education', noun: 'studies', buyTitle: 'Pay the fees', costHint: 'Tuition, plus books and living costs if any.', priceRise: 5),
  'renovation': ProjectKind(
      label: 'Home renovation', noun: 'renovation', buyTitle: 'Start the work', costHint: 'Contractor quote, materials, and about 10% for surprises.',
      canFinance: true, loanName: 'personal loan', rate: 7, term: 36, maxTerm: 48, rateChips: [5, 7, 9], priceRise: 3),
  'hajj': ProjectKind(label: 'Hajj or Umrah', noun: 'pilgrimage', buyTitle: 'Book the package', costHint: 'Package, flights and spending money for everyone going.', priceRise: 4),
  'business': ProjectKind(
      label: 'Start a business', noun: 'business', buyTitle: 'Launch it', costTitle: 'How much do you need to start?',
      costHint: 'Trade licence, visa, office or desk, stock, and a few months of running costs.'),
  'baby': ProjectKind(
      label: 'New baby', noun: 'baby fund', buyTitle: 'You\'re ready for the baby', costTitle: 'How much do you want to set aside?',
      costHint: 'Delivery, nursery, car seat and pram, and a few months of extra costs.'),
  'gold': ProjectKind(label: 'Buy gold', noun: 'gold', buyTitle: 'Buy the gold', costHint: 'What you want to spend, including making charges.'),
  'gadget': ProjectKind(label: 'Phone or laptop', noun: 'device', buyTitle: 'Buy it', costHint: 'The price, plus a case, cover or warranty.'),
  'other': ProjectKind(
      label: 'Something else', noun: 'purchase', buyTitle: 'Buy it', canFinance: true, loanName: 'personal loan', rate: 7, term: 36, maxTerm: 48, rateChips: [5, 7, 9]),
};

ProjectKind kindOf(String type) => kinds[type] ?? kinds['other']!;

/// Which questions to ask, in order. Money questions are skipped when they're already answered
/// (the user gets a one-screen check instead), unless they choose to update them.
enum Q { cost, when, pay, loan, rent, setAside, income, payday, spending, savings, repayments, card, situation, investments, moneyCheck }

/// [isNew]: only a new project asks about money already set aside; later it's added with "Add money".
List<Q> projectQuestions(Project p, {bool isNew = false}) {
  final k = kindOf(p.type);
  return [Q.cost, Q.when, if (k.canFinance) Q.pay, if (k.canFinance && p.pay == 'loan') Q.loan, if (p.type == 'home') Q.rent, if (isNew) Q.setAside];
}

const List<Q> moneyQuestions = [Q.income, Q.payday, Q.spending, Q.savings, Q.repayments, Q.card, Q.situation, Q.investments];

double instalment(double principal, double annualRate, int months) {
  if (months <= 0) return 0;
  final i = annualRate / 1200;
  return i != 0 ? principal * i / (1 - math.pow(1 + i, -months)) : principal / months;
}

double maxPrincipal(double monthly, double annualRate, int months) {
  if (months <= 0 || monthly <= 0) return 0;
  final i = annualRate / 1200;
  return i != 0 ? monthly * (1 - math.pow(1 + i, -months)) / i : monthly * months;
}

/// The numbers a plan needs about a project: what to save, and what it costs each month once bought.
({double upfront, double emi, double running, double rentSaved, bool small, int monthsLeft}) projectBasics(Money m, Project p, {required String today}) {
  final k = kindOf(p.type);
  final loan = k.canFinance && p.pay == 'loan';
  final down = loan ? math.max(p.downPct, k.minDown) : 100.0;
  final int term = loan ? math.max(6, math.min(p.term, k.maxTerm)) : 0;
  final principal = loan ? p.cost * (1 - down / 100) : 0.0;
  return (
    upfront: p.cost * (down + k.fees) / 100,
    emi: loan ? instalment(principal, p.rate, term) : 0.0,
    running: p.cost * k.runPctYear / 100 / 12,
    rentSaved: p.type == 'home' ? (p.rent ?? 0) : 0.0,
    small: !loan && p.cost <= (m.income ?? 0) * smallPurchaseMonths,
    monthsLeft: math.max(1, monthsUntil(today, p.target)),
  );
}

const double cardMonthlyRate = 0.03; // about 36% a year, typical for UAE credit cards
const double smallPurchaseMonths = 1; // "small" = up to one month of take-home pay

class PlanStep {
  final String title, body, when;
  final bool done;
  const PlanStep(this.title, this.body, {this.when = '', this.done = false});
}

/// One line of the regret check: how things look the month after buying.
class Check {
  final String label, detail;
  final bool ok;
  const Check(this.label, this.ok, this.detail);
}

/// What being later than wanted costs, line by line. Positive costs you money, negative saves it.
class WaitCost {
  final int months;
  final List<(String, double)> lines;
  const WaitCost(this.months, this.lines);
  double get total => lines.fold<double>(0, (a, l) => a + l.$2);
  double get perMonth => total / months;
  bool get saves => total < 0;
  String get sentence => saves
      ? 'Waiting isn\'t costing you money: it saves about ${money(roundDown(-total, 100))}.'
      : 'Waiting costs about ${money(roundUp(total, 100))}, roughly ${money(roundUp(perMonth, 50))} a month of delay.';
}

/// The cost of buying [months] later: rent still paid, owning or running costs not yet paid, and prices rising.
WaitCost? waitCost(Project p, int months, {required bool loan, required double principal, required double running, required double rentSaved}) {
  if (months <= 0) return null;
  final k = kindOf(p.type);
  final lines = <(String, double)>[];
  if (rentSaved > 0) lines.add(('Rent you keep paying', rentSaved * months));
  if (p.type == 'home') {
    final owning = (loan ? principal * p.rate / 1200 : 0) + running;
    if (owning > 0) lines.add(('Owning costs you don\'t pay yet (${loan ? 'interest, ' : ''}upkeep)', -owning * months));
  } else if (running > 0) {
    lines.add(('Running costs you don\'t pay yet', -running * months));
  }
  if (k.priceRise > 0) lines.add(('Price rise at ${num1(k.priceRise)}% a year', p.cost * k.priceRise / 100 * months / 12));
  return lines.isEmpty ? null : WaitCost(months, lines);
}

double _pathAt(List<double> l, int i) => l.isEmpty ? 0 : l[math.min(math.max(i, 0), l.length - 1)];

class Assessment {
  final String verdict; // ready | onTrack | later | rethink
  final String headline, summary;
  final bool small, loan;
  final double surplus, upfront, efTarget, efHave, emi, running, afterSurplus, principal, pace;
  final double earmarked; // money set aside for this project
  final double cardDebt;
  final int efMonths, monthsLeft, term;
  final int? readyIn; // months from now until it can be bought, null if not within 30 years
  final int? efReadyIn; // months until the safety cushion is full, null if never
  final int? cardReadyIn; // months until the credit card is clear
  final int projStart; // month when saving for the project begins (after card and cushion)
  final double potStart; // already held toward the upfront amount today
  final List<double> cardPath, efPath, potPath; // balances by month on the fastest path
  final double rentSaved; // rent that stops after buying (homes)
  final int? buyIn; // planned month to buy: the target when paced, otherwise as soon as it's ready
  final bool paced; // saving just enough to hit the target date (not every spare dirham)
  final int startsAt; // month its turn starts in a plan with other projects (0 = saving now)
  final String? after; // projects it waits for, in a plan with other projects
  final Sched? share; // its share of the plan when planned with other projects
  final WaitCost? wait; // when it's later than wanted: what the delay costs
  final List<Check> checks; // regret check, when it's ready or on track
  final double? dbr; // loan repayments as % of take-home after buying
  final String targetLabel, readyLabel;
  final List<PlanStep> steps;
  final List<String> options; // ways to make it work; may contain **bold** lead-ins
  final List<String> watchouts;
  const Assessment({
    required this.verdict,
    required this.headline,
    required this.summary,
    required this.small,
    required this.loan,
    required this.surplus,
    required this.upfront,
    required this.efTarget,
    required this.efHave,
    required this.emi,
    required this.running,
    required this.afterSurplus,
    required this.principal,
    required this.pace,
    required this.earmarked,
    required this.cardDebt,
    required this.efMonths,
    required this.monthsLeft,
    required this.term,
    required this.readyIn,
    required this.efReadyIn,
    required this.cardReadyIn,
    required this.projStart,
    required this.potStart,
    required this.cardPath,
    required this.efPath,
    required this.potPath,
    required this.rentSaved,
    required this.buyIn,
    required this.paced,
    required this.startsAt,
    required this.after,
    required this.share,
    required this.wait,
    required this.checks,
    required this.dbr,
    required this.targetLabel,
    required this.readyLabel,
    required this.steps,
    required this.options,
    required this.watchouts,
  });
}

class _Sim {
  int? cardDone, efDone, readyIn;
  double pot = 0;
  // Month-by-month balances (index 0 = today), kept for the first 20 years. Used for payday reminders.
  final List<double> cardPath = [], efPath = [], potPath = [];
  void record(double card, double ef, double pot) {
    if (cardPath.length > 240) return;
    cardPath.add(card);
    efPath.add(ef);
    potPath.add(pot);
  }
}

/// Month-by-month: spare money goes to the card, then the cushion (unless skipped), then the project.
/// The project is ready once the card is clear, the cushion is full and the upfront amount is saved.
_Sim _simulate({
  required double surplus,
  required double card,
  required double ef,
  required double efTarget,
  required bool skipEf,
  required double pot,
  required double upfront,
  required int horizon,
}) {
  final s = _Sim();
  bool cardClear() => card <= 0.5;
  bool efFull() => skipEf || ef >= efTarget - 0.5;
  bool ready() => cardClear() && efFull() && pot >= upfront - 0.5;
  if (cardClear()) s.cardDone = 0;
  if (efFull()) s.efDone = 0;
  s.record(card, ef, pot);
  if (ready()) {
    s.readyIn = 0;
    s.pot = pot;
    return s;
  }
  for (var m = 1; m <= horizon; m++) {
    var avail = surplus;
    if (!cardClear()) {
      card += card * cardMonthlyRate;
      final pay = math.min(avail, card);
      card -= pay;
      avail -= pay;
      if (cardClear()) s.cardDone ??= m;
    }
    if (avail > 0 && cardClear() && !efFull()) {
      final put = math.min(avail, efTarget - ef);
      ef += put;
      avail -= put;
      if (efFull()) s.efDone ??= m;
    }
    if (avail > 0 && cardClear() && efFull() && pot < upfront) {
      pot += math.min(avail, upfront - pot);
    }
    s.record(math.max(card, 0.0), ef, pot);
    if (ready()) {
      s.readyIn = m;
      break;
    }
  }
  s.pot = pot;
  return s;
}

/// [sh]: when the project is planned together with others, its share of that plan (see plan.dart).
/// Dates, monthly amounts and the cushion then come from the shared plan instead of this project alone.
/// [othersLate]: other projects in the plan that miss their dates and come no earlier than this one.
/// [explore]: look for a price or down payment that passes every check (off for those look-ups themselves).
Assessment assess(Money money0, Project p, {required String today, Sched? sh, List<String> othersLate = const [], bool explore = true}) {
  final k = kindOf(p.type);
  final income = money0.income ?? 0;
  // In a plan, a waiting project counts the costs of the projects bought before it as essentials.
  final double exSpend = sh == null ? 0 : (sh.waiting ? sh.extraSpendAtBuy : sh.extraSpendAtStart);
  final double exRepay = sh == null ? 0 : (sh.waiting ? sh.extraRepayAtBuy : sh.extraRepayAtStart);
  final spend = (money0.spending ?? 0) + exSpend, rep = (money0.repayments ?? 0) + exRepay;
  final card = (sh != null && sh.startsAt > 0) ? 0.0 : (money0.cardDebt ?? 0); // cleared before a later turn starts
  final savings = money0.savings ?? 0, inv = money0.investments ?? 0;
  final essentials = spend + rep;
  final surplus = income - essentials;
  final efMonths = (money0.family == true ? 6 : 3) + (money0.variable == true ? 3 : 0);
  final efTarget = essentials * efMonths;
  final monthsLeft = math.max(1, monthsUntil(today, p.target));
  final now = monthKey(today);
  String at(int months) => months <= 0 ? 'now' : monthLabel(addMonths(now, months));
  final targetLabel = monthLabel(p.target);

  final loan = k.canFinance && p.pay == 'loan';
  final down = loan ? math.max(p.downPct, k.minDown) : 100.0;
  final term = loan ? math.max(6, math.min(p.term, k.maxTerm)) : 0;
  final upfront = p.cost * (down + k.fees) / 100;
  final principal = loan ? p.cost * (1 - down / 100) : 0.0;
  final emi = loan ? instalment(principal, p.rate, term) : 0.0;
  final running = p.cost * k.runPctYear / 100 / 12;
  final rentSaved = p.type == 'home' ? (p.rent ?? 0) : 0.0;
  final small = !loan && p.cost <= income * smallPurchaseMonths;

  // Existing savings: pay the card down now (keeping one month's essentials), then the cushion, then the project.
  var cash = savings;
  final payCardNow = card > 0 ? math.min(card, math.max(0.0, cash - essentials)) : 0.0;
  cash -= payCardNow;
  final cardLeft = card - payCardNow;
  final efHave = sh != null ? math.min(sh.efAtStart, efTarget) : math.min(cash, efTarget);
  final spare = sh != null ? 0.0 : cash - efHave;
  // Money set aside for this project counts toward it first, then savings above the cushion.
  // In a plan, savings above the cushion were already shared out (nearest date first) and are in pot0.
  final earmarked = p.saved;
  final pot0 = sh != null ? math.min(upfront, sh.pot0) : math.min(upfront, earmarked + spare);
  final fromSpare = math.max(0.0, pot0 - math.min(earmarked, upfront));

  int? readyIn, cardDone, efDone, efReadyIn;
  List<double> cardPath, efPath, potPath;
  double potByTarget; // what it can have by its target date
  int projStart; // month money starts going to it
  if (sh == null) {
    final sim = _simulate(surplus: surplus, card: cardLeft, ef: efHave, efTarget: efTarget, skipEf: small, pot: pot0, upfront: upfront, horizon: 360);
    final byTarget = _simulate(
        surplus: surplus, card: cardLeft, ef: efHave, efTarget: efTarget, skipEf: small, pot: earmarked + spare, upfront: double.infinity, horizon: monthsLeft);
    final efOnly = _simulate(surplus: surplus, card: cardLeft, ef: efHave, efTarget: efTarget, skipEf: false, pot: 0, upfront: 0, horizon: 360);
    readyIn = surplus > 0 || sim.readyIn == 0 ? sim.readyIn : null;
    cardDone = sim.cardDone;
    efDone = sim.efDone;
    efReadyIn = surplus > 0 || efOnly.efDone == 0 ? efOnly.efDone : null;
    cardPath = sim.cardPath;
    efPath = sim.efPath;
    potPath = sim.potPath;
    potByTarget = byTarget.pot;
    final int cardAt = sim.cardDone ?? 0, efAt = small ? 0 : (sim.efDone ?? 0);
    projStart = math.max(cardAt, efAt);
  } else {
    readyIn = sh.readyIn;
    cardDone = sh.cardDone;
    efDone = sh.efDone;
    efReadyIn = sh.efDone;
    cardPath = sh.cardPath;
    efPath = sh.efPath;
    potPath = sh.potPath;
    potByTarget = sh.potAt(monthsLeft);
    projStart = sh.firstMoney;
  }
  final cardAtPurchase = (readyIn != null && cardDone != null && cardDone <= readyIn) ? 0.0 : cardLeft;
  // Loan repayments and spare money after buying count loans and costs of projects bought before it.
  final repAtBuy = (money0.repayments ?? 0) + (sh?.extraRepayAtBuy ?? 0);
  final spendAtBuy = (money0.spending ?? 0) + (sh?.extraSpendAtBuy ?? 0);
  final dbr = loan && income > 0 ? (repAtBuy + emi + cardAtPurchase * 0.05) / income * 100 : null;
  final afterSurplus = income - spendAtBuy - repAtBuy - emi - running + rentSaved;
  final int off = sh?.startsAt ?? 0;

  // Verdict
  String verdict, headline, summary;
  if (sh != null && sh.blocked) {
    verdict = 'rethink';
    headline = 'Waiting on the ${sh.after}';
    summary = 'This waits for the ${sh.after}, which can\'t be reached at your current savings rate. Save for this one now too, or plan it on its own.';
  } else if (income <= 0 || surplus <= 0) {
    verdict = 'rethink';
    headline = 'Not advisable right now';
    summary = 'Your spending and loan repayments (${money(essentials)}) use all of your take-home pay (${money(income)}), so there is nothing left to save from.';
  } else if (readyIn == null) {
    verdict = 'rethink';
    headline = 'Not advisable right now';
    summary = 'At ${money(surplus)} spare a month this would take more than 30 years.';
  } else if (dbr != null && dbr > 50) {
    verdict = 'rethink';
    headline = 'Not advisable right now';
    summary = 'The ${k.loanName} would take your loan repayments to ${dbr.toStringAsFixed(0)}% of your take-home pay. UAE banks cap this at 50%, so it is likely to be refused.';
  } else if (afterSurplus < 0) {
    verdict = 'rethink';
    headline = 'Not advisable right now';
    summary = 'After buying, the monthly costs would be ${money(-afterSurplus)} more than you have spare.';
  } else if (readyIn == 0) {
    verdict = 'ready';
    headline = 'You can afford this now';
    summary = loan
        ? 'You have the ${money(upfront)} ${k.fees > 0 ? 'down payment and fees' : 'down payment'} without touching your safety cushion, and the ${k.loanName} fits.'
        : 'You have ${money(upfront)} ${earmarked >= upfront ? 'set aside for it' : (earmarked > 0 ? 'between what you set aside and your savings' : 'available')}, without touching your safety cushion.';
  } else if (readyIn <= monthsLeft) {
    verdict = 'onTrack';
    headline = 'Yes, by $targetLabel';
    summary = 'Follow the plan below and you\'ll have the ${loan ? 'down payment' : 'money'} in time.';
  } else {
    verdict = 'later';
    headline = 'Possible by ${at(readyIn)}';
    final late = readyIn - monthsLeft;
    summary = 'That\'s ${durationLabel(late)} later than you wanted. Below are ways to keep your date.';
  }

  // Cost of waiting, when it's later than wanted
  final wait = verdict == 'later' ? waitCost(p, readyIn! - monthsLeft, loan: loan, principal: principal, running: running, rentSaved: rentSaved) : null;
  if (wait != null) summary += ' ${wait.sentence}';

  // Pace: on track means saving just enough to hit the target; otherwise everything spare.
  // In a plan with other projects, the plan sets the amounts.
  final paced = verdict == 'onTrack';
  double pace = surplus;
  if (sh != null) {
    pace = sh.mainAmount;
  } else if (paced && monthsLeft > projStart) {
    pace = math.min(surplus, roundUp((upfront - pot0) / (monthsLeft - projStart), 50));
  }

  // ---------- The plan, in order ----------
  final steps = <PlanStep>[];
  if (surplus <= 0) {
    steps.add(PlanStep(
        'Free up money each month first',
        'Until something is left over each month, there is nothing to save from. Start with your biggest costs: rent, car and loans. '
            'Even ${money(roundUp(income * 0.1, 100))} a month (10% of your pay) is enough to begin.'));
  } else {
    // 0. Projects it waits for, in a plan with others
    if (sh != null && !sh.blocked && sh.startsAt > 0) {
      final change = exSpend + exRepay;
      steps.add(PlanStep(
          'First: the ${sh.after}',
          'Your spare money goes to the ${sh.after} until ${at(off)}. '
              '${change > 0.5 ? 'By then, their costs take ${money(change)} a month, leaving ${money(surplus)} spare for this.' : change < -0.5 ? 'By then, the rent you stop paying frees ${money(-change)} a month, leaving ${money(surplus)} spare for this.' : 'Then all ${money(surplus)} spare goes to this.'}',
          when: 'Until ${at(off)}'));
    }

    // 1. Credit card
    if (card > 0) {
      final parts = <String>[
        if (payCardNow > 0) 'Use ${money(payCardNow)} of your savings to pay it down now, keeping one month of essentials in hand.',
        if (cardLeft > 0 && cardDone != null)
          '${payCardNow > 0 ? 'Then put' : 'Put'} your spare ${money(surplus)} a month toward ${payCardNow > 0 ? 'the rest' : 'it'} until it\'s clear in ${at(cardDone)}.',
        if (cardLeft > 0 && cardDone == null) 'Your spare money doesn\'t cover the interest, so it would keep growing. Cut spending first.',
        'Card interest is usually 30–40% a year, so clearing it beats any saving or investing.',
      ];
      steps.add(PlanStep('Pay off your credit card first', parts.join(' '),
          when: cardLeft > 0 && cardDone != null ? 'Until ${at(cardDone)}' : 'Now'));
    }

    // 2. Safety cushion
    final whyEf = 'That\'s $efMonths months of essentials (${money(essentials)} a month), because '
        '${money0.family == true ? 'others rely on your income' : 'only you rely on your income'} and '
        '${money0.variable == true ? 'it varies month to month' : 'your salary is fixed'}. In the UAE, losing your job also puts your visa on a clock.';
    if (small) {
      if (efHave < efTarget - 0.5) {
        steps.add(PlanStep(
            'Your safety cushion can wait for this one',
            'This costs less than a month of your pay, so it doesn\'t need to wait for a full cushion. '
                'Pay for it from your spare money each month and leave your savings alone. Then build the cushion to ${money(efTarget)}.'));
      }
    } else if (efHave >= efTarget - 0.5) {
      steps.add(PlanStep('Your safety cushion is in place', 'You have ${money(efTarget)} set aside. $whyEf Keep it separate and don\'t use it for this.', done: true));
    } else {
      steps.add(PlanStep(
          off > 0 ? 'Top up your safety cushion' : 'Build your safety cushion first',
          'Aim for ${money(efTarget)}. $whyEf You have ${money(efHave)} so far. '
              '${efDone != null ? 'Put your spare money toward it until ${at(efDone)}. ' : ''}Keep it in an instant-access savings account.',
          when: efDone != null ? 'Until ${at(efDone)}' : ''));
    }

    // 3. Save the upfront amount
    final what = loan ? (k.fees > 0 ? 'down payment and fees' : 'down payment') : k.noun;
    final sources = [
      if (earmarked > 0) '${money(math.min(earmarked, upfront))} you\'ve set aside for it',
      if (fromSpare > 0) '${money(fromSpare)} of savings above your safety cushion',
    ];
    if (pot0 >= upfront - 0.5) {
      steps.add(PlanStep(loan ? 'You already have the $what' : 'You already have the money', '${money(upfront)}: ${sources.join(' and ')}.', done: true));
    } else if (readyIn != null) {
      final within = monthsLeft <= 12 ? 'within a year' : 'within ${(monthsLeft / 12).ceil()} years';
      final b = StringBuffer();
      if (pot0 > 0) b.write('You have ${money(pot0)} toward it: ${sources.join(' and ')}. ');
      if (sh != null) {
        b.write(sh.amountsText(at));
        b.write(' and you\'ll have ${money(upfront)} by ${at(readyIn)}. ');
        if (sh.withNames.isNotEmpty) b.write('You\'re saving for the ${joinNames(sh.withNames)} at the same time. ');
      } else if (paced) {
        b.write('Put aside ${money(pace)} a month and you\'ll have ${money(upfront)} by $targetLabel');
        b.write(readyIn < monthsLeft ? ', or save all your spare ${money(surplus)} to get there by ${at(readyIn)}. ' : '. ');
      } else {
        b.write('Put aside your spare ${money(surplus)} a month and you\'ll have ${money(upfront)} by ${at(readyIn)}. ');
      }
      b.write(small ? 'Keep it separate from your savings.' : 'Keep it in a savings account or fixed deposit, not in shares: you need it $within.');
      steps.add(PlanStep('Save ${money(sh != null || paced ? pace : surplus)} a month for the $what', b.toString(),
          when: 'Until ${at(sh != null ? readyIn : (paced ? monthsLeft : readyIn))}'));
    }

    // 4. Buy
    final buyAt = readyIn == null ? null : (paced ? monthsLeft : readyIn);
    final buyWhen = buyAt == null ? '' : (buyAt == 0 ? 'Now' : at(buyAt));
    if (loan) {
      steps.add(PlanStep(
          'Take a ${durationLabel(term)} ${k.loanName} for ${money(principal)}',
          '${num1(down)}% down. At ${num1(p.rate)}% a year that\'s about ${money(emi)} a month, taking your loan repayments to '
              '${dbr!.toStringAsFixed(0)}% of your take-home pay. Banks cap this at 50%; under 35% is comfortable.',
          when: buyWhen));
    } else {
      steps.add(PlanStep(
          k.buyTitle,
          p.type == 'vacation'
              ? 'Pay from the money you\'ve saved, not on a card you can\'t clear or a buy-now-pay-later plan.'
              : 'Pay from the money you\'ve saved. Your safety cushion stays untouched.',
          when: buyWhen));
    }

    // 5. After buying
    final afterLine = afterSurplus >= 0
        ? 'After that you\'d have ${money(afterSurplus)} spare a month.'
        : 'That\'s ${money(-afterSurplus)} a month more than you have spare.';
    if (p.type == 'car') {
      steps.add(PlanStep('Budget ${money(running)} a month to run it', 'Fuel, insurance, servicing, registration and Salik. $afterLine'));
    } else if (p.type == 'home') {
      steps.add(PlanStep(
          'Your monthly costs change',
          '${loan ? 'Mortgage ${money(emi)} plus ' : ''}about ${money(running)} for service charges and upkeep'
              '${rentSaved > 0 ? ', instead of ${money(rentSaved)} rent' : ''}. $afterLine'));
    } else if (loan) {
      steps.add(PlanStep('Repay ${money(emi)} a month', afterLine));
    }
  }

  // ---------- Regret check: the month after buying ----------
  final checks = <Check>[];
  if ((verdict == 'ready' || verdict == 'onTrack') && (emi > 0 || running > 0 || rentSaved > 0 || sh != null)) {
    final buyMonth = sh?.buyIn ?? (paced ? monthsLeft : readyIn!);
    final newEss = spendAtBuy + repAtBuy + emi + running - rentSaved;
    final cover = newEss > 0 ? (_pathAt(efPath, buyMonth) / newEss * 10).floorToDouble() / 10 : 99.0;
    final coverOk = cover >= efMonths - 0.5;
    final costUp = emi + running - rentSaved;
    checks.add(Check(
        'Cushion still covers you',
        coverOk,
        coverOk
            ? 'It covers ${num1(math.min(cover, 99))} months at your new monthly costs.'
            : 'It would cover ${num1(cover)} months, not $efMonths${costUp > 0.5 ? ', because ${loan ? 'the ${k.loanName} and ' : ''}running costs add ${money(costUp)} a month' : ''}, until you top it up.'));
    final roomOk = afterSurplus >= income * 0.1;
    checks.add(Check('Room to breathe', roomOk,
        'Spare each month ${roomOk ? 'stays at' : 'drops to'} ${money(afterSurplus)} (${(afterSurplus / income * 100).floor()}% of your pay).'));
    if (dbr != null) {
      checks.add(Check('Loans comfortable', dbr <= 35,
          'Loan repayments ${dbr.toStringAsFixed(0)}% of your pay${dbr > 35 ? '. Banks allow 50%, but above 35% leaves little room if costs rise' : ''}.'));
    }
    if (sh != null) {
      checks.add(Check('Other plans hold', othersLate.isEmpty,
          othersLate.isEmpty ? 'Your other projects keep their dates.' : 'The ${joinNames(othersLate)} ${othersLate.length == 1 ? 'misses its' : 'miss their'} date.'));
    }
    if (checks.where((c) => !c.ok).length >= 2) {
      verdict = 'tight';
      headline = buyMonth <= 0 ? 'You can afford it now, but think twice' : 'You can buy it by ${at(buyMonth)}, but think twice';
      summary = 'The month after, you\'d be stretched.';
    }
  }

  // ---------- Ways to make it work ----------
  final options = <String>[];
  if (verdict == 'tight' && explore) {
    bool passes(Assessment x) => (x.verdict == 'ready' || x.verdict == 'onTrack') && x.checks.every((c) => c.ok);
    final step = p.cost >= 100000 ? 5000.0 : (p.cost >= 10000 ? 1000.0 : 100.0);
    for (var c = roundDown(p.cost * 0.95, step); c >= p.cost * 0.5; c -= step) {
      final x = assess(money0, p.copy()..cost = c, today: today, explore: false);
      if (passes(x)) {
        options.add('**A ${k.noun} around ${money(c)} passes every check.** You\'d keep ${money(x.afterSurplus)} spare a month.');
        break;
      }
    }
    if (loan) {
      for (var d = (down / 5).floor() * 5 + 5.0; d <= 50; d += 5) {
        final x = assess(money0, p.copy()..downPct = d, today: today, explore: false);
        if (x.verdict == 'ready' || x.verdict == 'onTrack') {
          options.add('**Put ${num1(d)}% down instead of ${num1(down)}%.** Spare each month goes up to ${money(x.afterSurplus)}${x.readyIn! > (readyIn ?? 0) ? ', ready ${x.readyLabel}' : ''}.');
          break;
        }
      }
    }
  }
  if (verdict == 'later' || verdict == 'rethink') {
    if (surplus <= 0) {
      options.add('**Cut a regular cost.** Moving somewhere cheaper, refinancing a loan or dropping a second car frees money every month.');
    }
    if (verdict == 'later') options.add('**Wait until ${at(readyIn!)}.** Saving all of your spare ${money(surplus)} a month gets you there then.');
    if (surplus > 0) {
      var maxCost = potByTarget / ((down + k.fees) / 100);
      if (loan) {
        final room = income * 0.35 - rep;
        maxCost = math.min(maxCost, room > 0 ? maxPrincipal(room, p.rate, term) / (1 - down / 100) : 0);
      }
      final step = p.cost >= 100000 ? 5000.0 : (p.cost >= 10000 ? 1000.0 : 100.0);
      if (maxCost >= p.cost * 0.2 && maxCost < p.cost) {
        options.add('**Aim for about ${money(roundDown(maxCost, step))} instead.** That fits your $targetLabel date.');
      }
      final shortfall = upfront - potByTarget;
      if (shortfall > 0 && verdict == 'later') {
        final extra = roundUp(shortfall / math.max(1, monthsLeft - off), 50);
        options.add('**Find ${money(extra)} more a month.** Together with what you already save, that gets you there by $targetLabel.'
            '${wait != null && !wait.saves && wait.perMonth > extra ? ' That\'s less than the ${money(roundUp(wait.perMonth, 50))} a month that waiting costs.' : ''}');
      }
      if (k.canFinance && !loan && k.minDown > 0) {
        final up2 = p.cost * (k.minDown + k.fees) / 100, emi2 = instalment(p.cost * (1 - k.minDown / 100), k.rate, k.term);
        final dbr2 = (rep + emi2) / income * 100;
        if (up2 < upfront && dbr2 <= 35 && surplus - emi2 - running + rentSaved >= 0) {
          options.add('**Consider a ${k.loanName}.** With ${num1(k.minDown)}% down you\'d need ${money(up2)} upfront instead of ${money(upfront)}, '
              'and pay about ${money(emi2)} a month (${dbr2.toStringAsFixed(0)}% of your pay).');
        }
      }
      if (loan && dbr != null && dbr > 35) {
        if (term < k.maxTerm) {
          final emi3 = instalment(principal, p.rate, k.maxTerm);
          options.add('**Stretch the loan to ${durationLabel(k.maxTerm)}.** The instalment drops to ${money(emi3)}, but you pay more interest overall.');
        }
        final pMax = maxPrincipal(income * 0.35 - rep, p.rate, term);
        final downNeeded = (1 - pMax / p.cost) * 100;
        if (pMax > 0 && downNeeded > down && downNeeded < 90) {
          options.add('**Put down ${roundUp(downNeeded, 5).toStringAsFixed(0)}% instead of ${num1(down)}%.** That keeps repayments under 35% of your pay.');
        }
      }
      if (inv > 0 && (shortfall > 0 || verdict == 'rethink') && !loan) {
        final use = math.min(inv, math.max(shortfall, 0.0));
        if (use > 0) {
          options.add('**Use part of your investments.** Selling ${money(use)} ${use >= shortfall ? 'closes the gap' : 'narrows the gap'}, but that money stops growing.');
        }
      }
      if (!small && efTarget > 0 && efHave < efTarget && efMonths > 3) {
        options.add('**Start this once you have 3 months of essentials saved**, then finish the cushion afterwards. Riskier, but sooner.');
      }
    }
    if (p.type == 'vacation') options.add('**Go shorter or off-peak.** Flights and hotels outside school holidays often cost a third less.');
    if (p.type == 'build') options.add('**Build in stages.** Land and foundations first, then structure, then finishing. Each stage becomes a smaller, nearer goal.');
    if (p.type == 'wedding') options.add('**Trim the guest list or venue.** These two usually make up most of the cost.');
    if (p.type == 'business') options.add('**Start smaller.** A flexi-desk licence and selling online first can cut the starting cost a lot.');
    if (p.type == 'renovation') options.add('**Do it room by room.** Each room becomes a smaller, nearer goal.');
    if (p.type == 'gadget') options.add('**Look at last year\'s model or certified refurbished.** Often a third cheaper.');
  }

  // ---------- Good to know ----------
  final watch = <String>[];
  if (checks.isEmpty && dbr != null && dbr > 35 && dbr <= 50) {
    watch.add('Loan repayments would reach ${dbr.toStringAsFixed(0)}% of your pay. Banks allow up to 50%, but above 35% leaves little room if costs rise.');
  }
  if (checks.isEmpty && afterSurplus >= 0 && afterSurplus < income * 0.1 && (emi > 0 || running > 0)) {
    watch.add('After buying you\'d have only ${money(afterSurplus)} spare a month.');
  }
  if (small) watch.add('Counted as a small purchase because it costs less than one month of your take-home pay.');
  switch (p.type) {
    case 'car':
      watch.add('A new car loses around 15–20% of its value a year. Treat it as spending, not as savings.');
      if (loan) watch.add('UAE car loans need at least 20% down and usually run up to 48 months; some banks offer 5 years.');
      if (loan && p.rate == 0) watch.add('0% deals are usually paid for in the car\'s price. Ask the cash price too and compare.');
      if (loan && term > 48) watch.add('Over 5 years you\'ll still be paying while the car is worth far less than you owe.');
    case 'home':
      watch.add('Expat mortgages usually need at least 20% down. Transfer and agent fees add about 6% on top.');
    case 'vacation':
      watch.add('Avoid buy-now-pay-later and cards you can\'t clear: interest can add 30% or more.');
    case 'build':
      watch.add('Building is paid in stages, so you may not need the full amount on day one. Ask the contractor for the payment schedule.');
    case 'education':
      watch.add('Fees usually rise every year. Add 5% a year if the course is more than a year away.');
    case 'renovation':
      watch.add('Renovations usually run over. Keep about 10% on top of the quote, and pay in stages as work is done.');
      watch.add('Renting? Check with your landlord first: changes may need approval and stay with the property.');
    case 'hajj':
      watch.add('Book only with licensed operators, and check the season\'s registration dates early.');
    case 'business':
      watch.add('Most new businesses take a year or more to pay you. Keep your safety cushion separate from the business money.');
      watch.add('Free-zone and mainland licences differ a lot in cost. Compare a few before you commit.');
    case 'baby':
      watch.add('Check what your health insurance covers for maternity before choosing a hospital.');
      watch.add('Your monthly costs will rise once the baby arrives. Update your spending after, so your other plans stay realistic.');
    case 'gold':
      watch.add('Gold prices move, and you lose the making charges when you sell. Count it as a long-term holding, not as your safety cushion.');
    case 'gadget':
      watch.add('Instalment plans often look free but add fees. Paying from savings keeps it simple.');
  }

  return Assessment(
    verdict: verdict,
    headline: headline,
    summary: summary,
    small: small,
    loan: loan,
    surplus: surplus,
    upfront: upfront,
    efTarget: efTarget,
    efHave: efHave,
    emi: emi,
    running: running,
    afterSurplus: afterSurplus,
    principal: principal,
    pace: pace,
    earmarked: earmarked,
    cardDebt: card,
    efMonths: efMonths,
    monthsLeft: monthsLeft,
    term: term,
    readyIn: readyIn,
    efReadyIn: efReadyIn,
    cardReadyIn: cardDone,
    projStart: projStart,
    potStart: pot0,
    cardPath: cardPath,
    efPath: efPath,
    potPath: potPath,
    rentSaved: rentSaved,
    buyIn: sh != null ? sh.buyIn : (readyIn == null ? null : (paced ? monthsLeft : readyIn)),
    paced: paced,
    startsAt: off,
    after: sh?.after,
    share: sh,
    wait: wait,
    checks: checks,
    dbr: dbr,
    targetLabel: targetLabel,
    readyLabel: readyIn == null ? 'Not within 30 years' : (readyIn == 0 ? 'Now' : at(readyIn)),
    steps: steps,
    options: options,
    watchouts: watch,
  );
}

/// 'A', 'A and B', 'A, B and C'.
String joinNames(List<String> names) =>
    names.length <= 1 ? names.join() : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

/// Every project's plan. Projects planned together share one plan (see plan.dart); the rest are planned on their own.
Map<int, Assessment> assessAll(AppData d, {required String today}) {
  final together = d.plannedProjects();
  final plan = together.isEmpty ? null : planAll(d.money, together, today: today, pinned: d.pinned.toSet());
  if (plan == null) return {for (final p in d.projects) p.id: assess(d.money, p, today: today)};
  bool isLate(Project p) {
    final s = plan[p.id]!;
    return s.readyIn == null || s.readyIn! > math.max(1, monthsUntil(today, p.target));
  }

  return {
    for (final p in d.projects)
      p.id: plan[p.id] == null
          ? assess(d.money, p, today: today)
          : assess(d.money, p, today: today, sh: plan[p.id], othersLate: [
              for (final o in together)
                if (o.id != p.id && plan[p.id]!.turn <= plan[o.id]!.turn && isLate(o)) o.name,
            ]),
  };
}

/// The plan for one project as the app shows it.
Assessment assessIn(AppData d, Project p, {required String today}) => assessAll(d, today: today)[p.id]!;
