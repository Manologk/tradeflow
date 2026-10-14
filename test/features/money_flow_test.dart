import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/app.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/providers.dart';
import 'package:tradeflow/data/setup_repository.dart';

void main() {
  testWidgets('expense, transfer and balance check on the Money tab', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(
      () => SetupRepository(db).completeSetup(
        storeName: 'Mano Imports',
        places: const [
          OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 10000),
          OpeningPlace(name: 'Mobile Money', kind: MoneyPlaceKind.mobileMoney, balanceZmw: 50000),
          OpeningPlace(name: 'Cash', kind: MoneyPlaceKind.cash, balanceZmw: 20000),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(overrides: [databaseProvider.overrideWithValue(db)], child: const TradeFlowApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money'));
    await tester.pumpAndSettle();
    expect(find.text('K800.00'), findsOneWidget);
    expect(find.text('Balances never checked'), findsOneWidget);

    // Expense: K30 transport, paid in cash by default.
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '30');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('-K30.00'), findsOneWidget);
    expect(find.text('K170.00'), findsOneWidget, reason: 'cash 200 - 30');

    // Move K400 from mobile money to card with a K5 fee.
    await tester.tap(find.text('Move money'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '400');
    await tester.enterText(find.widgetWithText(TextFormField, 'Fee (optional)'), '5');
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(find.text('K500.00'), findsOneWidget, reason: 'card 100 + 400');
    expect(find.text('K95.00'), findsOneWidget, reason: 'mobile 500 - 400 - 5');

    // Cash is really K150: K20 gap recorded.
    await tester.tap(find.text('Check balances'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Actually there').at(2), '150');
    await tester.pumpAndSettle();
    expect(find.textContaining('K20.00 less'), findsOneWidget);
    await tester.tap(find.text('Save balances'));
    await tester.pumpAndSettle();

    expect(find.text('K150.00'), findsOneWidget);
    expect(find.text('Taken out / unrecorded'), findsOneWidget);
    expect(find.text('Last checked today'), findsOneWidget);

    await tester.tap(find.text('Taken out / unrecorded'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal use'));
    await tester.pumpAndSettle();
    expect(find.text('Personal use'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
