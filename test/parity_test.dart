// Parity tests: the Dart engines must give the same results as the tested prototype.
// Fixtures in test/fixtures were exported from the prototype's own engine code.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_buddy/domain/basics.dart';
import 'package:wealth_buddy/domain/finance.dart';
import 'package:wealth_buddy/domain/models.dart';
import 'package:wealth_buddy/domain/parsers.dart';
import 'package:wealth_buddy/domain/recurring.dart';

const today = '2026-09-30';
dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());
AppState sampleState() => AppState.fromJson((fixture('sample_state.json') as Map).cast<String, dynamic>());

double r2(num x) => round2(x.toDouble());
Matcher near(num? v) => v == null ? isNull : closeTo(v, 0.011);

void expectSnapshot(Finance f, Map snap) {
  final t = f.t, et = snap['totals'] as Map;
  for (final k in ['assets', 'debts', 'net', 'cash', 'spent', 'received']) {
    final actual = {'assets': t.assets, 'debts': t.debts, 'net': t.net, 'cash': t.cash, 'spent': t.spent, 'received': t.received}[k]!;
    expect(r2(actual), near(et[k]), reason: 'totals.$k');
  }
  (et['byCat'] as Map).forEach((k, v) => expect(r2(t.byCat[k] ?? 0), near(v), reason: 'byCat.$k'));

  expect(f.income?.v, snap['income'] == null ? isNull : near(snap['income']['v']), reason: 'income');
  final h = snap['household'] as Map;
  expect(f.household.adults, h['adults']);
  expect(f.household.kids, h['kids']);
  expect(f.household.known, h['known']);

  final bench = f.benchmark(), eb = snap['benchmark'] as List;
  expect(bench.map((b) => b.cat).toList(), eb.map((b) => b['cat']).toList(), reason: 'benchmark categories');
  for (var i = 0; i < eb.length; i++) {
    expect(r2(bench[i].pct), near(eb[i]['pct']), reason: 'bench ${eb[i]['cat']} pct');
    expect(bench[i].lo, near(eb[i]['lo']), reason: 'bench ${eb[i]['cat']} lo');
    expect(bench[i].hi, near(eb[i]['hi']), reason: 'bench ${eb[i]['cat']} hi');
    expect(bench[i].s, eb[i]['s'], reason: 'bench ${eb[i]['cat']} status');
    expect(r2(bench[i].over), near(eb[i]['over']), reason: 'bench ${eb[i]['cat']} over');
  }

  final db = f.debtBurden, edb = snap['debtBurden'];
  if (edb == null) {
    expect(db, isNull);
  } else {
    expect(r2(db!.total), near(edb['total']));
    expect(r2(db.pct), near(edb['pct']));
    expect(db.s, edb['s']);
  }

  final pl = f.plan, ep = snap['plan'] as Map;
  expect(pl.surplus == null ? null : r2(pl.surplus!), near(ep['surplus']), reason: 'plan.surplus');
  expect(r2(pl.toDebt), near(ep['toDebt']), reason: 'plan.toDebt');
  expect(r2(pl.toEF), near(ep['toEF']), reason: 'plan.toEF');
  expect(r2(pl.toInvestBase), near(ep['toInvestBase']), reason: 'plan.toInvestBase');
  expect(r2(pl.projReserve), near(ep['projReserve']), reason: 'plan.projReserve');
  expect(r2(pl.toInvest), near(ep['toInvest']), reason: 'plan.toInvest');
  expect(pl.mix.map((m) => m.v).toList(), (ep['mix'] as List).cast<int>(), reason: 'plan.mix');
  expect(pl.eos == null ? null : r2(pl.eos!), near(ep['eos']), reason: 'plan.eos');

  final pr = f.projects, epr = snap['projects'] as List;
  expect(pr.length, epr.length);
  for (var i = 0; i < epr.length; i++) {
    final e = epr[i] as Map, a = pr[i], who = 'project ${e['id']}';
    expect(a.verdict, e['verdict'], reason: '$who verdict');
    if (e['verdict'] == null) continue;
    expect(r2(a.need), near(e['need']), reason: '$who need');
    expect(r2(a.fromCash), near(e['fromCash']), reason: '$who fromCash');
    expect(r2(a.canSave), near(e['canSave']), reason: '$who canSave');
    expect(r2(a.emi), near(e['emi']), reason: '$who emi');
    expect(a.dbr == null ? null : r2(a.dbr!), near(e['dbr']), reason: '$who dbr');
    expect(r2(a.freeAfter), near(e['freeAfter']), reason: '$who freeAfter');
    expect(a.checks.map((c) => c.s).toList(), (e['checks'] as List).cast<String>(), reason: '$who checks');
    expect(a.catImpact == null ? null : r2(a.catImpact!.ap), near(e['catAfterPct']), reason: '$who category impact');
    expect(a.fixes.length, e['fixes'], reason: '$who number of fixes');
  }

  final sg = f.suggestions, esg = snap['suggestions'] as List;
  expect(sg.map((x) => x.id).toList(), esg.map((x) => x['id']).toList(), reason: 'suggestion order');
  for (var i = 0; i < esg.length; i++) {
    expect(sg[i].sev, esg[i]['sev'], reason: 'suggestion ${esg[i]['id']} severity');
    expect(sg[i].impact == null ? null : r2(sg[i].impact!), near(esg[i]['impact']), reason: 'suggestion ${esg[i]['id']} impact');
  }
}

void main() {
  final scenarios = fixture('expected_scenarios.json') as Map;

  group('matches the prototype', () {
    test('example household (2 adults, 1 child)', () {
      expectSnapshot(Finance(sampleState(), today: today), scenarios['sample']);
    });
    test('same data, one adult', () {
      final s = sampleState()
        ..profile.adults = 1
        ..profile.kids = 0;
      expectSnapshot(Finance(s, today: today), scenarios['single']);
    });
    test('3-month cushion, growth risk, Sharia, gratuity', () {
      final s = sampleState();
      s.profile
        ..efMonths = 3
        ..basic = 15000
        ..years = 7
        ..risk = 'growth'
        ..ageBand = 'u30'
        ..sharia = true;
      expectSnapshot(Finance(s, today: today), scenarios['ef3']);
    });
    test('fresh install with no data', () {
      final s = AppState(budgets: Map.of(defaultBudgets));
      expectSnapshot(Finance(s, today: today), scenarios['fresh']);
    });
  });

  test('repeating costs expand one entry per month, and re-running adds nothing', () {
    final fx = fixture('recurring.json') as Map;
    final s = AppState(budgets: Map.of(defaultBudgets), profile: Profile(adults: 2, kids: 1));
    for (final r in fx['rules'] as List) {
      final rule = RecurringRule.fromJson({...(r as Map).cast<String, dynamic>(), 'id': 0});
      upsertRule(s, rule.setupKey!, rule);
    }
    syncRecurring(s, fx['today']);
    syncRecurring(s, fx['today']);
    final exp = fx['expectedTx'] as List;
    expect(s.tx.length, exp.length);
    for (var i = 0; i < exp.length; i++) {
      expect(s.tx[i].date, exp[i]['date']);
      expect(s.tx[i].merchant, exp[i]['merchant']);
      expect(s.tx[i].amount, near(exp[i]['amount']));
      expect(s.tx[i].method, exp[i]['method']);
    }
    expectSnapshot(Finance(s, today: fx['today']), fx['snapshot']);
  });

  group('parsers', () {
    final p = fixture('parsers.json') as Map;
    void rowsMatch(List<ImportRow> got, List exp) {
      expect(got.length, exp.length);
      for (var i = 0; i < exp.length; i++) {
        expect(got[i].date, exp[i]['date'], reason: 'row $i date');
        expect(got[i].merchant, exp[i]['merchant'], reason: 'row $i merchant');
        expect(got[i].cat, exp[i]['cat'], reason: 'row $i category');
        expect(got[i].amount, near(exp[i]['amount']), reason: 'row $i amount');
        expect(got[i].status, exp[i]['status'], reason: 'row $i status');
      }
    }

    test('credit card CSV: card payment skipped, duplicates flagged', () {
      final c = p['cardCsv'] as Map;
      expect(guessKind(c['text']), c['kind']);
      rowsMatch(classify(rowsToRaw(parseCsv(c['text']))!, 'card', sampleState().tx), c['rows']);
    });
    test('bank CSV with debit, credit and balance columns', () {
      final c = p['bankCsv'] as Map;
      expect(guessKind(c['text']), c['kind']);
      rowsMatch(classify(rowsToRaw(parseCsv(c['text']))!, 'bank', sampleState().tx), c['rows']);
    });
    test('PDF text lines: sign from running balance, FX amounts ignored', () {
      final c = p['pdfLines'] as Map;
      rowsMatch(classify(linesToRaw((c['lines'] as List).cast<String>()), 'bank', sampleState().tx), c['rows']);
    });
    test('bank SMS', () {
      for (final c in p['sms'] as List) {
        final r = parseSms(c['text'], today: today), e = c['result'];
        if (e == null) {
          expect(r, isNull);
          continue;
        }
        if (e['date'] != null) expect(r!.date, e['date']);
        expect(r!.merchant, e['merchant']);
        expect(r2(r.amount), near(e['amount']));
        expect(r.cat, e['cat']);
      }
    });
    test('merchant clean-up, categories and dates', () {
      for (final m in p['merchants'] as List) {
        expect(cleanMerchant(m['in']), m['out']);
      }
      for (final m in p['categories'] as List) {
        expect(guessCat(m['in']), m['out']);
      }
      for (final m in p['dates'] as List) {
        expect(parseDate(m['in']), m['out'], reason: m['in']);
      }
    });
  });

  test('loan, gratuity and projection maths', () {
    final m = fixture('maths.json') as Map;
    for (final c in m['eosb'] as List) {
      expect(eosb((c['basic'] as num).toDouble(), (c['years'] as num).toDouble()), near(c['out']));
    }
    for (final c in m['instalment'] as List) {
      expect(instalment((c['p'] as num).toDouble(), (c['r'] as num).toDouble(), c['n']), near(c['out']));
    }
    for (final c in m['projection'] as List) {
      expect(projection((c['m'] as num).toDouble(), c['y'], (c['r'] as num).toDouble())[c['y']].value, near(c['out']));
    }
  });

  test('money formatting', () {
    expect(money(25000), 'AED 25,000');
    expect(money(1234.5, 2), 'AED 1,234.50');
    expect(fmt(0.2), '0');
    expect(fmt(-9500), '-9,500');
    expect(monthsAhead('2026-09', 12), 'Sep 2027');
    expect(monthsAhead('2026-09', 4), 'Jan 2027');
  });
}
