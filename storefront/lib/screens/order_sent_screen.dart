import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/checkout.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'cart_screen.dart';

typedef OrderSentDetails = ({Order order, bool savedOnline, bool opened});

/// Confirmation after "Order on WhatsApp".
class OrderSentScreen extends ConsumerWidget {
  const OrderSentScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Details are only available right after ordering; after a page reload
    // the code alone is shown.
    final details = GoRouterState.of(context).extra as OrderSentDetails?;
    final settings = ref.watch(catalogProvider).value?.settings;
    final order = details?.order;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(color: ShopColors.ink, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Order ready to send!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Your order code is $code',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: ShopColors.grey),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: ShopColors.surface, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What happens next', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const _Step(n: 1, text: 'Press send in WhatsApp so we get your order.'),
                  const _Step(n: 2, text: 'We confirm availability and share payment details.'),
                  const _Step(n: 3, text: 'Track it any time under My orders.'),
                  if (details != null && !details.savedOnline)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        "Your connection dropped while saving, but your WhatsApp message has everything we need.",
                        style: TextStyle(color: ShopColors.sale),
                      ),
                    ),
                ],
              ),
            ),
            if (order != null) ...[
              const SizedBox(height: 16),
              for (final l in order.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('${l.qty} × ${l.name}')),
                      Text(kwacha(l.totalZmw)),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text(kwacha(order.totalZmw), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ],
            const SizedBox(height: 32),
            if (order != null && settings != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => ref.read(linkOpenerProvider)(whatsappLink(order, settings)),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Open WhatsApp again'),
                ),
              ),
            FilledButton(onPressed: () => context.go('/'), child: const Text('Back to shop')),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: ShopColors.ink,
          child: Text('$n', style: const TextStyle(fontSize: 12, color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
