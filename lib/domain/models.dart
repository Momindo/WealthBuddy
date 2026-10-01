// Data model. Everything stays on the phone; there is no account and nothing that identifies the user.

double? _dn(Object? v) => v == null ? null : (v as num).toDouble();

/// The user's finances. Asked once, reused for every project, editable any time.
class Money {
  double? income; // monthly take-home pay
  double? spending; // monthly spending, excluding loan repayments
  double? savings; // cash reachable within a few days
  double? repayments; // monthly loan instalments (not credit cards)
  double? cardDebt; // credit card balance carried month to month
  double? investments; // optional: shares, funds, gold, crypto that could be sold
  bool? family; // others rely on this income
  bool? variable; // income varies month to month

  Money({this.income, this.spending, this.savings, this.repayments, this.cardDebt, this.investments, this.family, this.variable});

  bool get complete =>
      income != null && spending != null && savings != null && repayments != null && cardDebt != null && family != null && variable != null;

  factory Money.fromJson(Map<String, dynamic> j) => Money(
        income: _dn(j['income']),
        spending: _dn(j['spending']),
        savings: _dn(j['savings']),
        repayments: _dn(j['repayments']),
        cardDebt: _dn(j['cardDebt']),
        investments: _dn(j['investments']),
        family: j['family'] as bool?,
        variable: j['variable'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'income': income, 'spending': spending, 'savings': savings, 'repayments': repayments,
        'cardDebt': cardDebt, 'investments': investments, 'family': family, 'variable': variable,
      };

  Money copy() => Money.fromJson(toJson());
}

/// Money put toward a project after the fact, or set aside when it was created.
/// [to] says where it went: the project pot, the safety cushion (added to savings) or the credit card.
class Contribution {
  final double amount;
  final String source; // Set aside at start | Bonus | Gift | Sold something | Other
  final String date; // yyyy-mm-dd
  final String to; // project | cushion | card
  const Contribution({required this.amount, required this.source, required this.date, this.to = 'project'});

  factory Contribution.fromJson(Map<String, dynamic> j) => Contribution(
        amount: (j['amount'] as num).toDouble(),
        source: j['source'] as String,
        date: j['date'] as String,
        to: (j['to'] as String?) ?? 'project',
      );

  Map<String, dynamic> toJson() => {'amount': amount, 'source': source, 'date': date, 'to': to};
}

/// Something the user wants to afford.
class Project {
  int id;
  String type; // a key of `kinds` in assess.dart
  String name;
  double cost;
  String target; // yyyy-mm, when they want it
  String pay; // savings | loan
  double downPct;
  double rate; // % a year
  int term; // months
  double? rent; // homes only: rent paid today, which stops after buying
  List<Contribution> contributions;

  Project({required this.id, required this.type, required this.name, required this.cost, required this.target, this.pay = 'savings',
      this.downPct = 20, this.rate = 0, this.term = 48, this.rent, List<Contribution>? contributions})
      : contributions = contributions ?? [];

  /// Money held for this project (set aside at the start plus anything added to it).
  double get saved => contributions.where((c) => c.to == 'project').fold<double>(0, (a, c) => a + c.amount);

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: (j['id'] as num).toInt(),
        type: j['type'] as String,
        name: j['name'] as String,
        cost: (j['cost'] as num).toDouble(),
        target: j['target'] as String,
        pay: (j['pay'] as String?) ?? 'savings',
        downPct: _dn(j['downPct']) ?? 20,
        rate: _dn(j['rate']) ?? 0,
        term: (j['term'] as num?)?.toInt() ?? 48,
        rent: _dn(j['rent']),
        contributions: ((j['contributions'] as List?) ?? []).map((e) => Contribution.fromJson((e as Map).cast<String, dynamic>())).toList(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type, 'name': name, 'cost': cost, 'target': target, 'pay': pay, 'downPct': downPct, 'rate': rate, 'term': term, 'rent': rent,
        'contributions': contributions.map((c) => c.toJson()).toList()};

  Project copy() => Project.fromJson(toJson());
}

class AppData {
  Money money;
  List<Project> projects;
  AppData({Money? money, List<Project>? projects})
      : money = money ?? Money(),
        projects = projects ?? [];

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        money: Money.fromJson(((j['money'] as Map?) ?? {}).cast<String, dynamic>()),
        projects: ((j['projects'] as List?) ?? []).map((e) => Project.fromJson((e as Map).cast<String, dynamic>())).toList(),
      );

  Map<String, dynamic> toJson() => {'money': money.toJson(), 'projects': projects.map((p) => p.toJson()).toList()};

  AppData copy() => AppData.fromJson(toJson());

  int nextProjectId() => projects.fold<int>(0, (m, p) => p.id > m ? p.id : m) + 1;

  /// Adds a bonus, gift or other windfall, recorded on the project it was added from.
  /// to = project: held in that project's pot.
  /// to = cushion: added to general savings, which fill the safety cushion first.
  /// to = card: pays down the card balance; anything beyond the balance goes to the project.
  void addMoney(int projectId, double amount, String source, String to, String date) {
    final p = projects.firstWhere((x) => x.id == projectId);
    if (to == 'card') {
      final pay = amount < (money.cardDebt ?? 0) ? amount : (money.cardDebt ?? 0);
      money.cardDebt = (money.cardDebt ?? 0) - pay;
      if (pay > 0) p.contributions.add(Contribution(amount: pay, source: source, date: date, to: 'card'));
      if (amount - pay > 0) p.contributions.add(Contribution(amount: amount - pay, source: source, date: date));
    } else if (to == 'cushion') {
      money.savings = (money.savings ?? 0) + amount;
      p.contributions.add(Contribution(amount: amount, source: source, date: date, to: 'cushion'));
    } else {
      p.contributions.add(Contribution(amount: amount, source: source, date: date));
    }
  }
}
