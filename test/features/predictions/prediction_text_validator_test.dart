import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/ai/output_validator.dart';
import 'package:my_football/features/predictions/prediction_result.dart';
import 'package:my_football/features/predictions/prediction_text_validator.dart';
import 'package:my_football/models/fixture.dart';

Fixture _fixture() => Fixture(
  id: 100,
  dateUtc: DateTime.utc(2026, 11, 8, 15),
  statusShort: 'NS',
  statusLong: '',
  elapsed: null,
  homeId: 1,
  homeName: 'Arsenal',
  homeLogo: '',
  awayId: 2,
  awayName: 'Chelsea',
  awayLogo: '',
  homeGoals: null,
  awayGoals: null,
);

PredictionResult _result() {
  return PredictionResult(
    pHome: 0.52,
    pDraw: 0.24,
    pAway: 0.24,
    displayPercents: const {
      Outcome.home: 52,
      Outcome.draw: 24,
      Outcome.away: 24,
    },
    verdict: Verdict.homeWin,
    isSlight: true,
    reasons: const [
      PredictionReason(
        factor: 'table',
        favours: PredictionFavour.home,
        text: 'Arsenal are 1st, Chelsea are 8th (2.1 vs 1.3 points per game).',
        numbers: {'homePpg': 2.1, 'awayPpg': 1.3},
      ),
      PredictionReason(
        factor: 'form',
        favours: PredictionFavour.home,
        text: 'Arsenal have won their last 3.',
        numbers: {'streak': 3},
      ),
    ],
    missingNotes: const [],
    completeness: Completeness.full,
    formulaVersion: 'v1',
  );
}

void main() {
  late Fixture fixture;
  late PredictionResult result;

  setUp(() {
    fixture = _fixture();
    result = _result();
  });

  test('a faithful summary passes', () {
    final validation = validatePredictionText(
      'Arsenal look slightly ahead of Chelsea. The table gap and home '
      'advantage point the same way, and recent form supports that. A draw '
      'is possible but less likely.',
      fixture,
      result,
    );
    expect(validation.ok, isTrue);
  });

  test('common sentence openers are accepted', () {
    for (final text in [
      'Based on the table, Arsenal are 1st and Chelsea are 8th.',
      'According to the table, Arsenal have the better points per game.',
      'Given their recent form, Arsenal are the slight favourites here.',
      'Compared with Chelsea, Arsenal have the stronger table position.',
    ]) {
      final validation = validatePredictionText(text, fixture, result);
      expect(
        validation.ok,
        isTrue,
        reason: '$text (${validation.reason?.name})',
      );
    }
  });

  test('an invented number is rejected', () {
    final validation = validatePredictionText(
      'Arsenal have won 7 of their last matches and look clear favourites.',
      fixture,
      result,
    );
    expect(validation.ok, isFalse);
    expect(validation.reason, RejectReason.unknownNumber);
  });

  test('a number that exists but is attributed to the wrong side passes', () {
    // Documented limitation (see validatePredictionText): the number check
    // is set-based, so 52 is allowed even though it belongs to Arsenal, not
    // Chelsea. Accepted for v1 — the deterministic percentages stay visible
    // above the summary, so a mis-attribution is visible to the user.
    final validation = validatePredictionText(
      'Chelsea sit on 52 percent here while Arsenal trail on 24 percent.',
      fixture,
      result,
    );
    expect(validation.ok, isTrue);
  });

  test('an invented team name is rejected', () {
    final validation = validatePredictionText(
      'Liverpool look slightly ahead of Chelsea after a strong run of games.',
      fixture,
      result,
    );
    expect(validation.ok, isFalse);
    expect(validation.reason, RejectReason.unknownName);
  });

  test('forbidden betting and over-confidence words are rejected', () {
    for (final text in [
      'Arsenal look good value in the odds for this match.',
      'Arsenal look strong and this looks good for betting.',
      'Arsenal will surely win, that much is guaranteed.',
      'The estimate is well calibrated for this fixture.',
    ]) {
      final validation = validatePredictionText(text, fixture, result);
      expect(validation.ok, isFalse, reason: text);
      expect(validation.reason, RejectReason.forbiddenClaim, reason: text);
    }
  });

  test('"better" and "alphabet" pass while "betting" fails', () {
    final ok = validatePredictionText(
      'Arsenal are the better team and the alphabet order favours them.',
      fixture,
      result,
    );
    expect(ok.ok, isTrue);

    final rejected = validatePredictionText(
      'Arsenal are the better team, so they look good for betting.',
      fixture,
      result,
    );
    expect(rejected.ok, isFalse);
    expect(rejected.reason, RejectReason.forbiddenClaim);
  });

  test('too short and too long are rejected', () {
    expect(
      validatePredictionText('Too short.', fixture, result).reason,
      RejectReason.tooShort,
    );
    expect(
      validatePredictionText('Arsenal ' * 80, fixture, result).reason,
      RejectReason.tooLong,
    );
  });

  test('rejection logs carry the rule name only, never match data', () {
    // CON-003: the matched number, team name or forbidden word is match
    // data (or reveals what the validator knows); logs keep the rule name.
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = previous);

    validatePredictionText(
      'Arsenal have won 7 of their last matches and look clear favourites.',
      fixture,
      result,
    );
    validatePredictionText(
      'Liverpool look slightly ahead of Chelsea this weekend.',
      fixture,
      result,
    );
    validatePredictionText(
      'Arsenal look good value in the odds for this match.',
      fixture,
      result,
    );
    validatePredictionText('Too short.', fixture, result);

    expect(logs, isNotEmpty);
    for (final log in logs) {
      expect(log, contains('rejected'));
      expect(log.contains('Liverpool'), isFalse, reason: log);
      expect(log.contains('Chelsea'), isFalse, reason: log);
      expect(log.contains('Arsenal'), isFalse, reason: log);
      expect(log.contains('7'), isFalse, reason: log);
      expect(log.contains('odds'), isFalse, reason: log);
    }
  });
}
