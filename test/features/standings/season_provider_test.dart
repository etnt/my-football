import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_football/features/home/home_shell.dart';
import 'package:my_football/features/standings/standings_providers.dart';

void main() {
  test('seasonProvider defaults to the latest season', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(seasonProvider), latestSeason);
  });

  test('season picker offers the latest season as its first entry', () {
    expect(HomeShell.seasons.first, latestSeason);
  });
}