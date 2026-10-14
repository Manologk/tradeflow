import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/app.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/providers.dart';
import 'package:tradeflow/data/setup_repository.dart';

void main() {
  testWidgets('log a purchase and see it in the list and on Home', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await SetupRepository(db).completeSetup(storeName: 'Mano Imports', places: const [
      OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 200000),
      OpeningPlace(name: 'Cash', kind: MoneyPlaceKind.cash, balanceZmw: 0),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const TradeFlowApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('K2,000.00'), findsWidgets);

    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    expect(find.text('No purchases yet'), findsOneWidget);

    await tester.tap(find.text('New purchase'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Item'), 'Earbuds');
    await tester.enterText(find.widgetWithText(TextFormField, 'Qty'), '2');
    await tester.enterText(find.widgetWithText(TextFormField, 'Price each'), '50');
    await tester.pumpAndSettle();
    expect(find.text('Total: ¥100.00'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Actually charged'), '370');
    await tester.pumpAndSettle();
    expect(find.text('Rate you got: K3.700 per ¥1'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Save purchase'),
      300,
      scrollable: find.descendant(of: find.byType(Form), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save purchase'));
    await tester.pumpAndSettle();

    expect(find.text('Earbuds'), findsOneWidget);
    expect(find.text('K370.00'), findsOneWidget);
    expect(find.textContaining('Ordered · 1'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('K1,630.00'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
