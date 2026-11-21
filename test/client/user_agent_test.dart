import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:quax/catcher/exceptions.dart';
import 'package:quax/client/client_unauthenticated.dart';
import 'package:quax/client/headers.dart';
import 'package:quax/client/x_client_transaction_id/client_transaction.dart';
import 'package:quax/constants.dart';

final _desktopChrome = RegExp(
    r'^Mozilla/5\.0 \(Windows NT 10\.0; Win64; x64\) AppleWebKit/537\.36 \(KHTML, like Gecko\) Chrome/(\d+)\.0\.0\.0 Safari/537\.36$');
final _mobileChrome = RegExp(
    r'^Mozilla/5\.0 \(Linux; Android 10; K\) AppleWebKit/537\.36 \(KHTML, like Gecko\) Chrome/(\d+)\.0\.0\.0 Mobile Safari/537\.36$');

Future<Map<String, String?>> _userAgentsSentByTheGuestClient() async {
  final userAgents = <String, String?>{};
  final x = MockClient((request) async {
    userAgents[request.url.path] = request.headers['user-agent'];
    return switch (request.url.path) {
      '/1.1/guest/activate.json' => http.Response('{"guest_token": "1"}', 200),
      '/home' => http.Response('', 503),
      _ => http.Response('{}', 200),
    };
  });
  await http.runWithClient(() async {
    await fetchUnauthenticated(Uri.https('api.x.com', '/graphql/UserByScreenName'), log: Logger('test'));
    await expectLater(ClientTransaction.initialize(), throwsA(isA<HttpException>()));
  }, () => x);
  return userAgents;
}

void main() {
  test('Should send the same desktop Chrome user agent on every request to X', () async {
    final guestUserAgents = await _userAgentsSentByTheGuestClient();
    final userAgents = {
      ...guestUserAgents,
      'logged in API': (await TwitterHeaders.getHeaders(null, null))['user-agent'],
    };

    expect(userAgents.keys, containsAll(['/1.1/guest/activate.json', '/graphql/UserByScreenName', '/home']),
        reason: 'Every request of the guest client and of the transaction id page should be checked');
    expect(userAgents.values.toSet(), hasLength(1),
        reason: 'X sees several browsers in one session when the requests disagree: $userAgents');
    expect(userAgents.values.first, matches(_desktopChrome),
        reason: 'The captures come from desktop Chrome, so the app should look like it');
  });

  test('Should log in with a mobile Chrome of the same release as the one sent to the API', () {
    final mobileVersion = _mobileChrome.firstMatch(mobileChromeUserAgent)?.group(1);
    final desktopVersion = _desktopChrome.firstMatch(desktopChromeUserAgent)?.group(1);

    expect(mobileVersion, isNotNull, reason: 'The login page should get a well-formed mobile Chrome user agent');
    expect(mobileVersion, desktopVersion, reason: 'Both user agents should be bumped together');
  });
}
