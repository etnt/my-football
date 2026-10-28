import '../../core/text/lookup_text_normalizer.dart';
import '../../models/fixture.dart';
import '../../models/goal_event.dart';
import '../../models/card_event.dart';
import '../../models/match_timeline.dart';

/// The immutable set of facts the recap (template or AI) is allowed to state.
///
/// Data gaps noted on purpose:
/// - `Fixture` carries no competition name and no half-time score, so
///   [competition] is an optional parameter and half-time is omitted.
/// - `CardEvent` carries no minute, so cards are listed with player, team and
///   yellow/red only.
class FactSheet {
  FactSheet({
    required this.fixtureId,
    this.competition,
    this.round,
    required this.dateLocal,
    required this.homeName,
    required this.awayName,
    required this.homeGoals,
    required this.awayGoals,
    required this.goals,
    required this.cards,
    required this.eventsComplete,
  });

  /// TheSportsDB event id, used for the recap cache key.
  final int fixtureId;

  /// Competition display name, when the caller has one (e.g. "Premier League").
  final String? competition;

  /// League round / matchweek number, when available.
  final int? round;

  /// Kick-off time in the device's local timezone.
  final DateTime dateLocal;

  final String homeName;
  final String awayName;

  /// Goals per side; a missing score is treated as 0.
  final int homeGoals;
  final int awayGoals;

  /// Goals sorted by minute (null minutes last).
  final List<GoalEvent> goals;

  /// Bookings, in timeline order.
  final List<CardEvent> cards;

  /// True when the timeline accounted for every goal in the score, so the
  /// model may assume the goal list is exhaustive. False when the provider
  /// returned fewer goals than the score implies (or none at all despite a
  /// positive score) — the recap must then stay score-only.
  final bool eventsComplete;

  int get totalGoals => homeGoals + awayGoals;

  /// Builds a fact sheet from a fixture and its (possibly empty) timeline.
  factory FactSheet.build({
    required Fixture fixture,
    required MatchTimeline timeline,
    String? competition,
  }) {
    final homeGoals = fixture.homeGoals ?? 0;
    final awayGoals = fixture.awayGoals ?? 0;
    final scored = homeGoals + awayGoals;
    final timelineGoals = timeline.goals;

    // Incomplete timeline: the provider returned fewer (or no) goal rows
    // than the score implies, so the goal and card lists cannot be trusted —
    // clear them both. The template (and the model prompt) must then stay
    // score-only rather than invent scorers.
    final eventsComplete = scored == 0 || timelineGoals.length == scored;
    final goals = eventsComplete
        ? (List<GoalEvent>.of(timelineGoals)..sort(_compareByMinute))
        : <GoalEvent>[];
    final cards = eventsComplete
        ? List<CardEvent>.of(timeline.cards)
        : <CardEvent>[];

    return FactSheet(
      fixtureId: fixture.id,
      competition: competition,
      round: fixture.round,
      dateLocal: fixture.dateUtc.toLocal(),
      homeName: fixture.homeName,
      awayName: fixture.awayName,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      goals: goals,
      cards: cards,
      eventsComplete: eventsComplete,
    );
  }

  static int _compareByMinute(GoalEvent a, GoalEvent b) {
    final am = a.minute;
    final bm = b.minute;
    if (am == null && bm == null) return 0;
    if (am == null) return 1;
    if (bm == null) return -1;
    return am.compareTo(bm);
  }

  /// Human-readable fact lines: also the "Show facts" list and the prompt body.
  List<String> toFactLines() {
    final lines = <String>[
      'Match: $homeName $homeGoals–$awayGoals $awayName',
      'Date: ${_formatDate(dateLocal)}',
      if (competition != null && competition!.isNotEmpty)
        'Competition: $competition',
      if (round != null) 'Round: $round',
    ];
    for (final goal in goals) {
      final team = goal.team.isNotEmpty ? goal.team : 'unknown team';
      final parts = <String>[];
      if (goal.penalty) parts.add('penalty');
      if (goal.ownGoal) parts.add('own goal');
      if (goal.assist != null && goal.assist!.isNotEmpty) {
        parts.add('assist ${goal.assist}');
      }
      final suffix = parts.isEmpty ? '' : ' – ${parts.join(', ')}';
      final minute = goal.minute == null ? 'unknown minute' : '${goal.minute}\'';
      lines.add(
        'Goal: $minute ${goal.scorer.isEmpty ? 'unknown scorer' : goal.scorer}'
        ' ($team)$suffix',
      );
    }
    for (final card in cards) {
      final team = card.team.isNotEmpty ? card.team : 'unknown team';
      lines.add(
        'Card: ${card.player.isEmpty ? 'unknown player' : card.player} ($team)'
        ' – ${card.red ? 'red card' : 'yellow card'}',
      );
    }
    return lines;
  }

  static String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  /// Numbers the recap may mention: score, total, minutes, round, date parts
  /// and event counts.
  Set<String> get allowedNumbers {
    final set = <String>{};
    void add(int? n) {
      if (n != null) set.add(n.toString());
    }

    add(homeGoals);
    add(awayGoals);
    add(totalGoals);
    add(round);
    add(goals.length);
    add(cards.length);
    add(dateLocal.day);
    add(dateLocal.year);
    for (final goal in goals) {
      add(goal.minute);
    }
    return set;
  }

  /// Normalised tokens the recap may mention: team names, scorers, assists,
  /// card players and the competition name.
  Set<String> get allowedNameTokens {
    final tokens = <String>{};
    void addTokens(String? value) {
      if (value == null) return;
      final normalized = normalizeLookupText(value);
      if (normalized.isEmpty) return;
      for (final token in normalized.split(' ')) {
        if (token.isNotEmpty) tokens.add(token);
      }
    }

    addTokens(homeName);
    addTokens(awayName);
    addTokens(competition);
    for (final goal in goals) {
      addTokens(goal.scorer);
      addTokens(goal.assist);
      addTokens(goal.team);
    }
    for (final card in cards) {
      addTokens(card.player);
      addTokens(card.team);
    }
    return tokens;
  }
}
