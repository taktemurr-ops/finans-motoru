/// 4. tur kayıt araçlarının modelleri (saf Dart, testli): altın günü /
/// dönüşümlü birikim grubu, esnaf veresiye defteri, kişisel sepet
/// enflasyonu, mini kasa ve stok.
///
/// Hiçbiri para tutmaz, aktarmaz ya da ödeme almaz: yalnızca kullanıcının
/// kendi girdiği kayıtları hesaplar. Tutarlar kuruş (`int`) olarak tutulur.
library;

import 'dart:math' as math;

import 'books.dart';

DateTime _date(Object? v, [DateTime? fallback]) =>
    (v is String ? DateTime.tryParse(v) : null) ?? fallback ?? DateTime(2026);

int _int(Object? v, [int f = 0]) => v is num ? v.toInt() : f;

String _str(Object? v, [String f = '']) => v is String ? v : f;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

// =============================================== altın günü (dönüşümlü grup)

/// Dönüşümlü birikim grubu (altın günü, arisan, tanda, chit, jam'iyya).
/// Her turda üyelerin hepsi [amount] kadar katkı yapar, sıradaki üye toplamı
/// alır. Uygulama yalnızca kim ödedi / kim aldı kaydını ve takvimi tutar.
class Rosca {
  final String id, name, note;

  /// Birim: boşsa para (aracın para simgesi), değilse serbest metin
  /// (ör. "gr altın", "çeyrek"). Tutar her durumda yüzde birlik (kuruş) tutulur.
  final String unit;
  final int amount;

  /// 'week' | '2week' | 'month'
  final String freq;
  final DateTime start;

  /// Alış sırası (tur i'de members[i] alır).
  final List<String> members;

  /// Tur → ödeyen üye sıraları.
  final Map<int, Set<int>> paid;

  /// Teslim edildi olarak işaretlenen turlar.
  final Set<int> delivered;

  const Rosca({
    required this.id,
    required this.name,
    required this.amount,
    required this.start,
    required this.members,
    this.unit = '',
    this.freq = 'month',
    this.note = '',
    this.paid = const {},
    this.delivered = const {},
  });

  int get rounds => members.length;

  /// Bir turda alanın eline geçen toplam (kendi payı dâhil).
  int get pot => amount * members.length;

  /// [i]. turun tarihi (0'dan).
  DateTime dateOf(int i) {
    var d = _day(start);
    if (freq == 'month') {
      final y = d.year + (d.month - 1 + i) ~/ 12;
      final m = (d.month - 1 + i) % 12 + 1;
      return dayInMonth(y, m, start.day);
    }
    final step = freq == '2week' ? 14 : 7;
    return DateTime(d.year, d.month, d.day + step * i);
  }

  /// Bugünden sonraki (ya da bugünkü) ilk teslim edilmemiş tur; yoksa null.
  int? nextRound(DateTime today) {
    final t = _day(today);
    for (var i = 0; i < rounds; i++) {
      if (!delivered.contains(i) && !dateOf(i).isBefore(t)) return i;
    }
    for (var i = 0; i < rounds; i++) {
      if (!delivered.contains(i)) return i;
    }
    return null;
  }

  bool get finished => delivered.length >= rounds && rounds > 0;

  /// Tarihi geçmiş ama ödemesi eksik olan (tur, üye) çiftleri.
  List<(int, int)> missing(DateTime today) {
    final t = _day(today);
    final out = <(int, int)>[];
    for (var i = 0; i < rounds; i++) {
      if (dateOf(i).isAfter(t)) break;
      for (var m = 0; m < members.length; m++) {
        if (m == i) continue; // alan üye kendi payını kendine öder sayılır
        if (!(paid[i]?.contains(m) ?? false)) out.add((i, m));
      }
    }
    return out;
  }

  /// [i]. turda toplanan (alan üyenin kendi payı dâhil).
  int collected(int i) {
    final p = paid[i] ?? const <int>{};
    var n = p.length;
    if (i < members.length && !p.contains(i)) n++;
    return n * amount;
  }

  /// Üyenin şimdiye kadar ödediği ve aldığı (kayıtlara göre).
  (int, int) memberTotals(int m) {
    var given = 0;
    for (var i = 0; i < rounds; i++) {
      // Kendi turunda kendi payı, ancak toplam teslim edildiyse sayılır.
      if ((i == m && delivered.contains(i)) || (paid[i]?.contains(m) ?? false)) given += amount;
    }
    final got = delivered.contains(m) ? pot : 0;
    return (given, got);
  }

  Rosca copyWith({
    String? name,
    String? note,
    String? unit,
    int? amount,
    String? freq,
    DateTime? start,
    List<String>? members,
    Map<int, Set<int>>? paid,
    Set<int>? delivered,
  }) =>
      Rosca(
        id: id,
        name: name ?? this.name,
        note: note ?? this.note,
        unit: unit ?? this.unit,
        amount: amount ?? this.amount,
        freq: freq ?? this.freq,
        start: start ?? this.start,
        members: members ?? this.members,
        paid: paid ?? this.paid,
        delivered: delivered ?? this.delivered,
      );

  /// Ödeme işaretini değiştirir.
  Rosca togglePaid(int round, int member) {
    final p = {for (final e in paid.entries) e.key: {...e.value}};
    final s = p.putIfAbsent(round, () => <int>{});
    if (!s.remove(member)) s.add(member);
    return copyWith(paid: p);
  }

  Rosca toggleDelivered(int round) {
    final d = {...delivered};
    if (!d.remove(round)) d.add(round);
    return copyWith(delivered: d);
  }

  /// Sırayı karıştırır (ödülsüz kura). Kayıtlar sıfırlanır; yalnızca başlamamış
  /// gruplarda kullanılmalıdır.
  Rosca shuffled(math.Random rnd) {
    final m = [...members]..shuffle(rnd);
    return copyWith(members: m, paid: const {}, delivered: const {});
  }

  bool get started => paid.values.any((s) => s.isNotEmpty) || delivered.isNotEmpty;

  Map<String, Object?> toJson() => {
        'id': id, 'name': name, 'note': note, 'unit': unit, 'amount': amount, 'freq': freq,
        'start': start.toIso8601String(), 'members': members,
        'paid': {for (final e in paid.entries) '${e.key}': (e.value.toList()..sort())},
        'delivered': (delivered.toList()..sort()),
      };

  static Rosca? fromJson(Map<String, Object?> j) {
    final a = _int(j['amount']);
    final ms = [for (final m in (j['members'] as List? ?? const [])) if (m is String) m];
    if (a <= 0 || j['id'] is! String || ms.length < 2) return null;
    final p = <int, Set<int>>{};
    final raw = j['paid'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final k = int.tryParse('${e.key}');
        if (k == null || e.value is! List) continue;
        p[k] = {for (final v in e.value as List) if (v is num && v >= 0 && v < ms.length) v.toInt()};
      }
    }
    final f = _str(j['freq'], 'month');
    return Rosca(
      id: j['id'] as String,
      name: _str(j['name']),
      note: _str(j['note']),
      unit: _str(j['unit']),
      amount: a,
      freq: const ['week', '2week', 'month'].contains(f) ? f : 'month',
      start: _date(j['start']),
      members: ms,
      paid: p,
      delivered: {for (final v in (j['delivered'] as List? ?? const [])) if (v is num) v.toInt()},
    );
  }
}

String roscaCsv(Rosca g) => toCsv([
      ['round', 'date', 'receiver', 'paid_members', 'collected', 'delivered'],
      for (var i = 0; i < g.rounds; i++)
        [
          '${i + 1}',
          dayKey(g.dateOf(i)),
          g.members[i],
          [for (var m = 0; m < g.members.length; m++) if (m == i || (g.paid[i]?.contains(m) ?? false)) g.members[m]].join(' / '),
          centsPlain(g.collected(i)),
          g.delivered.contains(i) ? 'yes' : 'no',
        ],
    ]);

// ====================================================== esnaf veresiye

/// Veresiye defterinde bir hareket: [cents] > 0 müşterinin borcunu artırır
/// (veresiye satış), < 0 azaltır (tahsilat).
class CreditTx {
  final DateTime date;
  final int cents;
  final String note;
  const CreditTx(this.date, this.cents, [this.note = '']);
}

class Customer {
  final String id, name, phone, note;

  /// Kullanıcının koyduğu limit (0: yok).
  final int limit;
  final List<CreditTx> txs;
  const Customer({required this.id, required this.name, this.phone = '', this.note = '', this.limit = 0, this.txs = const []});

  int get balance => txs.fold<int>(0, (a, x) => a + x.cents);
  bool get overLimit => limit > 0 && balance > limit;
  DateTime? get lastDate => txs.isEmpty ? null : txs.map((x) => x.date).reduce((a, b) => a.isAfter(b) ? a : b);

  /// Son tahsilattan (yoksa ilk kayıttan) bu yana geçen gün; bakiye yoksa null.
  int? daysSincePayment(DateTime today) {
    if (balance <= 0 || txs.isEmpty) return null;
    DateTime? ref;
    for (final x in txs) {
      if (x.cents < 0 && (ref == null || x.date.isAfter(ref))) ref = x.date;
    }
    ref ??= txs.map((x) => x.date).reduce((a, b) => a.isBefore(b) ? a : b);
    // Yerel gece yarıları arası (yaz saati günleri 23/25 saat): yuvarlanır.
    return (_day(today).difference(_day(ref)).inHours / 24).round();
  }

  Customer copyWith({String? name, String? phone, String? note, int? limit, List<CreditTx>? txs}) => Customer(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        note: note ?? this.note,
        limit: limit ?? this.limit,
        txs: txs ?? this.txs,
      );

  Customer add(CreditTx x) => copyWith(txs: [...txs, x]..sort((a, b) => a.date.compareTo(b.date)));

  Map<String, Object?> toJson() => {
        'id': id, 'name': name, 'phone': phone, 'note': note, 'limit': limit,
        'txs': [for (final x in txs) {'date': x.date.toIso8601String(), 'cents': x.cents, 'note': x.note}],
      };

  static Customer? fromJson(Map<String, Object?> j) {
    if (j['id'] is! String || _str(j['name']).isEmpty) return null;
    return Customer(
      id: j['id'] as String,
      name: _str(j['name']),
      phone: _str(j['phone']),
      note: _str(j['note']),
      limit: math.max(0, _int(j['limit'])),
      txs: [
        for (final x in (j['txs'] as List? ?? const []))
          if (x is Map && _int(x['cents']) != 0) CreditTx(_date(x['date']), _int(x['cents']), _str(x['note'])),
      ]..sort((a, b) => a.date.compareTo(b.date)),
    );
  }
}

/// Toplam alacak (yalnız pozitif bakiyeler) ve fazla ödeme (negatif bakiyeler).
(int, int) creditTotals(List<Customer> cs) {
  var due = 0, over = 0;
  for (final c in cs) {
    final b = c.balance;
    if (b > 0) {
      due += b;
    } else {
      over -= b;
    }
  }
  return (due, over);
}

/// Hatırlatma metni: {name}, {amount}, {shop} yer tutucuları doldurulur.
String fillTemplate(String tpl, Map<String, String> v) {
  var s = tpl;
  v.forEach((k, x) => s = s.replaceAll('{$k}', x));
  return s;
}

String customersCsv(List<Customer> cs) => toCsv([
      ['customer', 'phone', 'date', 'amount', 'note', 'balance'],
      for (final c in cs) ...[
        for (final x in c.txs) [c.name, c.phone, dayKey(x.date), centsPlain(x.cents), x.note, ''],
        [c.name, c.phone, '', '', '', centsPlain(c.balance)],
      ],
    ]);

// ===================================================== sepet enflasyonu

class PricePoint {
  final DateTime date;
  final int cents;
  final String store;
  const PricePoint(this.date, this.cents, [this.store = '']);
}

/// Sepetteki bir ürün: ayda ne kadar aldığın ([qty]) ve fiyat geçmişi.
class BasketItem {
  final String id, name, unit;
  final double qty;
  final List<PricePoint> prices;
  const BasketItem({required this.id, required this.name, this.unit = '', this.qty = 1, this.prices = const []});

  /// [at] tarihinde (ya da öncesinde) bilinen son fiyat.
  int? priceAt(DateTime at) {
    PricePoint? best;
    for (final p in prices) {
      if (!p.date.isAfter(at) && (best == null || !p.date.isBefore(best.date))) best = p;
    }
    return best?.cents;
  }

  PricePoint? get first => prices.isEmpty ? null : prices.reduce((a, b) => a.date.isAfter(b.date) ? b : a);
  PricePoint? get last => prices.isEmpty ? null : prices.reduce((a, b) => a.date.isBefore(b.date) ? b : a);

  /// İlk kayıttan son kayda yüzde değişim.
  double? get change {
    final f = first, l = last;
    if (f == null || l == null || f.cents == 0 || identical(f, l)) return null;
    return (l.cents / f.cents - 1) * 100;
  }

  BasketItem copyWith({String? name, String? unit, double? qty, List<PricePoint>? prices}) => BasketItem(
        id: id,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        qty: qty ?? this.qty,
        prices: prices ?? this.prices,
      );

  Map<String, Object?> toJson() => {
        'id': id, 'name': name, 'unit': unit, 'qty': qty,
        'prices': [for (final p in prices) {'date': p.date.toIso8601String(), 'cents': p.cents, 'store': p.store}],
      };

  static BasketItem? fromJson(Map<String, Object?> j) {
    if (j['id'] is! String || _str(j['name']).isEmpty) return null;
    final q = j['qty'];
    return BasketItem(
      id: j['id'] as String,
      name: _str(j['name']),
      unit: _str(j['unit']),
      qty: q is num && q > 0 ? q.toDouble() : 1,
      prices: [
        for (final p in (j['prices'] as List? ?? const []))
          if (p is Map && _int(p['cents']) > 0) PricePoint(_date(p['date']), _int(p['cents']), _str(p['store'])),
      ]..sort((a, b) => a.date.compareTo(b.date)),
    );
  }
}

/// Bir ayın sepet maliyeti ve endeksi.
class BasketMonth {
  final DateTime month;
  final int cost;

  /// Temel ay = 100 (aynı ürünlerle karşılaştırılır).
  final double index;
  const BasketMonth(this.month, this.cost, this.index);
}

/// Aylık kişisel sepet endeksi. Yalnızca temel ayda fiyatı bilinen ürünler
/// sayılır (sabit sepet, Laspeyres benzeri); bilinmeyen aylarda son fiyat
/// taşınır. Resmî enflasyon değildir.
List<BasketMonth> basketIndex(List<BasketItem> items, DateTime today) {
  DateTime? start;
  for (final it in items) {
    final f = it.first;
    if (f != null && (start == null || f.date.isBefore(start))) start = f.date;
  }
  if (start == null) return const [];
  // Temel ay: en az bir fiyatın bilindiği ilk ay; sepet o ayın sonunda fiyatı
  // bilinen ürünlerden oluşur.
  final base = DateTime(start.year, start.month);
  DateTime endOf(DateTime m) => DateTime(m.year, m.month + 1, 0, 23, 59, 59);
  final basket = [for (final it in items) if (it.priceAt(endOf(base)) != null) it];
  int cost(DateTime m) {
    var c = 0.0;
    for (final it in basket) {
      c += (it.priceAt(endOf(m)) ?? 0) * it.qty;
    }
    return c.round();
  }

  final baseCost = cost(base);
  final out = <BasketMonth>[];
  var m = base;
  final last = DateTime(today.year, today.month);
  while (!m.isAfter(last) && out.length < 600) {
    final c = cost(m);
    out.add(BasketMonth(m, c, baseCost == 0 ? 100 : c / baseCost * 100));
    m = DateTime(m.year, m.month + 1);
  }
  return out;
}

/// Son ayın bir önceki aya ve 12 ay önceye göre değişimi (%); veri yoksa null.
(double?, double?) basketChanges(List<BasketMonth> ms) {
  if (ms.length < 2) return (null, null);
  final l = ms.last;
  double? pct(BasketMonth a) => a.cost == 0 ? null : (l.cost / a.cost - 1) * 100;
  return (pct(ms[ms.length - 2]), ms.length > 12 ? pct(ms[ms.length - 13]) : null);
}

String basketCsv(List<BasketItem> items) => toCsv([
      ['item', 'unit', 'monthly_qty', 'date', 'price', 'store'],
      for (final it in items)
        for (final p in it.prices) [it.name, it.unit, '${it.qty}', dayKey(p.date), centsPlain(p.cents), p.store],
    ]);

// ======================================================= mini kasa ve stok

class Product {
  final String id, name;
  final int price, cost;
  final int stock, low;
  const Product({required this.id, required this.name, required this.price, this.cost = 0, this.stock = 0, this.low = 0});

  bool get isLow => low > 0 && stock <= low;

  Product copyWith({String? name, int? price, int? cost, int? stock, int? low}) => Product(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        cost: cost ?? this.cost,
        stock: stock ?? this.stock,
        low: low ?? this.low,
      );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'price': price, 'cost': cost, 'stock': stock, 'low': low};

  static Product? fromJson(Map<String, Object?> j) {
    if (j['id'] is! String || _str(j['name']).isEmpty) return null;
    return Product(
      id: j['id'] as String,
      name: _str(j['name']),
      price: math.max(0, _int(j['price'])),
      cost: math.max(0, _int(j['cost'])),
      stock: _int(j['stock']),
      low: math.max(0, _int(j['low'])),
    );
  }
}

/// Satış satırı: satış anındaki ad ve fiyat saklanır (sonradan fiyat
/// değişse de geçmiş doğru kalır).
class SaleLine {
  final String productId, name;
  final int qty, price, cost;
  const SaleLine(this.productId, this.name, this.qty, this.price, [this.cost = 0]);
  int get total => qty * price;
  int get profit => qty * (price - cost);
}

class Sale {
  final String id;
  final DateTime date;
  final List<SaleLine> lines;

  /// Ödeme şekli etiketi sırası (yalnızca kayıt; ödeme alınmaz).
  final int method;
  const Sale({required this.id, required this.date, required this.lines, this.method = 0});

  int get total => lines.fold<int>(0, (a, l) => a + l.total);
  int get profit => lines.fold<int>(0, (a, l) => a + l.profit);
  int get items => lines.fold<int>(0, (a, l) => a + l.qty);

  Map<String, Object?> toJson() => {
        'id': id, 'date': date.toIso8601String(), 'method': method,
        'lines': [for (final l in lines) {'p': l.productId, 'n': l.name, 'q': l.qty, 'price': l.price, 'cost': l.cost}],
      };

  static Sale? fromJson(Map<String, Object?> j) {
    if (j['id'] is! String) return null;
    final ls = [
      for (final l in (j['lines'] as List? ?? const []))
        if (l is Map && _int(l['q']) > 0) SaleLine(_str(l['p']), _str(l['n']), _int(l['q']), _int(l['price']), _int(l['cost'])),
    ];
    if (ls.isEmpty) return null;
    return Sale(id: j['id'] as String, date: _date(j['date']), lines: ls, method: _int(j['method']));
  }
}

/// Sepetten satış oluşturur ve stoğu düşer. [cart]: ürün kimliği → adet.
(Sale, List<Product>) checkout(List<Product> products, Map<String, int> cart, DateTime now, {int method = 0, String? id}) {
  final lines = <SaleLine>[];
  final out = <Product>[];
  for (final p in products) {
    final q = cart[p.id] ?? 0;
    if (q > 0) {
      lines.add(SaleLine(p.id, p.name, q, p.price, p.cost));
      out.add(p.copyWith(stock: p.stock - q));
    } else {
      out.add(p);
    }
  }
  return (Sale(id: id ?? newId(), date: now, lines: lines, method: method), out);
}

/// Satışı geri alır: stok iade edilir.
List<Product> refund(List<Product> products, Sale s) => [
      for (final p in products)
        p.copyWith(stock: p.stock + s.lines.where((l) => l.productId == p.id).fold<int>(0, (a, l) => a + l.qty)),
    ];

class DaySummary {
  final int revenue, profit, count, items;
  final List<(String, int, int)> top; // (ad, adet, ciro)
  const DaySummary(this.revenue, this.profit, this.count, this.items, this.top);
}

/// [from]–[to] (dâhil, gün bazında) satış özeti.
DaySummary summarize(List<Sale> sales, DateTime from, DateTime to) {
  final a = _day(from), b = _day(to).add(const Duration(days: 1));
  var rev = 0, prof = 0, n = 0, items = 0;
  final per = <String, (int, int)>{};
  for (final s in sales) {
    if (s.date.isBefore(a) || !s.date.isBefore(b)) continue;
    rev += s.total;
    prof += s.profit;
    n++;
    items += s.items;
    for (final l in s.lines) {
      final c = per[l.name] ?? (0, 0);
      per[l.name] = (c.$1 + l.qty, c.$2 + l.total);
    }
  }
  final top = [for (final e in per.entries) (e.key, e.value.$1, e.value.$2)]..sort((x, y) => y.$3.compareTo(x.$3));
  return DaySummary(rev, prof, n, items, top.take(5).toList());
}

String salesCsv(List<Sale> sales) => toCsv([
      ['date', 'time', 'sale', 'product', 'qty', 'price', 'total', 'method'],
      for (final s in sales)
        for (final l in s.lines)
          [dayKey(s.date), '${s.date.hour.toString().padLeft(2, '0')}:${s.date.minute.toString().padLeft(2, '0')}', s.id,
            l.name, '${l.qty}', centsPlain(l.price), centsPlain(l.total), '${s.method}'],
    ]);

String productsCsv(List<Product> ps) => toCsv([
      ['product', 'price', 'cost', 'stock', 'low_stock'],
      for (final p in ps) [p.name, centsPlain(p.price), centsPlain(p.cost), '${p.stock}', '${p.low}'],
    ]);
