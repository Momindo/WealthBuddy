// Scenario tests for the decision engine. Each one is a real situation the plan must get right.
import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_buddy/domain/assess.dart';
import 'package:wealth_buddy/domain/format.dart';
import 'package:wealth_buddy/domain/models.dart';

const today = '2026-10-01';
String inMonths(int n) => addMonths(monthKey(today), n);

Money salaried({double income = 20000, double spending = 12000, double savings = 5000, double repayments = 0, double card = 0, bool family = false, bool variable = false, double? investments}) =>
    Money(income: income, spending: spending, savings: savings, repayments: repayments, cardDebt: card, family: family, variable: variable, investments: investments);

Project project(String type, double cost, int months, {String pay = 'savings', double down = 20, double rate = 3.5, int term = 48, double? rent}) =>
    Project(id: 1, type: type, name: type, cost: cost, target: inMonths(months), pay: pay, downPct: down, rate: rate, term: term, rent: rent);

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

  test('questions adapt to the project', () {
    expect(projectQuestions(project('car', 1, 1), isNew: true), [Q.cost, Q.when, Q.pay, Q.setAside]);
    expect(projectQuestions(project('car', 1, 1, pay: 'loan')), [Q.cost, Q.when, Q.pay, Q.loan]);
    expect(projectQuestions(project('car', 1, 1)), [Q.cost, Q.when, Q.pay]);
    expect(projectQuestions(project('home', 1, 1)), [Q.cost, Q.when, Q.pay, Q.rent]);
    expect(projectQuestions(project('vacation', 1, 1)), [Q.cost, Q.when]);
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
