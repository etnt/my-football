import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/predictions/prediction_prompt.dart';
import 'package:my_football/features/predictions/prediction_result.dart';
import 'package:my_football/models/fixture.dart';

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

void main() {
  test('the prompt contains names, verdict, percents and every reason text', () {
    final prompt = buildPredictionPrompt(_fixture(), _result());

    expect(prompt, contains('Arsenal vs Chelsea'));
    expect(prompt, contains('Home win – slight favourite'));
    expect(prompt, contains('Arsenal 52%'));
    expect(prompt, contains('Draw 24%'));
    expect(prompt, contains('Chelsea 24%'));
    expect(
      prompt,
      contains('Arsenal are 1st, Chelsea are 8th (2.1 vs 1.3 points per game).'),
    );
    expect(prompt, contains('Arsenal have won their last 3.'));
    // Instruction limits, REQ-010 wording included.
    expect(prompt, contains('Do not give gambling advice.'));
    expect(prompt, contains('2 to 3 plain sentences.'));
  });

  test('the prompt contains no forbidden word (validator parity)', () {
    final prompt = buildPredictionPrompt(_fixture(), _result());
    final forbidden = RegExp(
      r"(?<![\p{L}\p{N}])(odds|bets?|betting|betted|guarantee\w*|calibrat\w*)(?![\p{L}\p{N}])",
      caseSensitive: false,
      unicode: true,
    );
    expect(forbidden.allMatches(prompt), isEmpty);
  });

  test('allowed numbers cover percents, reason numbers and name digits', () {
    final numbers = predictionAllowedNumbers(_fixture(), _result());

    // The three displayed percentages.
    expect(numbers, containsAll(['52', '24']));
    // Digits inside reason number values (2.1 → 2 and 1) and reason texts
    // (1st/8th ordinals, streak 3).
    expect(numbers, containsAll(['1', '2', '3', '8']));
    // Team names without digits contribute nothing.
    expect(numbers, isNot(contains('100')));
  });

  test('allowed name tokens are the normalised team name tokens', () {
    final tokens = predictionAllowedNameTokens(
      Fixture(
        id: 1,
        dateUtc: DateTime.utc(2026, 11, 8),
        statusShort: 'NS',
        statusLong: '',
        elapsed: null,
        homeId: 1,
        homeName: 'Paris Saint-Germain',
        homeLogo: '',
        awayId: 2,
        awayName: 'Chelsea',
        awayLogo: '',
        homeGoals: null,
        awayGoals: null,
      ),
    );
    expect(tokens, containsAll(['paris', 'saint', 'germain', 'chelsea']));
  });

  test('the prompt version is pinned', () {
    expect(predictionPromptVersion, 'v1');
  });
}
