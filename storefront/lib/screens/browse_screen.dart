import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/models.dart';
import '../theme.dart';
import '../widgets/catalog_gate.dart';
import '../widgets/common.dart';

/// Browse by anime series and by category.
class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: CatalogGate(
          builder: (catalog) {
            int countSeries(String id) =>
                catalog.products.where((p) => p.seriesId == id && p.canOrder).length;
            int countCategory(String id) =>
                catalog.products.where((p) => p.categoryId == id && p.canOrder).length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Row(
                  children: [
                    CircleIconButton(
                      icon: Icons.arrow_back_ios_new,
                      tooltip: 'Back',
                      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                    ),
                    const Expanded(
                      child: Text(
                        'Browse',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 44),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Anime series', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    for (final s in catalog.series)
                      _Tile(
                        title: s.name,
                        subtitle: _count(countSeries(s.id)),
                        imageUrl: s.imageUrl,
                        onTap: () => context.go(Uri(path: '/', queryParameters: {'series': s.id}).toString()),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text('Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                for (final ShopCategory c in catalog.categories)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(_count(countCategory(c.id))),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(Uri(path: '/', queryParameters: {'category': c.id}).toString()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _count(int n) => '$n ${n == 1 ? 'item' : 'items'}';
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.subtitle, required this.onTap, this.imageUrl});

  final String title;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ShopColors.ink,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              Opacity(
                opacity: 0.45,
                child: Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
