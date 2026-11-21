import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quax/catcher/exceptions.dart';
import 'package:quax/client/x_client_transaction_id/client_transaction.dart';
import 'package:quax/client/x_client_transaction_id/client_transaction_id_exception.dart';

import 'recorded_transaction.dart';

void main() {
  test('Should raise a ClientTransactionIdException when x.com serves nothing the generator can be built from', () {
    expect(
      () => ClientTransaction.fromSources(homePageHtml: '', signFileText: ''),
      throwsA(isA<ClientTransactionIdException>()),
      reason: 'Bug reports about this failure are recognised by the type of the exception',
    );
  });

  test('Should raise a ClientTransactionIdException when the page no longer has the shape the generator reads', () async {
    final sources = await ClientTransaction.fetchSources(fetch: replayRecordedFile);
    expect(
      () => ClientTransaction.fromSources(
        homePageHtml: sources.homePageHtml.replaceAll('loading-x-anim', 'gone'),
        signFileText: sources.signFileText,
      ),
      throwsA(isA<ClientTransactionIdException>()),
      reason: 'A RangeError would not carry the marker that starts the fix, although X changed the page',
    );
  });

  test('Should raise an HttpException, not a ClientTransactionIdException, when x.com answers an error page', () async {
    final unavailable = MockClient((request) async => http.Response('<html>Something went wrong</html>', 503));

    await expectLater(
      http.runWithClient(ClientTransaction.fetchSources, () => unavailable),
      throwsA(isA<HttpException>().having((error) => error.statusCode, 'statusCode', 503)),
      reason: 'A 503 says nothing about how X signs requests: it must not be reported as a transaction id bug',
    );
  });

  test('Should find the sign module by following the recorded x.com files', () async {
    await expectLater(ClientTransaction.fetchSources(fetch: replayRecordedFile), completes,
        reason: 'The chain page -> entry script -> importer -> sign module no longer leads to the sign module: '
            'read the recorded files and fix ClientTransaction._findSignFileUrl / constants.dart');
  });

  final expected = jsonDecode(File('$recordedTransactionFixtures/expected.json').readAsStringSync()) as Map<String, dynamic>;
  final now = DateTime.fromMillisecondsSinceEpoch(expected['nowMs'] as int);

  for (final testCase in (expected['cases'] as List).cast<Map<String, dynamic>>()) {
    final method = testCase['method'] as String;
    final path = testCase['path'] as String;

    test('Should sign $method $path exactly like x.com does', () async {
      final transaction = await recordedTransaction();
      expect(
        payloadOf(transaction.generateTransactionId(method, path, now: now)),
        payloadOf(testCase['transactionId'] as String),
        reason: 'X rejects a request whose transaction id differs from what its own sign module '
            'computes. If the fixtures were just recorded, X changed its algorithm',
      );
    });
  }
}
