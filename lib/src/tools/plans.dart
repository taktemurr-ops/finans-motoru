/// Uzun vadeli plan araçları: konut kredisi hesaplayıcı (ek ödemeli),
/// emeklilik birikim hesaplayıcı (bilgi amaçlı) ve net varlık takibi.
/// Hiçbiri yatırım, kredi ya da vergi tavsiyesi değildir.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../books.dart' show newId, toCsv;
import '../common.dart';
import '../core.dart';
import 'books_ui.dart' show BookState;
import 'calcs.dart' show CalcState;

/// Basit çubuk grafik (yıl/ay değerleri).
class _Bars extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  const _Bars(this.values, this.labels, this.color);

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final maxV = values.map((v) => v.abs()).reduce(math.max);
    final step = math.max(1, (values.length / 12).ceil());
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  height: 120 * (maxV <= 0 ? 0 : (values[i].abs() / maxV)).clamp(0.02, 1.0),
                  decoration: BoxDecoration(
                    color: values[i] < 0 ? Colors.redAccent : color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 14,
                  child: Text(i % step == 0 ? labels[i] : '',
                      maxLines: 1, overflow: TextOverflow.visible, style: const TextStyle(fontSize: 9, color: Colors.white60)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ================================================================ konut

class MortgageTool extends StatefulWidget {
  final ToolContext t;
  const MortgageTool(this.t, {super.key});
  @override
  State<MortgageTool> createState() => _MortgageState();
}

class _MortgageState extends CalcState<MortgageTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs =>
      const {'price': '5000000', 'down': '20', 'rate': '2.79', 'years': '10', 'extra': '0', 'lump': '0', 'lm': '12', 'fee': '1', 'inc': ''};
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final annual = saved('annual') as bool? ?? false;
    final downPct = saved('down_pct') as bool? ?? true;
    final price = v('price');
    final down = downPct ? price * v('down') / 100 : v('down');
    final principal = math.max(0.0, price - down);
    final r = annual ? monthlyFromAnnual(v('rate') / 100) : v('rate') / 100;
    final months = (v('years') * 12).round();
    final res = mortgage(principal, r, months, extra: v('extra'), lump: v('lump'), lumpMonth: v('lm').round());
    final fee = principal * v('fee') / 100;
    final income = n('inc');
    final rows = _showAll ? res.rows : res.rows.take(12).toList();
    final yearly = <double>[];
    for (var y = 0; y * 12 < res.rows.length; y++) {
      yearly.add(res.rows[math.min(res.rows.length - 1, y * 12 + 11)].balance);
    }
    final s = AppLook.of(context);
    return ToolList(children: [
      AppInfoCard(L(t, 'no_credit'), icon: Icons.info_outline_rounded),
      AppPanel(
        child: Column(children: [
          field('price', L(t, 'home_price'), '5000000'),
          Choice<bool>(
            values: const [true, false],
            labels: [L(t, 'down_pct'), L(t, 'down_amount')],
            selected: downPct,
            onChanged: (b) => setState(() => put('down_pct', b)),
          ),
          field('down', downPct ? L(t, 'down_pct') : L(t, 'down_amount'), '20', suffix: downPct ? '%' : null),
          Choice<bool>(
            values: const [false, true],
            labels: [L(t, 'rate_month'), L(t, 'rate_year')],
            selected: annual,
            onChanged: (b) => setState(() => put('annual', b)),
          ),
          field('rate', L(t, annual ? 'rate_year' : 'rate_month'), '2.79', suffix: '%'),
          field('years', L(t, 'term_years'), '10'),
          field('fee', L(t, 'fees_pct'), '1', suffix: '%'),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          AppHeading(L(t, 'prepay'), icon: Icons.fast_forward_rounded),
          field('extra', L(t, 'extra_monthly'), '0'),
          Row(children: [
            Expanded(child: field('lump', L(t, 'lump_sum'), '0')),
            const SizedBox(width: 8),
            Expanded(child: field('lm', L(t, 'in_month'), '12')),
          ]),
          field('inc', L(t, 'household_income'), ''),
        ]),
      ),
      if (res.rows.isEmpty)
        AppInfoCard(L(t, 'invalid'))
      else ...[
        AppPanel(
          child: Column(children: [
            line(L(t, 'payment'), m(res.payment), big: true),
            line(L(t, 'loan_amount'), m(principal)),
            line(L(t, 'ltv'), '${(price <= 0 ? 0 : principal / price * 100).toStringAsFixed(1)} %'),
            line(L(t, 'total_interest'), m(res.interest)),
            line(L(t, 'total_payment'), m(res.total)),
            if (fee > 0) line(L(t, 'fees'), m(fee)),
            line(L(t, 'upfront_cash'), m(down + fee)),
            if (res.months < res.baseMonths) ...[
              line(L(t, 'payoff_in'), '${res.months ~/ 12} ${L(t, 'years')} ${res.months % 12} ${L(t, 'months')}'),
              line(L(t, 'interest_saved'), m(res.interestSaved)),
            ],
            if (income != null && income > 0) line(L(t, 'payment_to_income'), '${(res.payment / income * 100).toStringAsFixed(1)} %'),
          ]),
        ),
        if (yearly.length > 1) ...[
          AppHeading(L(t, 'balance_by_year'), icon: Icons.bar_chart_rounded),
          AppPanel(child: _Bars(yearly, [for (var i = 0; i < yearly.length; i++) '${i + 1}'], s.accent)),
        ],
        AppHeading(L(t, 'schedule'), icon: Icons.table_rows_rounded),
        AppPanel(
          child: SingleChildScrollView(
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
                for (final x in rows)
                  DataRow(cells: [
                    DataCell(Text('${x.no}')),
                    DataCell(Text(m(x.payment))),
                    DataCell(Text(m(x.interest))),
                    DataCell(Text(m(x.principal))),
                    DataCell(Text(m(x.balance))),
                  ]),
              ],
            ),
          ),
        ),
        if (!_showAll && res.rows.length > 12)
          AppButton(label: L(t, 'show_all'), icon: Icons.unfold_more_rounded, onPressed: () => setState(() => _showAll = true)),
        AppInfoCard(L(t, 'mortgage_note')),
      ],
    ]);
  }
}

// ============================================================ emeklilik

class RetirementTool extends StatefulWidget {
  final ToolContext t;
  const RetirementTool(this.t, {super.key});
  @override
  State<RetirementTool> createState() => _RetirementState();
}

class _RetirementState extends CalcState<RetirementTool> {
  @override
  ToolContext get t => widget.t;

  @override
  Map<String, String> get defs => const {
        'age': '35',
        'ret': '60',
        'sav': '100000',
        'add': '5000',
        'raise': '20',
        'retn': '30',
        'infl': '25',
        'py': '25',
        'target': '',
      };

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    final age = v('age').round(), ret = v('ret').round(), py = v('py').round().clamp(1, 60);
    final res = retirement(
      age: age,
      retireAge: ret,
      savings: v('sav'),
      monthly: v('add'),
      annualReturn: v('retn') / 100,
      raise: v('raise') / 100,
      inflation: v('infl') / 100,
      payoutYears: py,
    );
    final target = n('target');
    final need = (target == null || target <= 0)
        ? null
        : requiredMonthly(
            targetReal: target,
            age: age,
            retireAge: ret,
            savings: v('sav'),
            annualReturn: v('retn') / 100,
            raise: v('raise') / 100,
            inflation: v('infl') / 100,
            payoutYears: py,
          );
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          Row(children: [
            Expanded(child: field('age', L(t, 'age_now'), '35')),
            const SizedBox(width: 8),
            Expanded(child: field('ret', L(t, 'retire_age'), '60')),
          ]),
          field('sav', L(t, 'current_savings'), '100000'),
          field('add', L(t, 'contribution'), '5000'),
          field('raise', L(t, 'contribution_raise'), '20', suffix: '%'),
          field('retn', L(t, 'expected_return'), '30', suffix: '%'),
          field('infl', L(t, 'expected_inflation'), '25', suffix: '%'),
          field('py', L(t, 'payout_years'), '25'),
        ]),
      ),
      if (res.yearly.isEmpty)
        AppInfoCard(L(t, 'invalid'))
      else ...[
        AppPanel(
          child: Column(children: [
            line(L(t, 'at_retirement'), m(res.atRetirement), big: true),
            line(L(t, 'in_todays_money'), m(res.atRetirementReal)),
            line(L(t, 'deposits'), m(res.deposited)),
            line(L(t, 'earned'), m(res.atRetirement - res.deposited)),
            line(L(t, 'monthly_income'), m(res.monthlyIncome)),
            line('${L(t, 'monthly_income')} · ${L(t, 'in_todays_money')}', m(res.monthlyIncomeReal)),
          ]),
        ),
        AppHeading(L(t, 'balance_by_year'), icon: Icons.stacked_line_chart_rounded),
        AppPanel(child: _Bars(res.yearly, [for (var i = 0; i < res.yearly.length; i++) '${age + i + 1}'], s.accent)),
        AppPanel(
          child: Column(children: [
            AppHeading(L(t, 'goal_income'), icon: Icons.flag_rounded),
            field('target', L(t, 'target_income_real'), ''),
            if (target != null && target > 0)
              line(L(t, 'needed_monthly'), need == null ? '—' : m(need), big: true),
          ]),
        ),
      ],
      AppInfoCard(L(t, 'retire_note')),
    ]);
  }
}

// ============================================================ net varlık

class NetWorthTool extends StatefulWidget {
  final ToolContext t;
  const NetWorthTool(this.t, {super.key});
  @override
  State<NetWorthTool> createState() => _NetWorthState();
}

class _NetWorthState extends BookState<NetWorthTool> {
  @override
  ToolContext get t => widget.t;
  List<Map<String, Object?>> _items = [];
  List<Map<String, Object?>> _snaps = [];

  @override
  Future<void> load() async {
    _items = await readList('items');
    _snaps = await readList('snaps');
  }

  bool _isAsset(Map<String, Object?> e) => e['k'] != 'l';
  int _c(Map<String, Object?> e) => ((e['c'] as num?) ?? 0).toInt();

  Future<void> _save() async {
    final (a, l, _) = netWorth([for (final e in _items) (_isAsset(e), _c(e))]);
    _snaps = upsertSnapshot(_snaps, DateTime.now(), a, l);
    await t.store.writeList('items', _items);
    await t.store.writeList('snaps', _snaps);
  }

  Future<void> _edit({required bool asset, Map<String, Object?>? e}) async {
    final cats = Ls(t, asset ? 'asset_cats' : 'debt_cats');
    final r = await editForm(context, t, L(t, e == null ? 'add' : 'edit'), [
      F.text('name', L(t, 'name'), initial: '${e?['n'] ?? ''}', must: true),
      F.choice('cat', L(t, 'category'), cats, initial: ((e?['cat'] as num?) ?? 0).toInt().clamp(0, cats.length - 1)),
      F.money('c', L(t, asset ? 'value' : 'balance'), initial: e == null ? null : _c(e)),
    ]);
    if (r == null || !mounted) return;
    final item = <String, Object?>{
      'id': e?['id'] ?? newId(),
      'n': r['name'],
      'k': asset ? 'a' : 'l',
      'cat': r['cat'],
      'c': r['c'] ?? 0,
      'u': DateTime.now().millisecondsSinceEpoch,
    };
    setState(() {
      final i = _items.indexWhere((x) => x['id'] == item['id']);
      if (i >= 0) {
        _items[i] = item;
      } else {
        _items.add(item);
      }
    });
    await _save();
  }

  Future<void> _delete(Map<String, Object?> e) async {
    if (!await confirmDelete(context, t)) return;
    setState(() => _items.removeWhere((x) => x['id'] == e['id']));
    await _save();
  }

  String _csv() => toCsv([
        [L(t, 'type'), L(t, 'category'), L(t, 'name'), L(t, 'amount')],
        for (final e in _items)
          [
            _isAsset(e) ? L(t, 'assets') : L(t, 'liabilities'),
            () {
              final cats = Ls(t, _isAsset(e) ? 'asset_cats' : 'debt_cats');
              final i = ((e['cat'] as num?) ?? 0).toInt();
              return i < cats.length ? cats[i] : '';
            }(),
            '${e['n']}',
            (_c(e) / 100).toStringAsFixed(2),
          ],
        [],
        [L(t, 'date'), L(t, 'assets'), L(t, 'liabilities'), L(t, 'net_worth')],
        for (final s in _snaps)
          [
            '${s['m']}',
            ((((s['a'] as num?) ?? 0)) / 100).toStringAsFixed(2),
            ((((s['l'] as num?) ?? 0)) / 100).toStringAsFixed(2),
            ((((s['a'] as num?) ?? 0) - ((s['l'] as num?) ?? 0)) / 100).toStringAsFixed(2),
          ],
      ]);

  Widget _group(bool asset) {
    final cats = Ls(t, asset ? 'asset_cats' : 'debt_cats');
    final list = _items.where((e) => _isAsset(e) == asset).toList()..sort((a, b) => _c(b).compareTo(_c(a)));
    return AppPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: AppHeading(L(t, asset ? 'assets' : 'liabilities'), icon: asset ? Icons.savings_rounded : Icons.credit_card_rounded)),
          IconButton.filledTonal(onPressed: () => _edit(asset: asset), icon: const Icon(Icons.add_rounded)),
        ]),
        if (list.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(L(t, 'empty_list'), style: const TextStyle(color: Colors.white60))),
        for (final e in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            onTap: () => _edit(asset: asset, e: e),
            onLongPress: () => _delete(e),
            title: Text('${e['n']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(() {
              final i = ((e['cat'] as num?) ?? 0).toInt();
              return i < cats.length ? cats[i] : '';
            }()),
            trailing: Text(mc(_c(e)), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final s = AppLook.of(context);
    final (a, l, net) = netWorth([for (final e in _items) (_isAsset(e), _c(e))]);
    final hist = _snaps.length > 24 ? _snaps.sublist(_snaps.length - 24) : _snaps;
    final prev = _snaps.length >= 2 ? _snaps[_snaps.length - 2] : null;
    final prevNet = prev == null ? null : ((prev['a'] as num?) ?? 0).toInt() - ((prev['l'] as num?) ?? 0).toInt();
    return ToolList(children: [
      bar(onExport: () => exportCsv(context, t, 'net_worth', _csv())),
      AppPanel(
        child: Column(children: [
          line(L(t, 'net_worth'), mc(net), big: true),
          line(L(t, 'assets'), mc(a)),
          line(L(t, 'liabilities'), mc(l)),
          if (a > 0) line(L(t, 'debt_ratio'), '${(l / a * 100).toStringAsFixed(1)} %'),
          if (prevNet != null)
            line(L(t, 'vs_last_month'), '${net >= prevNet ? '+' : '−'}${mc((net - prevNet).abs())}'),
        ]),
      ),
      if (hist.length >= 2) ...[
        AppHeading(L(t, 'net_worth_trend'), icon: Icons.show_chart_rounded),
        AppPanel(
          child: _Bars(
            [for (final h in hist) (((h['a'] as num?) ?? 0) - ((h['l'] as num?) ?? 0)) / 100.0],
            [for (final h in hist) '${h['m']}'.substring(2)],
            s.accent,
          ),
        ),
      ],
      _group(true),
      _group(false),
      AppInfoCard(L(t, 'networth_note'), icon: Icons.lock_rounded),
    ]);
  }
}
