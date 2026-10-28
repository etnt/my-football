import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/ai/output_validator.dart';
import 'package:my_football/features/recap/fact_sheet.dart';
import 'package:my_football/models/card_event.dart';
import 'package:my_football/models/goal_event.dart';
import 'package:my_football/models/match_timeline.dart';

import '../../support/fixture_helpers.dart';

FactSheet _factSheet() {
  return FactSheet.build(
    fixture: fixtureFinished(),
    timeline: MatchTimeline(
      goals: const [
        GoalEvent(scorer: 'Saka', minute: 12, team: 'Arsenal'),
        GoalEvent(
          scorer: 'Caicedo',
          minute: 58,
          team: 'Chelsea',
          penalty: true,
        ),
        GoalEvent(scorer: 'Saka', minute: 77, team: 'Arsenal'),
      ],
      cards: const [CardEvent(player: 'Caicedo', team: 'Chelsea', red: true)],
    ),
  );
}

/// A two-sentence recap that only states facts from [_factSheet].
const validRecap =
    'Arsenal beat Chelsea 2 to 1. Saka opened the scoring in the first '
    'half and Caicedo equalised from the penalty spot before being sent '
    'off with a red card late on.';

void main() {
  test('valid fact-only text passes', () {
    final result = validateRecapText(validRecap, _factSheet());
    expect(result.ok, isTrue);
    expect(result.reason, isNull);
  });

  test('common sentence starters and card words are not treated as names', () {
    // Seen on a Pixel 10 Pro: a longer recap opened a sentence with
    // "Several", which the name check used to reject.
    const text =
        'Arsenal beat Chelsea 2 to 1. Several chances fell to Saka, who '
        'scored twice. However, Caicedo equalised from the penalty spot. '
        'Later, Caicedo was shown a red card. Yellow cards were rare. '
        'Round 2 ended well.';
    final result = validateRecapText(text, _factSheet());
    expect(result.ok, isTrue);
  });

  test('an invented name at the start of a sentence is still rejected', () {
    const text =
        'Arsenal beat Chelsea 2 to 1. Several chances fell to Saka. '
        'Martinelli also hit the post before the break.';
    final result = validateRecapText(text, _factSheet());
    expect(result.ok, isFalse);
    expect(result.reason, RejectReason.unknownName);
  });

  test('made-up number is rejected', () {
    final result = validateRecapText(
      'Arsenal beat Chelsea 2 to 1 with 9 goals in total. Saka opened the '
      'scoring in the first half and Caicedo equalised from the penalty '
      'spot before being sent off with a red card late on.',
      _factSheet(),
    );
    expect(result.ok, isFalse);
    expect(result.reason, RejectReason.unknownNumber);
  });

  test('made-up player name is rejected', () {
    final result = validateRecapText(
      'Arsenal beat Chelsea 2 to 1. Zlatan opened the scoring in the first '
      'half and Caicedo equalised from the penalty spot before being sent '
      'off with a red card late on.',
      _factSheet(),
    );
    expect(result.ok, isFalse);
    expect(result.reason, RejectReason.unknownName);
  });

  test('accented name in the facts is accepted', () {
    final facts = FactSheet.build(
      fixture: fixtureFinished(),
      // 3 goal rows for the 2–1 score, so the timeline is complete and the
      // scorers stay in the fact sheet.
      timeline: MatchTimeline(
        goals: const [
          GoalEvent(scorer: 'Nkunku', minute: 12, team: 'Chelsea'),
          GoalEvent(scorer: 'Saka', minute: 34, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 77, team: 'Arsenal'),
        ],
      ),
    );
    final result = validateRecapText(
      'Chelsea levelled through Nkunku in the first half. The game stayed '
      'level from there and the sides went in at the interval all square '
      'after an open spell of football.',
      facts,
    );
    expect(result.ok, isTrue);
  });

  test('names with internal capitals (McGinn) are checked and accepted', () {
    final facts = FactSheet.build(
      fixture: fixtureFinished(),
      // 3 goal rows for the 2–1 score, so the timeline is complete and
      // the scorer stays in the fact sheet.
      timeline: MatchTimeline(
        goals: const [
          GoalEvent(scorer: 'John McGinn', minute: 12, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 40, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 77, team: 'Arsenal'),
        ],
      ),
    );
    final result = validateRecapText(
      'Arsenal beat Chelsea 2 to 1 thanks to John McGinn, whose first-half '
      'strike proved decisive after an open and entertaining second half.',
      facts,
    );
    expect(result.ok, isTrue);
  });

  test('names with a leading accent (Ødegaard) are checked and accepted', () {
    final facts = FactSheet.build(
      fixture: fixtureFinished(),
      // 3 goal rows for the 2–1 score, so the timeline is complete and
      // the scorer stays in the fact sheet.
      timeline: MatchTimeline(
        goals: const [
          GoalEvent(scorer: 'Martin Ødegaard', minute: 12, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 40, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 77, team: 'Arsenal'),
        ],
      ),
    );
    final result = validateRecapText(
      'Arsenal beat Chelsea 2 to 1 and Martin Ødegaard settled it with a '
      'calm first-half finish for the home side after a bright opening.',
      facts,
    );
    expect(result.ok, isTrue);
  });

  test('hyphenated name in the facts is accepted', () {
    final facts = FactSheet.build(
      fixture: fixtureFinished(),
      // 3 goal rows for the 2–1 score, so the timeline is complete and
      // the scorer stays in the fact sheet.
      timeline: MatchTimeline(
        goals: const [
          GoalEvent(scorer: 'Saka-Smith', minute: 12, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 40, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 77, team: 'Arsenal'),
        ],
      ),
    );
    final result = validateRecapText(
      'Arsenal beat Chelsea 2 to 1 and Saka-Smith opened the scoring with '
      'a calm finish before the home side closed the game out late on.',
      facts,
    );
    expect(result.ok, isTrue);
  });

  test('apostrophe name in the facts is accepted', () {
    final facts = FactSheet.build(
      fixture: fixtureFinished(),
      // 3 goal rows for the 2–1 score, so the timeline is complete and
      // the scorer stays in the fact sheet.
      timeline: MatchTimeline(
        goals: const [
          GoalEvent(scorer: "O'Neill", minute: 12, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 40, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 77, team: 'Arsenal'),
        ],
      ),
    );
    final result = validateRecapText(
      "Arsenal beat Chelsea 2 to 1 and O'Neill opened the scoring with a "
      'calm finish before the home side closed the game out late on.',
      facts,
    );
    expect(result.ok, isTrue);
  });

  test('made-up name with internal capitals is rejected', () {
    final result = validateRecapText(
      'Arsenal beat Chelsea 2 to 1. McGonnely opened the scoring in the '
      'first half and Caicedo equalised from the penalty spot late on.',
      _factSheet(),
    );
    expect(result.ok, isFalse);
    expect(result.reason, RejectReason.unknownName);
  });

  test('text under 60 characters is rejected', () {
    final result = validateRecapText('Too short.', _factSheet());
    expect(result.ok, isFalse);
    expect(result.reason, RejectReason.tooShort);
  });

  test('text over 600 characters is rejected', () {
    final long = 'Arsenal beat Chelsea 2 to 1. ' * 25; // 725 chars
    final result = validateRecapText(long, _factSheet());
    expect(result.ok, isFalse);
    expect(result.reason, RejectReason.tooLong);
  });

  test('a bare VAR claim is rejected even when the facts contain a similar '
      'name', () {
    final facts = FactSheet.build(
      fixture: fixtureFinished(),
      // 3 goal rows for the 2–1 score, so the timeline is complete and
      // the scorer stays in the fact sheet.
      timeline: MatchTimeline(
        goals: const [
          GoalEvent(scorer: 'Varane', minute: 12, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 40, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 77, team: 'Arsenal'),
        ],
      ),
    );
    final result = validateRecapText(
      'Arsenal beat Chelsea 2 to 1. A long VAR review delayed the restart, '
      'and the crowd grew restless as the officials checked the call.',
      facts,
    );
    expect(result.ok, isFalse);
    expect(result.reason, RejectReason.forbiddenClaim);
  });

  test('a bare VAR claim is rejected even when the facts contain an accented '
      'name that ASCII word boundaries would cut at', () {
    final facts = FactSheet.build(
      fixture: fixtureFinished(),
      // 3 goal rows for the 2–1 score, so the timeline is complete and
      // the scorer stays in the fact sheet.
      timeline: MatchTimeline(
        goals: const [
          GoalEvent(scorer: 'Varé', minute: 12, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 40, team: 'Arsenal'),
          GoalEvent(scorer: 'Saka', minute: 77, team: 'Arsenal'),
        ],
      ),
    );
    // Dart's ASCII `\b` sees a word boundary inside "Varé" (between "var"
    // and "é"), so a plain `\bvar\b` search of the fact text would match
    // and wrongly allow a bare VAR mention in the recap.
    final result = validateRecapText(
      'Arsenal beat Chelsea 2 to 1. A long VAR review delayed the restart, '
      'and the crowd grew restless as the officials checked the call.',
      facts,
    );
    expect(result.ok, isFalse);
    expect(result.reason, RejectReason.forbiddenClaim);
  });

  test('injury, transfer and referee claims are rejected when absent from '
      'the facts', () {
    const claims = {
      'injury':
          'Saka picked up an injury in the second half and had to be '
          'substituted, which changed the game for both sides.',
      'transfer':
          'There was a transfer rumour around the ground before the '
          'match kicked off, but neither side confirmed anything.',
      'referee':
          'The referee had a busy evening and handed out several '
          'bookings, but the result stood after a long check.',
      'VAR':
          'A long VAR review delayed the restart, and the crowd grew '
          'restless as the officials checked the offside call.',
      'suspend':
          'The player faces a suspend ruling after his red card and '
          'will sit out the next fixture for his club.',
      'sacked':
          'The board has hinted the coach could be sacked after this '
          'defeat, though no official comment has been made so far.',
    };
    claims.forEach((label, text) {
      final result = validateRecapText(text, _factSheet());
      expect(result.ok, isFalse, reason: label);
      expect(result.reason, RejectReason.forbiddenClaim, reason: label);
    });
  });

  test('sentence starters and month names are not rejected', () {
    const text =
        'Despite an even start, Arsenal led 2 to 1 at the interval. The '
        'game was played on Saturday and both sides had chances after the '
        'break before the home team closed it out in December.';
    final result = validateRecapText(text, _factSheet());
    expect(result.ok, isTrue);
  });

  test('claims present in the fact lines are allowed', () {
    final facts = FactSheet.build(
      fixture: fixtureFinished(),
      // 3 goal rows for the 2–1 score, so the timeline is complete and the
      // claim words stay in the fact lines.
      timeline: MatchTimeline(
        goals: const [
          GoalEvent(
            scorer: 'Referee Show',
            minute: 12,
            team: 'Arsenal',
            penalty: true,
          ),
          GoalEvent(scorer: 'Saka', minute: 40, team: 'Arsenal'),
          GoalEvent(scorer: 'Nkunku', minute: 77, team: 'Chelsea'),
        ],
      ),
    );
    const text =
        'Arsenal won 2 to 1 thanks to a penalty from Referee Show. The '
        'referee was the only name on the scoresheet and the spot kick '
        'proved decisive for the home side.';
    final result = validateRecapText(text, facts);
    expect(result.ok, isTrue);
  });
}
