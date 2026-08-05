// Basic smoke test for the app skeleton.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_football/app.dart';
import 'package:my_football/providers/app_providers.dart';

void main() {
  testWidgets('App renders the standings screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MyFootballApp(),
      ),
    );
    await tester.pump();

    expect(find.text('My Football'), findsOneWidget);
    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);
    expect(find.text('Matches'), findsOneWidget);
  });
}
