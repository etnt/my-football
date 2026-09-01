import '../../models/fixture.dart';

/// A configured kick-off reminder for one upcoming match.
class MatchReminder {
  const MatchReminder({
    required this.fixtureId,
    required this.kickoffUtc,
    required this.homeName,
    required this.awayName,
    required this.leadMinutes,
  });

  /// Default lead time when the user opens the sheet for the first time.
  static const defaultLeadMinutes = 15;

  /// Lead times the reminder sheet offers, in minutes before kick-off.
  static const allowedLeadMinutes = [15, 30, 60, 120];

  /// Whether a reminder can be set for [fixture]: only upcoming matches whose
  /// kick-off is still in the future (not finished, not live, not postponed).
  static bool canRemind(Fixture fixture) =>
      !fixture.postponed &&
      !fixture.isFinished &&
      !fixture.isLive &&
      fixture.dateUtc.isAfter(DateTime.now().toUtc());

  final int fixtureId;

  /// Kick-off in UTC. TheSportsDB timestamps carry no zone suffix but are UTC.
  final DateTime kickoffUtc;
  final String homeName;
  final String awayName;

  /// Minutes before kick-off at which the notification should fire.
  final int leadMinutes;

  /// When the notification should fire (UTC).
  DateTime get notifyAtUtc =>
      kickoffUtc.subtract(Duration(minutes: leadMinutes));

  /// True once the match has kicked off (the reminder is pointless then).
  bool get isExpired => DateTime.now().toUtc().isAfter(kickoffUtc);

  Map<String, dynamic> toJson() => {
        'fixtureId': fixtureId,
        'kickoffUtc': kickoffUtc.toUtc().toIso8601String(),
        'homeName': homeName,
        'awayName': awayName,
        'leadMinutes': leadMinutes,
      };

  factory MatchReminder.fromJson(Map<String, dynamic> json) {
    return MatchReminder(
      fixtureId: json['fixtureId'] as int,
      kickoffUtc: DateTime.parse(json['kickoffUtc'] as String).toUtc(),
      homeName: json['homeName'] as String,
      awayName: json['awayName'] as String,
      leadMinutes: json['leadMinutes'] as int,
    );
  }
}
