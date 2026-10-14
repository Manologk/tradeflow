import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/app.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/providers.dart';
import 'package:tradeflow/data/sales_repository.dart';
import 'package:tradeflow/data/setup_repository.dart';

void main() {
  testWidgets('Home shows this month\'s profit and Reports breaks it down', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      final storeId = await SetupRepository(db).completeSetup(
        storeName: 'Mano Imports',
        places: const [OpeningPlace(name: 'Mobile Money', kind: MoneyPlaceKind.mobileMoney, balanceZmw: 0)],
        stock: const [OpeningStockEntry(productName: 'Earbuds', qty: 3, unitCostZmw: 15000)],
      );
      final place = (await db.select(db.moneyPlaces).getSingle()).id;
      await SalesRepository(db, storeId).saveSale(
        SaleDraft(
          soldAt: DateTime.now(),
          kind: SaleKind.stock,
          items: const [SaleItemDraft(productName: 'Earbuds', qty: 2, unitPriceZmw: 25000)],
          paymentZmw: 50000,
          paymentPlaceId: place,
        ),
      );
    });

    await tester.pumpWidget(
      ProviderScope(overrides: [databaseProvider.overrideWithValue(db)], child: const TradeFlowApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profit this month'), findsOneWidget);
    expect(find.text('K200.00'), findsWidgets);
    expect(find.text('Sold K500.00 · goods cost K300.00'), findsOneWidget);
    expect(find.text('K150.00'), findsOneWidget, reason: 'stock value: 1 unit left');

    await tester.tap(find.text('Profit this month'));
    await tester.pumpAndSettle();
    expect(find.text('Net profit'), findsOneWidget);
    expect(find.text('Profit by product'), findsOneWidget);
    expect(find.text('2 sold · sales K500.00 · 40% margin'), findsWidgets);

    await tester.tap(find.text('Last month'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to report for last month'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
