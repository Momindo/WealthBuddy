// Bank SMS and statement parsing. Pure Dart, runs on the device; nothing is uploaded.
import 'basics.dart';
import 'models.dart';

// ---------- Dates and amounts ----------
const _mon = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12};

String? isoDate(int y, int m, int d) {
  if (y < 100) y += 2000;
  if (m < 1 || m > 12 || d < 1) return null;
  final dt = DateTime(y, m, d);
  if (dt.month != m || dt.day != d) return null; // rejects 31/02
  return isoOf(dt);
}

/// Parses day-first dates (UAE banks), ISO dates, "3-Sep-26", Excel serials and DateTime values.
String? parseDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return isoDate(v.year, v.month, v.day);
  if (v is num && v > 30000 && v < 60000) {
    final d = DateTime.utc(1899, 12, 30).add(Duration(days: v.round()));
    return isoDate(d.year, d.month, d.day);
  }
  final t = v.toString().trim();
  var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
  if (m != null) return isoDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  m = RegExp(r'^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})').firstMatch(t);
  if (m != null) return isoDate(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  m = RegExp(r'^(\d{1,2})[\s\-]?([A-Za-z]{3,4})[a-z]*[\s\-,]*(\d{2,4})').firstMatch(t);
  if (m != null) {
    final mo = _mon[m[2]!.toLowerCase()];
    if (mo != null) return isoDate(int.parse(m[3]!), mo, int.parse(m[1]!));
  }
  return null;
}

class Amount {
  final double n;
  final bool minus, cr, dr;
  const Amount(this.n, {this.minus = false, this.cr = false, this.dr = false});
}

Amount? parseAmount(Object? v) {
  if (v == null) return null;
  if (v is num) return Amount(v.abs().toDouble(), minus: v < 0);
  final t = v.toString().trim();
  if (t.isEmpty) return null;
  final n = double.tryParse(t.replaceAll(RegExp(r'[^\d.]'), ''));
  if (n == null) return null;
  return Amount(n,
      minus: RegExp(r'^-|^\(.*\)$|-$').hasMatch(t),
      cr: RegExp(r'\bcr\b', caseSensitive: false).hasMatch(t),
      dr: RegExp(r'\bdr\b', caseSensitive: false).hasMatch(t));
}

String cleanMerchant(String d) {
  var m = d
      .replaceAll(RegExp(r'\b(POS|PURCHASE|PUR|DEBIT CARD|CREDIT CARD|CARD NO\.?|CARD ENDING|TXN|REF(?:ERENCE)?|AUTH(?:ORI[SZ]ATION)?)\b[:#]?', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b(USD|EUR|GBP|INR|SAR|PKR)\s?[\d,]+\.\d{2}\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'[\w*]*\d{4,}[\w*]*'), ' ')
      .replaceAll(RegExp(r'[*#]+'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  final trailing = RegExp(r'[\s,]+(DUBAI|ABU ?DHABI|SHARJAH|AJMAN|AL AIN|UAE|ARE|AE)\.?$', caseSensitive: false);
  for (var k = 0; k < 3; k++) {
    m = m.replaceAll(trailing, '').trim();
  }
  if (m.isEmpty) m = d.trim();
  return m
      .toLowerCase()
      .replaceAllMapped(RegExp(r'(^|[\s\-\/&])([a-z])'), (x) => '${x[1]}${x[2]!.toUpperCase()}')
      .replaceAllMapped(RegExp(r'\.(com|ae)\b', caseSensitive: false), (x) => x[0]!.toLowerCase());
}

// ---------- SMS ----------
class SmsResult {
  final String date, merchant, cat, cur;
  final double amount;
  const SmsResult(this.date, this.merchant, this.amount, this.cat, this.cur);
}

SmsResult? parseSms(String txt, {required String today}) {
  final m = RegExp(r'\b(AED|USD|EUR|GBP)\s?([\d,]+(?:\.\d{1,2})?)', caseSensitive: false).firstMatch(txt);
  if (m == null) return null;
  final cur = m[1]!.toUpperCase(), amt = double.parse(m[2]!.replaceAll(',', ''));
  final credit = RegExp(r'credited|received|deposit', caseSensitive: false).hasMatch(txt);
  final mer = RegExp(r'\b(?:at|from)\s+(.+?)(?:\s+on\b|\s+dated\b|[.,]|\s+Avl|\s+Available|$)', caseSensitive: false).firstMatch(txt)?[1];
  final d = RegExp(r'(\d{2})[\/-](\d{2})[\/-](\d{2,4})').firstMatch(txt);
  var date = today;
  if (d != null) {
    final y = d[3]!.length == 2 ? '20${d[3]}' : d[3]!;
    date = '$y-${d[2]}-${d[1]}';
  }
  var merchant = (mer ?? (credit ? 'Incoming transfer' : 'Unknown merchant')).trim().replaceAll(RegExp(r'\s{2,}'), ' ');
  if (credit && RegExp(r'salary|payroll|wps', caseSensitive: false).hasMatch(txt)) merchant = 'Salary';
  return SmsResult(date, merchant, (credit ? 1 : -1) * toAed(amt, cur), credit ? 'Income' : guessCat(merchant), cur);
}

// ---------- Statements ----------
class RawEntry {
  final String date, desc;
  final double n;
  final bool minus, cr, dr;
  final double? bal;
  const RawEntry(this.date, this.desc, this.n, {this.minus = false, this.cr = false, this.dr = false, this.bal});
}

List<List<String>> parseCsv(String text) {
  final head = text.split(RegExp(r'\r?\n')).take(5).join('\n');
  final delims = [',', ';', '\t']..sort((a, b) => head.split(b).length.compareTo(head.split(a).length));
  final d = delims.first;
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var q = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (q) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      q = true;
    } else if (c == d) {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}

/// Rows from a CSV or spreadsheet. Finds the header row itself; handles one amount column
/// or separate debit and credit columns. Returns null when no header is found.
List<RawEntry>? rowsToRaw(List<List<Object?>> rows) {
  bool hasDate(List<Object?> r) => r.any((c) => RegExp(r'date', caseSensitive: false).hasMatch('${c ?? ''}'));
  bool hasAmt(List<Object?> r) => r.any((c) => RegExp(r'amount|debit|credit|withdraw|deposit', caseSensitive: false).hasMatch('${c ?? ''}'));
  final hIdx = rows.take(20).toList().indexWhere((r) => hasDate(r) && hasAmt(r));
  if (hIdx < 0) return null;
  final head = rows[hIdx].map((c) => '${c ?? ''}'.toLowerCase().trim()).toList();
  int col(String rx) => head.indexWhere((h) => RegExp(rx).hasMatch(h));
  var cDate = col(r'^(transaction|txn|trans\.?)\s*date');
  if (cDate < 0) cDate = col(r'date');
  final cDesc = col(r'desc|detail|narrat|particular|merchant|remark');
  final cAmt = head.indexWhere((h) => RegExp(r'amount').hasMatch(h) && !RegExp(r'balance|foreign|original').hasMatch(h));
  final cDr = col(r'^(debit|withdrawal)s?\b|\bdr\b|money out'), cCr = col(r'^(credit|deposit)s?\b|\bcr\b|money in');
  final cBal = col(r'balance');
  Object? at(List<Object?> r, int i) => i >= 0 && i < r.length ? r[i] : null;
  final out = <RawEntry>[];
  for (final r in rows.skip(hIdx + 1)) {
    final date = parseDate(at(r, cDate));
    if (date == null) continue;
    final desc = '${at(r, cDesc < 0 ? cDate + 1 : cDesc) ?? ''}'.trim();
    if (desc.isEmpty) continue;
    Amount? a;
    if (cDr >= 0 || cCr >= 0) {
      final dr = cDr >= 0 ? parseAmount(at(r, cDr)) : null, cr = cCr >= 0 ? parseAmount(at(r, cCr)) : null;
      if (dr != null && dr.n != 0) {
        a = Amount(dr.n, dr: true);
      } else if (cr != null && cr.n != 0) {
        a = Amount(cr.n, cr: true);
      }
    }
    if (a == null && cAmt >= 0) a = parseAmount(at(r, cAmt));
    if (a == null || a.n == 0) continue;
    final bal = cBal >= 0 ? parseAmount(at(r, cBal)) : null;
    out.add(RawEntry(date, desc, a.n, minus: a.minus, cr: a.cr, dr: a.dr, bal: bal == null ? null : bal.n * (bal.minus ? -1 : 1)));
  }
  return out;
}

/// Text lines (from a PDF) that start with a date and end with amounts. Skips a posting date,
/// and ignores foreign-currency amounts in the description ("USD 20.00").
List<RawEntry> linesToRaw(List<String> lines) {
  final date = RegExp(r'^(\d{1,2}[\/\-.]\d{1,2}[\/\-.]\d{2,4}|\d{1,2}[\s\-]?[A-Za-z]{3,4}[\s\-,]*\d{2,4}|\d{4}-\d{2}-\d{2})\s+');
  final amt = RegExp(r'\(?-?[\d,]*\d\.\d{2}\)?-?(?:\s?(?:CR|DR|Cr|Dr|cr|dr)\b)?');
  final fxBefore = RegExp(r'(USD|EUR|GBP|INR|SAR|PKR)\s?$', caseSensitive: false);
  final out = <RawEntry>[];
  for (final line in lines) {
    final m = date.firstMatch(line);
    if (m == null) continue;
    final d = parseDate(m[1]);
    if (d == null) continue;
    var rest = line.substring(m.end);
    final m2 = date.firstMatch(rest);
    if (m2 != null && parseDate(m2[1]) != null) rest = rest.substring(m2.end);
    final amts = amt.allMatches(rest).where((x) => !fxBefore.hasMatch(rest.substring(x.start - 5 < 0 ? 0 : x.start - 5, x.start))).toList();
    if (amts.isEmpty) continue;
    final desc = rest.substring(0, amts.first.start).trim();
    if (desc.isEmpty) continue;
    final a = parseAmount(amts.first[0])!;
    final b = amts.length >= 2 ? parseAmount(amts.last[0]) : null;
    out.add(RawEntry(d, desc, a.n, minus: a.minus, cr: a.cr, dr: a.dr, bal: b == null ? null : b.n * (b.minus ? -1 : 1)));
  }
  return out;
}

class ImportRow {
  final String date;
  String merchant, cat;
  double amount;
  final String status; // new | dup | skip
  final String reason;
  bool selected;
  ImportRow(this.date, this.merchant, this.cat, this.amount, this.status, this.reason) : selected = status == 'new';
}

final _transferRx = RegExp(
    r'payment received|thank you|card payment|cc payment|credit card payment|payment to (?:card|credit)|transfer to (?:own|card)|own account|autopay|direct debit.*card',
    caseSensitive: false);
final _balanceRx = RegExp(
    r'opening balance|closing balance|balance b\/?f|balance c\/?f|brought forward|carried forward|^total\b|statement balance|minimum (?:amount|payment) due',
    caseSensitive: false);
final _creditWords = RegExp(r'salary|payroll|wps|deposit|refund|reversal|received|transfer from|credited', caseSensitive: false);
final _salary = RegExp(r'salary|payroll|wps', caseSensitive: false);

/// Decides sign, category and whether to skip each entry. [kind] is `card` or `bank`.
/// Card payments and own-account transfers are skipped so money isn't counted twice;
/// entries already in [existing] (same date and amount) are marked as duplicates.
List<ImportRow> classify(List<RawEntry> raw, String kind, List<Tx> existing) {
  double? prevBal;
  final out = <ImportRow>[];
  for (final r in raw) {
    if (_balanceRx.hasMatch(r.desc)) {
      prevBal = r.bal ?? r.n;
      continue;
    }
    double amt;
    if (kind == 'card') {
      amt = (r.cr || r.minus) ? r.n : -r.n;
    } else if (r.dr || r.minus) {
      amt = -r.n;
    } else if (r.cr) {
      amt = r.n;
    } else if (r.bal != null && prevBal != null) {
      amt = (r.bal! < prevBal ? -1 : 1) * r.n;
    } else {
      amt = _creditWords.hasMatch(r.desc) ? r.n : -r.n;
    }
    if (r.bal != null) prevBal = r.bal;
    final merchant = _salary.hasMatch(r.desc) && amt > 0 ? 'Salary' : cleanMerchant(r.desc);
    final cat = amt > 0 ? 'Income' : guessCat(r.desc);
    var status = 'new', reason = '';
    if (_transferRx.hasMatch(r.desc)) {
      status = 'skip';
      reason = kind == 'card' ? 'Card payment, already counted as spending when you bought things' : 'Transfer between your own accounts';
    } else if (existing.any((t) => t.date == r.date && (t.amount.abs() - r.n).abs() < 0.01)) {
      status = 'dup';
      reason = 'Already in your transactions';
    }
    out.add(ImportRow(r.date, merchant, cat, round2(amt), status, reason));
  }
  return out;
}

String guessKind(String text) =>
    RegExp(r'credit card|card statement|minimum (?:amount|payment)|payment due date|credit limit', caseSensitive: false).hasMatch(text) ? 'card' : 'bank';
