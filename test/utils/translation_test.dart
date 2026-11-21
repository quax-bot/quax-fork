import 'dart:convert';

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quax/database/repository.dart';
import 'package:quax/utils/translation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../client/x_client_transaction_id/recorded_transaction.dart';

void main() {
  http.Response response(Object body, int status) =>
      http.Response(body is String ? body : jsonEncode(body), status);

  group('TranslationAPI.parseResponse()', () {
    test('Should accept a 200 that contains a translation', () async {
      final result = await TranslationAPI.parseResponse(
          response({'translation': 'bonjour'}, 200), 'Unable to translate');

      expect(result.success, isTrue,
          reason: 'A 200 with no error field is the normal case, so it should be accepted');

      expect(result.body, isA<Map>(),
          reason: 'The body should stay a JSON object, since the caller indexes fields on it');
      expect((result.body as Map)['translation'], 'bonjour',
          reason: 'The body should be passed on as it is, because the caller reads the translated '
              'text and the entities out of it');
    });

    test('Should reject a 200 that contains an error object', () async {
      final result = await TranslationAPI.parseResponse(
          response({
            'error': {'message': 'Grok is busy'}
          }, 200),
          'Unable to translate');

      expect(result.success, isFalse,
          reason: 'This endpoint reports failures inside a 200 answer, so the body should be read '
              'as well and this should not count as a success');
      expect(result.errorMessage, 'Grok is busy',
          reason: 'The message is shown to the user, so it should come from the API rather than '
              'be made up here');
    });

    test('Should add the Language prefix to the unsupported language error of a 400', () async {
      final result = await TranslationAPI.parseResponse(
          response({'error': 'fr is not supported'}, 400), 'Unable to translate');

      expect(result.success, isFalse,
          reason: 'A language that is not supported is a real failure, so it should not come back '
              'as a success with an empty translation');
      expect(result.errorMessage, 'Language fr is not supported',
          reason: 'The API only sends the language code, so the word Language should be added to '
              'make a sentence the user can read');
    });

    test('Should keep a 400 message that is not about an unsupported language', () async {
      final result = await TranslationAPI.parseResponse(
          response({'error': 'malformed request'}, 400), 'Unable to translate');

      expect(result.errorMessage, 'malformed request',
          reason: 'Only the "<language> is not supported" message should get the Language prefix. '
              'Adding it to anything else gives text like "Language malformed request"');
    });

    test('Should use a different message for a ban and for too many requests', () async {
      final banned =
          await TranslationAPI.parseResponse(response({'error': 'nope'}, 403), 'Unable');
      final tooMany =
          await TranslationAPI.parseResponse(response({'error': 'nope'}, 429), 'Unable');

      expect(banned.errorMessage, isNot(tooMany.errorMessage),
          reason: 'A ban lasts while too many requests goes away on its own, so the two should '
              'read differently. Showing the wrong one sends the user in the wrong direction');
      expect(banned.success, isFalse,
          reason: 'A 403 means the request did not work, so it should not come back as a success');
      expect(tooMany.success, isFalse,
          reason: 'A 429 also means no translation, so it should not come back as a success even '
              'though the user can try again later');
    });

    test('Should throw a FormatException when the answer is not JSON', () async {
      expect(() => TranslationAPI.parseResponse(response('<html>502</html>', 200), 'Unable'),
          throwsFormatException,
          reason: 'TranslationAPI.translate catches FormatException to try again while Grok is '
              'still writing the translation, so a body that is not JSON should reach it as an '
              'exception rather than as a result');
    });
  });
  group('TranslationAPI.translate()', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await databaseFactory.deleteDatabase(databaseName);
      await Repository().migrate();
    });

    test('Should send a transaction id signed for POST, the method of the translation request', () async {
      http.BaseRequest? translationRequest;
      final x = MockClient((request) async {
        if (request.url.host != 'api.x.com') {
          return http.Response.bytes(utf8.encode(await replayRecordedFile(request.url)), 200,
              headers: {'content-type': 'text/plain; charset=utf-8'});
        }
        translationRequest = request;
        return response({'translation': 'bonjour'}, 200);
      });

      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await http.runWithClient(
          () => TranslationAPI.translate(const Locale('fr'), '1', ['hello'], 'en'), () => x);
      final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      expect(translationRequest?.method, 'POST',
          reason: 'The translation endpoint only answers a POST, so the request should be sent as one');
      final transactionId = translationRequest!.headers['x-client-transaction-id'];
      expect(transactionId, isNotNull, reason: 'X rejects a request to api.x.com that has no transaction id');

      final transaction = await recordedTransaction();
      final path = translationRequest!.url.path;
      List<List<int>> signedFor(String method) => [
            for (var second = before; second <= after; second++)
              payloadOf(transaction.generateTransactionId(method, path,
                  now: DateTime.fromMillisecondsSinceEpoch(second * 1000)))
          ];
      expect(signedFor('POST'), anyElement(equals(payloadOf(transactionId!))),
          reason: 'X signs each request with its real method, so it rejects a POST whose id was computed '
              'for another one');
      expect(signedFor('GET'), isNot(anyElement(equals(payloadOf(transactionId)))),
          reason: 'The id should no longer be the one computed for GET, which every request used to get');
    });
  });
}
