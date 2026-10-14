import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'money.dart';

/// Amount input that accepts "1,184.50"-style text. Validates to a
/// non-negative amount with at most two decimals.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.currency = Currency.zmw,
    this.required = false,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final Currency currency;
  final bool required;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixText: '${currency.symbol} ',
        helperText: helperText,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return required ? 'Enter an amount' : null;
        return Money.parseMinor(text) == null ? 'Enter a valid amount' : null;
      },
    );
  }
}

/// Minor units from a [MoneyField] controller; empty means zero.
int moneyFromController(TextEditingController controller) => Money.parseMinor(controller.text.trim()) ?? 0;

/// Asks for a single line of text. Returns null if cancelled or empty.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirmLabel = 'Save',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(confirmLabel)),
      ],
    ),
  );
  controller.dispose();
  final trimmed = result?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Friendly placeholder for screens and lists with nothing in them yet.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
