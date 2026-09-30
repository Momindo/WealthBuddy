import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../domain/basics.dart';
import '../domain/finance.dart';
import 'widgets.dart';

class InvestScreen extends ConsumerStatefulWidget {
  const InvestScreen({super.key});
  @override
  ConsumerState<InvestScreen> createState() => _InvestState();
}

class _InvestState extends ConsumerState<InvestScreen> {
  bool onceReady = false;
  double years = 10;
  late final fdRate = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(financeProvider);
    if (f == null) return const SizedBox();
    final pl = f.plan, p = f.s.profile, ctl = ref.read(appProvider.notifier);
    if (fdRate.text.isEmpty) fdRate.text = '${f.fdRate}';
    if (pl.surplus == null) {
      return ScreenBody(children: [
        Text('How much could you invest?', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        Section(title: 'Add your income first', children: [
          note(context, 'Add your salary in setup, or pick an income range on the Suggestions tab.'),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => ref.read(showSetupProvider.notifier).state = 0, child: const Text('Add salary')),
        ]),
      ]);
    }
    final safe = f.invStyle == 'safe', sharia = p.sharia;
    final inc = pl.inc!.v, full = math.max(pl.surplus!, 0.0);
    final costly = f.costlyDebt, efGap = f.efGap;
    final ready = full > 0 ? ((costly + efGap) / full).ceil() : null;
    final verb = safe ? 'save' : 'invest';
    final parts = [
      ('Spending', math.min(f.t.spent, inc), Tone.plain),
      ('Card payoff', pl.toDebt, Tone.bad),
      ('Safety cushion', pl.toEF, Tone.warn),
      ('Projects', pl.projReserve, Tone.gold),
      (safe ? 'Save' : 'Invest', pl.toInvest, Tone.accent),
    ].where((x) => x.$2 > 0).toList();

    return ScreenBody(children: [
      MoneyHero(
        label: 'You can $verb',
        value: fmt(pl.toInvest),
        suffix: '/ month',
        sub: pl.toInvest < full
            ? 'Rising to ${aed(full)} once expensive debt and your cushion are done${ready != null && ready > 0 ? ', in about $ready month${ready > 1 ? 's' : ''}' : ''}.'
            : 'Your full surplus is free to $verb.',
      ),
      Section(title: 'Where that number comes from', children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
              height: 14,
              child: Row(children: [for (final x in parts) Expanded(flex: math.max(1, (x.$2 / inc * 1000).round()), child: Container(color: toneColor(context, x.$3).withValues(alpha: x.$3 == Tone.plain ? 0.3 : 1)))])),
        ),
        const SizedBox(height: 8),
        Row2('Income', fmt(inc)),
        for (final x in parts) Row2(x.$1, '${x.$1 == (safe ? 'Save' : 'Invest') ? '=' : '−'} ${fmt(x.$2)}', bold: x.$1 == (safe ? 'Save' : 'Invest')),
        note(context,
            "Income from ${pl.inc!.src}. While expensive debt remains, 70% of what's left goes to it; then 60% of the rest tops up a ${f.efMonths}-month cushion${pl.projReserve > 0 ? ', and your projects take what they need each month' : ''}."),
      ]),
      Section(title: 'Before you $verb', children: [
        Row(children: [const Expanded(child: Text('High-interest debt cleared')), costly > 0 ? Tag('${aed(costly)} left', tone: Tone.bad) : const Tag('Done', tone: Tone.good)]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: Text('${f.efMonths}-month safety cushion')), efGap > 0 ? Tag('${aed(efGap)} to go', tone: Tone.warn) : const Tag('Done', tone: Tone.good)]),
        const SizedBox(height: 8),
        note(context, 'You can start small before both are done. The amount above already accounts for them.'),
      ]),
      _emergencyFund(context, f),
      Section(title: 'Where to put it', children: [
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'grow', label: Text('Grow · market mix')), ButtonSegment(value: 'safe', label: Text('Safe · fixed rate'))],
          selected: {f.invStyle},
          onSelectionChanged: (v) => ctl.update((s) => s.profile.invStyle = v.first),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
            contentPadding: EdgeInsets.zero, title: const Text('Sharia-compliant'), value: sharia, onChanged: (v) => ctl.update((s) => s.profile.sharia = v)),
        if (!safe) ...[
          const Text('Age'),
          const SizedBox(height: 6),
          Choice<String>(
              options: ageBands.map((b) => b.key).toList(),
              selected: p.ageBand,
              labels: (k) => ageBands.firstWhere((b) => b.key == k).label,
              onSelected: (k) => ctl.update((s) => s.profile.ageBand = s.profile.ageBand == k ? null : k)),
          const SizedBox(height: 8),
          const Text('Risk'),
          const SizedBox(height: 6),
          Choice<String>(options: const ['cautious', 'balanced', 'growth'], selected: p.risk, labels: (k) => '${k[0].toUpperCase()}${k.substring(1)}', onSelected: (k) => ctl.update((s) => s.profile.risk = k)),
          const SizedBox(height: 10),
          note(context, 'Starting mix for ${pl.age.src} and ${p.risk} risk.'),
          for (final m in pl.mix)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${m.label} · ${m.v}%'),
              subtitle: Text(switch (m.kind) {
                'equity' => sharia
                    ? 'A fund holding thousands of global companies screened for Sharia rules. The growth engine.'
                    : 'A fund tracking thousands of companies worldwide, such as an MSCI World or FTSE All-World index. The growth engine.',
                'bonds' => sharia ? 'Sharia-compliant certificates that pay a profit share instead of interest.' : 'Government and high-grade corporate bonds. Steadier.',
                _ => 'A gold fund or bullion. Jewellery carries making charges you lose when selling.',
              }),
              trailing: Text(fmt(pl.toInvest * m.v / 100)),
            ),
        ] else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${sharia ? 'Islamic term deposit' : 'Fixed-rate savings or fixed deposit'} · 100%'),
            subtitle: Text(sharia
                ? 'Your bank invests in Sharia-compliant deals and pays an expected profit rate. The balance can\'t fall.'
                : 'Your bank pays a fixed rate for a set term, such as 3, 6 or 12 months. The balance can\'t fall.'),
            trailing: Text(fmt(pl.toInvest)),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              controller: fdRate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: sharia ? 'Expected profit rate (% a year)' : "Your bank's rate (% a year)"),
              onSubmitted: (v) {
                final r = double.tryParse(v);
                if (r != null && r >= 0 && r <= 15) ctl.update((s) => s.profile.fdRate = r);
              },
            ),
          ),
          const SizedBox(height: 6),
          note(context, "Check your bank's current rate; it moves with interest rates. Good for money you'll need in 1–5 years. Over 10+ years it usually grows far less than the market mix."),
        ],
      ]),
      _projectionCard(context, f, full),
      Section(title: 'How to do it', children: [
        for (final (i, st) in (safe ? _safeSteps(pl.toInvest, sharia) : _growSteps(pl.toInvest, sharia)).indexed)
          ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(radius: 13, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))), title: Text(st.$1), subtitle: Text(st.$2)),
      ]),
      Section(title: safe ? 'Where to find fixed rates' : 'Ways to invest from the UAE', children: [
        for (final w in safe ? _safeWays : _growWays) ListTile(contentPadding: EdgeInsets.zero, title: Text(w.$1), subtitle: Text(w.$2), trailing: Tag(w.$3)),
        note(context, 'Examples only, not endorsements. Compare fees and check the licence before you open an account.'),
      ]),
      note(context, 'Educational guidance from fixed rules. It describes types of investment, not specific products. Personalised investment advice in the UAE is a licensed activity.'),
    ]);
  }

  Widget _emergencyFund(BuildContext context, Finance f) {
    final spend = f.t.spent, m = f.efMonths, ctl = ref.read(appProvider.notifier);
    if (spend <= 0) return Section(title: 'Your emergency fund', children: [note(context, 'Add a few transactions so the app can size your fund from what you actually spend.')]);
    final target = spend * m, have = math.min(f.t.cash, target), pct = have / target;
    final rec = f.household.kids > 0 ? 9 : 6;
    const options = [
      (3, 'Two incomes, stable jobs, no dependants'),
      (6, 'One income, or a typical UAE expat household'),
      (9, 'Dependants, or a sponsor visa tied to one job'),
      (12, 'Self-employed, commission or contract work'),
    ];
    final layers = [
      ('Instant', 1, 'Your current account. For the first few weeks.'),
      ('Within a day or two', math.min(2, m - 1), 'Instant-access savings, money market fund or Sharia savings account.'),
      ('Within a few weeks', math.max(m - 3, 0), 'Notice account or short fixed deposits, staggered so one matures each month.'),
    ].where((l) => l.$2 > 0).toList();
    var left = f.t.cash;
    return Section(title: 'Your emergency fund', trailing: Tag(pct >= 1 ? 'Complete' : '${(pct * 100).toStringAsFixed(0)}%', tone: pct >= 1 ? Tone.good : Tone.warn), children: [
      Row2(aed(have), 'of ${aed(target)}'),
      Bar(pct, tone: pct >= 1 ? Tone.accent : Tone.warn, height: 10),
      const SizedBox(height: 6),
      note(context, '${(f.t.cash / spend).toStringAsFixed(1)} months of your ${aed(spend)} monthly spending is in cash. Build it before investing.'),
      const SizedBox(height: 10),
      Text('How many months fits you', style: Theme.of(context).textTheme.labelLarge),
      for (final o in options)
        RadioListTile<int>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: o.$1,
          groupValue: m,
          onChanged: (v) => ctl.update((s) => s.profile.efMonths = v!),
          title: Row(children: [Text('${o.$1} months'), if (f.household.known && o.$1 == rec) const Padding(padding: EdgeInsets.only(left: 6), child: Tag('Suggested for you', tone: Tone.good))]),
          subtitle: Text(o.$2),
          secondary: Text(fmt(spend * o.$1)),
        ),
      const SizedBox(height: 6),
      Text('Where to keep it', style: Theme.of(context).textTheme.labelLarge),
      for (final l in layers) ...[
        Builder(builder: (context) {
          final need = spend * l.$2, filled = math.min(math.max(left, 0.0), need);
          left -= need;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row2('${l.$1} · ${l.$2} month${l.$2 > 1 ? 's' : ''}', fmt(need)),
            note(context, l.$3),
            const SizedBox(height: 4),
            Bar(filled / need, tone: filled >= need ? Tone.accent : Tone.warn),
            const SizedBox(height: 8),
          ]);
        }),
      ],
      note(context,
          "Keep it in AED at a UAE bank, not in shares, crypto or gold. Use a separate account with no debit card. Check you're subscribed to the UAE unemployment insurance scheme (ILOE). Refill it first after using it."),
    ]);
  }

  Widget _projectionCard(BuildContext context, Finance f, double full) {
    final pl = f.plan, safe = f.invStyle == 'safe';
    final monthly = onceReady ? full : pl.toInvest, y = years.round();
    final mainRate = safe ? f.fdRate : f.growthRate(), otherRate = safe ? f.growthRate() : f.fdRate;
    final main = projection(monthly, y, mainRate), other = projection(monthly, y, otherRate);
    return Section(title: 'What it could grow to', children: [
      SegmentedButton<bool>(
        segments: [ButtonSegment(value: false, label: Text('Now · ${fmt(pl.toInvest)}')), ButtonSegment(value: true, label: Text('Once ready · ${fmt(full)}'))],
        selected: {onceReady},
        onSelectionChanged: (v) => setState(() => onceReady = v.first),
      ),
      const SizedBox(height: 8),
      Text('${safe ? 'Save' : 'Invest'} for $y years'),
      Slider(value: years, min: 1, max: 30, divisions: 29, label: '$y years', onChanged: (v) => setState(() => years = v)),
      SizedBox(
        height: 150,
        child: CustomPaint(
          size: Size.infinite,
          painter: _ProjectionPainter(main, other, Theme.of(context).colorScheme, toneColor(context, Tone.gold)),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, children: [
        _legend(context, Theme.of(context).colorScheme.primary, safe ? 'Fixed-rate savings' : 'Market mix'),
        _legend(context, toneColor(context, Tone.gold), safe ? 'Market mix, for comparison' : 'Fixed rate, for comparison'),
        _legend(context, Theme.of(context).colorScheme.onSurfaceVariant, 'Paid in'),
      ]),
      const SizedBox(height: 8),
      Row2('You put in', aed(main.last.paid)),
      Row2(safe ? 'Grows to' : 'Could grow to', aed(main.last.value), bold: true, tone: Tone.good),
      note(context,
          safe
              ? 'Uses your ${f.fdRate}% rate, renewed at the same rate. The balance never falls, but rates change at renewal and inflation takes part of the gain.'
              : 'Uses an assumed ${mainRate.toStringAsFixed(1)}% a year for this mix and ignores inflation. Real returns vary and can be negative for years at a time.'),
    ]);
  }

  Widget _legend(BuildContext c, Color col, String t) =>
      Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 6), Text(t, style: Theme.of(c).textTheme.bodySmall)]);

  List<(String, String)> _growSteps(double monthly, bool sharia) => [
        ('Pick a licensed platform', "Check it's regulated by the SCA, or by the DFSA (DIFC) or FSRA (ADGM). Each regulator has a public register you can search."),
        ('Choose low-cost index funds', 'Look for broad ${sharia ? 'Sharia-screened ' : ''}funds with total yearly fees under about 0.5%. Ireland-domiciled funds often suit UAE residents: lower US dividend tax, and no US estate-tax exposure above USD 60k.'),
        ('Automate it on salary day', 'Set a monthly buy of ${aed(monthly)} the day after your salary lands. Automating beats timing the market.'),
        ('Rebalance once a year', 'If shares have grown past their share of the mix, move the excess back into the other parts.'),
        ('Leave it alone in downturns', 'Markets fall 20% or more every few years. Selling then locks in the loss.'),
      ];
  List<(String, String)> _safeSteps(double monthly, bool sharia) => [
        ('Compare rates first', 'Check your own bank, then two or three others. Digital banks often pay more. Compare the ${sharia ? 'expected profit rate' : 'rate'} for the same term.'),
        ('Read the conditions', 'Look for the minimum deposit, the penalty for breaking it early, and whether the rate is fixed for the whole term.'),
        ('Pick a term you can wait out', 'Money locked for 12 months usually earns more than 3 months. Only lock what you won\'t need before it matures.'),
        ('Save monthly, deposit in batches', 'Move ${aed(monthly)} into savings each salary day. When it reaches the bank\'s minimum, open a new deposit.'),
        ('Renew or move at maturity', 'When a deposit matures, check the new rate before it auto-renews. Move it if another bank pays clearly more.'),
      ];
  static const _growWays = [
    ('Robo-advisor', 'Builds and rebalances the mix for you, often with Sharia portfolios. Example: Sarwa.', 'Easiest'),
    ('Online broker', 'You pick the funds yourself. Example: Interactive Brokers.', 'Lowest cost'),
    ("Your bank's investment account", 'Easy to open alongside your current account. Fees are usually higher.', 'Convenient'),
    ('Sharia savings scheme', 'Profit-sharing savings in place of the bond portion. Example: National Bonds.', 'Low risk'),
  ];
  static const _safeWays = [
    ('Your current bank', 'Open a fixed deposit in the app in minutes. Rates are not always the best.', 'Easiest'),
    ('Digital banks', 'App-only banks tend to pay more on savings and have low minimums.', 'Often higher'),
    ('Islamic banks', 'Term deposits that pay an expected profit rate instead of interest.', 'Sharia'),
    ('Sharia savings scheme', 'Profit-sharing savings you can withdraw from. Example: National Bonds.', 'Flexible'),
  ];
}

class _ProjectionPainter extends CustomPainter {
  _ProjectionPainter(this.main, this.other, this.cs, this.goldC);
  final List<ProjectionPoint> main, other;
  final ColorScheme cs;
  final Color goldC;
  @override
  void paint(Canvas c, Size s) {
    const pb = 18.0;
    final years = main.last.y == 0 ? 1 : main.last.y;
    final maxV = [main.last.value, other.last.value, 1.0].reduce(math.max);
    double x(int y) => s.width * y / years;
    double yv(double v) => (s.height - pb) * (1 - v / maxV) + 2;
    final grid = Paint()..color = cs.outlineVariant;
    for (final g in [0.25, 0.5, 0.75]) {
      c.drawLine(Offset(0, (s.height - pb) * g), Offset(s.width, (s.height - pb) * g), grid);
    }
    Path line(List<ProjectionPoint> pts, double Function(ProjectionPoint) v) {
      final p = Path()..moveTo(x(pts.first.y), yv(v(pts.first)));
      for (final pt in pts.skip(1)) {
        p.lineTo(x(pt.y), yv(v(pt)));
      }
      return p;
    }

    final area = line(main, (p) => p.value)
      ..lineTo(x(main.last.y), s.height - pb)
      ..lineTo(0, s.height - pb)
      ..close();
    c.drawPath(area, Paint()..color = cs.primary.withValues(alpha: 0.12));
    c.drawPath(line(other, (p) => p.value), Paint()
      ..color = goldC
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    c.drawPath(line(main, (p) => p.paid), Paint()
      ..color = cs.onSurfaceVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    c.drawPath(line(main, (p) => p.value), Paint()
      ..color = cs.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final (y, label) in [(0, 'Today'), (years, '${years}y')]) {
      tp.text = TextSpan(text: label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant));
      tp.layout();
      tp.paint(c, Offset(y == 0 ? 0 : s.width - tp.width, s.height - 14));
    }
  }

  @override
  bool shouldRepaint(covariant _ProjectionPainter o) => true;
}
