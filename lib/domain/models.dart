// Data model for Wealth Buddy.
//
// Everything lives on the device. There is no account, name, email or phone number.
// Field names match the prototype's JSON so fixtures and exports load unchanged.

double _d(Object? v) => v == null ? 0.0 : (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
int? _in(Object? v) => v == null ? null : (v as num).toInt();

class Tx {
  int id;
  String date; // yyyy-mm-dd
  String merchant;
  String cat;
  double amount; // negative = money out, positive = money in
  String? method; // cash | card | transfer | cheque
  int? rid; // id of the repeating rule that created it

  Tx({required this.id, required this.date, required this.merchant, required this.cat, required this.amount, this.method, this.rid});

  factory Tx.fromJson(Map<String, dynamic> j) => Tx(
        id: _in(j['id'])!,
        date: j['date'] as String,
        merchant: j['merchant'] as String,
        cat: j['cat'] as String,
        amount: _d(j['amount']),
        method: j['method'] as String?,
        rid: _in(j['rid']),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'date': date, 'merchant': merchant, 'cat': cat, 'amount': amount,
        if (method != null) 'method': method,
        if (rid != null) 'rid': rid,
      };
}

class Asset {
  int id;
  String name;
  String type; // cash | investment | property | gold | crypto | other
  double amount;
  String cur; // AED, USD, ... or GOLD_G for grams of gold

  Asset({required this.id, required this.name, required this.type, required this.amount, required this.cur});

  factory Asset.fromJson(Map<String, dynamic> j) =>
      Asset(id: _in(j['id'])!, name: j['name'] as String, type: j['type'] as String, amount: _d(j['amount']), cur: j['cur'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': type, 'amount': amount, 'cur': cur};
}

class Liability {
  int id;
  String name;
  String type; // card | loan
  double amount;
  String cur;
  double rate; // % a year
  double? monthly; // instalment, loans only
  String? setupKey;

  Liability({required this.id, required this.name, required this.type, required this.amount, this.cur = 'AED', this.rate = 0, this.monthly, this.setupKey});

  factory Liability.fromJson(Map<String, dynamic> j) => Liability(
        id: _in(j['id'])!,
        name: j['name'] as String,
        type: j['type'] as String,
        amount: _d(j['amount']),
        cur: (j['cur'] as String?) ?? 'AED',
        rate: _d(j['rate']),
        monthly: _dn(j['monthly']),
        setupKey: j['setupKey'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'type': type, 'amount': amount, 'cur': cur, 'rate': rate,
        if (monthly != null) 'monthly': monthly,
        if (setupKey != null) 'setupKey': setupKey,
      };
}

class Project {
  int id;
  String name;
  String type; // car | home | build | other
  double cost;
  int months;
  String method; // cash | loan
  double dp; // down payment %
  double rate;
  int term; // months
  double saved;

  Project({required this.id, required this.name, required this.type, required this.cost, required this.months, required this.method,
      this.dp = 0, this.rate = 0, this.term = 36, this.saved = 0});

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: _in(j['id'])!,
        name: j['name'] as String,
        type: j['type'] as String,
        cost: _d(j['cost']),
        months: _in(j['months'])!,
        method: j['method'] as String,
        dp: _d(j['dp']),
        rate: _d(j['rate']),
        term: _in(j['term']) ?? 36,
        saved: _d(j['saved']),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'type': type, 'cost': cost, 'months': months, 'method': method, 'dp': dp, 'rate': rate, 'term': term, 'saved': saved};
}

/// A cost or income that repeats. Expanded into one [Tx] per month by `syncRecurring`.
/// Yearly amounts are spread evenly over 12 months (UAE rent paid in cheques).
class RecurringRule {
  int id;
  String merchant;
  String cat;
  double amount; // monthly amount, or yearly amount when freq == yearly
  int sign; // -1 cost, +1 income
  String method;
  String freq; // monthly | yearly
  int? cheques;
  String start; // yyyy-mm-dd
  List<String> skip; // months (yyyy-mm) removed by the user
  String? until; // last month included (yyyy-mm)
  String? setupKey;

  RecurringRule({required this.id, required this.merchant, required this.cat, required this.amount, required this.sign, required this.method,
      required this.freq, this.cheques, required this.start, List<String>? skip, this.until, this.setupKey})
      : skip = skip ?? [];

  factory RecurringRule.fromJson(Map<String, dynamic> j) => RecurringRule(
        id: _in(j['id'])!,
        merchant: j['merchant'] as String,
        cat: j['cat'] as String,
        amount: _d(j['amount']),
        sign: _in(j['sign']) ?? -1,
        method: (j['method'] as String?) ?? 'cash',
        freq: j['freq'] as String,
        cheques: _in(j['cheques']),
        start: j['start'] as String,
        skip: ((j['skip'] as List?) ?? const []).cast<String>().toList(),
        until: j['until'] as String?,
        setupKey: j['setupKey'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'merchant': merchant, 'cat': cat, 'amount': amount, 'sign': sign, 'method': method, 'freq': freq,
        if (cheques != null) 'cheques': cheques,
        'start': start, 'skip': skip,
        if (until != null) 'until': until,
        if (setupKey != null) 'setupKey': setupKey,
      };
}

/// Everything here is optional, and income and age are stored as ranges unless typed exactly.
class Profile {
  int? adults;
  int? kids;
  int efMonths;
  double? income;
  String? incomeBand;
  String? ageBand;
  String risk; // cautious | balanced | growth
  bool sharia;
  double? basic;
  double? years;
  String? invStyle; // grow | safe
  double? fdRate;

  Profile({this.adults, this.kids, this.efMonths = 6, this.income, this.incomeBand, this.ageBand, this.risk = 'balanced', this.sharia = false,
      this.basic, this.years, this.invStyle, this.fdRate});

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        adults: _in(j['adults']),
        kids: _in(j['kids']),
        efMonths: _in(j['efMonths']) ?? 6,
        income: _dn(j['income']),
        incomeBand: j['incomeBand'] as String?,
        ageBand: j['ageBand'] as String?,
        risk: (j['risk'] as String?) ?? 'balanced',
        sharia: (j['sharia'] as bool?) ?? false,
        basic: _dn(j['basic']),
        years: _dn(j['years']),
        invStyle: j['invStyle'] as String?,
        fdRate: _dn(j['fdRate']),
      );

  Map<String, dynamic> toJson() => {
        'adults': adults, 'kids': kids, 'efMonths': efMonths, 'income': income, 'incomeBand': incomeBand, 'ageBand': ageBand,
        'risk': risk, 'sharia': sharia, 'basic': basic, 'years': years, 'invStyle': invStyle, 'fdRate': fdRate,
      };
}

class AppState {
  bool example;
  Profile profile;
  List<Asset> assets;
  List<Liability> liabilities;
  List<Project> projects;
  List<Tx> tx;
  List<RecurringRule> recurring;
  Map<String, double> budgets;
  List<String> dismissed;
  List<String> done;
  Map<String, Object?> setup;

  AppState({this.example = false, Profile? profile, List<Asset>? assets, List<Liability>? liabilities, List<Project>? projects, List<Tx>? tx,
      List<RecurringRule>? recurring, Map<String, double>? budgets, List<String>? dismissed, List<String>? done, Map<String, Object?>? setup})
      : profile = profile ?? Profile(),
        assets = assets ?? [],
        liabilities = liabilities ?? [],
        projects = projects ?? [],
        tx = tx ?? [],
        recurring = recurring ?? [],
        budgets = budgets ?? {},
        dismissed = dismissed ?? [],
        done = done ?? [],
        setup = setup ?? {};

  factory AppState.fromJson(Map<String, dynamic> j) => AppState(
        example: (j['example'] as bool?) ?? false,
        profile: Profile.fromJson((j['profile'] as Map?)?.cast<String, dynamic>() ?? {}),
        assets: ((j['assets'] as List?) ?? []).map((e) => Asset.fromJson((e as Map).cast<String, dynamic>())).toList(),
        liabilities: ((j['liabilities'] as List?) ?? []).map((e) => Liability.fromJson((e as Map).cast<String, dynamic>())).toList(),
        projects: ((j['projects'] as List?) ?? []).map((e) => Project.fromJson((e as Map).cast<String, dynamic>())).toList(),
        tx: ((j['tx'] as List?) ?? []).map((e) => Tx.fromJson((e as Map).cast<String, dynamic>())).toList(),
        recurring: ((j['recurring'] as List?) ?? []).map((e) => RecurringRule.fromJson((e as Map).cast<String, dynamic>())).toList(),
        budgets: ((j['budgets'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        dismissed: ((j['dismissed'] as List?) ?? []).cast<String>().toList(),
        done: ((j['done'] as List?) ?? []).cast<String>().toList(),
        setup: ((j['setup'] as Map?) ?? {}).cast<String, Object?>(),
      );

  Map<String, dynamic> toJson() => {
        'example': example,
        'profile': profile.toJson(),
        'assets': assets.map((e) => e.toJson()).toList(),
        'liabilities': liabilities.map((e) => e.toJson()).toList(),
        'projects': projects.map((e) => e.toJson()).toList(),
        'tx': tx.map((e) => e.toJson()).toList(),
        'recurring': recurring.map((e) => e.toJson()).toList(),
        'budgets': budgets,
        'dismissed': dismissed,
        'done': done,
        'setup': setup,
      };

  AppState copy() => AppState.fromJson(toJson());
}

int nextId(Iterable<int> ids) => ids.fold<int>(0, (m, x) => x > m ? x : m) + 1;
