import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/app.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/providers.dart';
import 'package:tradeflow/data/purchase_repository.dart';
import 'package:tradeflow/data/settings_repository.dart';
import 'package:tradeflow/data/setup_repository.dart';

void main() {
  testWidgets('refund a whole order and see the currency loss', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      final storeId = await SetupRepository(db).completeSetup(
        storeName: 'Mano Imports',
        places: const [OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 100000)],
      );
      final settings = SettingsRepository(db, storeId);
      final general = (await settings.watchLookups(LookupKind.cargoType).first).first.id;
      final card = (await settings.watchMoneyPlaces().first).first.id;
      await PurchaseRepository(db, storeId).savePurchase(
        PurchaseDraft(
          orderedAt: DateTime(2026, 10, 1),
          items: [
            PurchaseItemDraft(productName: 'Smart watch', qty: 1, unitPriceCny: 10000, cargoTypeId: general),
          ],
          paidZmw: 37000,
          moneyPlaceId: card,
        ),
      );
    });

    await tester.pumpWidget(
      ProviderScope(overrides: [databaseProvider.overrideWithValue(db)], child: const TradeFlowApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Smart watch'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refund…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Kwacha actually returned'), '350');
    await tester.pumpAndSettle();
    expect(find.text('Currency loss: K20.00'), findsOneWidget);
    await tester.tap(find.text('Record refund'));
    await tester.pumpAndSettle();

    expect(find.text('Refunded K350.00'), findsOneWidget);
    expect(find.text('Currency loss: K20.00'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget, reason: 'status chip');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
