import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/money_repository.dart';
import '../../data/providers.dart';

/// Records an expense. With [saleId] it is attached to that sale (delivery).
Future<void> showExpenseDialog(BuildContext context, {String? saleId, String? categoryId, String? title}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ExpenseDialog(saleId: saleId, categoryId: categoryId, title: title ?? 'Add expense'),
    );

class _ExpenseDialog extends ConsumerStatefulWidget {
  const _ExpenseDialog({this.saleId, this.categoryId, required this.title});

  final String? saleId;
  final String? categoryId;
  final String title;

  @override
  ConsumerState<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends ConsumerState<_ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String? _categoryId = widget.categoryId;
  String? _placeId;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(String categoryId, String placeId) async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(moneyRepositoryProvider)
        .addExpense(
          ExpenseDraft(
            spentAt: DateTime.now(),
            categoryId: categoryId,
            amountZmw: moneyFromController(_amount),
            moneyPlaceId: placeId,
            saleId: widget.saleId,
            note: _note.text,
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(lookupsProvider(LookupKind.expenseCategory)).value ?? const <Lookup>[])
        .where((c) => !c.archived)
        .toList();
    final places = (ref.watch(moneyPlacesProvider).value ?? const <MoneyPlace>[])
        .where((p) => !p.archived)
        .toList();
    final categoryId = categories.any((c) => c.id == _categoryId) ? _categoryId : categories.firstOrNull?.id;
    final placeId =
        _placeId ??
        places.where((p) => p.kind == MoneyPlaceKind.cash).firstOrNull?.id ??
        places.firstOrNull?.id;

    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MoneyField(controller: _amount, label: 'Amount', required: true),
              const SizedBox(height: 16),
              if (categoryId != null)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'What for'),
                  items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              const SizedBox(height: 16),
              if (placeId != null)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: placeId,
                  decoration: const InputDecoration(labelText: 'Paid from'),
                  items: [for (final p in places) DropdownMenuItem(value: p.id, child: Text(p.name))],
                  onChanged: (v) => setState(() => _placeId = v),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: categoryId == null || placeId == null ? null : () => _save(categoryId, placeId),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Moves money between two places, with an optional fee.
Future<void> showTransferDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _TransferDialog());

class _TransferDialog extends ConsumerStatefulWidget {
  const _TransferDialog();

  @override
  ConsumerState<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<_TransferDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _fee = TextEditingController();
  String? _fromId;
  String? _toId;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _fee.dispose();
    super.dispose();
  }

  Future<void> _save(String from, String to) async {
    if (!_formKey.currentState!.validate()) return;
    if (from == to) {
      setState(() => _error = 'Choose two different places');
      return;
    }
    await ref
        .read(moneyRepositoryProvider)
        .addTransfer(
          fromPlaceId: from,
          toPlaceId: to,
          amountZmw: moneyFromController(_amount),
          feeZmw: moneyFromController(_fee),
          at: DateTime.now(),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final places = (ref.watch(moneyPlacesProvider).value ?? const <MoneyPlace>[])
        .where((p) => !p.archived)
        .toList();
    // Typical move: customer money (mobile money / cash) onto the card.
    final fromId =
        _fromId ??
        places.where((p) => p.kind == MoneyPlaceKind.mobileMoney).firstOrNull?.id ??
        places.firstOrNull?.id;
    final toId =
        _toId ??
        places.where((p) => p.kind == MoneyPlaceKind.card && p.id != fromId).firstOrNull?.id ??
        places.where((p) => p.id != fromId).firstOrNull?.id;
    DropdownButtonFormField<String> picker(String label, String? value, ValueChanged<String?> onChanged) =>
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [for (final p in places) DropdownMenuItem(value: p.id, child: Text(p.name))],
          onChanged: onChanged,
        );

    return AlertDialog(
      title: const Text('Move money'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              picker('From', fromId, (v) => setState(() => _fromId = v)),
              const SizedBox(height: 16),
              picker('To', toId, (v) => setState(() => _toId = v)),
              const SizedBox(height: 16),
              MoneyField(controller: _amount, label: 'Amount', required: true),
              const SizedBox(height: 16),
              MoneyField(
                controller: _fee,
                label: 'Fee (optional)',
                helperText: 'e.g. mobile money or deposit charge',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: fromId == null || toId == null ? null : () => _save(fromId, toId),
          child: const Text('Move'),
        ),
      ],
    );
  }
}
