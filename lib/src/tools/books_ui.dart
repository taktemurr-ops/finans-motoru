/// Kayıt tutan araçlar: bütçe ve harcama, borç, birikim hedefi, abonelik,
/// fatura hatırlatıcı ve harçlık. Veriler yalnızca cihazda saklanır; banka
/// bağlantısı yoktur. Her biri CSV olarak dışa aktarılabilir.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../books.dart';
import '../common.dart';
import '../core.dart';
import '../platform/notify.dart';

/// Kayıt araçlarının ortak durumu: para simgesi ve yükleme.
abstract class BookState<W extends StatefulWidget> extends State<W> {
  ToolContext get t;
  String cur = '';
  bool loaded = false;

  Future<void> load();

  @override
  void initState() {
    super.initState();
    cur = defaultCurrency(t.lang);
    () async {
      final c = await loadCurrency(t);
      await load();
      if (mounted) {
        setState(() {
          cur = c;
          loaded = true;
        });
      }
    }();
  }

  String mc(int cents) => fmtCents(cents, t.lang, cur);

  Widget bar({VoidCallback? onExport, List<Widget> extra = const []}) => BookBar(
        t: t,
        currency: cur,
        onCurrency: (v) => setState(() => cur = v),
        onExport: onExport,
        extra: extra,
      );

  Widget line(String label, String value, {bool big = false}) => AppResult(label: label, value: value, lang: t.lang, big: big);

  String date(DateTime d) => MaterialLocalizations.of(context).formatMediumDate(d);

  Future<List<Map<String, Object?>>> readList(String key) => t.store.readList(key);
}

/// Bildirim kimliği (kayıt kimliğinden).
int notifyId(String id, [int slot = 0]) => ((id.hashCode & 0x0fffffff) << 2) + slot;

/// Bildirim izni: önce kısa açıklama, sonra sistem isteği (bir kez).
Future<bool> ensureNotify(BuildContext context, ToolContext t) async {
  if (!Notify.supported) return false;
  if (!await t.store.readBool('perm.notify')) {
    if (!context.mounted) return false;
    final ok = await explainPermission(context, lang: t.lang, icon: Icons.notifications_active_rounded, reason: L(t, 'perm_notify'));
    if (!ok) return false;
    await t.store.writeBool('perm.notify', true);
  }
  return Notify.requestPermission();
}

/// Sabah 09:00'a ayarlanmış hatırlatma zamanı (geçmişteyse null).
DateTime? remindAt(DateTime day, {int daysBefore = 0}) {
  final d = DateTime(day.year, day.month, day.day - daysBefore, 9);
  return d.isAfter(DateTime.now()) ? d : null;
}

// ================================================================= bütçe

class BudgetTool extends StatefulWidget {
  final ToolContext t;
  const BudgetTool(this.t, {super.key});
  @override
  State<BudgetTool> createState() => _BudgetState();
}

class _BudgetState extends BookState<BudgetTool> {
  @override
  ToolContext get t => widget.t;
  Ledger _l = const Ledger();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _tab = 0;
  String _q = '';
  final _search = TextEditingController();
  bool _report = false;

  @override
  Future<void> load() async {
    final m = await t.store.readMap('ledger');
    var l = Ledger.fromJson(m);
    final before = l.entries.length;
    l = l.postDue(DateTime.now());
    _l = l;
    if (l.entries.length != before) await _save();
    _report = await t.unlockedToday('year_report');
  }

  Future<void> _save() => t.store.writeMap('ledger', _l.toJson());

  void _set(Ledger l) {
    setState(() => _l = l);
    unawaited(_save());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _cats => Ls(t, 'cats');
  List<String> get _methods => Ls(t, 'methods');

  Future<void> _editEntry([Entry? e]) async {
    final cats = _cats;
    final r = await editForm(context, t, L(t, e == null ? 'add' : 'edit'), [
      F.choice('kind', L(t, 'type'), [L(t, 'expense'), L(t, 'income')], initial: e?.income == true ? 1 : 0),
      F.money('amount', L(t, 'amount'), initial: e?.cents),
      F.choice('cat', L(t, 'category'), cats, initial: e == null ? 0 : _catIndex(e.category)),
      F.choice('method', L(t, 'method'), _methods, initial: e?.method ?? 0),
      F.date('date', L(t, 'date'), initial: e?.date ?? DateTime.now()),
      F.text('note', L(t, 'note'), initial: e?.note ?? ''),
    ]);
    if (r == null) return;
    final ne = Entry(
      id: e?.id ?? newId(),
      date: r['date'] as DateTime? ?? DateTime.now(),
      cents: r['amount'] as int,
      income: r['kind'] == 1,
      category: cats[r['cat'] as int],
      method: r['method'] as int,
      note: r['note'] as String,
      ruleId: e?.ruleId,
    );
    final list = [for (final x in _l.entries) if (x.id != ne.id) x, ne]..sort((a, b) => b.date.compareTo(a.date));
    _set(_l.copyWith(entries: list));
  }

  int _catIndex(String c) {
    final i = _cats.indexOf(c);
    return i < 0 ? _cats.length - 1 : i;
  }

  Future<void> _editRule([Rule? x]) async {
    final cats = _cats;
    final r = await editForm(context, t, L(t, 'recurring'), [
      F.text('title', L(t, 'name'), initial: x?.title ?? '', must: true),
      F.choice('kind', L(t, 'type'), [L(t, 'expense'), L(t, 'income')], initial: x?.income == true ? 1 : 0),
      F.money('amount', L(t, 'amount'), initial: x?.cents),
      F.choice('cat', L(t, 'category'), cats, initial: x == null ? 0 : _catIndex(x.category)),
      F.choice('method', L(t, 'method'), _methods, initial: x?.method ?? 0),
      F.choice('freq', L(t, 'period'), [L(t, 'monthly'), L(t, 'weekly')], initial: x?.freq == 'week' ? 1 : 0),
      F.date('next', L(t, 'next_due'), initial: x?.next ?? DateTime.now()),
      F.toggle('on', L(t, 'active'), initial: x?.enabled ?? true),
    ]);
    if (r == null) return;
    final nr = Rule(
      id: x?.id ?? newId(),
      title: r['title'] as String,
      cents: r['amount'] as int,
      income: r['kind'] == 1,
      category: cats[r['cat'] as int],
      method: r['method'] as int,
      next: r['next'] as DateTime? ?? DateTime.now(),
      freq: r['freq'] == 1 ? 'week' : 'month',
      enabled: r['on'] as bool? ?? true,
    );
    _set(_l.copyWith(rules: [for (final y in _l.rules) if (y.id != nr.id) y, nr]).postDue(DateTime.now()));
  }

  Future<void> _editBudget(String cat) async {
    final r = await editForm(context, t, '${L(t, 'budget')} · $cat', [
      F.money('amount', L(t, 'monthly_limit'), initial: _l.budgets[cat], must: false),
    ]);
    if (r == null) return;
    final b = {..._l.budgets};
    final v = r['amount'] as int?;
    if (v == null || v == 0) {
      b.remove(cat);
    } else {
      b[cat] = v;
    }
    _set(_l.copyWith(budgets: b));
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final s = _l.month(_month);
    final loc = MaterialLocalizations.of(context);
    return ToolList(children: [
      bar(onExport: () => exportCsv(context, t, 'budget', _l.csv(_methods))),
      Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
        ),
        Expanded(
          child: Text(loc.formatMonthYear(_month),
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
        ),
      ]),
      Choice<int>(
        values: const [0, 1, 2, 3],
        labels: [L(t, 'summary'), L(t, 'records'), L(t, 'budgets'), L(t, 'recurring')],
        selected: _tab,
        onChanged: (i) => setState(() => _tab = i),
      ),
      ...switch (_tab) { 1 => _entries(), 2 => _budgets(s), 3 => _rules(), _ => _summary(s) },
    ]);
  }

  List<Widget> _summary(MonthSummary s) {
    final warn = _l.warnings(_month);
    final cats = s.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      AppPanel(
        child: Column(children: [
          line(L(t, 'balance'), mc(s.balance), big: true),
          line(L(t, 'income'), mc(s.income)),
          line(L(t, 'expense'), mc(s.expense)),
        ]),
      ),
      AppButton(label: L(t, 'add'), icon: Icons.add_rounded, onPressed: () => _editEntry()),
      for (final w in warn)
        AppInfoCard('${L(t, w.$2 >= 1 ? 'over_budget' : 'near_limit')}: ${w.$1} (${fmtPct(w.$2 * 100)})',
            icon: Icons.warning_amber_rounded),
      if (cats.isNotEmpty) ...[
        AppHeading(L(t, 'by_category'), icon: Icons.pie_chart_rounded),
        AppPanel(child: Column(children: [for (final c in cats) _bar(c.key, c.value, s.expense)])),
        AppHeading(L(t, 'by_method'), icon: Icons.credit_card_rounded),
        AppPanel(
          child: Column(children: [
            for (final e in s.byMethod.entries) _bar(_methods[e.key.clamp(0, _methods.length - 1)], e.value, s.expense),
          ]),
        ),
      ],
      AppHeading(L(t, 'year_report'), icon: Icons.calendar_view_month_rounded),
      if (_report)
        AppPanel(child: Column(children: _yearRows()))
      else
        AppButton(
          label: t.tx('unlock_ad'),
          icon: Icons.ondemand_video_rounded,
          onPressed: () async {
            final ok = await t.unlockForToday('year_report');
            if (mounted) setState(() => _report = ok);
          },
        ),
    ];
  }

  List<Widget> _yearRows() {
    final loc = MaterialLocalizations.of(context);
    var inc = 0, exp = 0;
    final rows = <Widget>[];
    for (var i = 11; i >= 0; i--) {
      final m = DateTime(_month.year, _month.month - i);
      final s = _l.month(m);
      inc += s.income;
      exp += s.expense;
      rows.add(line(loc.formatMonthYear(m), '${mc(s.income)} / ${mc(s.expense)}'));
    }
    rows.add(const Divider());
    rows.add(line(L(t, 'balance'), mc(inc - exp), big: true));
    return rows;
  }

  Widget _bar(String label, int v, int total) {
    final f = total <= 0 ? 0.0 : v / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(label)), Text(mc(v), style: const TextStyle(fontWeight: FontWeight.w700))]),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: f.clamp(0.0, 1.0), minHeight: 6, borderRadius: BorderRadius.circular(4)),
      ]),
    );
  }

  List<Widget> _entries() {
    final list = _l.search(_q, month: monthKey(_month));
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppTextField(controller: _search, label: L(t, 'search'), onChanged: (v) => setState(() => _q = v)),
      ),
      AppButton(label: L(t, 'add'), icon: Icons.add_rounded, onPressed: () => _editEntry()),
      if (list.isEmpty) emptyNote(t),
      for (final e in list)
        Card(
          child: ListTile(
            leading: Icon(e.income ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: e.income ? Colors.lightGreenAccent : Colors.orangeAccent),
            title: Text(e.note.isEmpty ? e.category : e.note),
            subtitle: Text('${date(e.date)} · ${e.category} · ${_methods[e.method.clamp(0, _methods.length - 1)]}'),
            trailing: Text('${e.income ? '+' : '−'}${mc(e.cents)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            onTap: () => _editEntry(e),
            onLongPress: () async {
              if (await confirmDelete(context, t)) {
                _set(_l.copyWith(entries: [for (final x in _l.entries) if (x.id != e.id) x]));
              }
            },
          ),
        ),
    ];
  }

  List<Widget> _budgets(MonthSummary s) {
    final cats = _cats;
    return [
      AppInfoCard(L(t, 'budget_hint')),
      for (final c in cats)
        Card(
          child: ListTile(
            title: Text(c),
            subtitle: _l.budgets[c] == null
                ? Text(mc(s.byCategory[c] ?? 0))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${mc(s.byCategory[c] ?? 0)} / ${mc(_l.budgets[c]!)}'),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: ((s.byCategory[c] ?? 0) / _l.budgets[c]!).clamp(0.0, 1.0),
                      color: (s.byCategory[c] ?? 0) > _l.budgets[c]! ? Colors.redAccent : null,
                    ),
                  ]),
            trailing: const Icon(Icons.edit_rounded),
            onTap: () => _editBudget(c),
          ),
        ),
    ];
  }

  List<Widget> _rules() {
    return [
      AppInfoCard(L(t, 'recurring_hint')),
      AppButton(label: L(t, 'add'), icon: Icons.add_rounded, onPressed: () => _editRule()),
      if (_l.rules.isEmpty) emptyNote(t),
      for (final r in _l.rules)
        Card(
          child: ListTile(
            leading: Icon(r.enabled ? Icons.repeat_rounded : Icons.pause_circle_outline_rounded),
            title: Text(r.title),
            subtitle: Text('${L(t, r.freq == 'week' ? 'weekly' : 'monthly')} · ${L(t, 'next_due')}: ${date(r.next)}'),
            trailing: Text('${r.income ? '+' : '−'}${mc(r.cents)}'),
            onTap: () => _editRule(r),
            onLongPress: () async {
              if (await confirmDelete(context, t)) {
                _set(_l.copyWith(rules: [for (final x in _l.rules) if (x.id != r.id) x]));
              }
            },
          ),
        ),
    ];
  }
}

// ================================================================== borç

class DebtTool extends StatefulWidget {
  final ToolContext t;
  const DebtTool(this.t, {super.key});
  @override
  State<DebtTool> createState() => _DebtState();
}

class _DebtState extends BookState<DebtTool> {
  @override
  ToolContext get t => widget.t;
  List<Debt> _d = [];
  bool _showSettled = false;

  @override
  Future<void> load() async {
    _d = (await readList('debts')).map(Debt.fromJson).whereType<Debt>().toList();
  }

  void _set(List<Debt> d) {
    setState(() => _d = d);
    unawaited(t.store.writeList('debts', [for (final x in d) x.toJson()]));
  }

  Future<void> _add([Debt? e]) async {
    final r = await editForm(context, t, L(t, e == null ? 'add' : 'edit'), [
      F.choice('kind', L(t, 'type'), [L(t, 'i_owe'), L(t, 'owed_to_me')], initial: e?.owe == false ? 1 : 0),
      F.text('name', L(t, 'person'), initial: e?.name ?? '', must: true),
      F.money('amount', L(t, 'amount'), initial: e?.cents),
      F.date('due', L(t, 'due_date'), initial: e?.due),
      F.text('note', L(t, 'note'), initial: e?.note ?? ''),
    ]);
    if (r == null) return;
    final nd = Debt(
      id: e?.id ?? newId(),
      name: r['name'] as String,
      cents: r['amount'] as int,
      owe: r['kind'] == 0,
      created: e?.created ?? DateTime.now(),
      due: r['due'] as DateTime?,
      note: r['note'] as String,
      payments: e?.payments ?? const [],
    );
    _set([for (final x in _d) if (x.id != nd.id) x, nd]);
  }

  Future<void> _pay(Debt d) async {
    final r = await editForm(context, t, '${L(t, 'pay')} · ${d.name}', [
      F.money('amount', L(t, 'amount'), initial: d.remaining),
      F.date('date', L(t, 'date'), initial: DateTime.now()),
    ]);
    if (r == null) return;
    _set([for (final x in _d) x.id == d.id ? x.pay(r['amount'] as int, r['date'] as DateTime? ?? DateTime.now()) : x]);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final tot = debtTotals(_d);
    final now = DateTime.now();
    final list = _d.where((d) => _showSettled || !d.settled).toList()
      ..sort((a, b) => (a.due ?? DateTime(9999)).compareTo(b.due ?? DateTime(9999)));
    return ToolList(children: [
      bar(onExport: () => exportCsv(context, t, 'debts', debtsCsv(_d))),
      AppPanel(
        child: Column(children: [
          line(L(t, 'i_owe'), mc(tot.$1), big: true),
          line(L(t, 'owed_to_me'), mc(tot.$2)),
          line(L(t, 'balance'), mc(tot.$2 - tot.$1)),
        ]),
      ),
      AppButton(label: L(t, 'add'), icon: Icons.add_rounded, onPressed: () => _add()),
      SwitchListTile(
        title: Text(L(t, 'show_settled')),
        value: _showSettled,
        onChanged: (b) => setState(() => _showSettled = b),
      ),
      if (list.isEmpty) emptyNote(t),
      for (final d in list)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(d.owe ? Icons.north_east_rounded : Icons.south_west_rounded,
                    color: d.owe ? Colors.orangeAccent : Colors.lightGreenAccent),
                const SizedBox(width: 8),
                Expanded(child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Text(mc(d.remaining), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: d.cents == 0 ? 0.0 : d.paid / d.cents),
              const SizedBox(height: 6),
              Text([
                '${L(t, 'paid')}: ${mc(d.paid)} / ${mc(d.cents)}',
                if (d.due != null) '${L(t, 'due_date')}: ${date(d.due!)}',
                if (d.overdue(now)) L(t, 'overdue'),
                if (d.note.isNotEmpty) d.note,
              ].join(' · ')),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (!d.settled) TextButton.icon(onPressed: () => _pay(d), icon: const Icon(Icons.payments_rounded), label: Text(L(t, 'pay'))),
                IconButton(onPressed: () => _add(d), icon: const Icon(Icons.edit_rounded)),
                IconButton(
                  onPressed: () async {
                    if (await confirmDelete(context, t)) _set([for (final x in _d) if (x.id != d.id) x]);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ]),
            ]),
          ),
        ),
      AppInfoCard(L(t, 'debt_note')),
    ]);
  }
}

// ======================================================== birikim hedefi

class GoalTool extends StatefulWidget {
  final ToolContext t;
  const GoalTool(this.t, {super.key});
  @override
  State<GoalTool> createState() => _GoalState();
}

class _GoalState extends BookState<GoalTool> {
  @override
  ToolContext get t => widget.t;
  List<Goal> _g = [];

  @override
  Future<void> load() async {
    _g = (await readList('goals')).map(Goal.fromJson).whereType<Goal>().toList();
  }

  void _set(List<Goal> g) {
    setState(() => _g = g);
    unawaited(t.store.writeList('goals', [for (final x in g) x.toJson()]));
  }

  Future<void> _add([Goal? e]) async {
    final r = await editForm(context, t, L(t, e == null ? 'add' : 'edit'), [
      F.text('title', L(t, 'goal'), initial: e?.title ?? '', must: true),
      F.money('target', L(t, 'target'), initial: e?.target),
      F.date('deadline', L(t, 'deadline'), initial: e?.deadline),
    ]);
    if (r == null) return;
    final ng = Goal(
      id: e?.id ?? newId(),
      title: r['title'] as String,
      target: r['target'] as int,
      created: e?.created ?? DateTime.now(),
      deadline: r['deadline'] as DateTime?,
      moves: e?.moves ?? const [],
    );
    _set([for (final x in _g) if (x.id != ng.id) x, ng]);
  }

  Future<void> _move(Goal g, bool deposit) async {
    final r = await editForm(context, t, '${L(t, deposit ? 'deposit' : 'withdraw')} · ${g.title}', [
      F.money('amount', L(t, 'amount')),
      F.date('date', L(t, 'date'), initial: DateTime.now()),
    ]);
    if (r == null) return;
    final c = r['amount'] as int;
    _set([for (final x in _g) x.id == g.id ? x.move(deposit ? c : -c, r['date'] as DateTime? ?? DateTime.now()) : x]);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final now = DateTime.now();
    final total = _g.fold<int>(0, (a, g) => a + g.saved);
    return ToolList(children: [
      bar(onExport: () => exportCsv(context, t, 'savings', goalsCsv(_g))),
      AppPanel(child: line(L(t, 'saved_amount'), mc(total), big: true)),
      AppButton(label: L(t, 'add'), icon: Icons.add_rounded, onPressed: () => _add()),
      if (_g.isEmpty) emptyNote(t),
      for (final g in _g)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(g.reached ? Icons.emoji_events_rounded : Icons.savings_rounded, color: Colors.amberAccent),
                const SizedBox(width: 8),
                Expanded(child: Text(g.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Text(fmtPct(g.progress * 100), style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: g.progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 6),
              Text([
                '${mc(g.saved)} / ${mc(g.target)}',
                if (g.deadline != null) '${L(t, 'deadline')}: ${date(g.deadline!)}',
                if (g.perMonth(now) != null) '${L(t, 'per_month_needed')}: ${mc(g.perMonth(now)!)}',
                if (g.reached) L(t, 'reached'),
              ].join(' · ')),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton.icon(onPressed: () => _move(g, true), icon: const Icon(Icons.add_rounded), label: Text(L(t, 'deposit'))),
                TextButton.icon(
                    onPressed: g.saved > 0 ? () => _move(g, false) : null,
                    icon: const Icon(Icons.remove_rounded),
                    label: Text(L(t, 'withdraw'))),
                IconButton(onPressed: () => _add(g), icon: const Icon(Icons.edit_rounded)),
                IconButton(
                  onPressed: () async {
                    if (await confirmDelete(context, t)) _set([for (final x in _g) if (x.id != g.id) x]);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

// ============================================================== abonelik

class SubsTool extends StatefulWidget {
  final ToolContext t;
  const SubsTool(this.t, {super.key});
  @override
  State<SubsTool> createState() => _SubsState();
}

class _SubsState extends BookState<SubsTool> {
  @override
  ToolContext get t => widget.t;
  List<Sub> _s = [];
  static const _periods = ['month', 'year', 'week'];

  @override
  Future<void> load() async {
    _s = (await readList('subs')).map(Sub.fromJson).whereType<Sub>().toList();
  }

  void _set(List<Sub> s) {
    setState(() => _s = s);
    unawaited(t.store.writeList('subs', [for (final x in s) x.toJson()]));
  }

  Future<void> _schedule(Sub s) async {
    await Notify.cancel(notifyId(s.id));
    if (!s.remind) return;
    final at = remindAt(s.upcoming(DateTime.now()), daysBefore: 1);
    if (at != null) await Notify.schedule(notifyId(s.id), s.name, '${L(t, 'renews')}: ${mc(s.cents)}', at);
  }

  Future<void> _add([Sub? e]) async {
    final r = await editForm(context, t, L(t, e == null ? 'add' : 'edit'), [
      F.text('name', L(t, 'name'), initial: e?.name ?? '', must: true),
      F.money('amount', L(t, 'amount'), initial: e?.cents),
      F.choice('period', L(t, 'period'), [L(t, 'monthly'), L(t, 'yearly'), L(t, 'weekly')],
          initial: e == null ? 0 : _periods.indexOf(e.period).clamp(0, 2)),
      F.date('next', L(t, 'renews'), initial: e?.next ?? DateTime.now()),
      F.toggle('remind', L(t, 'remind'), initial: e?.remind ?? false),
    ]);
    if (r == null || !mounted) return;
    var remind = r['remind'] as bool? ?? false;
    if (remind && !await ensureNotify(context, t)) remind = false;
    final ns = Sub(
      id: e?.id ?? newId(),
      name: r['name'] as String,
      cents: r['amount'] as int,
      period: _periods[r['period'] as int],
      next: r['next'] as DateTime? ?? DateTime.now(),
      remind: remind,
    );
    _set([for (final x in _s) if (x.id != ns.id) x, ns]);
    await _schedule(ns);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final now = DateTime.now();
    final monthly = _s.fold<double>(0, (a, s) => a + s.monthly);
    final list = [..._s]..sort((a, b) => a.upcoming(now).compareTo(b.upcoming(now)));
    return ToolList(children: [
      bar(onExport: () => exportCsv(context, t, 'subscriptions', subsCsv(_s, now))),
      AppPanel(
        child: Column(children: [
          line(L(t, 'monthly_total'), mc(monthly.round()), big: true),
          line(L(t, 'yearly_total'), mc((monthly * 12).round())),
        ]),
      ),
      AppButton(label: L(t, 'add'), icon: Icons.add_rounded, onPressed: () => _add()),
      if (kIsWeb) AppInfoCard(L(t, 'notify_web'), icon: Icons.notifications_off_rounded),
      if (list.isEmpty) emptyNote(t),
      for (final s in list)
        Card(
          child: ListTile(
            leading: Icon(s.remind ? Icons.notifications_active_rounded : Icons.autorenew_rounded),
            title: Text(s.name),
            subtitle: Text('${L(t, 'renews')}: ${date(s.upcoming(now))} · '
                '${L(t, s.period == 'year' ? 'yearly' : s.period == 'week' ? 'weekly' : 'monthly')}'),
            trailing: Text(mc(s.cents), style: const TextStyle(fontWeight: FontWeight.w800)),
            onTap: () => _add(s),
            onLongPress: () async {
              if (await confirmDelete(context, t)) {
                await Notify.cancel(notifyId(s.id));
                _set([for (final x in _s) if (x.id != s.id) x]);
              }
            },
          ),
        ),
    ]);
  }
}

// =============================================================== fatura

class BillTool extends StatefulWidget {
  final ToolContext t;
  const BillTool(this.t, {super.key});
  @override
  State<BillTool> createState() => _BillState();
}

class _BillState extends BookState<BillTool> {
  @override
  ToolContext get t => widget.t;
  List<Bill> _b = [];

  @override
  Future<void> load() async {
    _b = (await readList('bills')).map(Bill.fromJson).whereType<Bill>().toList();
  }

  void _set(List<Bill> b) {
    setState(() => _b = b);
    unawaited(t.store.writeList('bills', [for (final x in b) x.toJson()]));
  }

  /// Sonraki son ödeme gününe iki hatırlatma: bir gün önce ve o gün.
  Future<void> _schedule(Bill b) async {
    await Notify.cancel(notifyId(b.id, 0));
    await Notify.cancel(notifyId(b.id, 1));
    if (!b.remind) return;
    final due = b.nextDue(DateTime.now());
    final body = b.cents > 0 ? '${L(t, 'bill_due')} · ${mc(b.cents)}' : L(t, 'bill_due');
    final a = remindAt(due, daysBefore: 1), c = remindAt(due);
    if (a != null) await Notify.schedule(notifyId(b.id, 0), b.name, body, a);
    if (c != null) await Notify.schedule(notifyId(b.id, 1), b.name, body, c);
  }

  Future<void> _add([Bill? e]) async {
    final r = await editForm(context, t, L(t, e == null ? 'add' : 'edit'), [
      F.text('name', L(t, 'bill'), initial: e?.name ?? '', must: true),
      F.money('amount', L(t, 'estimate'), initial: e?.cents, must: false),
      F.integer('day', L(t, 'due_day'), initial: e?.day ?? 15),
      F.toggle('remind', L(t, 'remind'), initial: e?.remind ?? true),
    ]);
    if (r == null || !mounted) return;
    var remind = r['remind'] as bool? ?? true;
    if (remind && !await ensureNotify(context, t)) remind = false;
    final nb = Bill(
      id: e?.id ?? newId(),
      name: r['name'] as String,
      cents: r['amount'] as int? ?? 0,
      day: (r['day'] as int).clamp(1, 31),
      remind: remind,
      paid: e?.paid ?? const {},
    );
    _set([for (final x in _b) if (x.id != nb.id) x, nb]);
    await _schedule(nb);
  }

  Future<void> _togglePaid(Bill b, DateTime month) async {
    Bill nb;
    if (b.paidIn(month)) {
      nb = b.unmark(month);
    } else {
      final r = await editForm(context, t, '${L(t, 'mark_paid')} · ${b.name}', [
        F.money('amount', L(t, 'amount'), initial: b.cents > 0 ? b.cents : null, must: false),
      ]);
      if (r == null) return;
      nb = b.markPaid(month, r['amount'] as int? ?? 0);
    }
    _set([for (final x in _b) x.id == b.id ? nb : x]);
    await _schedule(nb);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final list = [..._b]..sort((a, b) => a.dueIn(month).compareTo(b.dueIn(month)));
    final unpaid = list.where((b) => !b.paidIn(month)).fold<int>(0, (a, b) => a + b.cents);
    final today = DateTime(now.year, now.month, now.day);
    return ToolList(children: [
      bar(onExport: () => exportCsv(context, t, 'bills', billsCsv(_b))),
      AppPanel(
        child: Column(children: [
          line(L(t, 'unpaid'), mc(unpaid), big: true),
          line(L(t, 'paid'), '${list.where((b) => b.paidIn(month)).length} / ${list.length}'),
        ]),
      ),
      AppButton(label: L(t, 'add'), icon: Icons.add_rounded, onPressed: () => _add()),
      if (!Notify.supported) AppInfoCard(L(t, 'notify_web'), icon: Icons.notifications_off_rounded),
      if (list.isEmpty) emptyNote(t),
      for (final b in list)
        Card(
          child: ListTile(
            leading: Checkbox(value: b.paidIn(month), onChanged: (_) => _togglePaid(b, month)),
            title: Text(b.name),
            subtitle: Text([
              '${L(t, 'due_date')}: ${date(b.dueIn(month))}',
              if (!b.paidIn(month) && b.dueIn(month).isBefore(today)) L(t, 'overdue'),
              if (b.remind) '🔔',
            ].join(' · ')),
            trailing: Text(b.paidIn(month) ? mc(b.paid[monthKey(month)] ?? 0) : (b.cents > 0 ? mc(b.cents) : '')),
            onTap: () => _add(b),
            onLongPress: () async {
              if (await confirmDelete(context, t)) {
                await Notify.cancel(notifyId(b.id, 0));
                await Notify.cancel(notifyId(b.id, 1));
                _set([for (final x in _b) if (x.id != b.id) x]);
              }
            },
          ),
        ),
    ]);
  }
}

// ============================================================== harçlık

class AllowanceTool extends StatefulWidget {
  final ToolContext t;
  const AllowanceTool(this.t, {super.key});
  @override
  State<AllowanceTool> createState() => _AllowanceState();
}

class _AllowanceState extends BookState<AllowanceTool> {
  @override
  ToolContext get t => widget.t;
  List<Kid> _k = [];
  String? _open;

  @override
  Future<void> load() async {
    _k = (await readList('kids')).map(Kid.fromJson).whereType<Kid>().toList();
  }

  void _set(List<Kid> k) {
    setState(() => _k = k);
    unawaited(t.store.writeList('kids', [for (final x in k) x.toJson()]));
  }

  Future<void> _add([Kid? e]) async {
    final r = await editForm(context, t, L(t, e == null ? 'add' : 'edit'), [
      F.text('name', L(t, 'name'), initial: e?.name ?? '', must: true),
      F.money('weekly', L(t, 'weekly_amount'), initial: e?.weekly, must: false),
    ]);
    if (r == null) return;
    final nk = Kid(id: e?.id ?? newId(), name: r['name'] as String, weekly: r['weekly'] as int? ?? 0, moves: e?.moves ?? const []);
    _set([for (final x in _k) if (x.id != nk.id) x, nk]);
  }

  Future<void> _move(Kid k, bool give) async {
    final r = await editForm(context, t, '${L(t, give ? 'give' : 'spend')} · ${k.name}', [
      F.money('amount', L(t, 'amount'), initial: give && k.weekly > 0 ? k.weekly : null),
      F.text('note', L(t, 'note')),
      F.date('date', L(t, 'date'), initial: DateTime.now()),
    ]);
    if (r == null) return;
    final c = r['amount'] as int;
    _set([
      for (final x in _k) x.id == k.id ? x.add(give ? c : -c, r['date'] as DateTime? ?? DateTime.now(), r['note'] as String) : x,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    return ToolList(children: [
      bar(onExport: () => exportCsv(context, t, 'allowance', kidsCsv(_k))),
      AppInfoCard(L(t, 'parent_note'), icon: Icons.family_restroom_rounded),
      AppButton(label: L(t, 'add'), icon: Icons.person_add_alt_1_rounded, onPressed: () => _add()),
      if (_k.any((k) => k.weekly > 0))
        AppButton(
          label: L(t, 'give_all'),
          icon: Icons.redeem_rounded,
          onPressed: () => _set([for (final k in _k) k.weekly > 0 ? k.add(k.weekly, DateTime.now(), L(t, 'weekly_amount')) : k]),
        ),
      if (_k.isEmpty) emptyNote(t),
      for (final k in _k)
        Card(
          child: Column(children: [
            ListTile(
              leading: CircleAvatar(child: Text(k.name.isEmpty ? '?' : k.name.characters.first.toUpperCase())),
              title: Text(k.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${L(t, 'balance')}: ${mc(k.balance)}'
                  '${k.weekly > 0 ? ' · ${L(t, 'weekly_amount')}: ${mc(k.weekly)}' : ''}'),
              trailing: Icon(_open == k.id ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              onTap: () => setState(() => _open = _open == k.id ? null : k.id),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(onPressed: () => _move(k, true), icon: const Icon(Icons.add_rounded), label: Text(L(t, 'give'))),
              TextButton.icon(onPressed: () => _move(k, false), icon: const Icon(Icons.shopping_bag_rounded), label: Text(L(t, 'spend'))),
              IconButton(onPressed: () => _add(k), icon: const Icon(Icons.edit_rounded)),
              IconButton(
                onPressed: () async {
                  if (await confirmDelete(context, t)) _set([for (final x in _k) if (x.id != k.id) x]);
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ]),
            if (_open == k.id)
              for (final m in k.moves.reversed.take(50))
                ListTile(
                  dense: true,
                  title: Text(m.$3.isEmpty ? date(m.$1) : m.$3),
                  subtitle: m.$3.isEmpty ? null : Text(date(m.$1)),
                  trailing: Text('${m.$2 >= 0 ? '+' : '−'}${mc(m.$2.abs())}'),
                ),
          ]),
        ),
    ]);
  }
}
