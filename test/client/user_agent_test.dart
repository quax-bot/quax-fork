import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:quax/client/client_unauthenticated.dart';
import 'package:quax/client/headers.dart';
import 'package:quax/client/x_client_transaction_id/client_transaction.dart';
import 'package:quax/constants.dart';
import 'package:quax/utils/urls.dart';

final _desktopChromePattern = RegExp(
    r'^Mozilla/5\.0 \(Windows NT 10\.0; Win64; x64\) AppleWebKit/537\.36 \(KHTML, like Gecko\) Chrome/\d+\.0\.0\.0 Safari/537\.36$');
final _mobileChromePattern = RegExp(
    r'^Mozilla/5\.0 \(Linux; Android 10; K\) AppleWebKit/537\.36 \(KHTML, like Gecko\) Chrome/\d+\.0\.0\.0 Mobile Safari/537\.36$');

const _guestToken = '/1.1/guest/activate.json';
const _guestRequest = '/graphql/UserByScreenName';
const _transactionIdPage = '/home';
const _shortLink = '/abc';

Future<Map<String, String?>> _userAgentsSentToX() async {
  final userAgents = <String, String?>{};
  final fakeX = MockClient((request) async {
    userAgents[request.url.path] = request.headers['user-agent'];
    return switch (request.url.path) {
      _guestToken => http.Response('{"guest_token": "1"}', 200),
      // Stops the transaction id setup right after it fetched the page
      _transactionIdPage => http.Response('', 503),
      _ => http.Response('{}', 200),
    };
  });
  await http.runWithClient(() async {
    await fetchUnauthenticated(Uri.https('api.x.com', _guestRequest), log: Logger('test'));
    await ClientTransaction.initialize().then((_) {}, onError: (_) {});
    await parseUri(Uri.https('t.co', _shortLink));
  }, () => fakeX);
  return userAgents;
}

void main() {
  test('Should send the desktop Chrome user agent on every request to X', () async {
    final userAgents = {
      ...await _userAgentsSentToX(),
      'logged in API headers': (await TwitterHeaders.getHeaders(null, null))['user-agent'],
    };

    expect(userAgents.keys, containsAll([_guestToken, _guestRequest, _transactionIdPage, _shortLink]),
        reason: 'Every kind of request to X should have been sent');
    expect(userAgents.values, everyElement(desktopChromeUserAgent),
        reason: 'X sees several browsers in one session when the requests disagree');
  });

  test('Should give well-formed Chrome user agents to X and to the login page', () {
    expect(desktopChromeUserAgent, matches(_desktopChromePattern),
        reason: 'The API should get the user agent a desktop Chrome really sends');
    expect(mobileChromeUserAgent, matches(_mobileChromePattern),
        reason: 'The login page should get the user agent a mobile Chrome really sends');
  });
}
