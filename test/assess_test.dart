// Scenario tests for the decision engine. Each one is a real situation the plan must get right.
import 'dart:math' as math;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_buddy/domain/assess.dart';
import 'package:wealth_buddy/domain/backup.dart';
import 'package:wealth_buddy/domain/checkin.dart';
import 'package:wealth_buddy/domain/format.dart';
import 'package:wealth_buddy/domain/history.dart';
import 'package:wealth_buddy/domain/impact.dart';
import 'package:wealth_buddy/domain/models.dart';
import 'package:wealth_buddy/domain/reminders.dart';
import 'package:wealth_buddy/domain/whatif.dart';

const today = '2026-10-01';
String inMonths(int n) => addMonths(monthKey(today), n);

Money salaried({double income = 20000, double spending = 12000, double savings = 5000, double repayments = 0, double card = 0, bool family = false, bool variable = false, double? investments}) =>
    Money(income: income, spending: spending, savings: savings, repayments: repayments, cardDebt: card, family: family, variable: variable, investments: investments);

Project project(String type, double cost, int months, {String pay = 'savings', double down = 20, double rate = 3.5, int term = 48, double? rent}) =>
    Project(id: 1, type: type, name: type == 'car' && cost == 120000 ? 'Family SUV' : type, cost: cost, target: inMonths(months), pay: pay, downPct: down, rate: rate, term: term, rent: rent);

List<String> titles(Assessment a) => a.steps.map((s) => s.title).toList();

void main() {
  test('no safety cushion: build it before saving for a car', () {
    final a = assess(salaried(), project('car', 60000, 24), today: today);
    expect(a.verdict, 'onTrack');
    expect(titles(a).first, 'Build your safety cushion first');
    expect(titles(a).indexOf('Build your safety cushion first') < titles(a).indexWhere((t) => t.startsWith('Save ')), isTrue);
    expect(a.efTarget, 36000); // 3 months of essentials: single, fixed salary
    expect(a.readyIn, 12); // cushion full in month 4, then 60,000 saved by month 12
    expect(a.pace, 3000); // 60,000 over the 20 months left after the cushion
  });

  test('small purchase skips the cushion rule but leaves savings alone', () {
    final a = assess(salaried(), project('vacation', 6000, 6), today: today);
    expect(a.small, isTrue);
    expect(titles(a), contains('Your safety cushion can wait for this one'));
    expect(titles(a), isNot(contains('Build your safety cushion first')));
    expect(a.readyIn, 1);
    expect(a.verdict, 'onTrack');
  });

  test('a loan is never a small purchase', () {
    final a = assess(salaried(), project('other', 10000, 6, pay: 'loan', rate: 7, term: 24), today: today);
    expect(a.small, isFalse);
  });

  test('credit card debt comes first, paid partly from savings', () {
    final a = assess(salaried(savings: 15000, card: 10000), project('car', 60000, 24), today: today);
    expect(titles(a).first, 'Pay off your credit card first');
    expect(a.steps.first.body, contains('AED 3,000 of your savings')); // keeps one month (12,000) in hand
  });

  test('loan above the 50% repayment cap is not advisable', () {
    final a = assess(salaried(income: 15000, spending: 9000, repayments: 4000, savings: 100000), project('car', 200000, 6, pay: 'loan'), today: today);
    expect(a.dbr, greaterThan(50));
    expect(a.verdict, 'rethink');
    expect(a.options.any((o) => o.contains('instead of 20%') || o.contains('Aim for')), isTrue);
  });

  test('spending uses all the pay', () {
    final a = assess(salaried(income: 10000, spending: 10000), project('car', 40000, 12), today: today);
    expect(a.verdict, 'rethink');
    expect(titles(a).first, 'Free up money each month first');
  });

  test('enough savings above the cushion: ready now', () {
    final a = assess(salaried(income: 30000, spending: 15000, savings: 200000, family: true), project('car', 80000, 12), today: today);
    expect(a.efTarget, 90000); // 6 months: family relies on this income
    expect(a.verdict, 'ready');
    expect(a.readyIn, 0);
    expect(a.steps.first.done, isTrue);
  });

  test('home: the rent you stop paying offsets the mortgage', () {
    final a = assess(salaried(income: 40000, spending: 20000, savings: 400000),
        project('home', 1500000, 12, pay: 'loan', down: 20, rate: 4.5, term: 300, rent: 8000), today: today);
    expect(a.upfront, closeTo(390000, 0.01)); // 20% down + 6% fees
    expect(a.readyIn, 3);
    expect(a.verdict, 'onTrack');
    expect(a.afterSurplus, closeTo(a.surplus - a.emi - a.running + 8000, 0.01));
    expect(a.emi, closeTo(6670, 1));
  });

  test('too soon: says when it is possible and how to keep the date', () {
    final a = assess(salaried(), project('car', 120000, 12), today: today);
    expect(a.verdict, 'later');
    expect(a.readyIn, 19);
    expect(a.options.first, contains('Wait until'));
    expect(a.options.any((o) => o.contains('Aim for about')), isTrue);
  });

  test('variable income with family: 9-month cushion', () {
    final a = assess(salaried(family: true, variable: true), project('car', 60000, 24), today: today);
    expect(a.efMonths, 9);
  });

  group('money set aside', () {
    Project suv([List<Contribution> c = const []]) => project('car', 120000, 12)..contributions = [...c];

    test('set aside at the start brings the date forward', () {
      expect(assess(salaried(), suv(), today: today).readyIn, 19);
      final a = assess(salaried(), suv([const Contribution(amount: 10000, source: 'Set aside at start', date: today)]), today: today);
      expect(a.earmarked, 10000);
      expect(a.readyIn, 18); // Apr 2028, as in the mockup
    });

    test('a bonus to the project: 3 months sooner', () {
      final d = AppData(money: salaried(), projects: [suv([const Contribution(amount: 10000, source: 'Set aside at start', date: today)])]);
      d.addMoney(1, 25000, 'Bonus', 'project', today);
      final a = assess(d.money, d.projects.first, today: today);
      expect(a.earmarked, 35000);
      expect(a.readyIn, 15); // Jan 2028
    });

    test('the same bonus to the cushion: same date, cushion full sooner', () {
      final d = AppData(money: salaried(), projects: [suv([const Contribution(amount: 10000, source: 'Set aside at start', date: today)])]);
      final before = assess(d.money, d.projects.first, today: today);
      d.addMoney(1, 25000, 'Bonus', 'cushion', today);
      final a = assess(d.money, d.projects.first, today: today);
      expect(d.money.savings, 30000);
      expect(a.readyIn, 15);
      expect(before.efReadyIn, 4);
      expect(a.efReadyIn, 1);
      expect(d.projects.first.saved, 10000); // cushion money isn't counted in the pot
    });

    test('paying the card: extra beyond the balance goes to the project', () {
      final d = AppData(money: salaried(card: 4000), projects: [suv()]);
      d.addMoney(1, 10000, 'Gift', 'card', today);
      expect(d.money.cardDebt, 0);
      expect(d.projects.first.saved, 6000);
    });

    test('set aside still waits for the safety cushion', () {
      final a = assess(salaried(), project('car', 60000, 24)..contributions = [const Contribution(amount: 60000, source: 'Set aside at start', date: today)], today: today);
      expect(a.readyIn, 4); // the money is there, but the cushion fills in month 4
      expect(titles(a).first, 'Build your safety cushion first');
    });

    test('saved money survives a save and reload', () {
      final d = AppData(money: salaried(), projects: [suv([const Contribution(amount: 10000, source: 'Bonus', date: today)])]);
      expect(AppData.fromJson(d.toJson()).projects.first.saved, 10000);
    });
  });

  group('payday reminders', () {
    AppData data(Money m, List<Project> ps) => AppData(money: m..payday = 25, projects: ps);
    Project suv() => project('car', 120000, 12)..contributions = [const Contribution(amount: 10000, source: 'Set aside at start', date: today)];

    test('no payday, no reminders', () {
      expect(paydayReminders(AppData(money: salaried(), projects: [suv()]), today: today), isEmpty);
      expect(paydayReminders(AppData(money: salaried()..payday = 0, projects: [suv()]), today: today), isEmpty);
    });

    test('cushion first, then saving for the project', () {
      final r = paydayReminders(data(salaried(), [suv()]), today: today, count: 6);
      expect(r.first.date, '2026-10-25');
      expect(r.first.title, 'Payday: build your safety cushion');
      expect(r.first.body, contains('AED 8,000'));
      expect(r.first.body, contains('36% full')); // 13,000 of 36,000
      expect(r[3].body, contains('That completes it'));
      expect(r[4].title, 'Payday: Family SUV');
      expect(r[4].body, contains('15%')); // 19,000 of 120,000 by month 5, rounded down
    });

    test('credit card comes first', () {
      final r = paydayReminders(data(salaried(card: 10000), [suv()]), today: today);
      expect(r.first.title, 'Payday: clear your credit card');
      expect(r.first.body, contains('left after this'));
    });

    test('goal reached', () {
      final car = project('car', 60000, 24)..contributions = [const Contribution(amount: 60000, source: 'Bonus', date: today)];
      final r = paydayReminders(data(salaried(savings: 100000), [car]), today: today);
      expect(r.first.title, 'You can afford the car');
    });

    test('payday 31 falls on the last day of shorter months', () {
      final r = paydayReminders(AppData(money: salaried()..payday = 31, projects: [suv()]), today: today, count: 2);
      expect(r.map((x) => x.date), ['2026-10-31', '2026-11-30']);
    });
  });

  test('questions adapt to the project', () {
    expect(projectQuestions(project('car', 1, 1), isNew: true), [Q.cost, Q.when, Q.pay, Q.setAside]);
    expect(projectQuestions(project('car', 1, 1, pay: 'loan')), [Q.cost, Q.when, Q.pay, Q.loan]);
    expect(projectQuestions(project('car', 1, 1)), [Q.cost, Q.when, Q.pay]);
    expect(projectQuestions(project('home', 1, 1)), [Q.cost, Q.when, Q.pay, Q.rent]);
    expect(projectQuestions(project('vacation', 1, 1)), [Q.cost, Q.when]);
  });

  group('several projects', () {
    // AED 8,000 spare a month, 5,000 savings. A vacation in 12 months, an SUV in 24,
    // and a 900,000 home in 60 (20% down, 6% fees, 6,000 rent today).
    Project vacation() => project('vacation', 15000, 12)..id = 1;
    Project suv() => project('car', 120000, 24)..id = 2;
    Project home() => project('home', 900000, 60, pay: 'loan', rate: 4.5, term: 300, rent: 6000)..id = 3;
    AppData three() => AppData(money: salaried(), projects: [home(), suv(), vacation()]);
    bool onTime(Assessment a) => a.readyIn != null && a.readyIn! <= a.monthsLeft;

    test('vacation and SUV save together; the home waits, and everything makes its date', () {
      final all = assessAll(three(), today: today);
      final v = all[1]!, c = all[2]!, h = all[3]!;
      expect(v.share!.turn, 0);
      expect(c.share!.turn, 0);
      expect(h.share!.turn, 1);
      expect(h.share!.startsAt, math.max(v.readyIn!, c.readyIn!));
      expect(onTime(v) && onTime(c) && onTime(h), isTrue);
      expect(c.share!.withNames, ['vacation']);
      expect(c.pace, inInclusiveRange(5500, 6500)); // what the SUV needs to make its date
      expect(titles(h).first, 'First: the vacation and Family SUV');
      expect(titles(h), contains('Top up your safety cushion')); // the SUV's running costs raise the cushion target
      expect(h.surplus, 6800); // 8,000 minus 1,200 a month to run the SUV
    });

    test('saving for everything at once wouldn\'t fit', () {
      final d = three();
      final plan = planAll(d.money, d.projects, today: today);
      expect(plan.needAll, greaterThan(8000));
      expect(plan.anyWaiting, isTrue);
    });

    test('everything fits: all save at once', () {
      final d = AppData(money: salaried(income: 40000), projects: [home(), suv(), vacation()]);
      final all = assessAll(d, today: today);
      expect(all.values.every((a) => a.share!.turn == 0), isTrue);
      expect(all.values.every(onTime), isTrue);
    });

    test('saving for the home now too makes the SUV wait', () {
      final d = three()..setPinned(3, true);
      final all = assessAll(d, today: today);
      expect(all[3]!.share!.turn, 0);
      expect(all[2]!.share!.waiting, isTrue);
      expect(onTime(all[2]!), isFalse);
    });

    test('a project after one that can\'t be reached waits for it', () {
      final d = AppData(money: salaried(), projects: [project('car', 9000000, 12)..id = 1, home()]);
      final h = assessAll(d, today: today)[3]!;
      expect(h.verdict, 'rethink');
      expect(h.headline, startsWith('Waiting on'));
    });

    test('planned on its own, and saved choices', () {
      final d = three()..setSolo(3, true);
      expect(assessAll(d, today: today)[3]!.share, isNull);
      expect(assessAll(d, today: today)[2]!.share, isNotNull);
      d.setPinned(2, true);
      final back = AppData.fromJson(d.toJson());
      expect(back.solo, [3]);
      expect(back.pinned, [2]);
      d.removeProject(2);
      expect(d.pinned, isEmpty);
      expect(d.plannedProjects(), isEmpty); // one project alone isn't a shared plan
    });

    test('payday reminder splits the money', () {
      final d = three()..money.payday = 25;
      final r = paydayReminders(d, today: today, count: 6);
      final split = r.firstWhere((x) => x.title == 'Payday: put money aside' && !x.body.contains('cushion'));
      expect(split.body, contains('for the vacation'));
      expect(split.body, contains('for the Family SUV'));
    });
  });

  group('cost of waiting and regret check', () {
    test('a late home: rent still paid and prices rising, minus owning costs', () {
      final a = assess(salaried(), project('home', 900000, 24, pay: 'loan', rate: 4.5, term: 300, rent: 6000), today: today);
      expect(a.verdict, 'later');
      expect(a.wait!.perMonth, closeTo(6000 - (2700 + 1125) + 2250, 1)); // rent - (interest + upkeep) + 3% a year on 900,000
      expect(a.summary, contains('Waiting costs about'));
    });

    test('waiting on a car saves money', () {
      final a = assess(salaried(), project('car', 120000, 12), today: today);
      expect(a.verdict, 'later');
      expect(a.wait!.saves, isTrue);
      expect(a.summary, contains('isn\'t costing you money'));
    });

    test('an SUV on a loan that leaves you stretched: yes, but tight', () {
      final a = assess(salaried(spending: 15000), project('car', 150000, 24, pay: 'loan'), today: today);
      expect(a.verdict, 'tight');
      expect(a.checks.where((c) => !c.ok).map((c) => c.label), containsAll(['Cushion still covers you', 'Room to breathe']));
      expect(a.checks.firstWhere((c) => c.label == 'Loans comfortable').ok, isTrue);
      expect(a.options.any((o) => o.contains('AED 105,000 passes every check')), isTrue);
      expect(a.paced, isTrue); // still saves to its date
    });

    test('one warning keeps the verdict', () {
      final a = assess(salaried(spending: 8000, repayments: 6000), project('car', 60000, 24, pay: 'loan'), today: today);
      expect(a.verdict, 'onTrack');
      expect(a.checks.where((c) => !c.ok).map((c) => c.label), ['Loans comfortable']);
    });
  });

  group('what if', () {
    AppData lateHome() => AppData(money: salaried(), projects: [project('home', 900000, 24, pay: 'loan', rate: 4.5, term: 300, rent: 6000)]);

    test('more pay and less spending put the home on time, without saving anything', () {
      final d = lateHome();
      expect(assessAll(d, today: today)[1]!.readyIn, 34);
      final a = whatIf(d, today: today, income: 22000, spending: 11000)[1]!;
      expect(a.readyIn, 24);
      expect(a.verdict, 'onTrack');
      expect(readyChange(assessAll(d, today: today)[1]!, a), '10 months sooner');
      expect(d.money.income, 20000); // untouched
      expect(d.money.spending, 12000);
    });

    test('smallest fix: spending less counts for more than earning more', () {
      final f = smallestFix(lateHome(), today: today);
      expect(f.spendCut, 2750); // also shrinks the cushion needed first
      expect(f.payRise, 3050);
    });

    test('nothing to fix when everything is on time', () {
      final f = smallestFix(AppData(money: salaried(), projects: [project('car', 60000, 24)]), today: today);
      expect(f.spendCut, isNull);
      expect(f.payRise, isNull);
    });

    test('in a shared plan, moving one date moves the others', () {
      final d = AppData(money: salaried(), projects: [
        project('vacation', 15000, 12)..id = 1,
        project('car', 120000, 24)..id = 2,
        project('home', 900000, 60, pay: 'loan', rate: 4.5, term: 300, rent: 6000)..id = 3,
      ]);
      final before = assessAll(d, today: today);
      final after = whatIf(d, today: today, targets: {2: inMonths(72)}); // the SUV can wait until after the home
      expect(after[3]!.readyIn! < before[3]!.readyIn!, isTrue); // so the home comes sooner
    });
  });

  group('what it costs the others', () {
    AppData three() => AppData(money: salaried(), projects: [
          project('vacation', 15000, 12)..id = 1,
          project('car', 120000, 24)..id = 2,
          project('home', 900000, 60, pay: 'loan', rate: 4.5, term: 300, rent: 6000)..id = 3,
        ]);
    Project wedding() => project('wedding', 80000, 18)..id = 4;
    bool onTime(Assessment a) => a.readyIn != null && a.readyIn! <= a.monthsLeft;

    test('adding a wedding pushes the others back, and says why', () {
      final d = three();
      final im = impactOf(d, d.money, wedding(), today: today);
      expect(im.anyMoves, isTrue);
      expect(im.others.any((o) => o.later), isTrue);
      expect(im.others.any((o) => o.nowMisses), isTrue);
      expect(im.why, contains('to wait'));
    });

    test('the suggested date keeps everyone on time', () {
      final d = three();
      final t = harmlessTarget(d, d.money, wedding(), today: today);
      expect(t, isNotNull);
      expect(t!.compareTo(wedding().target), greaterThan(0));
      final all = assessAll(d.copy()..projects.add(wedding()..target = t), today: today);
      expect(all.values.every(onTime), isTrue);
    });

    test('a project paid for already moves nothing', () {
      final d = three();
      final phone = project('gadget', 3000, 6)
        ..id = 4
        ..contributions = [const Contribution(amount: 3000, source: 'Set aside at start', date: today)];
      final im = impactOf(d, d.money, phone, today: today);
      expect(im.anyMoves, isFalse);
      expect(im.why, isEmpty);
    });

    test('editing a project shows the effect on the others', () {
      final d = three();
      final pricier = d.projects.firstWhere((p) => p.id == 2).copy()..cost = 200000;
      final im = impactOf(d, d.money, pricier, today: today);
      expect(im.others.map((o) => o.p.id), [1, 3]);
      expect(im.others.firstWhere((o) => o.p.id == 3).later, isTrue); // the home waits longer for the SUV
    });
  });

  group('price staleness', () {
    Staleness? check(Project p, {Money? m}) => staleness(p, assess(m ?? salaried(), p, today: today), today: today);

    test('a car priced 7 months ago is due a check', () {
      final st = check(project('car', 60000, 24)..priceDate = '2026-03-01');
      expect(st, isNotNull);
      expect(st!.price, isTrue);
      expect(st.months, 7);
      expect(st.chip, 'Price checked 7 months ago');
    });

    test('education fees hold for a year', () {
      expect(check(project('education', 60000, 24)..priceDate = '2026-03-01'), isNull);
    });

    test('a loan rate goes stale after about 3 months', () {
      final st = check(project('car', 60000, 24, pay: 'loan')..priceDate = '2026-06-15');
      expect(st!.rate, isTrue);
      expect(st.price, isFalse);
    });

    test('close to buying, always ask for a fresh quote', () {
      final st = check(project('car', 60000, 2)..priceDate = '2026-09-10', m: salaried(savings: 200000));
      expect(st!.nearBuy, isTrue);
      expect(st.chip, 'Get a fresh quote before you buy');
    });

    test('"Still right" clears it', () {
      expect(check(project('car', 60000, 24)..priceDate = today), isNull);
    });

    test('old data without a price date loads without flags', () {
      final p = Project.fromJson({'id': 1, 'type': 'car', 'name': 'Car', 'cost': 60000, 'target': inMonths(24)});
      expect(p.priceDate, isNull);
      expect(check(p), isNull);
      expect(Project.fromJson((p..priceDate = '2026-03-01').toJson()).priceDate, '2026-03-01');
    });
  });

  group('plan history', () {
    AppData lateHome() => AppData(money: salaried(), projects: [project('home', 900000, 24, pay: 'loan', rate: 4.5, term: 300, rent: 6000)]);

    test('the first point, and nothing new while the date holds', () {
      final d = lateHome();
      recordHistory(d, today: today, why: 'x');
      final h = d.projects.first.history;
      expect(h.length, 1);
      expect(h.first.why, 'Started');
      expect(h.first.ready, '2029-08'); // 34 months from Oct 2026
      recordHistory(d, today: today, why: 'Nothing changed');
      expect(h.length, 1);
      expect(sinceStart(d.projects.first), isNull);
    });

    test('a bonus moves it sooner, with its reason', () {
      final d = lateHome();
      recordHistory(d, today: today, why: 'x');
      d.addMoney(1, 50000, 'Bonus', 'project', today);
      recordHistory(d, today: today, why: 'Added AED 50,000 (bonus)');
      final h = d.projects.first.history;
      expect(h.length, 2);
      expect(h.last.why, 'Added AED 50,000 (bonus)');
      expect(monthsMoved(h.first.ready, h.last.ready)! < 0, isTrue);
      expect(sinceStart(d.projects.first), contains('sooner since you started'));
    });

    test('time passing with the same answers is honest about the slip', () {
      final d = lateHome();
      recordHistory(d, today: today, why: 'x');
      recordHistory(d, today: '2026-12-01', why: timePassed);
      final p = d.projects.first;
      expect(p.history.last.ready, '2029-10');
      expect(sinceStart(p), '2 months later since you started');
      expect(biggestSetback(p)!.why, timePassed);
    });

    test('history survives a save and reload, and is capped', () {
      final p = project('car', 60000, 24)
        ..history = [for (var i = 0; i < 70; i++) HistoryPoint(date: today, ready: inMonths(i), why: 'step $i')];
      final back = Project.fromJson(p.toJson());
      expect(back.history.length, 70);
      final d = AppData(money: salaried(), projects: [back]);
      recordHistory(d, today: today, why: 'again');
      expect(d.projects.first.history.length, historyCap);
      expect(d.projects.first.history.first.why, 'step 0'); // the start is kept
    });
  });

  group('check-in and drift', () {
    AppData lateHome({String? asOf = today}) =>
        AppData(money: salaried()..asOf = asOf, projects: [project('home', 900000, 24, pay: 'loan', rate: 4.5, term: 300, rent: 6000)]);

    test('with a savings date, time passing doesn\'t move the date', () {
      final d = lateHome();
      expect(readyMonth(assessAll(d, today: today)[1]!, today), '2029-08');
      expect(readyMonth(assessAll(d, today: '2026-12-01')[1]!, '2026-12-01'), '2029-08');
    });

    test('the plan expects what it would have saved', () {
      final e = expectedNow(lateHome(), today: '2026-12-01');
      expect(e.months, 2);
      expect(e.total, 21000); // 5,000 + 2 × 8,000 into the cushion
      expect(checkInDue(lateHome(), today: '2026-12-01'), isTrue);
      expect(checkInDue(lateHome(), today: today), isFalse);
    });

    test('behind the plan: real numbers in, and a spending suggestion', () {
      final d = lateHome();
      final r = applyCheckIn(d, today: '2026-12-01', actual: 18000);
      expect(r.gap, 3000);
      expect(r.perMonth, 1500);
      expect(r.label, 'Check-in: AED 3,000 behind plan');
      expect(d.money.savings, 18000);
      expect(d.money.asOf, '2026-12-01');
      expect(suggestedSpending(d.money, r), 13500);
    });

    test('a small slip is just a slip', () {
      final d = lateHome();
      final r = applyCheckIn(d, today: '2026-12-01', actual: 20800);
      expect(r.onPlan, isTrue);
      expect(suggestedSpending(d.money, r), isNull);
    });
  });

  group('why not yet', () {
    String? why(Money m, Project p) => whyNotYet(assess(m, p, today: today), today: today);

    test('the cushion comes first', () {
      expect(why(salaried(), project('home', 900000, 24, pay: 'loan', rate: 4.5, term: 300, rent: 6000)),
          'Your safety cushion comes first: full by Feb 2027.');
    });

    test('the card comes first', () {
      expect(why(salaried(card: 10000), project('car', 60000, 24)), startsWith('Your credit card comes first'));
    });

    test('progress when nothing blocks it', () {
      expect(why(salaried(savings: 100000), project('car', 120000, 24)), startsWith('You\'re 53% of the way: AED 56,000 to go'));
    });

    test('waiting for other projects', () {
      final d = AppData(money: salaried(), projects: [
        project('vacation', 15000, 12)..id = 1,
        project('car', 120000, 24)..id = 2,
        project('home', 900000, 60, pay: 'loan', rate: 4.5, term: 300, rent: 6000)..id = 3,
      ]);
      expect(whyNotYet(assessAll(d, today: today)[3]!, today: today), startsWith('It\'s waiting for the vacation and Family SUV'));
    });

    test('ready now has nothing to explain', () {
      expect(why(salaried(income: 30000, spending: 15000, savings: 200000, family: true), project('car', 80000, 12)), isNull);
    });
  });

  group('big number and no cushion', () {
    AppData lateHome({bool cushion = true}) =>
        AppData(money: salaried()..cushion = cushion, projects: [project('home', 900000, 24, pay: 'loan', rate: 4.5, term: 300, rent: 6000)]);

    test('what to save a month so every goal is on time', () {
      expect(neededMonthly(lateHome(), today: today), 11050); // 8,000 spare + the 3,050 pay rise that fixes it
    });

    test('without a cushion, savings go to the project straight away', () {
      final a = assessAll(lateHome(cushion: false), today: today)[1]!;
      expect(a.efTarget, 0);
      expect(a.readyIn, 29); // 5,000 + 8,000 a month toward 234,000, instead of month 34
      expect(titles(a).any((t) => t.contains('safety cushion')), isFalse);
      expect(a.checks.any((c) => c.label == 'Cushion still covers you'), isFalse);
      expect(neededMonthly(lateHome(cushion: false), today: today), 9550);
    });

    test('nothing to plan, nothing to show', () {
      expect(neededMonthly(AppData(money: salaried()), today: today), isNull);
    });

    test('the cushion choice is saved', () {
      expect(Money.fromJson((salaried()..cushion = false).toJson()).cushion, isFalse);
      expect(Money.fromJson({}).cushion, isTrue);
    });
  });

  group('backup', () {
    AppData sample() => AppData(money: salaried()..payday = 25, projects: [
          project('car', 120000, 24)
            ..contributions = [const Contribution(amount: 10000, source: 'Bonus', date: today)]
            ..history = [const HistoryPoint(date: today, ready: '2028-04', why: 'Started')],
        ])
      ..settings.lastBackup = '2026-09-01';

    test('round trip: everything comes back', () async {
      final bytes = await makeBackup(sample(), 'secret pass', today: today, version: '0.15.0', iterations: 1000);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'WBK1');
      final back = await readBackup(bytes, 'secret pass');
      expect(back.created, today);
      expect(back.version, '0.15.0');
      expect(back.data.toJson(), sample().toJson());
    });

    test('the plan text is not readable in the file', () async {
      final bytes = await makeBackup(sample(), 'secret pass', today: today, version: '0.15.0', iterations: 1000);
      expect(String.fromCharCodes(bytes).contains('Family SUV'), isFalse);
      expect(String.fromCharCodes(bytes).contains('120000'), isFalse);
    });

    test('wrong password, damaged file, not a backup, short password', () async {
      final bytes = await makeBackup(sample(), 'secret pass', today: today, version: '0.15.0', iterations: 1000);
      await expectLater(readBackup(bytes, 'wrong pass'), throwsA(isA<BackupError>().having((e) => e.message, 'message', startsWith('Wrong password'))));
      final damaged = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 0xFF;
      await expectLater(readBackup(damaged, 'secret pass'), throwsA(isA<BackupError>()));
      await expectLater(readBackup(Uint8List.fromList('hello world, not a backup at all.......................'.codeUnits), 'x'),
          throwsA(isA<BackupError>().having((e) => e.message, 'message', contains('isn\'t a WealthBuddy backup'))));
      await expectLater(makeBackup(sample(), '123', today: today, version: '0.15.0'), throwsA(isA<BackupError>()));
    });

    test('each backup is encrypted differently', () async {
      final a = await makeBackup(sample(), 'secret pass', today: today, version: '0.15.0', iterations: 1000);
      final b = await makeBackup(sample(), 'secret pass', today: today, version: '0.15.0', iterations: 1000);
      expect(a, isNot(equals(b))); // fresh salt and nonce each time
    });
  });

  test('car loans: 0% and 5 years', () {
    expect(instalment(60000, 0, 60), 1000);
    final a = assess(salaried(savings: 100000), project('car', 75000, 12, pay: 'loan', rate: 0, term: 60), today: today);
    expect(a.term, 60);
    expect(a.emi, 1000); // 60,000 borrowed over 60 months at 0%
    expect(a.watchouts.any((w) => w.contains('0% deals')), isTrue);
    expect(kinds['car']!.terms, contains(60));
    expect(kinds['car']!.rateChips, contains(0));
  });

  test('new project types', () {
    for (final t in ['renovation', 'hajj', 'business', 'baby', 'gold', 'gadget']) {
      expect(kinds.containsKey(t), isTrue, reason: t);
      final a = assess(salaried(), project(t, 30000, 24), today: today);
      expect(a.verdict, isNot('rethink'), reason: t);
      expect(a.watchouts, isNotEmpty, reason: t);
    }
    expect(kinds.keys.last, 'other');
    expect(projectQuestions(project('renovation', 1, 1)), [Q.cost, Q.when, Q.pay]);
    expect(kinds['business']!.costTitle, isNotEmpty);
  });

  test('formatting and months', () {
    expect(money(25000), 'AED 25,000');
    expect(fmt(1234.5, 2), '1,234.50');
    expect(addMonths('2026-10', 3), '2027-01');
    expect(monthsUntil(today, '2028-10'), 24);
    expect(monthLabel('2027-03'), 'Mar 2027');
    expect(durationLabel(48), '4 years');
    expect(durationLabel(18), '18 months');
  });
}
