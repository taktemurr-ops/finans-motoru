/// Hesaplayıcılar: kredi, faiz/birikim, indirim/KDV, hesap bölüşme, taksit,
/// kredi kartı, kira artışı, enflasyon, gelir vergisi, zekât, birim fiyat.
library;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../core.dart';

/// Girdileri saklayan ortak durum: son girilen değerler açılışta geri gelir.
abstract class CalcState<W extends StatefulWidget> extends State<W> {
  ToolContext get t;
  final Map<String, TextEditingController> _c = {};
  Map<String, Object?> _saved = {};
  bool _ready = false;

  /// Alan denetleyicisi ([def] ilk değer).
  TextEditingController c(String key, String def) =>
      _c.putIfAbsent(key, () => TextEditingController(text: _saved[key] as String? ?? def));

  /// Alanların ilk değerleri (hesap, alan çizilmeden önce de yapılabilsin).
  Map<String, String> get defs => const {};

  double? n(String key) => parseNumber(c(key, defs[key] ?? '').text);

  double v(String key, [double f = 0]) => n(key) ?? f;

  Object? saved(String key) => _saved[key];

  void put(String key, Object? value) {
    _saved[key] = value;
    _persist();
  }

  @override
  void initState() {
    super.initState();
    t.store.readMap('inputs').then((m) {
      if (!mounted) return;
      setState(() {
        _saved = Map.of(m);
        for (final e in _c.entries) {
          final s = _saved[e.key];
          if (s is String) e.value.text = s;
        }
        _ready = true;
      });
    });
  }

  void changed([String _ = '']) {
    setState(() {});
    _persist();
  }

  void _persist() {
    if (!_ready) return;
    final m = <String, Object?>{..._saved};
    _c.forEach((k, v) => m[k] = v.text);
    t.store.writeMap('inputs', m);
  }

  Widget field(String key, String label, String def, {String? suffix}) =>
      AppNumberField(controller: c(key, defs[key] ?? def), label: label, suffix: suffix, onChanged: changed);

  Widget line(String label, String value, {bool big = false}) => AppResult(label: label, value: value, lang: t.lang, big: big);

  String m(double x, [String sym = '']) => fmtMoney(x, t.lang, sym);

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }
}

// ------------------------------------------------------------------ kredi

class LoanTool extends StatefulWidget {
  final ToolContext t;
  const LoanTool(this.t, {super.key});
  @override
  State<LoanTool> createState() => _LoanState();
}

class _LoanState extends CalcState<LoanTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {'p': '100000', 'r': '3.5', 'n': '24', 'kkdf': '15', 'bsmv': '15'};
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final taxes = saved('taxes') as bool? ?? (t.lang == 'tr');
    final p = v('p'), r = v('r') / 100, months = v('n').round();
    final tax = taxes ? (v('kkdf') + v('bsmv')) / 100 : 0.0;
    final res = loan(p, r, months, taxRate: tax);
    final rows = _showAll ? res.rows : res.rows.take(12).toList();
    return ToolList(children: [
      AppInfoCard(L(t, 'no_credit'), icon: Icons.info_outline_rounded),
      AppPanel(
        child: Column(children: [
          field('p', L(t, 'principal'), '100000'),
          field('r', L(t, 'rate_month'), '3.5', suffix: '%'),
          field('n', L(t, 'term'), '24'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L(t, 'taxes_tr')),
            value: taxes,
            onChanged: (b) => setState(() => put('taxes', b)),
          ),
          if (taxes)
            Row(children: [
              Expanded(child: field('kkdf', 'KKDF', '15', suffix: '%')),
              const SizedBox(width: 8),
              Expanded(child: field('bsmv', 'BSMV', '15', suffix: '%')),
            ]),
        ]),
      ),
      if (res.rows.isEmpty)
        AppInfoCard(L(t, 'invalid'))
      else ...[
        AppPanel(
          child: Column(children: [
            line(L(t, 'payment'), m(res.payment), big: true),
            line(L(t, 'total_interest'), m(res.interest)),
            if (taxes) line('KKDF + BSMV', m(res.tax)),
            line(L(t, 'total_payment'), m(res.total)),
          ]),
        ),
        AppHeading(L(t, 'schedule'), icon: Icons.table_rows_rounded),
        AppPanel(child: _table(rows)),
        if (!_showAll && res.rows.length > 12)
          AppButton(
            label: L(t, 'show_all'),
            icon: Icons.unfold_more_rounded,
            onPressed: () => setState(() => _showAll = true),
          ),
      ],
    ]);
  }

  Widget _table(List<LoanRow> rows) {
    const st = TextStyle(color: Colors.white70, fontSize: 13);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
        columns: [
          const DataColumn(label: Text('#')),
          DataColumn(label: Text(L(t, 'payment')), numeric: true),
          DataColumn(label: Text(L(t, 'interest')), numeric: true),
          DataColumn(label: Text(L(t, 'principal')), numeric: true),
          DataColumn(label: Text(L(t, 'remaining')), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text('${r.no}', style: st)),
              DataCell(Text(m(r.payment), style: st)),
              DataCell(Text(m(r.interest + r.tax), style: st)),
              DataCell(Text(m(r.principal), style: st)),
              DataCell(Text(m(r.balance), style: st)),
            ]),
        ],
      ),
    );
  }
}

// --------------------------------------------------------- faiz/birikim

class GrowthTool extends StatefulWidget {
  final ToolContext t;
  const GrowthTool(this.t, {super.key});
  @override
  State<GrowthTool> createState() => _GrowthState();
}

class _GrowthState extends CalcState<GrowthTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {'init': '10000', 'add': '1000', 'rate': '40', 'wht': '0', 'term': '5'};

  @override
  Widget build(BuildContext context) {
    final yearsMode = saved('years') as bool? ?? true;
    final term = v('term').round();
    final months = yearsMode ? term * 12 : term;
    final ok = months > 0 && months <= 1200;
    final g = grow(v('init'), v('add'), v('rate') / 100, ok ? months : 0, withholding: v('wht') / 100);
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          field('init', L(t, 'initial'), '10000'),
          field('add', L(t, 'contribution'), '1000'),
          field('rate', L(t, 'rate_year'), '40', suffix: '%'),
          Choice<bool>(
            values: const [true, false],
            labels: [L(t, 'years'), L(t, 'months')],
            selected: yearsMode,
            onChanged: (b) => setState(() => put('years', b)),
          ),
          field('term', L(t, yearsMode ? 'years' : 'months'), '5'),
          field('wht', L(t, 'withholding'), '0', suffix: '%'),
        ]),
      ),
      if (!ok)
        AppInfoCard(L(t, 'invalid'))
      else ...[
        AppPanel(
          child: Column(children: [
            line(L(t, 'final_value'), m(g.finalValue), big: true),
            line(L(t, 'deposits'), m(g.deposited)),
            line(L(t, 'earned'), m(g.earned)),
            if (g.tax > 0) line(L(t, 'withholding'), '− ${m(g.tax)}'),
          ]),
        ),
        if (g.yearly.length > 1)
          AppPanel(
            child: Column(children: [
              for (var i = 0; i < g.yearly.length; i++)
                line('${L(t, 'year')} ${i + 1}', m(g.yearly[i])),
            ]),
          ),
        AppInfoCard(L(t, 'compound_note')),
      ],
    ]);
  }
}

// ------------------------------------------------------------ indirim/KDV

class DiscountTool extends StatefulWidget {
  final ToolContext t;
  const DiscountTool(this.t, {super.key});
  @override
  State<DiscountTool> createState() => _DiscountState();
}

class _DiscountState extends CalcState<DiscountTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {'price': '1000', 'd1': '20', 'd2': '0', 'vprice': '1000', 'rate': '20'};

  @override
  Widget build(BuildContext context) {
    final vatMode = saved('vat') as bool? ?? false;
    return ToolList(children: [
      Choice<bool>(
        values: const [false, true],
        labels: [L(t, 'discount_tab'), L(t, 'vat')],
        selected: vatMode,
        onChanged: (b) => setState(() => put('vat', b)),
      ),
      if (!vatMode) ..._discount() else ..._vat(),
    ]);
  }

  List<Widget> _discount() {
    final p = v('price'), d1 = v('d1'), d2 = v('d2');
    final after = discounted(p, [d1, d2]);
    return [
      AppPanel(
        child: Column(children: [
          field('price', L(t, 'price'), '1000'),
          field('d1', L(t, 'discount'), '20', suffix: '%'),
          field('d2', L(t, 'extra_discount'), '0', suffix: '%'),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          line(L(t, 'result'), m(after), big: true),
          line(L(t, 'saved'), m(p - after)),
          if (p > 0) line(L(t, 'discount'), fmtPct((1 - after / p) * 100)),
        ]),
      ),
    ];
  }

  List<Widget> _vat() {
    final included = saved('incl') as bool? ?? false;
    final rate = v('rate', 20);
    final r = vat(v('vprice'), rate, included: included);
    return [
      AppPanel(
        child: Column(children: [
          field('vprice', L(t, 'price'), '1000'),
          Wrap(spacing: 8, children: [
            for (final x in const [1, 10, 20])
              ChoiceChip(
                label: Text('%$x'),
                selected: rate == x,
                onSelected: (_) {
                  c('rate', '20').text = '$x';
                  changed();
                },
              ),
          ]),
          field('rate', L(t, 'vat_rate'), '20', suffix: '%'),
          Choice<bool>(
            values: const [false, true],
            labels: [L(t, 'add_vat'), L(t, 'remove_vat')],
            selected: included,
            onChanged: (b) => setState(() => put('incl', b)),
          ),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          line(L(t, 'excl_vat'), m(r.$1), big: included),
          line(L(t, 'vat'), m(r.$2)),
          line(L(t, 'incl_vat'), m(r.$3), big: !included),
        ]),
      ),
    ];
  }
}

// ------------------------------------------------------------ bölüşme

class SplitTool extends StatefulWidget {
  final ToolContext t;
  const SplitTool(this.t, {super.key});
  @override
  State<SplitTool> createState() => _SplitState();
}

class _SplitState extends CalcState<SplitTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {'bill': '1500', 'tip': '10', 'people': '2'};

  @override
  Widget build(BuildContext context) {
    final people = v('people', 1).round();
    final round = saved('round') as bool? ?? false;
    final tip = v('tip');
    final r = split(v('bill'), tip, people, roundUp: round);
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          field('bill', L(t, 'bill_total'), '1500'),
          Wrap(spacing: 8, children: [
            for (final x in const [0, 5, 10, 15, 20])
              ChoiceChip(
                label: Text('%$x'),
                selected: tip == x,
                onSelected: (_) {
                  c('tip', '10').text = '$x';
                  changed();
                },
              ),
          ]),
          field('tip', L(t, 'tip'), '10', suffix: '%'),
          Row(children: [
            IconButton.filledTonal(
              icon: const Icon(Icons.remove_rounded),
              onPressed: people > 1
                  ? () {
                      c('people', '2').text = '${people - 1}';
                      changed();
                    }
                  : null,
            ),
            Expanded(child: field('people', L(t, 'people'), '2')),
            IconButton.filledTonal(
              icon: const Icon(Icons.add_rounded),
              onPressed: () {
                c('people', '2').text = '${people + 1}';
                changed();
              },
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L(t, 'round_up')),
            value: round,
            onChanged: (b) => setState(() => put('round', b)),
          ),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          line(L(t, 'per_person'), m(r.$3), big: true),
          line(L(t, 'tip_amount'), m(r.$1)),
          line(L(t, 'sum'), m(r.$2)),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------- taksit

class InstallmentTool extends StatefulWidget {
  final ToolContext t;
  const InstallmentTool(this.t, {super.key});
  @override
  State<InstallmentTool> createState() => _InstallmentState();
}

class _InstallmentState extends CalcState<InstallmentTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {'cash': '12000', 'count': '12', 'inst': '1100', 'alt': '3'};

  @override
  Widget build(BuildContext context) {
    final cash = v('cash'), count = v('count').round(), inst = v('inst');
    final ok = cash > 0 && count > 0 && count <= 120 && inst > 0;
    final total = inst * count;
    final irr = ok ? effectiveMonthlyRate(cash, inst, count) : 0.0;
    final alt = v('alt') / 100;
    final pv = ok ? presentValue(inst, count, alt) : 0.0;
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          field('cash', L(t, 'cash_price'), '12000'),
          field('count', L(t, 'installments'), '12'),
          field('inst', L(t, 'inst_amount'), '1100'),
          field('alt', L(t, 'alt_rate'), '3', suffix: '%'),
        ]),
      ),
      if (!ok)
        AppInfoCard(L(t, 'invalid'))
      else ...[
        AppPanel(
          child: Column(children: [
            line(L(t, 'inst_total'), m(total), big: true),
            line(L(t, 'diff'), m(total - cash)),
            line(L(t, 'effective_rate'), fmtPct(irr * 100)),
            line(L(t, 'pv_inst'), m(pv)),
          ]),
        ),
        AppInfoCard(L(t, pv < cash ? 'better_inst' : 'better_cash'), icon: Icons.lightbulb_rounded),
      ],
    ]);
  }
}

// --------------------------------------------------------- kredi kartı

class CardTool extends StatefulWidget {
  final ToolContext t;
  const CardTool(this.t, {super.key});
  @override
  State<CardTool> createState() => _CardState();
}

class _CardState extends CalcState<CardTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {'bal': '30000', 'rate': '3.5', 'min': '20', 'pay': '5000'};

  @override
  Widget build(BuildContext context) {
    final taxes = saved('taxes') as bool? ?? (t.lang == 'tr');
    final tax = taxes ? 0.30 : 0.0;
    final b = v('bal'), r = v('rate') / 100, pay = v('pay'), minPct = v('min');
    final ok = b > 0 && r >= 0;
    final plan = ok ? cardPayoff(b, r, pay, taxRate: tax) : null;
    final minOnly = ok && minPct > 0 ? cardPayoff(b, r, 0, taxRate: tax, minPct: minPct) : null;
    String months(PayoffResult p) => p.months < 0 ? L(t, 'never_pay') : '${p.months} ${L(t, 'months')}';
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          field('bal', L(t, 'card_balance'), '30000'),
          field('rate', L(t, 'card_rate'), '3.5', suffix: '%'),
          field('min', L(t, 'min_pct'), '20', suffix: '%'),
          field('pay', L(t, 'monthly_pay'), '5000'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L(t, 'taxes_tr')),
            value: taxes,
            onChanged: (x) => setState(() => put('taxes', x)),
          ),
        ]),
      ),
      if (plan != null)
        AppPanel(
          child: Column(children: [
            line(L(t, 'months_to_pay'), months(plan), big: true),
            if (plan.months >= 0) ...[
              line(L(t, 'total_interest'), m(plan.interest + plan.tax)),
              line(L(t, 'total_payment'), m(plan.total)),
            ],
          ]),
        ),
      if (minOnly != null) ...[
        AppHeading(L(t, 'min_only'), icon: Icons.warning_amber_rounded),
        AppPanel(
          child: Column(children: [
            line(L(t, 'months_to_pay'), months(minOnly)),
            if (minOnly.months >= 0) line(L(t, 'total_interest'), m(minOnly.interest + minOnly.tax)),
          ]),
        ),
      ],
      AppInfoCard(L(t, 'rate_note')),
    ]);
  }
}

// ---------------------------------------------------------------- kira

class RentTool extends StatefulWidget {
  final ToolContext t;
  const RentTool(this.t, {super.key});
  @override
  State<RentTool> createState() => _RentState();
}

class _RentState extends CalcState<RentTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {'rent': '20000'};

  @override
  Widget build(BuildContext context) {
    final months = kRentCaps.keys.toList()..sort();
    final now = monthOf(DateTime.now());
    final sel = saved('month') as String? ?? (kRentCaps.containsKey(now) ? now : months.last);
    final manual = saved('manual') as bool? ?? false;
    final table = rentCapFor(sel);
    final pct = manual ? v('pct') : (table?.$2 ?? 0.0);
    final rent = v('rent');
    final loc = MaterialLocalizations.of(context);
    String label(String k) => loc.formatMonthYear(DateTime(int.parse(k.substring(0, 4)), int.parse(k.substring(5, 7))));
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          field('rent', L(t, 'rent'), '20000', suffix: '₺'),
          Pick<String>(
            label: L(t, 'renew_month'),
            values: months,
            text: (k) => '${label(k)} · ${fmtPct(kRentCaps[k]!)}',
            value: months.contains(sel) ? sel : months.last,
            onChanged: (k) => setState(() => put('month', k)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L(t, 'manual_rate')),
            value: manual,
            onChanged: (b) => setState(() => put('manual', b)),
          ),
          if (manual) field('pct', L(t, 'cpi_avg'), '${table?.$2 ?? 30}', suffix: '%'),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          line(L(t, 'new_rent'), m(newRent(rent, pct), '₺'), big: true),
          line(L(t, 'increase'), m(newRent(rent, pct) - rent, '₺')),
          line(L(t, 'cpi_avg'), fmtPct(pct)),
        ]),
      ),
      AppInfoCard(L(t, 'rent_note'), icon: Icons.gavel_rounded),
      sourceNote(t, kRentSource, kRentAsOf),
    ]);
  }
}

String monthOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

// ----------------------------------------------------------- enflasyon

class InflationTool extends StatefulWidget {
  final ToolContext t;
  const InflationTool(this.t, {super.key});
  @override
  State<InflationTool> createState() => _InflationState();
}

class _InflationState extends CalcState<InflationTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {'amount': '1000'};

  @override
  Widget build(BuildContext context) {
    final years = [2003, ...kCpiAnnual.keys];
    final from = saved('from') as int? ?? 2020;
    final to = saved('to') as int? ?? years.last;
    final f = cpiFactor(from, to);
    final amount = v('amount');
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          field('amount', L(t, 'amount'), '1000', suffix: '₺'),
          Row(children: [
            Expanded(
              child: Pick<int>(
                label: L(t, 'from'),
                values: years,
                text: (y) => '$y',
                value: years.contains(from) ? from : years.first,
                onChanged: (y) => setState(() => put('from', y)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Pick<int>(
                label: L(t, 'to'),
                values: years,
                text: (y) => '$y',
                value: years.contains(to) ? to : years.last,
                onChanged: (y) => setState(() => put('to', y)),
              ),
            ),
          ]),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          line(L(t, 'equiv'), m(amount * f, '₺'), big: true),
          line(L(t, 'cum_infl'), fmtPct((f - 1) * 100)),
        ]),
      ),
      AppHeading(L(t, 'cpi_table'), icon: Icons.table_chart_rounded),
      AppPanel(
        child: Column(children: [
          for (final y in kCpiAnnual.keys.toList().reversed) line('$y', fmtPct(kCpiAnnual[y]!)),
        ]),
      ),
      AppInfoCard(L(t, 'infl_note')),
      sourceNote(t, kCpiSource, kCpiAsOf),
    ]);
  }
}

// ------------------------------------------------------- gelir vergisi

class IncomeTaxTool extends StatefulWidget {
  final ToolContext t;
  const IncomeTaxTool(this.t, {super.key});
  @override
  State<IncomeTaxTool> createState() => _IncomeTaxState();
}

class _IncomeTaxState extends CalcState<IncomeTaxTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {'income': '600000'};

  TaxTariff _tariff(bool wage) {
    final j = saved(wage ? 'tariff_w' : 'tariff_n');
    if (j is Map) {
      final x = TaxTariff.fromJson(Map<String, Object?>.from(j));
      if (x != null) return x;
    }
    return wage ? TaxTariff.wage2026 : TaxTariff.nonWage2026;
  }

  Future<void> _edit(bool wage) async {
    final cur = _tariff(wage);
    final limits = TextEditingController(text: cur.limits.map((e) => e.toStringAsFixed(0)).join(' '));
    final rates = TextEditingController(text: cur.rates.map((e) => formatNumber(e * 100)).join(' '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(L(t, 'parameters')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppTextField(controller: limits, label: L(t, 'brackets')),
          AppTextField(controller: rates, label: L(t, 'rates_pct')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(t.core('cancel'))),
          TextButton(
            onPressed: () {
              put(wage ? 'tariff_w' : 'tariff_n', null);
              Navigator.pop(d, false);
            },
            child: Text(L(t, 'defaults')),
          ),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(t.core('ok'))),
        ],
      ),
    );
    if (ok == true) {
      List<double> nums(String s) => [
            for (final p in s.trim().split(RegExp(r'\s+')))
              if (parseNumber(p) != null) parseNumber(p)!,
          ];
      final l = nums(limits.text), r = nums(rates.text).map((e) => e / 100).toList();
      if (r.length == l.length + 1) put(wage ? 'tariff_w' : 'tariff_n', TaxTariff(l, r).toJson());
    }
    limits.dispose();
    rates.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final wage = saved('wage') as bool? ?? true;
    final tariff = _tariff(wage);
    final income = v('income');
    final tax = tariff.taxOn(income);
    return ToolList(children: [
      Choice<bool>(
        values: const [true, false],
        labels: [L(t, 'wage'), L(t, 'non_wage')],
        selected: wage,
        onChanged: (b) => setState(() => put('wage', b)),
      ),
      AppPanel(child: field('income', L(t, 'annual_income'), '600000', suffix: '₺')),
      AppPanel(
        child: Column(children: [
          line(L(t, 'income_tax'), m(tax, '₺'), big: true),
          line(L(t, 'after_tax'), m(income - tax, '₺')),
          if (income > 0) line(L(t, 'avg_rate'), fmtPct(tax / income * 100)),
          line(L(t, 'marginal'), fmtPct(tariff.marginal(income) * 100)),
        ]),
      ),
      AppHeading(L(t, 'tariff'), icon: Icons.stairs_rounded),
      AppPanel(
        child: Column(children: [
          for (var i = 0; i < tariff.rates.length; i++)
            line(
              i < tariff.limits.length
                  ? '${i == 0 ? '0' : m(tariff.limits[i - 1])} – ${m(tariff.limits[i])}'
                  : '> ${m(tariff.limits.last)}',
              fmtPct(tariff.rates[i] * 100),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              icon: const Icon(Icons.tune_rounded),
              label: Text(L(t, 'parameters')),
              onPressed: () => _edit(wage),
            ),
          ),
        ]),
      ),
      AppInfoCard(L(t, wage ? 'wage_note' : 'nonwage_note')),
      sourceNote(t, TaxTariff.source, TaxTariff.asOf),
    ]);
  }
}

// ---------------------------------------------------------------- zekât

class ZakatTool extends StatefulWidget {
  final ToolContext t;
  const ZakatTool(this.t, {super.key});
  @override
  State<ZakatTool> createState() => _ZakatState();
}

class _ZakatState extends CalcState<ZakatTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {};

  @override
  Widget build(BuildContext context) {
    final z = zakat(
      cash: v('cash'),
      goldGrams: v('gold'),
      goldPrice: v('gp'),
      otherMetals: v('silver'),
      receivables: v('recv'),
      trade: v('trade'),
      debts: v('debts'),
    );
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          field('gp', L(t, 'gold_price'), '0'),
          field('cash', L(t, 'cash'), '0'),
          field('gold', L(t, 'gold_g'), '0', suffix: 'g'),
          field('silver', L(t, 'silver_value'), '0'),
          field('recv', L(t, 'receivables'), '0'),
          field('trade', L(t, 'trade'), '0'),
          field('debts', L(t, 'debts'), '0'),
        ]),
      ),
      if (v('gp') <= 0)
        AppInfoCard(L(t, 'enter_gold_price'), icon: Icons.edit_rounded)
      else
        AppPanel(
          child: Column(children: [
            line(L(t, 'zakat_due'), z.above ? m(z.due) : '—', big: true),
            line(L(t, 'net_assets'), m(z.net)),
            line('${L(t, 'nisab')} (${formatNumber(kNisabGrams)} g)', m(z.nisab)),
            if (!z.above) Padding(padding: const EdgeInsets.only(top: 8), child: Text(L(t, 'below_nisab'))),
          ]),
        ),
      AppInfoCard(L(t, 'zakat_note')),
    ]);
  }
}

// ---------------------------------------------------------- birim fiyat

class UnitPriceTool extends StatefulWidget {
  final ToolContext t;
  const UnitPriceTool(this.t, {super.key});
  @override
  State<UnitPriceTool> createState() => _UnitPriceState();
}

class _UnitPriceState extends CalcState<UnitPriceTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {'p0': '45', 'q0': '500', 'p1': '120', 'q1': '1.5'};

  int get _count => (saved('count') as int? ?? 2).clamp(2, 6);

  String _unit(int i) => saved('u$i') as String? ?? 'g';

  @override
  Widget build(BuildContext context) {
    final units = kUnits.keys.toList();
    String ul(String u) => u == 'pc' ? L(t, 'piece') : u;
    final items = [for (var i = 0; i < _count; i++) (v('p$i', -1), v('q$i', -1), _unit(i))];
    final best = cheapest(items);
    return ToolList(children: [
      for (var i = 0; i < _count; i++)
        AppPanel(
          child: Column(children: [
            Row(children: [
              Text('${L(t, 'item')} ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer(),
              if (best == i) Chip(avatar: const Icon(Icons.star_rounded, size: 18), label: Text(L(t, 'cheapest'))),
            ]),
            Row(children: [
              Expanded(child: field('p$i', L(t, 'price'), i == 0 ? '45' : '120')),
              const SizedBox(width: 8),
              Expanded(child: field('q$i', L(t, 'quantity'), i == 0 ? '500' : '1.5')),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: Pick<String>(
                  label: L(t, 'unit'),
                  values: units,
                  text: ul,
                  value: units.contains(_unit(i)) ? _unit(i) : 'g',
                  onChanged: (u) => setState(() => put('u$i', u)),
                ),
              ),
            ]),
            Builder(builder: (_) {
              final up = unitPrice(items[i].$1, items[i].$2, items[i].$3);
              if (up == null) return const SizedBox.shrink();
              final base = kUnits[items[i].$3]!.$1;
              final big = base == 'pc' ? 1 : 1000;
              final bl = base == 'pc' ? L(t, 'piece') : (base == 'g' ? 'kg' : 'L');
              return line('${L(t, 'per_unit')} (1 $bl)', m(up * big));
            }),
          ]),
        ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (_count < 6)
          TextButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: Text(L(t, 'add')),
            onPressed: () => setState(() => put('count', _count + 1)),
          ),
        if (_count > 2)
          TextButton.icon(
            icon: const Icon(Icons.remove_rounded),
            label: Text(L(t, 'delete')),
            onPressed: () => setState(() => put('count', _count - 1)),
          ),
      ]),
      AppInfoCard(L(t, 'unit_note')),
    ]);
  }
}
