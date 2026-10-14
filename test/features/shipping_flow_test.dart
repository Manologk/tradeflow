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
  testWidgets('enter a bill by tracking number, then collect', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      final storeId = await SetupRepository(db).completeSetup(
        storeName: 'Mano Imports',
        places: const [
          OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 200000),
          OpeningPlace(name: 'Cash', kind: MoneyPlaceKind.cash, balanceZmw: 10000),
        ],
      );
      final settings = SettingsRepository(db, storeId);
      final general = (await settings.watchLookups(LookupKind.cargoType).first).first.id;
      final card = (await settings.watchMoneyPlaces().first).first.id;
      await settings.saveAgent(name: 'Speedy', usdPerKgByCargoType: {general: 900});
      await PurchaseRepository(db, storeId).savePurchase(
        PurchaseDraft(
          orderedAt: DateTime(2026, 10, 1),
          items: [
            PurchaseItemDraft(productName: 'Earbuds', qty: 2, unitPriceCny: 5000, cargoTypeId: general),
          ],
          paidZmw: 37000,
          moneyPlaceId: card,
          trackingNumbers: const ['YT123'],
        ),
      );
    });

    await tester.pumpWidget(
      ProviderScope(overrides: [databaseProvider.overrideWithValue(db)], child: const TradeFlowApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shipping'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shipping bill'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Tracking number on the bill'), 'yt123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Earbuds'), findsOneWidget, reason: 'linked by tracking number');

    await tester.enterText(find.widgetWithText(TextFormField, 'Weight'), '2');
    await tester.pumpAndSettle();
    expect(find.text('Bill total: \$18.00'), findsOneWidget, reason: 'rate 9/kg x 2 kg');

    await tester.enterText(find.widgetWithText(TextFormField, 'Actually paid'), '400');
    final scrollable = find.descendant(of: find.byType(Form), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Save bill'), 300, scrollable: scrollable);
    await tester.tap(find.text('Save bill'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Speedy · \$18.00'), findsOneWidget);
    expect(find.textContaining('1 purchase at the agent or on the way'), findsOneWidget);

    await tester.tap(find.text('Collect arrived goods'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Transport'), '30');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collect 1 purchase'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 purchase collected'), findsOneWidget);

    // Landed: K370 + K400 shipping + K30 pickup = K800 for 2 units.
    await tester.tap(find.text('Purchases'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Earbuds'));
    await tester.pumpAndSettle();
    expect(find.text('K400.00 each'), findsOneWidget);
    expect(find.textContaining('landed K800.00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
