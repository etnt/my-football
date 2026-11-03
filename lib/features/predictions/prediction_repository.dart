import '../../models/fixture.dart';
import '../../models/league.dart';
import '../../models/team_standing.dart';
import '../fixtures/fixtures_repository.dart';
import '../standings/standings_repository.dart';
import 'prediction_input.dart';
import 'prediction_result.dart';
import 'team_form.dart';

/// The form data picked for one team, per plan §4.1.
typedef TeamFormData = ({
  List<String> form,
  bool ordered,
  FormSource source,
  List<FormMatch> matches,
});

/// Builds a [PredictionInput] from the data the app already loads and caches
/// (REQ-008): the league table (6 h TTL) and the season events (30 min TTL).
/// No new network endpoints are used.
class PredictionRepository {
  PredictionRepository({required this.standings, required this.fixtures});

  final StandingsRepository standings;
  final FixturesRepository fixtures;

  /// Loads both cached sources, finds the fixture and both teams, and picks
  /// each team's form source. Throws [PredictionUnavailable] when the fixture
  /// is gone from the season data or a team is not in the selected table
  /// (REQ-007).
  Future<PredictionInput> build({
    required League league,
    required int season,
    required int fixtureId,
  }) async {
    // Start both loads before awaiting either, so the two cached sources are
    // fetched in parallel.
    final tableFuture = standings.getStandings(league: league, season: season);
    final eventsFuture = fixtures.getSeasonEvents(
      league: league,
      season: season,
    );
    final table = await tableFuture;
    final events = await eventsFuture;

    Fixture? fixture;
    for (final e in events) {
      if (e.id == fixtureId) {
        fixture = e;
        break;
      }
    }
    if (fixture == null) {
      throw const PredictionUnavailable(
        'This match is no longer in the cached season data.',
      );
    }

    final homeRow = _findTeam(table, fixture.homeId);
    if (homeRow == null) {
      throw PredictionUnavailable(
        '${fixture.homeName} is not in the selected league table.',
      );
    }
    final awayRow = _findTeam(table, fixture.awayId);
    if (awayRow == null) {
      throw PredictionUnavailable(
        '${fixture.awayName} is not in the selected league table.',
      );
    }

    final homeForm = _formFor(fixture.homeId, events, fixture.dateUtc, homeRow);
    final awayForm = _formFor(fixture.awayId, events, fixture.dateUtc, awayRow);

    // League average points per game over the rows that have played games;
    // 0.0 makes the calculator use its own fallback constant.
    var totalPoints = 0;
    var totalPlayed = 0;
    for (final row in table) {
      if (row.played > 0) {
        totalPoints += row.points;
        totalPlayed += row.played;
      }
    }
    final leagueAvgPpg = totalPlayed > 0 ? totalPoints / totalPlayed : 0.0;

    return PredictionInput(
      fixture: fixture,
      home: _factors(homeRow, homeForm),
      away: _factors(awayRow, awayForm),
      leagueAvgPpg: leagueAvgPpg,
      // TeamStanding has no group field, so the current single-table
      // behaviour is kept (plan §3).
      sameGroup: true,
      // Every team's record, to rate the opponents in the recent form.
      table: {
        for (final row in table)
          row.teamId: TeamRecord(
            played: row.played,
            points: row.points,
            goalsDiff: row.goalsDiff,
          ),
      },
    );
  }

  TeamStanding? _findTeam(List<TeamStanding> table, int teamId) {
    for (final row in table) {
      if (row.teamId == teamId) return row;
    }
    return null;
  }

  /// Picks the form source per plan §4.1: derived season-event form when it
  /// has at least one result, otherwise `strForm`, otherwise no form at all
  /// (REQ-006: missing data is never invented).
  ///
  /// The app assumes a Premium key, so the season events are complete and
  /// even one derived result is the team's real latest result, with its
  /// opponent (plan §4.10). The old threshold of 3 guarded against the free
  /// key's ~15-event sample. `strForm` is now only a fallback for when the
  /// season events have no result for the team.
  TeamFormData _formFor(
    int teamId,
    List<Fixture> events,
    DateTime kickoffUtc,
    TeamStanding row,
  ) {
    // Season-event form is always newest first with a known order (fixture
    // dates); only results strictly before kick-off count.
    final matches = recentMatches(teamId, events, before: kickoffUtc);
    if (matches.isNotEmpty) {
      final withContext = formMatchesFor(teamId, matches);
      return (
        form: [for (final m in withContext) m.result],
        ordered: true,
        source: FormSource.seasonEvents,
        matches: withContext,
      );
    }
    final parsed = parseStandingForm(row.form);
    if (parsed != null) {
      return (
        form: parsed.results,
        ordered: parsed.ordered,
        source: FormSource.standingsForm,
        // strForm has no opponents: form is compared with the season
        // average instead (plan §4.10).
        matches: const <FormMatch>[],
      );
    }
    return (
      form: const <String>[],
      ordered: false,
      source: FormSource.none,
      matches: const <FormMatch>[],
    );
  }

  TeamFactors _factors(TeamStanding row, TeamFormData form) {
    return TeamFactors(
      teamId: row.teamId,
      name: row.teamName,
      rank: row.rank,
      played: row.played,
      points: row.points,
      goalsDiff: row.goalsDiff,
      form: form.form,
      formOrdered: form.ordered,
      formSource: form.source,
      formMatches: form.matches,
    );
  }
}
