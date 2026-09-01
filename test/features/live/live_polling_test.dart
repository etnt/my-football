import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/api_exception.dart';
import 'package:my_football/core/api/sportsdb_v2_client.dart';
import 'package:my_football/features/live/live_providers.dart';
import 'package:my_football/models/fixture.dart';
import 'package:my_football/providers/app_providers.dart';

/// A client whose first [attempts]-th polls fail, simulating a flaky
/// livescore feed (rate limits, timeouts) without touching the network.
class _FlakyV2Client extends SportsDbV2Client {
  _FlakyV2Client(this.failures) : super(apiKey: 'test-key');

  final int failures;
  int attempts = 0;

  @override
  Future<List<Fixture>> getLiveScores({required int leagueId}) async {
    attempts++;
    if (attempts <= failures) {
      throw const ApiException('transient failure');
    }
    return const [];
  }
}

void main() {
  test('a transient poll failure is retried instead of killing the stream',
      () async {
    final client = _FlakyV2Client(2); // fails twice, then recovers
    final container = ProviderContainer(
      overrides: [
        sportsDbV2ClientProvider.overrideWithValue(client),
        livePollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 5),
        ),
      ],
    );
    addTearDown(container.dispose);

    var sawData = false;
    final subscription = container.listen<AsyncValue<List<Fixture>>>(
      liveScoresProvider,
      (_, next) {
        if (next.hasValue) sawData = true;
      },
    );
    addTearDown(subscription.close);

    // Give the loop time to fail twice and then succeed.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(sawData, isTrue, reason: 'stream must recover after retries');
    expect(client.attempts, greaterThanOrEqualTo(3));
  });

  test('polling gives up only after several consecutive failures', () async {
    final client = _FlakyV2Client(999); // never recovers
    final container = ProviderContainer(
      overrides: [
        sportsDbV2ClientProvider.overrideWithValue(client),
        livePollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 5),
        ),
      ],
    );
    addTearDown(container.dispose);

    var sawError = false;
    final subscription = container.listen<AsyncValue<List<Fixture>>>(
      liveScoresProvider,
      (_, next) {
        if (next.hasError) sawError = true;
      },
    );
    addTearDown(subscription.close);

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(sawError, isTrue, reason: 'persistent failure must surface');
    // Exactly _maxConsecutiveFailures attempts before giving up.
    expect(client.attempts, 3);
  });
}
