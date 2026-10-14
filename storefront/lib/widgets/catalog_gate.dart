import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/shop_repository.dart';
import '../domain/models.dart';
import '../state/providers.dart';
import 'common.dart';

/// Shows [builder] once the catalog has loaded, with friendly loading,
/// "opening soon" and error states.
class CatalogGate extends ConsumerWidget {
  const CatalogGate({super.key, required this.builder});

  final Widget Function(Catalog catalog) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(catalogProvider)) {
      AsyncData(:final value) => builder(value),
      AsyncError(error: ShopNotConfigured()) => const EmptyMessage(
        icon: Icons.storefront_outlined,
        title: 'Opening soon',
        message: 'The shop is being set up. Check back shortly!',
      ),
      AsyncError() => EmptyMessage(
        icon: Icons.wifi_off,
        title: "Couldn't load the shop",
        message: 'Check your internet connection and try again.',
        action: OutlinedButton(
          onPressed: () => ref.invalidate(catalogProvider),
          child: const Text('Try again'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}
