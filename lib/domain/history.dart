// Plan history: how each project's ready date has moved, and why.
// A point is added only when the ready month changes. Changes the user makes carry their reason;
// a move found just before a change, with nothing new entered, is put down to time passing.
import 'assess.dart';
import 'format.dart';
import 'models.dart';

const int historyCap = 60; // points kept per project
const String timePassed = 'Time passed with the same answers';

/// The ready month for a project's plan today, or null when it's out of reach.
String? readyMonth(Assessment a, String today) => a.readyIn == null ? null : addMonths(monthKey(today), a.readyIn!);

/// Adds a point to every project whose ready month differs from its last point.
/// Projects with no history yet get [first] instead of [why].
void recordHistory(AppData d, {required String today, required String why, String first = 'Started'}) {
  if (!d.money.complete || d.projects.isEmpty) return;
  final all = assessAll(d, today: today);
  for (final p in d.projects) {
    final ready = readyMonth(all[p.id]!, today);
    final h = p.history;
    if (h.isNotEmpty && h.last.ready == ready) continue;
    h.add(HistoryPoint(date: today, ready: ready, why: h.isEmpty ? first : why));
    if (h.length > historyCap) h.removeRange(1, h.length - historyCap + 1); // keep the first point
  }
}

/// Months between two ready months: positive = later, negative = sooner. Null when either is out of reach.
int? monthsMoved(String? from, String? to) => from == null || to == null ? null : monthsUntil('$from-01', to);

/// "3 months sooner since you started", "2 months later since you started", or null when it hasn't moved.
String? sinceStart(Project p) {
  final h = p.history;
  if (h.length < 2) return null;
  final m = monthsMoved(h.first.ready, h.last.ready);
  if (m == null) return h.last.ready == null ? 'Out of reach since ${_day(h.last.date)}' : 'Within reach since ${_day(h.last.date)}';
  if (m == 0) return null;
  return '${durationLabel(m.abs())} ${m < 0 ? 'sooner' : 'later'} since you started';
}

/// The single change that moved the date the most in the wrong direction, if the date is later than at the start.
HistoryPoint? biggestSetback(Project p) {
  final h = p.history;
  HistoryPoint? worst;
  var worstBy = 0;
  for (var i = 1; i < h.length; i++) {
    final m = monthsMoved(h[i - 1].ready, h[i].ready) ?? (h[i].ready == null ? 1000 : 0);
    if (m > worstBy) {
      worstBy = m;
      worst = h[i];
    }
  }
  return worst;
}

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _day(String iso) => '${int.parse(iso.substring(8, 10))} ${_mon[int.parse(iso.substring(5, 7)) - 1]} ${iso.substring(0, 4)}';
String dayLabel(String iso) => _day(iso);
