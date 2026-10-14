import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/app.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/providers.dart';
import 'package:tradeflow/data/setup_repository.dart';

void main() {
  testWidgets('sell with part payment, see the debt, collect it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(
      () => SetupRepository(db).completeSetup(
        storeName: 'Mano Imports',
        places: const [
          OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 0),
          OpeningPlace(name: 'Mobile Money', kind: MoneyPlaceKind.mobileMoney, balanceZmw: 0),
        ],
        stock: const [OpeningStockEntry(productName: 'Earbuds', qty: 3, unitCostZmw: 15000)],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(overrides: [databaseProvider.overrideWithValue(db)], child: const TradeFlowApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New sale'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Item'), 'Earbuds');
    await tester.enterText(find.widgetWithText(TextFormField, 'Qty'), '2');
    await tester.enterText(find.widgetWithText(TextFormField, 'Price each'), '250');
    await tester.pumpAndSettle();
    expect(find.text('3 in stock · cost about K150.00 each'), findsOneWidget);
    expect(find.text('Estimated profit: K200.00'), findsOneWidget);

    final form = find.descendant(of: find.byType(Form), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(
      find.widgetWithText(TextFormField, 'Received now'),
      200,
      scrollable: form,
    );
    // Received follows the total until changed.
    expect(find.widgetWithText(TextFormField, '500.00'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Received now'), '300');
    await tester.pumpAndSettle();
    expect(find.text('Balance owed: K200.00'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Save sale'), 200, scrollable: form);
    await tester.tap(find.text('Save sale'));
    await tester.pumpAndSettle();
    expect(find.text('Who owes the balance?'), findsOneWidget, reason: 'customer required when owed');

    await tester.enterText(find.widgetWithText(TextFormField, 'Name (needed — they owe a balance)'), 'Mwila');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save sale'), 200, scrollable: form);
    await tester.tap(find.text('Save sale'));
    await tester.pumpAndSettle();

    expect(find.text('owes K200.00'), findsOneWidget);
    await tester.tap(find.text('Earbuds'));
    await tester.pumpAndSettle();
    expect(find.text('Profit'), findsOneWidget);
    expect(find.text('K200.00'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Owed K200.00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mwila'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    expect(find.text('Nobody owes you money'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('K500.00'), findsWidgets, reason: 'all money received into mobile money');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
