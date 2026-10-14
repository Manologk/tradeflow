import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/problems_repository.dart';
import '../../data/providers.dart';

/// Picks a money place, defaulting to the first of [preferred] kind.
class _PlacePicker extends ConsumerWidget {
  const _PlacePicker({required this.value, required this.onChanged, required this.label, this.preferred});

  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final MoneyPlaceKind? preferred;

  static String? defaultFor(List<MoneyPlace> places, MoneyPlaceKind? kind) =>
      places.where((p) => p.kind == kind).firstOrNull?.id ?? places.firstOrNull?.id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = (ref.watch(moneyPlacesProvider).value ?? const <MoneyPlace>[])
        .where((p) => !p.archived)
        .toList();
    final selected = value ?? defaultFor(places, preferred);
    if (selected == null) return const SizedBox.shrink();
    if (value == null) WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(selected));
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: selected,
      decoration: InputDecoration(labelText: label),
      items: [for (final p in places) DropdownMenuItem(value: p.id, child: Text(p.name))],
      onChanged: onChanged,
    );
  }
}

// Refund ------------------------------------------------------------------

Future<void> showRefundDialog(BuildContext context, {required Purchase purchase}) => showDialog<void>(
  context: context,
  builder: (_) => _RefundDialog(purchase: purchase),
);

class _RefundDialog extends ConsumerStatefulWidget {
  const _RefundDialog({required this.purchase});

  final Purchase purchase;

  @override
  ConsumerState<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends ConsumerState<_RefundDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  var _whole = true;
  String? _placeId;

  @override
  void initState() {
    super.initState();
    _placeId = widget.purchase.moneyPlaceId;
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _placeId == null) return;
    await ref
        .read(problemsRepositoryProvider)
        .refundPurchase(
          purchaseId: widget.purchase.id,
          wholeOrder: _whole,
          amountZmw: moneyFromController(_amount),
          moneyPlaceId: _placeId!,
          at: DateTime.now(),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paid = widget.purchase.paidZmw;
    final back = moneyFromController(_amount);
    return AlertDialog(
      title: const Text('Refund from seller'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Whole order')),
                  ButtonSegment(value: false, label: Text('Part of it')),
                ],
                selected: {_whole},
                onSelectionChanged: (s) => setState(() => _whole = s.single),
              ),
              const SizedBox(height: 8),
              Text(
                _whole
                    ? 'Nothing from this order will arrive.'
                    : 'Some items were refunded; the rest still arrive and cost less.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              MoneyField(
                controller: _amount,
                label: 'Kwacha actually returned',
                required: true,
                helperText: 'You paid ${Money(paid)}',
              ),
              const SizedBox(height: 16),
              _PlacePicker(
                value: _placeId,
                onChanged: (v) => setState(() => _placeId = v),
                label: 'Returned to',
              ),
              if (_whole && back > 0 && back < paid) ...[
                const SizedBox(height: 12),
                Text(
                  'Currency loss: ${Money(paid - back)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Record refund')),
      ],
    );
  }
}

// Lost parcel -------------------------------------------------------------

Future<void> showLostDialog(BuildContext context, {required Purchase purchase}) => showDialog<void>(
  context: context,
  builder: (_) => _LostDialog(purchase: purchase),
);

class _LostDialog extends ConsumerStatefulWidget {
  const _LostDialog({required this.purchase});

  final Purchase purchase;

  @override
  ConsumerState<_LostDialog> createState() => _LostDialogState();
}

class _LostDialogState extends ConsumerState<_LostDialog> {
  final _formKey = GlobalKey<FormState>();
  final _compensation = TextEditingController();
  String? _placeId;

  @override
  void initState() {
    super.initState();
    _compensation.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _compensation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final compensation = moneyFromController(_compensation);
    await ref
        .read(problemsRepositoryProvider)
        .markLost(
          purchaseId: widget.purchase.id,
          compensationZmw: compensation,
          moneyPlaceId: compensation > 0 ? _placeId : null,
          at: DateTime.now(),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Parcel lost'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('What it cost you so far is counted as a loss.'),
              const SizedBox(height: 16),
              MoneyField(controller: _compensation, label: 'Compensation received (optional)'),
              if (moneyFromController(_compensation) > 0) ...[
                const SizedBox(height: 16),
                _PlacePicker(
                  value: _placeId,
                  onChanged: (v) => setState(() => _placeId = v),
                  label: 'Received into',
                  preferred: MoneyPlaceKind.mobileMoney,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Mark as lost')),
      ],
    );
  }
}

// Write-off ---------------------------------------------------------------

Future<void> showWriteOffDialog(BuildContext context, {required Product product, required int inStock}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _WriteOffDialog(product: product, inStock: inStock),
    );

class _WriteOffDialog extends ConsumerStatefulWidget {
  const _WriteOffDialog({required this.product, required this.inStock});

  final Product product;
  final int inStock;

  @override
  ConsumerState<_WriteOffDialog> createState() => _WriteOffDialogState();
}

class _WriteOffDialogState extends ConsumerState<_WriteOffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qty = TextEditingController(text: '1');
  var _reason = WriteOffReason.damaged;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(problemsRepositoryProvider)
        .writeOff(
          productId: widget.product.id,
          qty: int.parse(_qty.text.trim()),
          reason: _reason,
          at: DateTime.now(),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Take ${widget.product.name} out of stock'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _qty,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: 'How many', helperText: '${widget.inStock} in stock'),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'At least 1' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<WriteOffReason>(
                isExpanded: true,
                initialValue: _reason,
                decoration: const InputDecoration(labelText: 'Why'),
                items: [
                  for (final MapEntry(:key, :value) in writeOffReasonLabels.entries)
                    DropdownMenuItem(value: key, child: Text(value)),
                ],
                onChanged: (v) => setState(() => _reason = v ?? _reason),
              ),
              const SizedBox(height: 12),
              const Text('What these units cost you is counted as a loss.'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Take out of stock')),
      ],
    );
  }
}

// Customer return ---------------------------------------------------------

Future<void> showReturnDialog(BuildContext context, {required String saleId, required int paidZmw}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ReturnDialog(saleId: saleId, paidZmw: paidZmw),
    );

class _ReturnDialog extends ConsumerStatefulWidget {
  const _ReturnDialog({required this.saleId, required this.paidZmw});

  final String saleId;
  final int paidZmw;

  @override
  ConsumerState<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends ConsumerState<_ReturnDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _refund = TextEditingController(text: Money.editable(widget.paidZmw));
  var _restock = true;
  String? _placeId;

  @override
  void initState() {
    super.initState();
    _refund.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _refund.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final refund = moneyFromController(_refund);
    await ref
        .read(problemsRepositoryProvider)
        .returnSale(
          saleId: widget.saleId,
          refundZmw: refund,
          moneyPlaceId: refund > 0 ? _placeId : null,
          restock: _restock,
          at: DateTime.now(),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Customer returned it'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MoneyField(
                controller: _refund,
                label: 'Refunded to customer',
                helperText: 'They paid ${Money(widget.paidZmw)}',
              ),
              if (moneyFromController(_refund) > 0) ...[
                const SizedBox(height: 16),
                _PlacePicker(
                  value: _placeId,
                  onChanged: (v) => setState(() => _placeId = v),
                  label: 'Paid back from',
                  preferred: MoneyPlaceKind.mobileMoney,
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _restock,
                onChanged: (v) => setState(() => _restock = v),
                title: const Text('Can be sold again'),
                subtitle: Text(_restock ? 'Goes back into stock' : 'Written off as damaged'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Record return')),
      ],
    );
  }
}
