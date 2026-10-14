import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/providers.dart';
import '../theme.dart';

/// Tabs with the design's floating dark bottom bar.
class ShopShell extends ConsumerWidget {
  const ShopShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(cartProvider).fold<int>(0, (sum, l) => sum + l.qty);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            left: 20,
            right: 20,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: ShopColors.ink,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _BarButton(
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home,
                      label: 'Shop',
                      selected: location == '/',
                      onTap: () => context.go('/'),
                    ),
                    _BarButton(
                      icon: Icons.shopping_bag_outlined,
                      selectedIcon: Icons.shopping_bag,
                      label: cartCount == 0 ? 'Cart' : 'Cart, $cartCount items',
                      selected: false,
                      badge: cartCount > 0,
                      onTap: () => context.push('/cart'),
                    ),
                    _BarButton(
                      icon: Icons.favorite_border,
                      selectedIcon: Icons.favorite,
                      label: 'Favourites',
                      selected: location == '/favourites',
                      onTap: () => context.go('/favourites'),
                    ),
                    _BarButton(
                      icon: Icons.receipt_long_outlined,
                      selectedIcon: Icons.receipt_long,
                      label: 'My orders',
                      selected: location == '/orders',
                      onTap: () => context.go('/orders'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: selected ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(selected ? selectedIcon : icon, color: Colors.white, size: 24),
                if (badge)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: ShopColors.sale,
                        shape: BoxShape.circle,
                        border: Border.all(color: ShopColors.ink, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Space so content can scroll clear of the floating bar.
const bottomBarClearance = 112.0;
