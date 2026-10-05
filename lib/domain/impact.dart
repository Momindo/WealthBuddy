// What adding or changing a project costs the others: their ready dates before and after,
// and the earliest want-by date for it that keeps everything else on time.
import 'assess.dart';
import 'format.dart';
import 'models.dart';

/// One other project, before and after the change.
class Moved {
  final Project p;
  final Assessment before, after;
  const Moved(this.p, this.before, this.after);
  bool get changed => before.readyIn != after.readyIn || before.verdict != after.verdict;
  bool get later => after.readyIn == null ? before.readyIn != null : (before.readyIn != null && after.readyIn! > before.readyIn!);
  bool get nowMisses => _late(after) && !_late(before);
}

bool _late(Assessment a) => a.readyIn == null || a.readyIn! > a.monthsLeft;

class Impact {
  final List<Moved> others;
  final Assessment mine;
  final String why; // one sentence on why the others move, empty when nothing does
  const Impact(this.others, this.mine, this.why);
  bool get anyMoves => others.any((o) => o.changed);
}

/// [saved]: the data as saved. [mo]: the money answers being saved with it. [p]: the new or edited project.
/// Both sides use [mo], so only the project change shows.
Impact impactOf(AppData saved, Money mo, Project p, {required String today}) {
  final before = saved.copy()..money = mo.copy();
  final after = _withProject(before, p);
  final b = assessAll(before, today: today), a = assessAll(after, today: today);
  final others = [
    for (final o in before.projects)
      if (o.id != p.id) Moved(o, b[o.id]!, a[o.id]!),
  ];
  final mine = a[p.id]!;

  var why = '';
  final pushed = [for (final o in others) if (o.later) o.p.name];
  final sh = mine.share;
  if (pushed.isNotEmpty) {
    final spare = (mo.income ?? 0) - (mo.spending ?? 0) - (mo.repayments ?? 0);
    final until = mine.readyIn == null || mine.readyIn == 0 ? 'The' : 'Until ${monthLabel(addMonths(monthKey(today), mine.readyIn!))} the';
    final takes = sh != null && !sh.waiting && sh.mainAmount > 0 ? 'needs about ${money(sh.mainAmount)} of it' : 'shares it';
    why = 'Spare money is ${money(spare)} a month. $until ${p.name} $takes, so the ${joinNames(pushed)} '
        '${pushed.length == 1 ? 'has' : 'have'} to wait.';
  }
  return Impact(others, mine, why);
}

AppData _withProject(AppData d, Project p) {
  final c = d.copy();
  final i = c.projects.indexWhere((x) => x.id == p.id);
  if (i >= 0) {
    c.projects[i] = p.copy();
  } else {
    c.projects.add(p.copy());
  }
  return c;
}

/// The earliest want-by date, from [p]'s own, that keeps every other project that is on time today on time,
/// with [p] itself on time too. Null when [p]'s date already does, or when nothing within 10 years does.
String? harmlessTarget(AppData saved, Money mo, Project p, {required String today}) {
  final before = saved.copy()..money = mo.copy();
  final b = assessAll(before, today: today);
  final onTimeNow = {for (final o in before.projects) if (o.id != p.id && !_late(b[o.id]!)) o.id};

  bool ok(int k) {
    final q = p.copy()..target = addMonths(p.target, k);
    final a = assessAll(_withProject(before, q), today: today);
    return !_late(a[p.id]!) && onTimeNow.every((id) => !_late(a[id]!));
  }

  if (ok(0)) return null;
  // Gallop out, then narrow down: later dates only ever ease the pressure.
  var hi = 1;
  while (hi <= 120 && !ok(hi)) {
    hi *= 2;
  }
  if (hi > 120) {
    if (!ok(120)) return null;
    hi = 120;
  }
  var lo = hi ~/ 2; // ok(lo) is false (or lo is 0)
  while (hi - lo > 1) {
    final mid = (lo + hi) ~/ 2;
    if (ok(mid)) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return addMonths(p.target, hi);
}
