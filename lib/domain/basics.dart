// Constants and small helpers shared by the engines.
import 'dart:math' as math;

/// Demo conversion rates to AED. GOLD_G is AED per gram of 24k gold.
/// Replaced by a live price feed in a later milestone.
const Map<String, double> fx = {'AED': 1, 'USD': 3.6725, 'EUR': 4.30, 'GBP': 4.90, 'INR': 0.0418, 'PKR': 0.0131, 'GOLD_G': 400};

double toAed(double amount, String cur) => amount * (fx[cur] ?? 1);

const List<String> categories = [
  'Rent', 'Groceries', 'Dining', 'Transport', 'Bills', 'Education', 'Home help', 'Subscriptions', 'Shopping', 'Health', 'Other'
];

const Map<String, double> defaultBudgets = {
  'Rent': 9500, 'Groceries': 1800, 'Dining': 900, 'Transport': 2600, 'Bills': 1400, 'Education': 3000, 'Home help': 0,
  'Subscriptions': 300, 'Shopping': 1000, 'Health': 400, 'Other': 500,
};

const Map<String, String> assetTypes = {
  'cash': 'Cash & bank', 'investment': 'Investments', 'property': 'Property', 'gold': 'Gold', 'crypto': 'Crypto', 'other': 'Other'
};

const Map<String, String> paymentMethods = {'cash': 'Cash', 'card': 'Card', 'transfer': 'Bank transfer', 'cheque': 'Cheque'};

class Band {
  final String key, label;
  final double mid;
  const Band(this.key, this.label, this.mid);
}

const List<Band> incomeBands = [
  Band('u10', 'Under 10k', 7500), Band('10-20', '10–20k', 15000), Band('20-35', '20–35k', 27500), Band('35-60', '35–60k', 47500), Band('60+', '60k+', 75000),
];
const List<Band> ageBands = [Band('u30', 'Under 30', 26), Band('30-45', '30–45', 37), Band('45-60', '45–60', 52), Band('60+', '60+', 65)];

/// Rounds like JavaScript's Math.round, so results match the prototype exactly.
double jsRound(double x) => (x + 0.5).floorToDouble();
double round2(double x) => jsRound(x * 100) / 100;

// ---------- Months ----------
String monthKey(String isoDate) => isoDate.substring(0, 7);
String nextMonth(String k) {
  final y = int.parse(k.substring(0, 4)), m = int.parse(k.substring(5));
  return m == 12 ? '${y + 1}-01' : '$y-${(m + 1).toString().padLeft(2, '0')}';
}
String isoOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _monthsLong = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String monthLong(String k) => _monthsLong[int.parse(k.substring(5, 7)) - 1];
String monthShort(String k) => _monthsShort[int.parse(k.substring(5, 7)) - 1];
String monthYear(String k) => '${monthShort(k)} ${k.substring(0, 4)}';
String dayLabel(String isoDate) => '${int.parse(isoDate.substring(8, 10))} ${monthShort(isoDate)}';

/// Month label `m` months after [from] (yyyy-mm), e.g. "Sep 2027".
String monthsAhead(String from, int m) {
  final y = int.parse(from.substring(0, 4)), mo = int.parse(from.substring(5, 7)) - 1 + m;
  return '${_monthsShort[mo % 12]} ${y + mo ~/ 12}';
}

// ---------- Money ----------
String fmt(double n, [int dp = 0]) {
  if (n.abs() < 0.5 / math.pow(10, dp)) return '0';
  final neg = n < 0;
  final scaled = (n.abs() * math.pow(10, dp) + 0.5).floor(); // half away from zero, like Intl
  var s = scaled.toString().padLeft(dp + 1, '0');
  final whole = dp > 0 ? s.substring(0, s.length - dp) : s;
  final frac = dp > 0 ? s.substring(s.length - dp) : '';
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return '${neg ? '-' : ''}$grouped${dp > 0 ? '.$frac' : ''}';
}
String money(double n, [int dp = 0]) => 'AED ${fmt(n, dp)}';

// ---------- Categories ----------
final List<(RegExp, String)> _catRules = [
  (RegExp(r'netflix|spotify|osn|shahid|anghami|youtube premium|fitness first|gym|icloud|apple\.com\/bill|google \*|disney', caseSensitive: false), 'Subscriptions'),
  (RegExp(r'rent|landlord|ejari|tenancy', caseSensitive: false), 'Rent'),
  (RegExp(r'maid|nanny|housekeeper|driver salary|cleaner|home help', caseSensitive: false), 'Home help'),
  (RegExp(r'school|nursery|gems |taaleem|aldar academ|kindergarten|tuition', caseSensitive: false), 'Education'),
  (RegExp(r'carrefour|lulu|spinneys|waitrose|union coop|grocery', caseSensitive: false), 'Groceries'),
  (RegExp(r'talabat|deliveroo|careem food|restaurant|cafe|coffee|zuma', caseSensitive: false), 'Dining'),
  (RegExp(r'adnoc|enoc|salik|careem|uber|rta|nol|instalment', caseSensitive: false), 'Transport'),
  (RegExp(r'dewa|addc|etisalat|e&|du\b|sewa', caseSensitive: false), 'Bills'),
  (RegExp(r'noon|amazon|ikea|mall|namshi|duty free|centrepoint|max fashion', caseSensitive: false), 'Shopping'),
  (RegExp(r'pharmacy|clinic|hospital|aster', caseSensitive: false), 'Health'),
];

String guessCat(String merchant) {
  for (final (rx, cat) in _catRules) {
    if (rx.hasMatch(merchant)) return cat;
  }
  return 'Other';
}
