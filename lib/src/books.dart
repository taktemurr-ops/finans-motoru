/// Kayıt tutan araçların veri modelleri ve hesapları (saf Dart, testli).
///
/// Tutarlar kuruş (`int`) olarak tutulur; toplamada yuvarlama hatası olmaz.
/// Bütçe defteri eski Bütçe 360 (app-009) ve Harcama 360 (app-010)
/// uygulamalarının özelliklerini birleştirir: gelir/gider, kategori
/// bütçeleri, ödeme şekli, haftalık/aylık tekrarlayan kayıtlar, arama,
/// uyarılar ve CSV dışa aktarma.
library;

import 'dart:math' as math;

int _seq = 0;

/// Yerel liste kimliği (kriptografik değildir).
String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}-${math.Random().nextInt(1 << 30)}';

String monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

String dayKey(DateTime d) => '${monthKey(d)}-${d.day.toString().padLeft(2, '0')}';

DateTime _date(Object? v, [DateTime? fallback]) =>
    (v is String ? DateTime.tryParse(v) : null) ?? fallback ?? DateTime(2026);

int _int(Object? v, [int f = 0]) => v is num ? v.toInt() : f;

String _str(Object? v, [String f = '']) => v is String ? v : f;

/// Ay sonu taşmasını önleyerek bir sonraki tarih (31 Ocak → 28/29 Şubat).
DateTime advance(DateTime d, String freq) {
  if (freq == 'week') return DateTime(d.year, d.month, d.day + 7, d.hour, d.minute);
  final months = freq == 'year' ? 12 : 1;
  final y = d.year + (d.month - 1 + months) ~/ 12;
  final m = (d.month - 1 + months) % 12 + 1;
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, math.min<int>(d.day, last));
}

/// Ayın [day]. günü; ay kısa ise son gün.
DateTime dayInMonth(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, math.min<int>(math.max<int>(1, day), last));
}

// ------------------------------------------------------------------ CSV

String _cell(String s) => RegExp(r'[",\n\r;]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

/// RFC 4180 CSV (virgül ayraçlı).
String toCsv(List<List<String>> rows) => rows.map((r) => r.map(_cell).join(',')).join('\r\n');

String centsPlain(int c) => (c / 100).toStringAsFixed(2);

// ------------------------------------------------------------- bütçe

class Entry {
  final String id;
  final DateTime date;
  final int cents;
  final bool income;
  final String category;
  final int method; // 0 kart, 1 nakit, 2 havale
  final String note;
  final String? ruleId;
  const Entry({
    required this.id,
    required this.date,
    required this.cents,
    required this.income,
    required this.category,
    this.method = 0,
    this.note = '',
    this.ruleId,
  });

  Map<String, Object?> toJson() => {
        'id': id, 'date': date.toIso8601String(), 'cents': cents, 'income': income,
        'category': category, 'method': method, 'note': note, 'ruleId': ruleId,
      };

  static Entry? fromJson(Map<String, Object?> j) {
    final c = _int(j['cents']);
    if (c <= 0 || j['id'] is! String) return null;
    return Entry(
      id: j['id'] as String,
      date: _date(j['date']),
      cents: c,
      income: j['income'] == true,
      category: _str(j['category']),
      method: _int(j['method']).clamp(0, 2),
      note: _str(j['note']),
      ruleId: j['ruleId'] as String?,
    );
  }
}

class Rule {
  final String id;
  final String title;
  final int cents;
  final bool income;
  final String category;
  final int method;
  final DateTime next;
  final String freq; // week | month
  final bool enabled;
  const Rule({
    required this.id,
    required this.title,
    required this.cents,
    required this.income,
    required this.category,
    this.method = 0,
    required this.next,
    this.freq = 'month',
    this.enabled = true,
  });

  Rule copyWith({DateTime? next, bool? enabled}) => Rule(
        id: id, title: title, cents: cents, income: income, category: category, method: method,
        next: next ?? this.next, freq: freq, enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toJson() => {
        'id': id, 'title': title, 'cents': cents, 'income': income, 'category': category,
        'method': method, 'next': next.toIso8601String(), 'freq': freq, 'enabled': enabled,
      };

  static Rule? fromJson(Map<String, Object?> j) {
    final c = _int(j['cents']);
    if (c <= 0 || j['id'] is! String) return null;
    return Rule(
      id: j['id'] as String,
      title: _str(j['title']),
      cents: c,
      income: j['income'] == true,
      category: _str(j['category']),
      method: _int(j['method']).clamp(0, 2),
      next: _date(j['next']),
      freq: j['freq'] == 'week' ? 'week' : 'month',
      enabled: j['enabled'] != false,
    );
  }
}

class MonthSummary {
  final int income, expense;
  final Map<String, int> byCategory;
  final Map<int, int> byMethod;
  const MonthSummary(this.income, this.expense, this.byCategory, this.byMethod);
  int get balance => income - expense;
}

class Ledger {
  final List<Entry> entries;
  final Map<String, int> budgets; // kategori → aylık sınır (kuruş)
  final List<Rule> rules;
  const Ledger({this.entries = const [], this.budgets = const {}, this.rules = const []});

  Ledger copyWith({List<Entry>? entries, Map<String, int>? budgets, List<Rule>? rules}) =>
      Ledger(entries: entries ?? this.entries, budgets: budgets ?? this.budgets, rules: rules ?? this.rules);

  MonthSummary month(DateTime m) {
    final k = monthKey(m);
    var inc = 0, exp = 0;
    final cat = <String, int>{};
    final met = <int, int>{};
    for (final e in entries) {
      if (monthKey(e.date) != k) continue;
      if (e.income) {
        inc += e.cents;
      } else {
        exp += e.cents;
        cat[e.category] = (cat[e.category] ?? 0) + e.cents;
        met[e.method] = (met[e.method] ?? 0) + e.cents;
      }
    }
    return MonthSummary(inc, exp, cat, met);
  }

  /// Bütçesi aşılan (oran > 1) ya da %80'ine yaklaşılan kategoriler.
  List<(String, double)> warnings(DateTime m) {
    final s = month(m);
    final out = <(String, double)>[];
    budgets.forEach((cat, limit) {
      if (limit <= 0) return;
      final r = (s.byCategory[cat] ?? 0) / limit;
      if (r >= 0.8) out.add((cat, r));
    });
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  /// Vadesi [today] dahil gelmiş tekrarlayan kayıtları deftere işler.
  /// Her kural en çok 60 kez ilerler (uzun aradan sonra açılışta taşmasın).
  Ledger postDue(DateTime today) {
    final end = DateTime(today.year, today.month, today.day, 23, 59);
    final add = <Entry>[];
    final rs = <Rule>[];
    for (final r in rules) {
      var cur = r;
      var n = 0;
      while (cur.enabled && !cur.next.isAfter(end) && n < 60) {
        add.add(Entry(
          id: newId(), date: cur.next, cents: cur.cents, income: cur.income, category: cur.category,
          method: cur.method, note: cur.title, ruleId: cur.id,
        ));
        cur = cur.copyWith(next: advance(cur.next, cur.freq));
        n++;
      }
      rs.add(cur);
    }
    return copyWith(entries: [...entries, ...add]..sort((a, b) => b.date.compareTo(a.date)), rules: rs);
  }

  List<Entry> search(String q, {String? month}) {
    final s = q.trim().toLowerCase();
    return entries
        .where((e) => month == null || monthKey(e.date) == month)
        .where((e) => s.isEmpty || e.note.toLowerCase().contains(s) || e.category.toLowerCase().contains(s))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  String csv(List<String> methods) => toCsv([
        ['date', 'type', 'category', 'method', 'amount', 'note'],
        for (final e in [...entries]..sort((a, b) => a.date.compareTo(b.date)))
          [dayKey(e.date), e.income ? 'income' : 'expense', e.category, methods[e.method.clamp(0, methods.length - 1)],
            centsPlain(e.cents), e.note],
      ]);

  Map<String, Object?> toJson() => {
        'v': 2,
        'entries': [for (final e in entries) e.toJson()],
        'budgets': budgets,
        'rules': [for (final r in rules) r.toJson()],
      };

  static Ledger fromJson(Map<String, Object?> j) {
    List<Map<String, Object?>> l(String k) =>
        [for (final x in (j[k] as List? ?? const [])) if (x is Map) Map<String, Object?>.from(x)];
    final b = <String, int>{};
    final raw = j['budgets'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is num && v > 0) b[k] = v.toInt();
      });
    }
    return Ledger(
      entries: l('entries').map(Entry.fromJson).whereType<Entry>().toList(),
      budgets: b,
      rules: l('rules').map(Rule.fromJson).whereType<Rule>().toList(),
    );
  }
}

// ---------------------------------------------------------------- borç

class Debt {
  final String id, name, note;
  final int cents;
  final bool owe; // true: ben borçluyum, false: bana borçlu
  final DateTime created;
  final DateTime? due;
  final List<(DateTime, int)> payments;
  const Debt({
    required this.id,
    required this.name,
    required this.cents,
    required this.owe,
    required this.created,
    this.due,
    this.note = '',
    this.payments = const [],
  });

  int get paid => payments.fold<int>(0, (a, p) => a + p.$2);
  int get remaining => math.max<int>(0, cents - paid);
  bool get settled => remaining == 0;
  bool overdue(DateTime today) => !settled && due != null && due!.isBefore(DateTime(today.year, today.month, today.day));

  Debt pay(int c, DateTime when) => Debt(
        id: id, name: name, cents: cents, owe: owe, created: created, due: due, note: note,
        payments: [...payments, (when, math.min<int>(c, remaining))],
      );

  Map<String, Object?> toJson() => {
        'id': id, 'name': name, 'note': note, 'cents': cents, 'owe': owe, 'created': created.toIso8601String(),
        'due': due?.toIso8601String(),
        'payments': [for (final p in payments) {'date': p.$1.toIso8601String(), 'cents': p.$2}],
      };

  static Debt? fromJson(Map<String, Object?> j) {
    final c = _int(j['cents']);
    if (c <= 0 || j['id'] is! String) return null;
    return Debt(
      id: j['id'] as String,
      name: _str(j['name']),
      note: _str(j['note']),
      cents: c,
      owe: j['owe'] != false,
      created: _date(j['created']),
      due: j['due'] is String ? DateTime.tryParse(j['due'] as String) : null,
      payments: [
        for (final p in (j['payments'] as List? ?? const []))
          if (p is Map && _int(p['cents']) > 0) (_date(p['date']), _int(p['cents'])),
      ],
    );
  }
}

/// (borçlarım, alacaklarım) kalan toplamları.
(int, int) debtTotals(List<Debt> ds) {
  var o = 0, r = 0;
  for (final d in ds) {
    if (d.owe) {
      o += d.remaining;
    } else {
      r += d.remaining;
    }
  }
  return (o, r);
}

String debtsCsv(List<Debt> ds) => toCsv([
      ['name', 'type', 'amount', 'paid', 'remaining', 'due', 'note'],
      for (final d in ds)
        [d.name, d.owe ? 'i_owe' : 'owed_to_me', centsPlain(d.cents), centsPlain(d.paid), centsPlain(d.remaining),
          d.due == null ? '' : dayKey(d.due!), d.note],
    ]);

// ------------------------------------------------------- birikim hedefi

class Goal {
  final String id, title;
  final int target;
  final DateTime created;
  final DateTime? deadline;
  final List<(DateTime, int)> moves; // + yatırma, − çekme
  const Goal({
    required this.id,
    required this.title,
    required this.target,
    required this.created,
    this.deadline,
    this.moves = const [],
  });

  int get saved => math.max<int>(0, moves.fold<int>(0, (a, m) => a + m.$2));
  double get progress => target <= 0 ? 0.0 : math.min(1.0, saved / target);
  bool get reached => saved >= target;

  /// Hedef tarihe kadar her ay ayrılması gereken (kalan / kalan ay).
  int? perMonth(DateTime today) {
    if (deadline == null || reached) return null;
    final months = (deadline!.year - today.year) * 12 + deadline!.month - today.month;
    final left = target - saved;
    return months <= 0 ? left : (left / months).ceil();
  }

  Goal move(int c, DateTime when) => Goal(
        id: id, title: title, target: target, created: created, deadline: deadline,
        moves: [...moves, (when, c < 0 ? -math.min<int>(-c, saved) : c)],
      );

  Map<String, Object?> toJson() => {
        'id': id, 'title': title, 'target': target, 'created': created.toIso8601String(),
        'deadline': deadline?.toIso8601String(),
        'moves': [for (final m in moves) {'date': m.$1.toIso8601String(), 'cents': m.$2}],
      };

  static Goal? fromJson(Map<String, Object?> j) {
    final t = _int(j['target']);
    if (t <= 0 || j['id'] is! String) return null;
    return Goal(
      id: j['id'] as String,
      title: _str(j['title']),
      target: t,
      created: _date(j['created']),
      deadline: j['deadline'] is String ? DateTime.tryParse(j['deadline'] as String) : null,
      moves: [
        for (final p in (j['moves'] as List? ?? const []))
          if (p is Map && p['cents'] is num) (_date(p['date']), _int(p['cents'])),
      ],
    );
  }
}

String goalsCsv(List<Goal> gs) => toCsv([
      ['goal', 'date', 'amount'],
      for (final g in gs)
        for (final m in g.moves) [g.title, dayKey(m.$1), centsPlain(m.$2)],
    ]);

// ------------------------------------------------------------ abonelik

class Sub {
  final String id, name;
  final int cents;
  final String period; // week | month | year
  final DateTime next;
  final bool remind;
  const Sub({required this.id, required this.name, required this.cents, this.period = 'month', required this.next, this.remind = false});

  /// Aylık karşılığı (kuruş).
  double get monthly => switch (period) { 'week' => cents * 52 / 12, 'year' => cents / 12, _ => cents.toDouble() };

  /// [today] veya sonrasındaki ilk yenileme tarihi.
  DateTime upcoming(DateTime today) {
    var d = next;
    final t = DateTime(today.year, today.month, today.day);
    var n = 0;
    while (d.isBefore(t) && n < 1000) {
      d = advance(d, period);
      n++;
    }
    return d;
  }

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'cents': cents, 'period': period, 'next': next.toIso8601String(), 'remind': remind};

  static Sub? fromJson(Map<String, Object?> j) {
    final c = _int(j['cents']);
    if (c <= 0 || j['id'] is! String) return null;
    final p = _str(j['period'], 'month');
    return Sub(
      id: j['id'] as String,
      name: _str(j['name']),
      cents: c,
      period: const ['week', 'month', 'year'].contains(p) ? p : 'month',
      next: _date(j['next']),
      remind: j['remind'] == true,
    );
  }
}

String subsCsv(List<Sub> ss, DateTime today) => toCsv([
      ['name', 'amount', 'period', 'monthly', 'next'],
      for (final s in ss) [s.name, centsPlain(s.cents), s.period, centsPlain(s.monthly.round()), dayKey(s.upcoming(today))],
    ]);

// -------------------------------------------------------------- fatura

class Bill {
  final String id, name;
  final int cents; // tahmini tutar (0 olabilir)
  final int day; // ayın günü
  final bool remind;
  final Map<String, int> paid; // ay → ödenen kuruş
  const Bill({required this.id, required this.name, this.cents = 0, required this.day, this.remind = true, this.paid = const {}});

  DateTime dueIn(DateTime month) => dayInMonth(month.year, month.month, day);
  bool paidIn(DateTime month) => paid.containsKey(monthKey(month));

  /// Bu ay ödenmemişse bu ayın, ödenmişse gelecek ayın son günü.
  DateTime nextDue(DateTime today) {
    final t = DateTime(today.year, today.month, 1);
    return paidIn(t) ? dueIn(DateTime(t.year, t.month + 1)) : dueIn(t);
  }

  Bill markPaid(DateTime month, int c) => Bill(id: id, name: name, cents: cents, day: day, remind: remind, paid: {...paid, monthKey(month): c});

  Bill unmark(DateTime month) =>
      Bill(id: id, name: name, cents: cents, day: day, remind: remind, paid: {...paid}..remove(monthKey(month)));

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'cents': cents, 'day': day, 'remind': remind, 'paid': paid};

  static Bill? fromJson(Map<String, Object?> j) {
    if (j['id'] is! String) return null;
    final p = <String, int>{};
    final raw = j['paid'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is num) p[k] = v.toInt();
      });
    }
    return Bill(
      id: j['id'] as String,
      name: _str(j['name']),
      cents: math.max<int>(0, _int(j['cents'])),
      day: _int(j['day'], 1).clamp(1, 31),
      remind: j['remind'] != false,
      paid: p,
    );
  }
}

String billsCsv(List<Bill> bs) => toCsv([
      ['bill', 'month', 'paid'],
      for (final b in bs)
        for (final e in (b.paid.entries.toList()..sort((a, c) => a.key.compareTo(c.key)))) [b.name, e.key, centsPlain(e.value)],
    ]);

// ------------------------------------------------------------- harçlık

class Kid {
  final String id, name;
  final int weekly;
  final List<(DateTime, int, String)> moves; // + verilen, − harcanan
  const Kid({required this.id, required this.name, this.weekly = 0, this.moves = const []});

  int get balance => moves.fold<int>(0, (a, m) => a + m.$2);

  Kid add(int c, DateTime when, String note) => Kid(id: id, name: name, weekly: weekly, moves: [...moves, (when, c, note)]);

  Map<String, Object?> toJson() => {
        'id': id, 'name': name, 'weekly': weekly,
        'moves': [for (final m in moves) {'date': m.$1.toIso8601String(), 'cents': m.$2, 'note': m.$3}],
      };

  static Kid? fromJson(Map<String, Object?> j) {
    if (j['id'] is! String) return null;
    return Kid(
      id: j['id'] as String,
      name: _str(j['name']),
      weekly: math.max<int>(0, _int(j['weekly'])),
      moves: [
        for (final p in (j['moves'] as List? ?? const []))
          if (p is Map && p['cents'] is num) (_date(p['date']), _int(p['cents']), _str(p['note'])),
      ],
    );
  }
}

String kidsCsv(List<Kid> ks) => toCsv([
      ['name', 'date', 'amount', 'note'],
      for (final k in ks)
        for (final m in k.moves) [k.name, dayKey(m.$1), centsPlain(m.$2), m.$3],
    ]);
