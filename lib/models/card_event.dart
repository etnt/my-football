/// A single booking parsed from a match timeline (v2 `event_timeline`).
///
/// Only rows where `strTimeline == 'Card'` are represented.
class CardEvent {
  const CardEvent({
    required this.player,
    this.team = '',
    this.red = false,
  });

  /// Name of the booked player (`strPlayer`).
  final String player;

  /// The player's team (`strTeam`).
  final String team;

  /// True for a red card (including a second-yellow dismissal); false for a
  /// plain yellow.
  final bool red;

  factory CardEvent.fromTimelineJson(Map<String, dynamic> json) {
    final detail = (json['strTimelineDetail'] as String?)?.trim().toLowerCase() ?? '';
    return CardEvent(
      player: (json['strPlayer'] as String?)?.trim() ?? '',
      team: (json['strTeam'] as String?)?.trim() ?? '',
      red: detail.contains('red') || detail.contains('second yellow'),
    );
  }

  Map<String, dynamic> toJson() => {
        'p': player,
        if (team.isNotEmpty) 't': team,
        if (red) 'r': true,
      };

  factory CardEvent.fromJson(Map<String, dynamic> json) => CardEvent(
        player: (json['p'] as String?) ?? '',
        team: (json['t'] as String?) ?? '',
        red: json['r'] == true,
      );
}
