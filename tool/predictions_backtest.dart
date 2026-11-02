// Back-test CLI for the prediction formula (plan §4.7, TASK-024).
//
// Rebuilds the league table and recent form at each fixture's kickoff from
// the cached season events, predicts every finished match with the formula,
// and reports argmax accuracy and Brier score against the in-sample baseline,
// once with the shipped formula and once with the original v1 constants.
//
// Key safety: the API key comes from the environment only (SPORTSDB_API_KEY).
// The tool never reads a key file, never prints the key, any request URL or
// exception details — on error it prints `ApiException.message` (already
// sanitised) or the error's runtime type only (CON-003: no match data leaves
// the device; the output contains aggregate metrics only).
//
// Usage: dart run tool/predictions_backtest.dart --league=4328 --season=2025-2026
// (a Premium key is required for a meaningful season; the free key returns
// only about 15 events).

import 'dart:io';

import 'package:my_football/core/api/api_exception.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/models/fixture.dart';

import 'src/backtest.dart';

const _usage =
    '''
Back-test the match prediction formula against one league season.

Usage:
  dart run tool/predictions_backtest.dart --league=<id> --season=<season>

Options:
  --league=<id>     League id, e.g. 4328 (English Premier League).
  --season=<season> Season string as the API indexes it, e.g. 2025-2026
                    (European leagues) or 2025 (calendar-year leagues).
  -h, --help        Show this help.

The API key is read from the $apiKeyEnvVar environment variable. A Premium
key is required for a meaningful back-test: the free key returns only about
15 events per season.

The script makes exactly one GET request per run (no retries) and prints
aggregate metrics only: no team names, fixture ids or per-match lines.
''';

// Exit codes: 0 success (including "not enough data"), 64 usage error or
// missing key, 1 API error or an unexpected response body, 74
// network/transport failure.
Future<void> main(List<String> arguments) async {
  final BacktestArgs args;
  try {
    args = parseArgs(arguments, Platform.environment);
  } on ArgumentError catch (e) {
    stderr.writeln('error: ${e.message}');
    stdout.writeln(_usage);
    exit(64);
  }
  if (args.help) {
    stdout.writeln(_usage);
    exit(0);
  }
  if (args.leagueId == null || args.season == null) {
    stderr.writeln('error: --league and --season are required.');
    stdout.writeln(_usage);
    exit(64);
  }
  if (args.apiKey == null) {
    stderr.writeln(
      'error: no API key. Set the $apiKeyEnvVar environment variable '
      '(a Premium key is recommended).',
    );
    exit(64);
  }

  // One GET per run, no retry: the free key allows 30 requests/min and the
  // run is repeated manually, not in a loop.
  final client = FootballApiClient(apiKey: args.apiKey);
  final List<Fixture> events;
  try {
    events = await client.getSeasonEvents(
      leagueId: args.leagueId!,
      season: args.season!,
      // A body without an `events` list is a rejected request, not an empty
      // season: surface it as an error instead of reporting no data.
      strict: true,
    );
  } on ApiException catch (e) {
    stderr.writeln('error: ${e.message}');
    exit(1);
  } on Object catch (e) {
    // Type only: a raw exception message can carry the request URL (CON-003).
    stderr.writeln('error: request failed (${e.runtimeType}).');
    exit(74);
  } finally {
    client.close();
  }

  if (events.length < 100) {
    stdout.writeln(
      'warning: only ${events.length} events were returned for this season. '
      'The free key caps the season endpoint at about 15 events, so the '
      'sample is likely too small; a Premium key is recommended.',
    );
  }
  if (events.isEmpty) {
    stdout.writeln('not enough data: the season returned no events.');
    exit(0);
  }

  final (:current, :v1) = compareBacktests(events);
  stdout.writeln(formatReport(current));
  stdout.writeln(formatReport(v1));

  if (current.n == 0) {
    stdout.writeln('not enough data: no fixture could be scored.');
    exit(0);
  }

  // Both metrics come from the same scored fixtures, so the comparison is
  // like-for-like. One season is noisy: judge tuning on several (plan §4.8).
  final cur = current.formulaVersion;
  final old = v1.formulaVersion;
  stdout.writeln('comparison (same ${current.n} scored fixtures):');
  stdout.writeln(
    '  accuracy: $cur ${current.accuracy.toStringAsFixed(3)} '
    'vs $old ${v1.accuracy.toStringAsFixed(3)}',
  );
  stdout.writeln(
    '  Brier:    $cur ${current.brier.toStringAsFixed(4)} '
    'vs $old ${v1.brier.toStringAsFixed(4)} (lower is better)',
  );
  if (current.n < minMeaningfulSample) {
    stdout.writeln(
      '  n = ${current.n} is too small to support a tuning decision.',
    );
  }
}
