/// Finans hesaplarının saf mantığı (arayüzden bağımsız, testli).
///
/// Tutarlar hesaplayıcılarda `double`, kayıt tutan araçlarda kuruş (`int`)
/// olarak tutulur. Yasal oran ve endeks tabloları tarihleriyle birliktedir;
/// kullanıcı ekranda değiştirebilir.
library;

import 'dart:math' as math;

// ------------------------------------------------------------ biçimlendirme

/// Ondalık ayırıcısı nokta olan diller (diğerlerinde virgül).
const Set<String> _dotLangs = {'en', 'he', 'ja', 'ko', 'zh', 'hi', 'bn', 'th', 'ms', 'fil', 'ur', 'ar', 'fa'};

/// 2 basamaklı, binlik ayraçlı tutar. [sym] boşsa simge yazılmaz.
String fmtMoney(double v, String lang, [String sym = '']) {
  final dot = _dotLangs.contains(lang);
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(2);
  final parts = s.split('.');
  final digits = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(dot ? ',' : '.');
    b.write(digits[i]);
  }
  final text = '${neg ? '-' : ''}$b${dot ? '.' : ','}${parts[1]}';
  if (sym.isEmpty) return text;
  return '$text $sym';
}

/// Kuruştan biçimli tutar.
String fmtCents(int cents, String lang, [String sym = '']) => fmtMoney(cents / 100, lang, sym);

/// Yüzde gösterimi (iki basamak).
String fmtPct(double v) => '%${v.toStringAsFixed(2)}';

/// Dile göre önerilen para simgesi (kullanıcı değiştirebilir).
String defaultCurrency(String lang) => const {
      'tr': '₺', 'en': r'$', 'de': '€', 'es': '€', 'fr': '€', 'ar': '', 'fa': '', 'he': '₪', 'ur': 'Rs',
      'ru': '₽', 'uk': '₴', 'pl': 'zł', 'cs': 'Kč', 'ro': 'lei', 'hu': 'Ft', 'el': '€', 'it': '€', 'pt': '€',
      'nl': '€', 'sv': 'kr', 'da': 'kr', 'nb': 'kr', 'fi': '€', 'ja': '¥', 'ko': '₩', 'zh': '¥', 'hi': '₹',
      'bn': '৳', 'id': 'Rp', 'ms': 'RM', 'th': '฿', 'vi': '₫', 'fil': '₱',
    }[lang] ??
    '';

/// Metinden kuruş (geçersizse null). Arapça/Farsça rakamları da kabul eder.
int? parseCents(String raw) {
  var s = raw.trim();
  const sets = ['٠١٢٣٤٥٦٧٨٩', '۰۱۲۳۴۵۶۷۸۹'];
  for (final set in sets) {
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(set[i], '$i');
    }
  }
  s = s.replaceAll('٫', '.').replaceAll('٬', '').replaceAll(' ', '').replaceAll(' ', '');
  if (s.isEmpty || !RegExp(r'^[0-9.,]+$').hasMatch(s)) return null;
  final sep = math.max(s.lastIndexOf(','), s.lastIndexOf('.'));
  final frac = sep >= 0 && s.length - sep - 1 <= 2;
  final whole = (frac ? s.substring(0, sep) : s).replaceAll(',', '').replaceAll('.', '');
  final f = frac ? s.substring(sep + 1).padRight(2, '0') : '00';
  if (whole.isEmpty && f == '00') return null;
  final w = int.tryParse(whole.isEmpty ? '0' : whole);
  final c = int.tryParse(f);
  if (w == null || c == null || w > 100000000000) return null;
  return w * 100 + c;
}

// --------------------------------------------------------------- kredi

class LoanRow {
  final int no;
  final double payment, interest, tax, principal, balance;
  const LoanRow(this.no, this.payment, this.interest, this.tax, this.principal, this.balance);
}

class LoanResult {
  final double payment;
  final List<LoanRow> rows;
  const LoanResult(this.payment, this.rows);
  double get total => rows.fold<double>(0, (a, r) => a + r.payment);
  double get interest => rows.fold<double>(0, (a, r) => a + r.interest);
  double get tax => rows.fold<double>(0, (a, r) => a + r.tax);
}

/// Eşit taksitli (anüite) kredi. [monthlyRate] ör. 0.03; [taxRate] faize
/// eklenen vergi oranı (TR tüketici kredisinde KKDF %15 + BSMV %15 = 0.30).
LoanResult loan(double principal, double monthlyRate, int months, {double taxRate = 0}) {
  if (principal <= 0 || months < 1 || months > 600 || monthlyRate < 0) return const LoanResult(0, []);
  final r = monthlyRate * (1 + taxRate);
  final pay = r == 0 ? principal / months : principal * r / (1 - math.pow(1 + r, -months));
  var bal = principal;
  final rows = <LoanRow>[];
  for (var i = 1; i <= months; i++) {
    final interest = bal * monthlyRate;
    final tax = interest * taxRate;
    var p = pay - interest - tax;
    if (i == months) p = bal;
    bal = math.max(0.0, bal - p);
    rows.add(LoanRow(i, p + interest + tax, interest, tax, p, bal));
  }
  return LoanResult(pay, rows);
}

// ------------------------------------------------------ faiz ve birikim

class GrowthResult {
  final double finalValue, deposited, grossInterest, tax;
  final List<double> yearly;
  const GrowthResult(this.finalValue, this.deposited, this.grossInterest, this.tax, this.yearly);
  double get earned => finalValue - deposited;
}

/// Aylık bileşik getiri; her ayın sonunda [monthly] katkı eklenir. Getiri
/// üzerinden [withholding] oranında stopaj kesilir.
GrowthResult grow(double initial, double monthly, double annualRate, int months, {double withholding = 0}) {
  final r = annualRate / 12;
  var v = initial, dep = initial, gross = 0.0, tax = 0.0;
  final yearly = <double>[];
  for (var m = 1; m <= months; m++) {
    final i = v * r;
    final t = i * withholding;
    gross += i;
    tax += t;
    v += i - t + monthly;
    dep += monthly;
    if (m % 12 == 0 || m == months) yearly.add(v);
  }
  return GrowthResult(v, dep, gross, tax, yearly);
}

// ----------------------------------------------------------- KDV/indirim

/// İndirimli fiyat: art arda indirimler (ör. %20 + %10 = %28).
double discounted(double price, List<double> pcts) {
  var p = price;
  for (final x in pcts) {
    p *= 1 - x / 100;
  }
  return p;
}

/// KDV: [included] ise fiyat KDV dahildir. (hariç, kdv, dahil) döndürür.
(double, double, double) vat(double price, double rate, {required bool included}) {
  if (included) {
    final net = price / (1 + rate / 100);
    return (net, price - net, price);
  }
  final tax = price * rate / 100;
  return (price, tax, price + tax);
}

// ----------------------------------------------------- hesap bölüşme

/// (bahşiş, toplam, kişi başı). [roundUp] kişi başını tama yukarı yuvarlar.
(double, double, double) split(double bill, double tipPct, int people, {bool roundUp = false}) {
  final n = math.max(1, people);
  final tip = bill * tipPct / 100;
  var each = (bill + tip) / n;
  if (roundUp) each = each.ceilToDouble();
  return (tip, each * n, each);
}

// ------------------------------------------------------------- taksit

/// Peşin fiyat [cash] ile [n] adet [inst] taksidin aylık etkin faizi (IRR).
/// Taksitli toplam peşinden azsa negatif olabilir.
double effectiveMonthlyRate(double cash, double inst, int n) {
  if (cash <= 0 || inst <= 0 || n < 1) return 0;
  double pv(double r) => r.abs() < 1e-12 ? inst * n : inst * (1 - math.pow(1 + r, -n)) / r;
  var lo = -0.99, hi = 10.0;
  for (var i = 0; i < 200; i++) {
    final mid = (lo + hi) / 2;
    if (pv(mid) > cash) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// Taksitleri bugünkü değere indirger: parayı aylık [rate] getiriyle
/// tutsaydınız taksitlerin bugünkü karşılığı.
double presentValue(double inst, int n, double rate) =>
    rate.abs() < 1e-12 ? inst * n : inst * (1 - math.pow(1 + rate, -n)) / rate;

// ---------------------------------------------------------- kredi kartı

class PayoffResult {
  final int months; // -1: bu ödemeyle bitmez
  final double interest, tax, total;
  const PayoffResult(this.months, this.interest, this.tax, this.total);
}

/// Kart borcu: her ay faiz (+vergi) eklenir, [payment] ödenir; [minPct] > 0
/// ise ödeme en az borcun o yüzdesi kadardır. 600 ayda bitmezse months = -1.
PayoffResult cardPayoff(double balance, double monthlyRate, double payment, {double taxRate = 0, double minPct = 0}) {
  var b = balance, interest = 0.0, tax = 0.0, total = 0.0;
  for (var m = 1; m <= 600; m++) {
    final i = b * monthlyRate, t = i * taxRate;
    interest += i;
    tax += t;
    b += i + t;
    var p = math.max(payment, b * minPct / 100);
    if (p <= i + t + 1e-9 && p < b) return PayoffResult(-1, interest, tax, total);
    p = math.min(p, b);
    total += p;
    b -= p;
    if (b < 0.005) return PayoffResult(m, interest, tax, total);
  }
  return PayoffResult(-1, interest, tax, total);
}

// ---------------------------------------------------------------- kira

/// Kira artışında kullanılan TÜFE 12 aylık ortalama değişimi (%),
/// sözleşmenin yenilendiği aya göre. Kaynak: TÜİK; her ay güncellenmeli.
const Map<String, double> kRentCaps = {
  '2026-01': 34.88,
  '2026-02': 33.98,
  '2026-03': 33.39,
  '2026-04': 32.82,
  '2026-05': 32.43,
  '2026-06': 32.24,
  '2026-07': 32.03,
  '2026-08': 31.90,
  '2026-09': 31.79,
  '2026-10': 31.49,
  '2026-11': 31.23,
};
const String kRentAsOf = '2026-11-03';
const String kRentSource = 'TÜİK TÜFE 12 aylık ortalama değişim';

/// Tablodaki en yakın (aynı ya da önceki) ayın oranı.
(String, double)? rentCapFor(String month) {
  final keys = kRentCaps.keys.toList()..sort();
  String? best;
  for (final k in keys) {
    if (k.compareTo(month) <= 0) best = k;
  }
  best ??= keys.isEmpty ? null : keys.first;
  return best == null ? null : (best, kRentCaps[best]!);
}

double newRent(double rent, double pct) => rent * (1 + pct / 100);

// ----------------------------------------------------------- enflasyon

/// TÜİK TÜFE yıllık değişim (Aralık/Aralık, %). 2026: Ocak–Ekim kümülatif.
const Map<int, double> kCpiAnnual = {
  2004: 9.35, 2005: 7.72, 2006: 9.65, 2007: 8.39, 2008: 10.06, 2009: 6.53, 2010: 6.40,
  2011: 10.45, 2012: 6.16, 2013: 7.40, 2014: 8.17, 2015: 8.81, 2016: 8.53, 2017: 11.92,
  2018: 20.30, 2019: 11.84, 2020: 14.60, 2021: 36.08, 2022: 64.27, 2023: 64.77,
  2024: 44.38, 2025: 30.89, 2026: 27.52,
};
const String kCpiAsOf = '2026-11-03';
const String kCpiSource = 'TÜİK TÜFE (Aralık-Aralık); 2026 Ocak–Ekim';

/// [from] yılı sonundaki 1 birimin [to] yılı sonundaki karşılığı (çarpan).
/// Tabloda olmayan yıllar için [fallback] yıllık oranı kullanılır.
double cpiFactor(int from, int to, {Map<int, double> table = kCpiAnnual, double fallback = 0}) {
  var f = 1.0;
  if (to >= from) {
    for (var y = from + 1; y <= to; y++) {
      f *= 1 + (table[y] ?? fallback) / 100;
    }
  } else {
    for (var y = to + 1; y <= from; y++) {
      f /= 1 + (table[y] ?? fallback) / 100;
    }
  }
  return f;
}

// --------------------------------------------------------- gelir vergisi

/// Artan oranlı vergi tarifesi (GVK 103).
class TaxTariff {
  final List<double> limits;
  final List<double> rates;
  const TaxTariff(this.limits, this.rates);

  /// Ücret gelirleri, 2026.
  static const wage2026 = TaxTariff([190000, 400000, 1500000, 5300000], [0.15, 0.20, 0.27, 0.35, 0.40]);

  /// Ücret dışı gelirler, 2026.
  static const nonWage2026 = TaxTariff([190000, 400000, 1000000, 5300000], [0.15, 0.20, 0.27, 0.35, 0.40]);
  static const asOf = '2026-01-01';
  static const source = 'GİB 2026 gelir vergisi tarifesi (332 Seri No.lu GV Genel Tebliği)';

  bool get valid => rates.length == limits.length + 1;

  double taxOn(double income) {
    var tax = 0.0, prev = 0.0;
    for (var i = 0; i < rates.length; i++) {
      final top = i < limits.length ? limits[i] : double.infinity;
      if (income <= prev) break;
      tax += (math.min(income, top) - prev) * rates[i];
      prev = top;
    }
    return tax;
  }

  /// Gelirin düştüğü en yüksek dilimin oranı.
  double marginal(double income) {
    for (var i = 0; i < limits.length; i++) {
      if (income <= limits[i]) return rates[i];
    }
    return rates.last;
  }

  Map<String, Object?> toJson() => {'limits': limits, 'rates': rates};

  static TaxTariff? fromJson(Map<String, Object?> j) {
    final l = (j['limits'] as List?)?.map((e) => (e as num).toDouble()).toList();
    final r = (j['rates'] as List?)?.map((e) => (e as num).toDouble()).toList();
    if (l == null || r == null || r.length != l.length + 1) return null;
    return TaxTariff(l, r);
  }
}

// ---------------------------------------------------------------- zekât

/// Diyanet'in esas aldığı nisap: 80,18 g altın.
const double kNisabGrams = 80.18;

class ZakatResult {
  final double net, nisab, due;
  const ZakatResult(this.net, this.nisab, this.due);
  bool get above => net >= nisab && nisab > 0;
}

ZakatResult zakat({
  required double cash,
  required double goldGrams,
  required double goldPrice,
  double otherMetals = 0,
  double receivables = 0,
  double trade = 0,
  double debts = 0,
}) {
  final net = cash + goldGrams * goldPrice + otherMetals + receivables + trade - debts;
  final nisab = kNisabGrams * goldPrice;
  final above = net >= nisab && nisab > 0;
  return ZakatResult(net, nisab, above ? net / 40 : 0);
}

// ------------------------------------------------------------ birim fiyat

/// Birimler ve taban birime çarpanları (g, ml, adet).
const Map<String, (String, double)> kUnits = {
  'g': ('g', 1), 'kg': ('g', 1000), 'ml': ('ml', 1), 'L': ('ml', 1000), 'pc': ('pc', 1),
};

/// 1 taban birim (g/ml/adet) başına fiyat; geçersizse null.
double? unitPrice(double price, double qty, String unit) {
  final u = kUnits[unit];
  if (u == null || qty <= 0 || price < 0) return null;
  return price / (qty * u.$2);
}

/// En ucuz kalemin sırası (aynı taban birimdeki kalemler arasında).
int? cheapest(List<(double, double, String)> items) {
  int? best;
  double? bestV;
  String? base;
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final v = unitPrice(it.$1, it.$2, it.$3);
    if (v == null) continue;
    final b = kUnits[it.$3]!.$1;
    base ??= b;
    if (b != base) continue;
    if (bestV == null || v < bestV) {
      bestV = v;
      best = i;
    }
  }
  return best;
}
