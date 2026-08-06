import 'card_event.dart';
import 'goal_event.dart';

/// The parsed contents of a single match timeline (v2 `event_timeline`): the
/// goals (with scorers/assists) and the cards, from one API call.
class MatchTimeline {
  const MatchTimeline({this.goals = const [], this.cards = const []});

  final List<GoalEvent> goals;
  final List<CardEvent> cards;

  Map<String, dynamic> toJson() => {
        'g': goals.map((e) => e.toJson()).toList(),
        'c': cards.map((e) => e.toJson()).toList(),
      };

  factory MatchTimeline.fromJson(Map<String, dynamic> json) => MatchTimeline(
        goals: (json['g'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(GoalEvent.fromJson)
                .toList() ??
            const [],
        cards: (json['c'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(CardEvent.fromJson)
                .toList() ??
            const [],
      );
}
