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
  int? payday; // day of the month salary arrives (1–31), 0 = it varies, null = not asked yet
  String? asOf; // yyyy-mm-dd the savings and card answers were given; plans assume they've been followed since
  String? lastCheckIn; // yyyy-mm-dd of the last monthly check-in

  Money({this.income, this.spending, this.savings, this.repayments, this.cardDebt, this.investments, this.family, this.variable, this.payday, this.asOf, this.lastCheckIn});

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
        payday: (j['payday'] as num?)?.toInt(),
        asOf: j['asOf'] as String?,
        lastCheckIn: j['lastCheckIn'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'income': income, 'spending': spending, 'savings': savings, 'repayments': repayments,
        'cardDebt': cardDebt, 'investments': investments, 'family': family, 'variable': variable, 'payday': payday, 'asOf': asOf, 'lastCheckIn': lastCheckIn,
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

/// One point in a project's history: on [date] the plan said it would be ready in [ready] (yyyy-mm, null = out of reach).
class HistoryPoint {
  final String date; // yyyy-mm-dd
  final String? ready;
  final String why;
  const HistoryPoint({required this.date, required this.ready, required this.why});

  factory HistoryPoint.fromJson(Map<String, dynamic> j) =>
      HistoryPoint(date: j['date'] as String, ready: j['ready'] as String?, why: (j['why'] as String?) ?? '');

  Map<String, dynamic> toJson() => {'date': date, 'ready': ready, 'why': why};
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
  String? priceDate; // yyyy-mm-dd the cost (and loan rate) were last set or confirmed
  List<Contribution> contributions;
  List<HistoryPoint> history; // how the ready date has moved

  Project({required this.id, required this.type, required this.name, required this.cost, required this.target, this.pay = 'savings',
      this.downPct = 20, this.rate = 0, this.term = 48, this.rent, this.priceDate, List<Contribution>? contributions, List<HistoryPoint>? history})
      : contributions = contributions ?? [],
        history = history ?? [];

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
        priceDate: j['priceDate'] as String?,
        contributions: ((j['contributions'] as List?) ?? []).map((e) => Contribution.fromJson((e as Map).cast<String, dynamic>())).toList(),
        history: ((j['history'] as List?) ?? []).map((e) => HistoryPoint.fromJson((e as Map).cast<String, dynamic>())).toList(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type, 'name': name, 'cost': cost, 'target': target, 'pay': pay, 'downPct': downPct, 'rate': rate, 'term': term, 'rent': rent, 'priceDate': priceDate,
        'contributions': contributions.map((c) => c.toJson()).toList(), 'history': history.map((h) => h.toJson()).toList()};

  Project copy() => Project.fromJson(toJson());
}

/// App preferences. Stored with the rest of the data, encrypted.
class Settings {
  String theme; // system | light | dark
  bool privacySeen; // the first-launch privacy pop-up has been shown
  bool reminders; // payday reminder at 3 pm
  bool appLock; // ask for fingerprint, face or device PIN when the app opens
  bool tourSeen; // the feature tour after the privacy pop-up has been shown
  String? paydayDone; // yyyy-mm-dd of the payday whose card was marked done
  List<int> celebrated; // projects already celebrated as affordable

  Settings({this.theme = 'system', this.privacySeen = false, this.reminders = true, this.appLock = false, this.tourSeen = false, this.paydayDone, List<int>? celebrated})
      : celebrated = celebrated ?? [];

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        theme: (j['theme'] as String?) ?? 'system',
        privacySeen: (j['privacySeen'] as bool?) ?? false,
        reminders: (j['reminders'] as bool?) ?? true,
        appLock: (j['appLock'] as bool?) ?? false,
        // People who already saw the privacy pop-up before the tour existed don't get it on update.
        tourSeen: (j['tourSeen'] as bool?) ?? ((j['privacySeen'] as bool?) ?? false),
        paydayDone: j['paydayDone'] as String?,
        celebrated: ((j['celebrated'] as List?) ?? []).map((e) => (e as num).toInt()).toList(),
      );

  Map<String, dynamic> toJson() =>
      {'theme': theme, 'privacySeen': privacySeen, 'reminders': reminders, 'appLock': appLock, 'tourSeen': tourSeen, 'paydayDone': paydayDone, 'celebrated': celebrated};
}

class AppData {
  Money money;
  List<Project> projects;
  Settings settings;
  /// Projects are planned together by default (see plan.dart). These are the exceptions:
  List<int> solo; // planned on their own, as if the others didn't exist
  List<int> pinned; // saving from the start even if that makes others wait
  AppData({Money? money, List<Project>? projects, Settings? settings, List<int>? solo, List<int>? pinned})
      : money = money ?? Money(),
        projects = projects ?? [],
        settings = settings ?? Settings(),
        solo = solo ?? [],
        pinned = pinned ?? [];

  static List<int> _ids(Object? v) => ((v as List?) ?? []).map((e) => (e as num).toInt()).toList();

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        money: Money.fromJson(((j['money'] as Map?) ?? {}).cast<String, dynamic>()),
        projects: ((j['projects'] as List?) ?? []).map((e) => Project.fromJson((e as Map).cast<String, dynamic>())).toList(),
        settings: Settings.fromJson(((j['settings'] as Map?) ?? {}).cast<String, dynamic>()),
        solo: _ids(j['solo']),
        pinned: _ids(j['pinned']),
      );

  Map<String, dynamic> toJson() => {
        'money': money.toJson(),
        'projects': projects.map((p) => p.toJson()).toList(),
        'settings': settings.toJson(),
        'solo': solo,
        'pinned': pinned,
      };

  AppData copy() => AppData.fromJson(toJson());

  /// The projects planned together (empty unless there are at least two).
  List<Project> plannedProjects() {
    final list = projects.where((p) => !solo.contains(p.id)).toList();
    return list.length >= 2 ? list : [];
  }

  bool isPlanned(int id) => plannedProjects().any((p) => p.id == id);

  void setSolo(int id, bool on) {
    solo.remove(id);
    pinned.remove(id);
    if (on) solo.add(id);
  }

  void setPinned(int id, bool on) {
    pinned.remove(id);
    if (on) pinned.add(id);
  }

  void removeProject(int id) {
    projects.removeWhere((p) => p.id == id);
    solo.remove(id);
    pinned.remove(id);
  }

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
