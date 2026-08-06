/// A single goal parsed from a match timeline (v2 `event_timeline`).
///
/// Only rows where `strTimeline == 'Goal'` are represented. It captures who
/// scored, who assisted (if anyone), and whether it was a penalty or own goal
/// so leaderboards can count and annotate correctly.
class GoalEvent {
  const GoalEvent({
    required this.scorer,
    this.assist,
    this.team = '',
    this.penalty = false,
    this.ownGoal = false,
  });

  /// Name of the scorer (`strPlayer`). May be empty for malformed rows.
  final String scorer;

  /// Name of the assisting player (`strAssist`), or null when unassisted.
  final String? assist;

  /// The scoring team (`strTeam`) — also the assisting player's team.
  final String team;

  /// True when the goal was scored from a penalty.
  final bool penalty;

  /// True when the goal was an own goal (excluded from scorer tallies).
  final bool ownGoal;

  factory GoalEvent.fromTimelineJson(Map<String, dynamic> json) {
    final detail = (json['strTimelineDetail'] as String?)?.trim() ?? '';
    final lower = detail.toLowerCase();
    final assist = (json['strAssist'] as String?)?.trim();
    return GoalEvent(
      scorer: (json['strPlayer'] as String?)?.trim() ?? '',
      assist: (assist == null || assist.isEmpty) ? null : assist,
      team: (json['strTeam'] as String?)?.trim() ?? '',
      penalty: lower.contains('penalty'),
      ownGoal: lower.contains('own goal'),
    );
  }

  /// Compact form persisted in the cache (kept tiny on purpose).
  Map<String, dynamic> toJson() => {
        'p': scorer,
        if (assist != null) 'a': assist,
        if (team.isNotEmpty) 't': team,
        if (penalty) 'pen': true,
        if (ownGoal) 'og': true,
      };

  factory GoalEvent.fromJson(Map<String, dynamic> json) => GoalEvent(
        scorer: (json['p'] as String?) ?? '',
        assist: json['a'] as String?,
        team: (json['t'] as String?) ?? '',
        penalty: json['pen'] == true,
        ownGoal: json['og'] == true,
      );
}
