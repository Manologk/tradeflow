import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/providers.dart';
import '../widgets/catalog_gate.dart';
import '../widgets/common.dart';
import 'shell.dart';

class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favourites = ref.watch(favouritesProvider);
    return SafeArea(
      bottom: false,
      child: CatalogGate(
        builder: (catalog) {
          final products = catalog.products.where((p) => favourites.contains(p.id)).toList();
          if (products.isEmpty) {
            return const EmptyMessage(
              icon: Icons.favorite_border,
              title: 'No favourites yet',
              message: 'Tap the heart on anything you like to save it here.',
            );
          }
          return CustomScrollView(
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Text('Favourites', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, bottomBarClearance),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 20,
                    mainAxisExtent: 330,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, i) {
                    final p = products[i];
                    return ProductCard(
                      product: p,
                      seriesName: catalog.seriesOf(p.seriesId)?.name,
                      favourite: true,
                      onFavourite: () => ref.read(favouritesProvider.notifier).toggle(p.id),
                      onTap: () => context.push('/p/${p.id}'),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
