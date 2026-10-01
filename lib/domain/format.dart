// Formatting and month helpers.
import 'dart:math' as math;

/// Whole or decimal number with thousands separators, e.g. 25,000 or 1,234.50.
String fmt(double n, [int dp = 0]) {
  if (n.abs() < 0.5 / math.pow(10, dp)) return '0';
  final neg = n < 0;
  final scaled = (n.abs() * math.pow(10, dp) + 0.5).floor();
  final s = scaled.toString().padLeft(dp + 1, '0');
  final whole = dp > 0 ? s.substring(0, s.length - dp) : s;
  final frac = dp > 0 ? s.substring(s.length - dp) : '';
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return '${neg ? '-' : ''}$grouped${dp > 0 ? '.$frac' : ''}';
}

String money(double n, [int dp = 0]) => 'AED ${fmt(n, dp)}';

/// 20 -> "20", 3.5 -> "3.5"
String num1(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

double roundUp(double v, double step) => (v / step).ceilToDouble() * step;
double roundDown(double v, double step) => (v / step).floorToDouble() * step;

String isoOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String todayIso() => isoOf(DateTime.now());

/// yyyy-mm from yyyy-mm-dd
String monthKey(String iso) => iso.substring(0, 7);

/// yyyy-mm plus [n] months.
String addMonths(String ym, int n) {
  final total = int.parse(ym.substring(0, 4)) * 12 + int.parse(ym.substring(5, 7)) - 1 + n;
  return '${total ~/ 12}-${(total % 12 + 1).toString().padLeft(2, '0')}';
}

/// Whole months from the month of [todayIso] to [targetYm].
int monthsUntil(String todayIso, String targetYm) {
  int idx(String ym) => int.parse(ym.substring(0, 4)) * 12 + int.parse(ym.substring(5, 7));
  return idx(targetYm) - idx(monthKey(todayIso));
}

const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "2027-03" -> "Mar 2027"
String monthLabel(String ym) => '${_short[int.parse(ym.substring(5, 7)) - 1]} ${ym.substring(0, 4)}';

/// 6 -> "6 months", 24 -> "2 years", 18 -> "18 months"
String durationLabel(int months) {
  if (months >= 24 && months % 12 == 0) return '${months ~/ 12} years';
  if (months == 12) return '1 year';
  return '$months month${months == 1 ? '' : 's'}';
}
