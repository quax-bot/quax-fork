import 'dart:convert';
import 'dart:io';

import 'package:quax/client/x_client_transaction_id/client_transaction.dart';

const recordedTransactionFixtures = 'test/fixtures/XClientTransactionId';

/// A transaction id is a random byte followed by the payload XORed with it, so
/// two ids for the same request only compare equal once that byte is removed.
List<int> payloadOf(String transactionId) {
  final bytes = base64.decode(base64.normalize(transactionId));
  return bytes.skip(1).map((byte) => byte ^ bytes.first).toList();
}

/// Replays the files recorded by tool/record/transaction_id.dart.
Future<String> replayRecordedFile(Uri uri) async {
  final index =
      jsonDecode(File('$recordedTransactionFixtures/sources.json').readAsStringSync()) as Map<String, dynamic>;
  final name = index['$uri'] as String?;
  if (name == null) {
    throw StateError('The app asked for $uri, which Chrome never downloaded on x.com, so the app no longer '
        'follows the path Chrome takes. Files Chrome downloaded: ${index.keys.join(', ')}. '
        'Fix ClientTransaction._findSignFileUrl / constants.dart to follow them');
  }
  return File('$recordedTransactionFixtures/$name').readAsStringSync();
}

Future<ClientTransaction> recordedTransaction() async {
  final sources = await ClientTransaction.fetchSources(fetch: replayRecordedFile);
  return ClientTransaction.fromSources(homePageHtml: sources.homePageHtml, signFileText: sources.signFileText);
}
