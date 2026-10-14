import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/purchase_repository.dart';
import '../../domain/costing.dart';
import 'purchase_labels.dart';

class _ItemRow {
  _ItemRow({this.id, String name = '', String qty = '1', String price = '', this.cargoTypeId})
    : name = TextEditingController(text: name),
      qty = TextEditingController(text: qty),
      price = TextEditingController(text: price);

  final String? id;
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController price;
  final focus = FocusNode();
  String? cargoTypeId;

  int get qtyValue => int.tryParse(qty.text.trim()) ?? 0;
  int get valueCny => qtyValue * moneyFromController(price);

  void dispose() {
    name.dispose();
    qty.dispose();
    price.dispose();
    focus.dispose();
  }
}

/// Create a purchase, or edit one when [existing] is given.
class PurchaseEditScreen extends ConsumerStatefulWidget {
  const PurchaseEditScreen({super.key, this.existing});

  final PurchaseDetail? existing;

  @override
  ConsumerState<PurchaseEditScreen> createState() => _PurchaseEditScreenState();
}

class _PurchaseEditScreenState extends ConsumerState<PurchaseEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _seller = TextEditingController();
  final _orderRef = TextEditingController();
  final _delivery = TextEditingController();
  final _paid = TextEditingController();
  final _notes = TextEditingController();
  final _trackingInput = TextEditingController();
  final _items = <_ItemRow>[];
  final _tracking = <String>[];
  var _orderedAt = DateTime.now();
  String? _platformId;
  String? _moneyPlaceId;
  var _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final p = e.purchase;
      _seller.text = p.sellerName ?? '';
      _orderRef.text = p.orderRef ?? '';
      _notes.text = p.notes ?? '';
      _delivery.text = Money.editable(e.sellerDeliveryCny);
      _paid.text = Money.editable(p.paidZmw);
      _orderedAt = p.orderedAt;
      _platformId = p.platformId;
      _moneyPlaceId = p.moneyPlaceId;
      _tracking.addAll(e.trackingNumbers);
      for (final i in e.items) {
        _items.add(
          _ItemRow(
            id: i.item.id,
            name: i.product.name,
            qty: '${i.item.qty}',
            price: Money.editable(i.item.unitPriceCny),
            cargoTypeId: i.item.cargoTypeId,
          ),
        );
      }
    } else {
      _items.add(_ItemRow());
      ref.read(purchaseRepositoryProvider).lastUsedMoneyPlaceId().then((id) {
        if (mounted && _moneyPlaceId == null && id != null) setState(() => _moneyPlaceId = id);
      });
    }
    for (final row in _items) {
      _listen(row);
    }
    _delivery.addListener(_refresh);
    _paid.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  void _listen(_ItemRow row) {
    row.qty.addListener(_refresh);
    row.price.addListener(_refresh);
  }

  @override
  void dispose() {
    for (final c in [_seller, _orderRef, _delivery, _paid, _notes, _trackingInput]) {
      c.dispose();
    }
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  int get _totalCny => _items.fold(0, (sum, r) => sum + r.valueCny) + moneyFromController(_delivery);

  void _addTracking() {
    final number = _trackingInput.text.trim().toUpperCase();
    if (number.isEmpty) return;
    setState(() {
      if (!_tracking.contains(number)) _tracking.add(number);
      _trackingInput.clear();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _orderedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _orderedAt = picked);
  }

  Future<void> _save(List<Lookup> cargoTypes, String moneyPlaceId) async {
    _addTracking();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final draft = PurchaseDraft(
      id: widget.existing?.purchase.id,
      platformId: _platformId,
      sellerName: _seller.text,
      orderRef: _orderRef.text,
      orderedAt: _orderedAt,
      items: [
        for (final row in _items)
          PurchaseItemDraft(
            id: row.id,
            productName: row.name.text,
            qty: row.qtyValue,
            unitPriceCny: moneyFromController(row.price),
            cargoTypeId: row.cargoTypeId ?? cargoTypes.first.id,
          ),
      ],
      sellerDeliveryCny: moneyFromController(_delivery),
      paidZmw: moneyFromController(_paid),
      moneyPlaceId: moneyPlaceId,
      trackingNumbers: _tracking,
      notes: _notes.text,
    );
    try {
      await ref.read(purchaseRepositoryProvider).savePurchase(draft);
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
    final platforms = _activeOrCurrent(ref.watch(lookupsProvider(LookupKind.platform)).value, _platformId);
    final cargoTypes = (ref.watch(lookupsProvider(LookupKind.cargoType)).value ?? const <Lookup>[])
        .where((c) => !c.archived)
        .toList();
    final places = (ref.watch(moneyPlacesProvider).value ?? const <MoneyPlace>[])
        .where((p) => !p.archived || p.id == _moneyPlaceId)
        .toList();
    // Last-used place, else the first one, so the common case needs no tap.
    final moneyPlaceId = _moneyPlaceId ?? (places.isEmpty ? null : places.first.id);
    final productNames = <String>[
      for (final p in ref.watch(productsProvider).value ?? const <ProductSummary>[]) p.product.name,
    ];

    final totalCny = _totalCny;
    final paidZmw = moneyFromController(_paid);
    final rate = effectiveRate(paidZmw: paidZmw, totalCny: totalCny);

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit purchase' : 'New purchase')),
      body: cargoTypes.isEmpty || moneyPlaceId == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          isExpanded: true,
                          initialValue: _platformId,
                          decoration: const InputDecoration(labelText: 'Platform'),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Not set')),
                            for (final p in platforms) DropdownMenuItem(value: p.id, child: Text(p.name)),
                          ],
                          onChanged: (v) => setState(() => _platformId = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _pickDate,
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Date'),
                            child: Text(shortDate.format(_orderedAt)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _seller,
                    decoration: const InputDecoration(labelText: 'Seller / shop (optional)'),
                  ),
                  const SizedBox(height: 24),
                  Text('Items', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final (i, row) in _items.indexed)
                    _ItemCard(
                      key: ObjectKey(row),
                      row: row,
                      productNames: productNames,
                      cargoTypes: cargoTypes,
                      onCargoChanged: (id) => setState(() => row.cargoTypeId = id),
                      onRemove: _items.length == 1
                          ? null
                          : () => setState(() => _items.removeAt(i).dispose()),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        final row = _ItemRow();
                        _listen(row);
                        _items.add(row);
                        row.focus.requestFocus();
                      }),
                      icon: const Icon(Icons.add),
                      label: const Text('Add item'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  MoneyField(
                    controller: _delivery,
                    label: "Seller's delivery fee (optional)",
                    currency: Currency.cny,
                  ),
                  const SizedBox(height: 12),
                  Text('Total: ${Money(totalCny, Currency.cny)}', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 24),
                  Text('Payment', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  MoneyField(
                    controller: _paid,
                    label: 'Actually charged',
                    required: true,
                    helperText: 'The kwacha that left your account, including fees',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey(moneyPlaceId),
                    initialValue: moneyPlaceId,
                    decoration: const InputDecoration(labelText: 'Paid from'),
                    items: [for (final p in places) DropdownMenuItem(value: p.id, child: Text(p.name))],
                    onChanged: (v) => setState(() => _moneyPlaceId = v),
                  ),
                  if (rate != null && paidZmw > 0) ...[
                    const SizedBox(height: 12),
                    Text('Rate you got: ${rateLabel(rate)}', style: theme.textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 24),
                  Text('Tracking numbers', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Optional. Add them when the seller ships; they match the agent\'s bill later.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final t in _tracking)
                        InputChip(label: Text(t), onDeleted: () => setState(() => _tracking.remove(t))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _trackingInput,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                    decoration: InputDecoration(
                      labelText: 'Add tracking number',
                      suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _addTracking),
                    ),
                    onSubmitted: (_) => _addTracking(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _orderRef,
                    decoration: const InputDecoration(labelText: 'Order number (optional)'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(cargoTypes, moneyPlaceId),
                    child: Text(_isEdit ? 'Save changes' : 'Save purchase'),
                  ),
                ],
              ),
            ),
    );
  }

  /// Unarchived lookups plus the one currently selected, even if archived.
  List<Lookup> _activeOrCurrent(List<Lookup>? all, String? currentId) =>
      (all ?? const <Lookup>[]).where((l) => !l.archived || l.id == currentId).toList();
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    super.key,
    required this.row,
    required this.productNames,
    required this.cargoTypes,
    required this.onCargoChanged,
    required this.onRemove,
  });

  final _ItemRow row;
  final List<String> productNames;
  final List<Lookup> cargoTypes;
  final ValueChanged<String?> onCargoChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    // An archived cargo type isn't offered; show the default instead.
    final cargoId = cargoTypes.any((c) => c.id == row.cargoTypeId) ? row.cargoTypeId! : cargoTypes.first.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 4, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  RawAutocomplete<String>(
                    textEditingController: row.name,
                    focusNode: row.focus,
                    optionsBuilder: (value) {
                      final q = value.text.trim().toLowerCase();
                      if (q.isEmpty) return const [];
                      return productNames.where((n) => n.toLowerCase().contains(q) && n.toLowerCase() != q);
                    },
                    fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Item'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the item' : null,
                    ),
                    optionsViewBuilder: (context, onSelected, options) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
                          child: ListView(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            children: [
                              for (final option in options)
                                ListTile(title: Text(option), onTap: () => onSelected(option)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: row.qty,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Qty'),
                          validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Min 1' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: MoneyField(
                          controller: row.price,
                          label: 'Price each',
                          currency: Currency.cny,
                          required: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: cargoId,
                    decoration: const InputDecoration(labelText: 'Cargo type'),
                    items: [for (final c in cargoTypes) DropdownMenuItem(value: c.id, child: Text(c.name))],
                    onChanged: onCargoChanged,
                  ),
                ],
              ),
            ),
            IconButton(tooltip: 'Remove item', onPressed: onRemove, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    );
  }
}
