import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/purchase_repository.dart';
import '../../data/sales_repository.dart';
import '../../domain/fifo.dart';
import '../purchases/purchase_labels.dart';

class _ItemRow {
  _ItemRow({this.id, String name = '', String qty = '1', String price = ''})
    : name = TextEditingController(text: name),
      qty = TextEditingController(text: qty),
      price = TextEditingController(text: price);

  final String? id;
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController price;
  final focus = FocusNode();

  int get qtyValue => int.tryParse(qty.text.trim()) ?? 0;
  int get totalZmw => qtyValue * moneyFromController(price);

  void dispose() {
    name.dispose();
    qty.dispose();
    price.dispose();
    focus.dispose();
  }
}

/// Record a sale from stock or a pre-order, or edit one when [existing] is set.
class SaleEditScreen extends ConsumerStatefulWidget {
  const SaleEditScreen({super.key, this.existing});

  final SaleDetail? existing;

  @override
  ConsumerState<SaleEditScreen> createState() => _SaleEditScreenState();
}

class _SaleEditScreenState extends ConsumerState<SaleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customer = TextEditingController();
  final _customerFocus = FocusNode();
  final _phone = TextEditingController();
  final _received = TextEditingController();
  final _notes = TextEditingController();
  final _items = <_ItemRow>[];
  var _kind = SaleKind.stock;
  var _soldAt = DateTime.now();
  String? _channelId;
  String? _placeId;

  /// The received amount follows the total until the user types in it.
  var _receivedEdited = false;
  var _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final s = e.sale;
      _kind = s.kind;
      _soldAt = s.soldAt;
      _channelId = s.channelId;
      _customer.text = e.summary.customer?.name ?? '';
      _phone.text = e.summary.customer?.phone ?? '';
      _notes.text = s.notes ?? '';
      for (final i in e.items) {
        _items.add(
          _ItemRow(
            id: i.item.id,
            name: i.product.name,
            qty: '${i.item.qty}',
            price: Money.editable(i.item.unitPriceZmw),
          ),
        );
      }
    } else {
      _items.add(_ItemRow());
      ref.read(salesRepositoryProvider).lastPaymentPlaceId().then((id) {
        if (mounted && _placeId == null && id != null) setState(() => _placeId = id);
      });
    }
    for (final row in _items) {
      _listen(row);
    }
    _received.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  void _listen(_ItemRow row) {
    row.name.addListener(_refresh);
    row.qty.addListener(_syncReceived);
    row.price.addListener(_syncReceived);
  }

  void _syncReceived() {
    if (!_receivedEdited && !_isEdit) {
      final text = Money.editable(_total);
      if (_received.text != text) _received.text = text;
    }
    setState(() {});
  }

  int get _total => _items.fold(0, (sum, r) => sum + r.totalZmw);

  @override
  void dispose() {
    for (final c in [_customer, _phone, _received, _notes]) {
      c.dispose();
    }
    _customerFocus.dispose();
    for (final r in _items) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _soldAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _soldAt = picked);
  }

  Future<void> _save(String? placeId) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(salesRepositoryProvider)
          .saveSale(
            SaleDraft(
              id: widget.existing?.sale.id,
              soldAt: _soldAt,
              kind: _kind,
              customerName: _customer.text,
              customerPhone: _phone.text,
              channelId: _channelId,
              items: [
                for (final r in _items)
                  SaleItemDraft(
                    id: r.id,
                    productName: r.name.text,
                    qty: r.qtyValue,
                    unitPriceZmw: moneyFromController(r.price),
                  ),
              ],
              paymentZmw: _isEdit ? 0 : moneyFromController(_received),
              paymentPlaceId: placeId,
              notes: _notes.text,
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final message = e is ArgumentError ? '${e.message}' : 'Could not save: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = ref.watch(productsProvider).value ?? const <ProductSummary>[];
    final ledger = ref.watch(stockLedgerProvider).value;
    final customers = ref.watch(customersProvider).value ?? const <Customer>[];
    final channels = (ref.watch(lookupsProvider(LookupKind.channel)).value ?? const <Lookup>[])
        .where((c) => !c.archived || c.id == _channelId)
        .toList();
    final places = (ref.watch(moneyPlacesProvider).value ?? const <MoneyPlace>[])
        .where((p) => !p.archived)
        .toList();
    // Customers mostly pay by mobile money.
    final placeId =
        _placeId ??
        places.where((p) => p.kind == MoneyPlaceKind.mobileMoney).firstOrNull?.id ??
        places.firstOrNull?.id;

    final productByName = {for (final p in products) p.product.name.toLowerCase(): p.product};
    ProductStock? stockFor(_ItemRow r) {
      final product = productByName[r.name.text.trim().toLowerCase()];
      return product == null || ledger == null ? null : ledger.stockOf(product.id);
    }

    final total = _total;
    final received = _isEdit ? widget.existing!.summary.paidZmw : moneyFromController(_received);
    final owed = total - received;
    var estimatedCost = 0;
    var costKnown = _kind == SaleKind.stock;
    for (final r in _items) {
      final unit = stockFor(r)?.unitCostZmw;
      if (unit == null) {
        costKnown = false;
      } else {
        estimatedCost += unit * r.qtyValue;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit sale' : 'New sale')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            SegmentedButton<SaleKind>(
              segments: const [
                ButtonSegment(
                  value: SaleKind.stock,
                  label: Text('From stock'),
                  icon: Icon(Icons.inventory_2_outlined),
                ),
                ButtonSegment(value: SaleKind.preOrder, label: Text('Pre-order'), icon: Icon(Icons.schedule)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.single),
            ),
            if (_kind == SaleKind.preOrder) ...[
              const SizedBox(height: 8),
              Text(
                'For something you will order for this customer. Profit counts when you hand it over.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date'),
                child: Text(shortDate.format(_soldAt)),
              ),
            ),
            const SizedBox(height: 24),
            Text('Items', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final (i, row) in _items.indexed)
              Card(
                key: ObjectKey(row),
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SuggestField(
                              controller: row.name,
                              focusNode: row.focus,
                              options: [for (final p in products) p.product.name],
                              label: 'Item',
                              requiredMessage: 'Enter the item',
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
                                    required: true,
                                  ),
                                ),
                              ],
                            ),
                            _StockHint(stock: stockFor(row), qty: row.qtyValue, kind: _kind),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove item',
                        onPressed: _items.length == 1
                            ? null
                            : () => setState(() {
                                _items.removeAt(i).dispose();
                                _syncReceived();
                              }),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
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
            Text('Total: ${Money(total)}', style: theme.textTheme.titleMedium),
            if (costKnown && total > 0)
              Text(
                'Estimated profit: ${Money(total - estimatedCost)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: total - estimatedCost < 0 ? theme.colorScheme.error : theme.colorScheme.primary,
                ),
              ),
            const SizedBox(height: 24),
            Text('Customer', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SuggestField(
              controller: _customer,
              focusNode: _customerFocus,
              options: [for (final c in customers) c.name],
              label: owed > 0 ? 'Name (needed — they owe a balance)' : 'Name (optional)',
              requiredMessage: owed > 0 ? 'Who owes the balance?' : null,
              onSelected: (name) {
                final match = customers.where((c) => c.name == name).firstOrNull;
                if (match?.phone != null && _phone.text.isEmpty) _phone.text = match!.phone!;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: _channelId,
              decoration: const InputDecoration(labelText: 'Sold via (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Not set')),
                for (final c in channels) DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _channelId = v),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 24),
              Text('Payment', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Focus(
                onFocusChange: (focused) {
                  if (focused) _receivedEdited = true;
                },
                child: MoneyField(
                  controller: _received,
                  label: 'Received now',
                  helperText: _kind == SaleKind.preOrder ? 'The deposit, if any' : null,
                ),
              ),
              if (placeId != null && moneyFromController(_received) > 0) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: placeId,
                  decoration: const InputDecoration(labelText: 'Received into'),
                  items: [for (final p in places) DropdownMenuItem(value: p.id, child: Text(p.name))],
                  onChanged: (v) => setState(() => _placeId = v),
                ),
              ],
            ],
            if (owed > 0) ...[
              const SizedBox(height: 12),
              Text('Balance owed: ${Money(owed)}', style: theme.textTheme.titleSmall),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : () => _save(placeId),
              child: Text(_isEdit ? 'Save changes' : 'Save sale'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockHint extends StatelessWidget {
  const _StockHint({required this.stock, required this.qty, required this.kind});

  final ProductStock? stock;
  final int qty;
  final SaleKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = stock;
    if (s == null || kind == SaleKind.preOrder) return const SizedBox.shrink();
    final short = qty > s.qty;
    final text = [
      '${s.qty} in stock',
      if (s.unitCostZmw != null) 'cost about ${Money(s.unitCostZmw!)} each',
      if (short) 'not enough recorded stock',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: short ? theme.colorScheme.error : theme.colorScheme.outline,
        ),
      ),
    );
  }
}
