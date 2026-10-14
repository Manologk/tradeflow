import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/units.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/shipping_repository.dart';
import '../purchases/purchase_labels.dart';
import '../settings/agents_screen.dart';
import 'purchase_picker.dart';

class _LineRow {
  _LineRow({this.id, this.cargoTypeId, String kg = '', String usd = '', List<String>? purchaseIds})
    : kg = TextEditingController(text: kg),
      usd = TextEditingController(text: usd),
      tracking = TextEditingController(),
      purchaseIds = purchaseIds ?? [],
      amountEdited = usd.isNotEmpty;

  final String? id;
  String? cargoTypeId;
  final TextEditingController kg;
  final TextEditingController usd;
  final TextEditingController tracking;
  final List<String> purchaseIds;

  /// Once the user types an amount, stop filling it from the agent's rate.
  bool amountEdited;

  void dispose() {
    kg.dispose();
    usd.dispose();
    tracking.dispose();
  }
}

/// Enter an agent's shipping bill: one line per tracking number or per
/// consolidated parcel, each linked to the purchases it covers.
class BillEditScreen extends ConsumerStatefulWidget {
  const BillEditScreen({super.key, this.existing});

  final ShippingBillDetail? existing;

  @override
  ConsumerState<BillEditScreen> createState() => _BillEditScreenState();
}

class _BillEditScreenState extends ConsumerState<BillEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _paid = TextEditingController();
  final _lines = <_LineRow>[];
  var _billedAt = DateTime.now();
  String? _agentId;
  String? _moneyPlaceId;
  Map<String, int> _rates = const {};
  List<OpenPurchase> _open = const [];
  String? _defaultCargoId;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _billedAt = e.bill.billedAt;
      _agentId = e.bill.agentId;
      _moneyPlaceId = e.bill.moneyPlaceId;
      _paid.text = Money.editable(e.bill.paidZmw);
      for (final l in e.lines) {
        _lines.add(
          _LineRow(
            id: l.line.id,
            cargoTypeId: l.line.cargoTypeId,
            kg: editableKg(l.line.weightGrams),
            usd: Money.editable(l.line.amountUsd),
            purchaseIds: [...l.purchaseIds],
          ),
        );
      }
      _loadRates(e.bill.agentId);
    } else {
      _lines.add(_LineRow());
    }
    for (final l in _lines) {
      _listen(l);
    }
    _paid.addListener(_refresh);
    _loadOpen();
  }

  Future<void> _loadOpen() async {
    final open = await ref
        .read(shippingRepositoryProvider)
        .openPurchases(include: widget.existing?.purchaseIds ?? const {});
    if (mounted) setState(() => _open = open);
  }

  Future<void> _loadRates(String agentId) async {
    final rates = await ref.read(settingsRepositoryProvider).agentRates(agentId);
    if (!mounted) return;
    setState(() {
      _rates = rates;
      for (final l in _lines) {
        _autofill(l);
      }
    });
  }

  void _refresh() => setState(() {});

  void _listen(_LineRow row) {
    row.kg.addListener(() => setState(() => _autofill(row)));
    row.usd.addListener(_refresh);
  }

  /// Amount = agent rate × weight, until the user overrides it.
  void _autofill(_LineRow row) {
    final cargo = row.cargoTypeId ?? _defaultCargoId;
    if (row.amountEdited || cargo == null) return;
    final rate = _rates[cargo];
    final grams = parseKgToGrams(row.kg.text);
    if (rate == null || grams == null) return;
    final text = Money.editable((rate * grams / 1000).round());
    if (row.usd.text != text) row.usd.text = text;
  }

  @override
  void dispose() {
    _paid.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  int get _totalUsd => _lines.fold(0, (sum, l) => sum + moneyFromController(l.usd));

  Future<void> _addByTracking(_LineRow row) async {
    final number = row.tracking.text.trim();
    if (number.isEmpty) return;
    final matches = await ref.read(shippingRepositoryProvider).purchasesForTracking(number);
    if (!mounted) return;
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No purchase has tracking number ${number.toUpperCase()}. '
            'Add it to the purchase first, or choose the purchase from the list.',
          ),
        ),
      );
      return;
    }
    setState(() {
      for (final id in matches) {
        if (!row.purchaseIds.contains(id)) row.purchaseIds.add(id);
      }
      row.tracking.clear();
    });
  }

  Future<void> _choosePurchases(_LineRow row) async {
    final chosen = await pickPurchases(context, options: _open, initial: row.purchaseIds.toSet());
    if (chosen == null) return;
    setState(() {
      row.purchaseIds
        ..clear()
        ..addAll(chosen);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _billedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _billedAt = picked);
  }

  Future<void> _save(String agentId, String moneyPlaceId, String defaultCargo) async {
    if (!_formKey.currentState!.validate()) return;
    final unlinked = _lines.indexWhere((l) => l.purchaseIds.isEmpty);
    if (unlinked >= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Line ${unlinked + 1} is not linked to any purchase.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(shippingRepositoryProvider)
          .saveBill(
            ShippingBillDraft(
              id: widget.existing?.bill.id,
              agentId: agentId,
              billedAt: _billedAt,
              paidZmw: moneyFromController(_paid),
              moneyPlaceId: moneyPlaceId,
              lines: [
                for (final l in _lines)
                  ShippingLineDraft(
                    id: l.id,
                    cargoTypeId: l.cargoTypeId ?? defaultCargo,
                    weightGrams: parseKgToGrams(l.kg.text) ?? 0,
                    amountUsd: moneyFromController(l.usd),
                    purchaseIds: l.purchaseIds,
                  ),
              ],
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agents = (ref.watch(agentsProvider).value ?? const <Agent>[])
        .where((a) => !a.archived || a.id == _agentId)
        .toList();
    final cargoTypes = (ref.watch(lookupsProvider(LookupKind.cargoType)).value ?? const <Lookup>[])
        .where((c) => !c.archived || _lines.any((l) => l.cargoTypeId == c.id))
        .toList();
    final places = (ref.watch(moneyPlacesProvider).value ?? const <MoneyPlace>[])
        .where((p) => !p.archived || p.id == _moneyPlaceId)
        .toList();

    if (ref.watch(agentsProvider).value == null || cargoTypes.isEmpty || places.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (agents.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('New shipping bill')),
        body: EmptyState(
          icon: Icons.local_shipping_outlined,
          title: 'Add your shipping agent first',
          message: 'Their rates per kg will fill in the bill for you.',
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AgentEditScreen())),
          icon: const Icon(Icons.add),
          label: const Text('Add agent'),
        ),
      );
    }

    final agentId = _agentId ?? agents.first.id;
    if (_agentId == null) {
      _agentId = agentId;
      _loadRates(agentId);
    }
    final moneyPlaceId = _moneyPlaceId ?? places.first.id;
    final defaultCargo = cargoTypes.first.id;
    _defaultCargoId = defaultCargo;
    final labels = {for (final o in _open) o.purchase.id: o.label};
    final totalUsd = _totalUsd;
    final paid = moneyFromController(_paid);

    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New shipping bill' : 'Edit shipping bill')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: agentId,
                    decoration: const InputDecoration(labelText: 'Agent'),
                    items: [for (final a in agents) DropdownMenuItem(value: a.id, child: Text(a.name))],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _agentId = v);
                      _loadRates(v);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date'),
                      child: Text(shortDate.format(_billedAt)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Lines on the bill', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'One line per tracking number, or one line for a consolidated parcel '
              'linked to several purchases.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 8),
            for (final (i, row) in _lines.indexed)
              _LineCard(
                key: ObjectKey(row),
                index: i,
                row: row,
                cargoTypes: cargoTypes,
                defaultCargo: defaultCargo,
                purchaseLabels: labels,
                onCargoChanged: (id) => setState(() {
                  row.cargoTypeId = id;
                  _autofill(row);
                }),
                onAmountTyped: () => row.amountEdited = true,
                onAddTracking: () => _addByTracking(row),
                onChoose: () => _choosePurchases(row),
                onUnlink: (id) => setState(() => row.purchaseIds.remove(id)),
                onRemove: _lines.length == 1 ? null : () => setState(() => _lines.removeAt(i).dispose()),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  final row = _LineRow(cargoTypeId: defaultCargo);
                  _listen(row);
                  _lines.add(row);
                }),
                icon: const Icon(Icons.add),
                label: const Text('Add line'),
              ),
            ),
            const SizedBox(height: 8),
            Text('Bill total: ${Money(totalUsd, Currency.usd)}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            Text('Payment', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            MoneyField(
              controller: _paid,
              label: 'Actually paid',
              required: true,
              helperText: 'The kwacha you paid the agent for this bill',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: moneyPlaceId,
              decoration: const InputDecoration(labelText: 'Paid from'),
              items: [for (final p in places) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => setState(() => _moneyPlaceId = v),
            ),
            if (totalUsd > 0 && paid > 0) ...[
              const SizedBox(height: 12),
              Text('Rate you got: K${(paid / totalUsd).toStringAsFixed(3)} per \$1'),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : () => _save(agentId, moneyPlaceId, defaultCargo),
              child: const Text('Save bill'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.index,
    required this.row,
    required this.cargoTypes,
    required this.defaultCargo,
    required this.purchaseLabels,
    required this.onCargoChanged,
    required this.onAmountTyped,
    required this.onAddTracking,
    required this.onChoose,
    required this.onUnlink,
    required this.onRemove,
  });

  final int index;
  final _LineRow row;
  final List<Lookup> cargoTypes;
  final String defaultCargo;
  final Map<String, String> purchaseLabels;
  final ValueChanged<String?> onCargoChanged;
  final VoidCallback onAmountTyped;
  final VoidCallback onAddTracking;
  final VoidCallback onChoose;
  final ValueChanged<String> onUnlink;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Line ${index + 1}', style: theme.textTheme.labelLarge)),
                IconButton(tooltip: 'Remove line', onPressed: onRemove, icon: const Icon(Icons.close)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: row.tracking,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                    decoration: InputDecoration(
                      labelText: 'Tracking number on the bill',
                      suffixIcon: IconButton(icon: const Icon(Icons.link), onPressed: onAddTracking),
                    ),
                    onSubmitted: (_) => onAddTracking(),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final id in row.purchaseIds)
                        InputChip(
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(purchaseLabels[id] ?? 'Purchase', overflow: TextOverflow.ellipsis),
                          ),
                          onDeleted: () => onUnlink(id),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.checklist, size: 18),
                        label: Text(row.purchaseIds.isEmpty ? 'Choose purchases' : 'Change'),
                        onPressed: onChoose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: row.cargoTypeId ?? defaultCargo,
                    decoration: const InputDecoration(labelText: 'Cargo type'),
                    items: [for (final c in cargoTypes) DropdownMenuItem(value: c.id, child: Text(c.name))],
                    onChanged: onCargoChanged,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: row.kg,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Weight', suffixText: 'kg'),
                          validator: (v) {
                            final g = parseKgToGrams(v ?? '');
                            return (g == null || g == 0) ? 'Enter kg' : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Focus(
                          onFocusChange: (focused) {
                            if (focused) onAmountTyped();
                          },
                          child: MoneyField(
                            controller: row.usd,
                            label: 'Amount',
                            currency: Currency.usd,
                            required: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
