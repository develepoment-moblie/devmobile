import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_paris/maintenance/services/translation_service.dart';

// MyMemory as it answers: UTF-8 bytes without a charset in the header.
http.Response answer(Map<String, Object?> json, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(json)),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, Object?> ok(String text, [String? detected]) => {
  'responseData': {'translatedText': text, 'detectedLanguage': ?detected},
  'responseStatus': 200,
  'responseDetails': '',
  'quotaFinished': false,
};

void main() {
  final calls = <Uri>[];
  late Future<http.Response> Function(http.Request) reply;
  setUp(() {
    calls.clear();
    TranslationService.client = () => MockClient((request) {
      calls.add(request.url);
      return reply(request);
    });
  });
  tearDown(() => TranslationService.client = http.Client.new);

  test('a report in English is translated into French', () async {
    reply = (_) async =>
        answer(ok('L’évacuation de la douche est bouchée.', 'en'));
    final t = await TranslationService.translate('The shower drain is blocked');
    expect(t.text, 'L’évacuation de la douche est bouchée.');
    expect(t.label, 'anglais → français');
    expect(calls.single.queryParameters['langpair'], 'autodetect|fr');
  });

  test('Arabic too, accents and letters decoded as UTF-8', () async {
    reply = (_) async => answer(ok('L’eau ne s’écoule pas.', 'ar-SA'));
    final t = await TranslationService.translate('الماء لا يخرج');
    expect(t.text, 'L’eau ne s’écoule pas.');
    expect(t.from, 'ar');
  });

  test('a French text is translated into English', () async {
    reply = (request) async =>
        request.url.queryParameters['langpair'] == 'autodetect|fr'
        ? answer({
            'responseData': {
              'translatedText': 'PLEASE SELECT TWO DISTINCT LANGUAGES',
            },
            'responseStatus': 403,
            'responseDetails': 'PLEASE SELECT TWO DISTINCT LANGUAGES',
          })
        : answer(ok('The TV no longer works.'));
    final t = await TranslationService.translate(
      'La télévision ne marche plus.',
    );
    expect(t.text, 'The TV no longer works.');
    expect(t.label, 'français → anglais');
    expect(
      [for (final c in calls) c.queryParameters['langpair']],
      ['autodetect|fr', 'fr|en'],
    );
  });

  test('a long text is sent in pieces of 450 bytes at most', () async {
    reply = (request) async => answer(ok('x', 'ar'));
    await TranslationService.translate(List.filled(120, 'الماء').join(' '));
    expect(calls.length, greaterThan(1));
    for (final c in calls) {
      expect(
        utf8.encode(c.queryParameters['q']!).length,
        lessThanOrEqualTo(450),
      );
    }
  });

  test('each failure says why', () async {
    Future<String> failure() async {
      try {
        await TranslationService.translate('Hello');
      } on TranslationException catch (e) {
        return e.message;
      }
      fail('no exception');
    }

    reply = (_) async => throw const SocketException('down');
    expect(await failure(), contains('Pas de connexion Internet'));
    reply = (_) async => answer({...ok(''), 'quotaFinished': true});
    expect(await failure(), contains('Quota'));
    reply = (_) async => answer({
      'responseData': null,
      'responseStatus': 403,
      'responseDetails': 'INVALID LANGUAGE PAIR',
    });
    expect(await failure(), 'Traduction refusée : INVALID LANGUAGE PAIR');
    reply = (_) async => http.Response('<html>', 502);
    expect(await failure(), contains('illisible'));
  });
}
