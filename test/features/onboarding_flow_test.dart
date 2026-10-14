import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/app.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/providers.dart';

void main() {
  testWidgets('first run sets up the store and lands on Home', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(overrides: [databaseProvider.overrideWithValue(db)], child: const TradeFlowApp()),
    );
    await tester.pumpAndSettle();

    // Step 1: business name is required.
    expect(find.text('Welcome to TradeFlow'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Mano Imports');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2: default places, enter balances.
    expect(find.text('Where is your money?'), findsOneWidget);
    final balances = find.widgetWithText(TextFormField, 'Balance');
    await tester.enterText(balances.at(0), '1,500');
    await tester.enterText(balances.at(2), '250.50');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 3: skip opening stock.
    expect(find.text('Stock you already have'), findsOneWidget);
    await tester.tap(find.text('Finish setup'));
    await tester.pumpAndSettle();

    expect(find.text('Mano Imports'), findsOneWidget);
    expect(find.text('Money now'), findsOneWidget);
    expect(find.text('K1,750.50'), findsOneWidget);
    expect(find.text('Mobile Money'), findsOneWidget);

    // Unmount so drift's stream timers are cleaned up before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
