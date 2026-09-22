import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/api_exception.dart';
import 'package:my_football/core/api/football_api_client.dart';

/// Minimal [HttpClientAdapter] that returns a canned body + status, so we can
/// exercise the client without any network access.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.body, this.statusCode = 200});

  final String body;
  final int statusCode;
  RequestOptions? lastOptions;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

FootballApiClient _clientWith(
  _FakeAdapter adapter, {
  String? apiKey,
  void Function()? onRateLimited,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = adapter
    ..options.validateStatus = (status) => status != null && status < 500;
  return FootballApiClient(
    apiKey: apiKey,
    onRateLimited: onRateLimited,
    dio: dio,
  );
}

void main() {
  group('FootballApiClient.getStandings', () {
    const standingsBody = '''
    {
      "table": [
        {
          "intRank": "1",
          "idTeam": "133613",
          "strTeam": "Manchester City",
          "strBadge": "c.png",
          "intPoints": "89",
          "intGoalDifference": "61",
          "strForm": "WWDWW",
          "intPlayed": "38",
          "intWin": "28",
          "intDraw": "5",
          "intLoss": "5"
        },
        {
          "intRank": "2",
          "idTeam": "133604",
          "strTeam": "Arsenal",
          "strBadge": "a.png",
          "intPoints": "84",
          "intGoalDifference": "45",
          "strForm": "WLWWW",
          "intPlayed": "38",
          "intWin": "26",
          "intDraw": "6",
          "intLoss": "6"
        }
      ]
    }
    ''';

    test('parses the league table', () async {
      final client = _clientWith(_FakeAdapter(body: standingsBody));

      final table =
          await client.getStandings(leagueId: 4328, season: '2023-2024');

      expect(table, hasLength(2));
      expect(table.first.teamName, 'Manchester City');
      expect(table.first.points, 89);
      expect(table[1].teamName, 'Arsenal');
    });

    test('uses the free key in the path and sends l/s query params', () async {
      final adapter = _FakeAdapter(body: standingsBody);
      final client = _clientWith(adapter);

      await client.getStandings(leagueId: 4328, season: '2023-2024');

      expect(adapter.lastOptions?.path, '/123/lookuptable.php');
      expect(adapter.lastOptions?.queryParameters['l'], 4328);
      expect(adapter.lastOptions?.queryParameters['s'], '2023-2024');
    });

    test('uses a premium key in the path when provided', () async {
      final adapter = _FakeAdapter(body: standingsBody);
      final client = _clientWith(adapter, apiKey: 'premium123');

      await client.getStandings(leagueId: 4328, season: '2023-2024');

      expect(adapter.lastOptions?.path, '/premium123/lookuptable.php');
    });

    test('returns empty list when the table is null', () async {
      final client = _clientWith(_FakeAdapter(body: '{"table": null}'));

      final table =
          await client.getStandings(leagueId: 4328, season: '2023-2024');

      expect(table, isEmpty);
    });
  });

  group('FootballApiClient.getCountries', () {
    const countriesBody = '''
    {
      "countries": [
        {"name_en": "England", "flag_url_32": "e.png"},
        {"name_en": "Spain", "flag_url_32": "s.png"},
        {"name_en": "  France  "},
        {"name_en": ""},
        {"broken": "entry"}
      ]
    }
    ''';

    test('parses countries, trims them and sorts alphabetically', () async {
      final adapter = _FakeAdapter(body: countriesBody);
      final client = _clientWith(adapter);

      final countries = await client.getCountries();

      expect(countries, containsAll(['England', 'Spain', 'France']));
      expect(countries.indexOf('England'), lessThan(countries.indexOf('Spain')));
      expect(adapter.lastOptions?.path, '/123/all_countries.php');
    });

    test('merges in pseudo-countries like Europe so the Champions League '
        'can be browsed', () async {
      final client = _clientWith(_FakeAdapter(body: countriesBody));

      final countries = await client.getCountries();

      for (final pseudo in FootballApiClient.pseudoCountries) {
        expect(countries, contains(pseudo));
      }
      expect(countries, contains('Europe'));
      expect(countries.indexOf('England'), lessThan(countries.indexOf('World')));
    });

    test('does not duplicate a pseudo-country the server already returned',
        () async {
      const body = '{"countries": [{"name_en": "Europe"}, {"name_en": "Spain"}]}';
      final client = _clientWith(_FakeAdapter(body: body));

      final countries = await client.getCountries();

      expect(countries.where((c) => c.toLowerCase() == 'europe'), hasLength(1));
    });

    test('still returns pseudo-countries when the list is null', () async {
      final client = _clientWith(_FakeAdapter(body: '{"countries": null}'));

      final countries = await client.getCountries();

      expect(countries, FootballApiClient.pseudoCountries);
    });
  });

  group('FootballApiClient.getSeasonEvents', () {
    const eventsBody = '''
    {
      "events": [
        {
          "idEvent": "100",
          "strTimestamp": "2023-08-11T19:00:00",
          "strStatus": "FT",
          "idHomeTeam": "40",
          "strHomeTeam": "Liverpool",
          "strHomeTeamBadge": "l.png",
          "idAwayTeam": "34",
          "strAwayTeam": "Newcastle",
          "strAwayTeamBadge": "n.png",
          "intHomeScore": "2",
          "intAwayScore": "1"
        },
        {
          "idEvent": "101",
          "strTimestamp": "2023-08-19T14:00:00",
          "strStatus": "NS",
          "idHomeTeam": "42",
          "strHomeTeam": "Arsenal",
          "idAwayTeam": "47",
          "strAwayTeam": "Tottenham",
          "intHomeScore": null,
          "intAwayScore": null
        }
      ]
    }
    ''';

    test('parses events with and without scores', () async {
      final adapter = _FakeAdapter(body: eventsBody);
      final client = _clientWith(adapter);

      final events =
          await client.getSeasonEvents(leagueId: 4328, season: '2023-2024');

      expect(events, hasLength(2));
      expect(events.first.homeName, 'Liverpool');
      expect(events.first.isFinished, isTrue);
      expect(events.first.hasScore, isTrue);
      expect(events.first.homeGoals, 2);

      expect(events[1].isFinished, isFalse);
      expect(events[1].hasScore, isFalse);
      expect(events[1].homeGoals, isNull);

      expect(adapter.lastOptions?.path, '/123/eventsseason.php');
      expect(adapter.lastOptions?.queryParameters['id'], 4328);
      expect(adapter.lastOptions?.queryParameters['s'], '2023-2024');
    });

    test('returns empty list when events is missing', () async {
      final client = _clientWith(_FakeAdapter(body: '{}'));

      final events =
          await client.getSeasonEvents(leagueId: 4328, season: '2023-2024');

      expect(events, isEmpty);
    });
  });

  group('FootballApiClient error handling', () {
    test('throws a rate-limit ApiException on HTTP 429', () async {
      final client = _clientWith(_FakeAdapter(body: '{}', statusCode: 429));

      expect(
        () => client.getStandings(leagueId: 4328, season: '2023-2024'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Rate limit'),
          ),
        ),
      );
    });

    test('invokes onRateLimited on HTTP 429', () async {
      var hits = 0;
      final client = _clientWith(
        _FakeAdapter(body: '{}', statusCode: 429),
        onRateLimited: () => hits++,
      );

      await expectLater(
        () => client.getStandings(leagueId: 4328, season: '2023-2024'),
        throwsA(isA<ApiException>()),
      );
      expect(hits, 1);
    });
  });

  group('FootballApiClient.getTeamLastEvents', () {
    const lastBody = '''
    {
      "results": [
        {
          "idEvent": "200",
          "strTimestamp": "2023-08-11T19:00:00",
          "strStatus": "FT",
          "idHomeTeam": "40",
          "strHomeTeam": "Girona",
          "idAwayTeam": "34",
          "strAwayTeam": "Arsenal",
          "intHomeScore": "1",
          "intAwayScore": "2"
        }
      ]
    }
    ''';

    test('parses the results key and hits eventslast.php', () async {
      final adapter = _FakeAdapter(body: lastBody);
      final client = _clientWith(adapter, apiKey: 'premium123');

      final events = await client.getTeamLastEvents(teamId: 133604);

      expect(events, hasLength(1));
      expect(events.first.homeName, 'Girona');
      expect(events.first.awayName, 'Arsenal');
      expect(adapter.lastOptions?.path, '/premium123/eventslast.php');
      expect(adapter.lastOptions?.queryParameters['id'], 133604);
    });

    test('returns empty list when results is missing', () async {
      final client = _clientWith(_FakeAdapter(body: '{}'), apiKey: 'p');

      final events = await client.getTeamLastEvents(teamId: 1);

      expect(events, isEmpty);
    });
  });

  group('FootballApiClient.getTeamNextEvents', () {
    const nextBody = '''
    {
      "events": [
        {
          "idEvent": "300",
          "strTimestamp": "2026-08-20T19:00:00",
          "strStatus": "NS",
          "idHomeTeam": "34",
          "strHomeTeam": "Arsenal",
          "idAwayTeam": "40",
          "strAwayTeam": "Leeds",
          "intHomeScore": null,
          "intAwayScore": null
        }
      ]
    }
    ''';

    test('parses the events key and hits eventsnext.php', () async {
      final adapter = _FakeAdapter(body: nextBody);
      final client = _clientWith(adapter, apiKey: 'premium123');

      final events = await client.getTeamNextEvents(teamId: 133604);

      expect(events, hasLength(1));
      expect(events.first.awayName, 'Leeds');
      expect(events.first.hasScore, isFalse);
      expect(adapter.lastOptions?.path, '/premium123/eventsnext.php');
      expect(adapter.lastOptions?.queryParameters['id'], 133604);
    });
  });

  group('FootballApiClient.searchPlayers', () {
    const playersBody = '''
    {
      "player": [
        {
          "idPlayer": "34146370",
          "strPlayer": "Erling Haaland",
          "strTeam": "Manchester City",
          "strSport": "Soccer",
          "strPosition": "Forward",
          "strNationality": "Norway",
          "dateBorn": "2000-07-21",
          "strThumb": "haaland.png"
        },
        {
          "idPlayer": "",
          "strPlayer": ""
        }
      ]
    }
    ''';

    test('parses player profiles and hits searchplayers.php', () async {
      final adapter = _FakeAdapter(body: playersBody);
      final client = _clientWith(adapter, apiKey: 'premium123');

      final players = await client.searchPlayers('Erling Haaland');

      expect(players, hasLength(1));
      expect(players.single.name, 'Erling Haaland');
      expect(players.single.team, 'Manchester City');
      expect(players.single.position, 'Forward');
      expect(adapter.lastOptions?.path, '/premium123/searchplayers.php');
      expect(adapter.lastOptions?.queryParameters['p'], 'Erling Haaland');
    });

    test('returns empty list when player is missing', () async {
      final client = _clientWith(_FakeAdapter(body: '{"player": null}'));

      final players = await client.searchPlayers('Someone');

      expect(players, isEmpty);
    });
  });

  group('FootballApiClient.getLeagueCurrentSeason', () {
    test('reads strCurrentSeason from lookupleague.php', () async {
      final adapter = _FakeAdapter(
        body:
            '{"leagues":[{"idLeague":"4347","strLeague":"Swedish Allsvenskan",'
            '"strCountry":"Sweden","strCurrentSeason":"2026"}]}',
      );
      final client = _clientWith(adapter);

      final season = await client.getLeagueCurrentSeason(leagueId: 4347);

      expect(season, '2026');
      expect(adapter.lastOptions?.path, '/123/lookupleague.php');
      expect(adapter.lastOptions?.queryParameters['id'], 4347);
    });

    test('trims the declared season', () async {
      final client = _clientWith(
        _FakeAdapter(body: '{"leagues":[{"strCurrentSeason": " 2026 "}]}'),
      );

      expect(await client.getLeagueCurrentSeason(leagueId: 1), '2026');
    });

    test('returns null when no league or season is declared', () async {
      expect(
        await _clientWith(
          _FakeAdapter(body: '{"leagues":[]}'),
        ).getLeagueCurrentSeason(leagueId: 1),
        isNull,
      );
      expect(
        await _clientWith(
          _FakeAdapter(body: '{"leagues":[{"strCurrentSeason":""}]}'),
        ).getLeagueCurrentSeason(leagueId: 1),
        isNull,
      );
    });
  });

  group('FootballApiClient.lookupPlayerById', () {
    const body = '''
    {
      "players": [
        {
          "idPlayer": "34169116",
          "strPlayer": "Erling Haaland",
          "strTeam": "Manchester City",
          "strNumber": "9",
          "strStatus": "Active",
          "strWage": "£525,000 per week",
          "strSigning": "€185M",
          "strSide": "Left",
          "strTeam2": "Norway",
          "strBirthLocation": "Leeds, England",
          "strHeight": "195 cm",
          "strWeight": "192 lbs",
          "strDescriptionEN": "Norwegian striker."
        }
      ]
    }
    ''';

    test('parses the full profile and hits lookupplayer.php', () async {
      final adapter = _FakeAdapter(body: body);
      final client = _clientWith(adapter, apiKey: 'p');

      final player = await client.lookupPlayerById(playerId: 34169116);

      expect(player, isNotNull);
      expect(player!.name, 'Erling Haaland');
      expect(player.number, '9');
      expect(player.wage, '£525,000 per week');
      expect(player.signing, '€185M');
      expect(player.preferredFoot, 'Left');
      expect(player.nationalTeam, 'Norway');
      expect(player.birthLocation, 'Leeds, England');
      expect(player.height, '195 cm');
      expect(player.description, 'Norwegian striker.');
      expect(adapter.lastOptions?.path, '/p/lookupplayer.php');
      expect(adapter.lastOptions?.queryParameters['id'], 34169116);
    });

    test('falls back to strSign when strSigning is absent', () async {
      final client = _clientWith(
        _FakeAdapter(
          body:
              '{"players":[{"idPlayer":"1","strPlayer":"Someone","strSign":"£5M"}]}',
        ),
      );

      expect((await client.lookupPlayerById(playerId: 1))!.signing, '£5M');
    });

    test('returns null when the player is unknown', () async {
      final client = _clientWith(_FakeAdapter(body: '{}'));

      expect(await client.lookupPlayerById(playerId: 1), isNull);
    });
  });

  group('FootballApiClient.getEventLineup', () {
    const body = '''
    {
      "lineup": [
        {"idPlayer":"34145506","strPlayer":"Mohamed Salah","idTeam":"133602","strTeam":"Liverpool","strPosition":"Right Winger","intSquadNumber":"11","strHome":"Yes","strSubstitute":"No","strCutout":"cutout.png","strThumb":"thumb.jpg"},
        {"idPlayer":"34145999","strPlayer":"Sub Guy","idTeam":"133602","strTeam":"Liverpool","strPosition":"Striker","intSquadNumber":"","strHome":"Yes","strSubstitute":"Yes"},
        {"idPlayer":"34146000","strPlayer":"Opponent Keeper","idTeam":"134301","strTeam":"Bournemouth","strPosition":"Goalkeeper","intSquadNumber":"1","strHome":"No","strSubstitute":"No","strThumb":"keeper.jpg"},
        {"strPlayer":"Broken row"}
      ]
    }
    ''';

    test('parses both teams and substitutes, hits lookuplineup.php', () async {
      final adapter = _FakeAdapter(body: body);
      final client = _clientWith(adapter, apiKey: 'p');

      final lineup = await client.getEventLineup(eventId: 2267073);

      expect(lineup, hasLength(3)); // malformed row skipped
      expect(lineup.first.name, 'Mohamed Salah');
      expect(lineup.first.isHome, isTrue);
      expect(lineup.first.isSubstitute, isFalse);
      expect(lineup.first.squadNumber, '11');
      expect(lineup.first.imageUrl, 'cutout.png'); // cutout preferred
      expect(lineup[1].isSubstitute, isTrue);
      expect(lineup[1].imageUrl, isEmpty);
      expect(lineup[2].isHome, isFalse);
      expect(lineup[2].imageUrl, 'keeper.jpg'); // thumb fallback
      expect(adapter.lastOptions?.path, '/p/lookuplineup.php');
      expect(adapter.lastOptions?.queryParameters['id'], 2267073);
    });

    test('returns an empty list when there is no line-up', () async {
      final client = _clientWith(_FakeAdapter(body: '{"lineup": null}'));

      expect(await client.getEventLineup(eventId: 1), isEmpty);
    });
  });
}
