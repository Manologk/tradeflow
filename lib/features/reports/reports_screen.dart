import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../data/report_repository.dart';
import '../../domain/reports.dart';
import '../purchases/purchase_labels.dart';

enum ReportPeriod {
  thisMonth('This month'),
  lastMonth('Last month'),
  last3Months('Last 3 months'),
  thisYear('This year'),
  allTime('All time');

  const ReportPeriod(this.label);

  final String label;

  (DateTime, DateTime) range(DateTime now) => switch (this) {
    thisMonth => (monthStart(now), nextMonth(now)),
    lastMonth => (DateTime(now.year, now.month - 1), monthStart(now)),
    last3Months => (DateTime(now.year, now.month - 2), nextMonth(now)),
    thisYear => (DateTime(now.year), DateTime(now.year + 1)),
    allTime => (DateTime(2000), DateTime(now.year + 100)),
  };
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  var _period = ReportPeriod.thisMonth;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(snapshotProvider);
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            children: [
              for (final p in ReportPeriod.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.label),
                    selected: _period == p,
                    onSelected: (_) => setState(() => _period = p),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (snapshot) {
            AsyncData(:final value) => _Report(snapshot: value, period: _period),
            AsyncError(:final error) => Center(child: Text('Could not load: $error')),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.snapshot, required this.period});

  final BusinessSnapshot snapshot;
  final ReportPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (from, to) = period.range(DateTime.now());
    final r = snapshot.report(from, to);
    final names = snapshot.names;
    String nameOf(String? id, String fallback) => id == null ? fallback : names[id] ?? fallback;

    if (r.totals.revenueZmw == 0 && r.expensesZmw == 0 && r.lossesZmw == 0 && r.otherCostsZmw == 0) {
      return ListView(
        children: [
          EmptyState(
            icon: Icons.insights_outlined,
            title: 'Nothing to report for ${period.label.toLowerCase()}',
            message: 'Profit appears here once you record sales.',
          ),
          if (!snapshot.cnyRates.isEmpty || !snapshot.usdRates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _Rates(snapshot: snapshot),
            ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        _Section(
          title: 'Profit',
          children: [
            _Row('Sales', Money(r.totals.revenueZmw)),
            _Row('Cost of goods sold', -Money(r.totals.costZmw)),
            _Row('Gross profit', Money(r.grossProfitZmw), bold: true),
            for (final MapEntry(:key, :value) in r.expensesByCategory.entries)
              _Row(names[key] ?? 'Expense', -Money(value)),
            if (r.otherCostsZmw > 0) _Row('Fees & forgotten expenses', -Money(r.otherCostsZmw)),
            if (r.lossesZmw != 0) _Row('Losses', -Money(r.lossesZmw)),
            if (r.returnsKeptZmw > 0) _Row('Kept from returns', Money(r.returnsKeptZmw)),
            const Divider(),
            _Row('Net profit', Money(r.netProfitZmw), bold: true),
            if (r.missingCostUnits > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${r.missingCostUnits} units were sold with no recorded stock, so profit is overstated.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
        _Section(
          title: 'Profit by product',
          children: [
            _RankedBars(
              lines: {
                for (final MapEntry(:key, :value) in r.byProduct.entries) nameOf(key, 'Product'): value,
              },
            ),
          ],
        ),
        _Section(
          title: 'Profit by platform',
          subtitle: 'Where the units you sold were bought',
          children: [
            _RankedBars(
              lines: {
                for (final MapEntry(:key, :value) in r.byPlatform.entries)
                  nameOf(key, 'Opening stock / unrecorded'): value,
              },
            ),
          ],
        ),
        _Section(
          title: 'Profit by sales channel',
          children: [
            _RankedBars(
              lines: {
                for (final MapEntry(:key, :value) in r.byChannel.entries)
                  nameOf(key, 'Channel not set'): value,
              },
            ),
          ],
        ),
        if (r.losses.isNotEmpty)
          _Section(
            title: 'Losses',
            children: [
              for (final l in r.losses)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l.label),
                  subtitle: Text(shortDate.format(l.at)),
                  trailing: Text(Money(l.amountZmw).toString()),
                ),
            ],
          ),
        _Rates(snapshot: snapshot),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null)
              Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});

  final String label;
  final Money value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = bold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value.toString(), style: style),
        ],
      ),
    );
  }
}

/// Horizontal bars ranked by profit, one hue, value written beside each bar
/// so nothing depends on colour. Losses draw in the error colour with a minus.
class _RankedBars extends StatelessWidget {
  const _RankedBars({required this.lines});

  final Map<String, ProfitLine> lines;
  static const _maxRows = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (lines.isEmpty) return Text('No sales', style: theme.textTheme.bodyMedium);
    final ranked = lines.entries.toList()..sort((a, b) => b.value.profitZmw.compareTo(a.value.profitZmw));
    final shown = ranked.take(_maxRows).toList();
    final maxAbs = shown.map((e) => e.value.profitZmw.abs()).fold(1, (a, b) => a > b ? a : b);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);

    return Column(
      children: [
        for (final MapEntry(key: name, value: line) in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(Money(line.profitZmw).toString(), style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 8,
                      width: (constraints.maxWidth * line.profitZmw.abs() / maxAbs).clamp(
                        2,
                        constraints.maxWidth,
                      ),
                      decoration: BoxDecoration(
                        color: line.profitZmw < 0 ? theme.colorScheme.error : theme.colorScheme.primary,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '${line.units} sold',
                    'sales ${Money(line.revenueZmw)}',
                    if (line.margin != null) '${(line.margin! * 100).round()}% margin',
                  ].join(' · '),
                  style: muted,
                ),
              ],
            ),
          ),
        if (ranked.length > _maxRows)
          Align(
            alignment: Alignment.centerLeft,
            child: Text('+${ranked.length - _maxRows} more', style: muted),
          ),
      ],
    );
  }
}

class _Rates extends StatelessWidget {
  const _Rates({required this.snapshot});

  final BusinessSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget block(String title, String symbol, RateSummary s) {
      if (s.isEmpty) return const SizedBox.shrink();
      String fmt(double v) => 'K${v.toStringAsFixed(3)}';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title (per ${symbol}1)', style: theme.textTheme.titleSmall),
            _TextRow('Latest (${shortDate.format(s.latest!.at)})', fmt(s.latest!.rate)),
            _TextRow('Average', fmt(s.average!)),
            _TextRow('Best', fmt(s.best!)),
            _TextRow('Worst', fmt(s.worst!)),
          ],
        ),
      );
    }

    return _Section(
      title: 'Exchange rates you got',
      subtitle: 'What your payments actually cost in kwacha, fees included',
      children: [
        block('Card payments in yuan', '¥', snapshot.cnyRates),
        block('Shipping in dollars', r'$', snapshot.usdRates),
        if (snapshot.cnyRates.isEmpty && snapshot.usdRates.isEmpty)
          Text('No payments yet', style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _TextRow extends StatelessWidget {
  const _TextRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value),
      ],
    ),
  );
}
