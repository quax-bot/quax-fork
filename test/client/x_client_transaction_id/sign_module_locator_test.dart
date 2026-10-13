import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quax/client/x_client_transaction_id/client_transaction_id_exception.dart';
import 'package:quax/client/x_client_transaction_id/sign_module_locator.dart';

const _signModule = 'export default function(){return [(e[4], 16), (e[12], 16)]}';
final _page = Uri.https('x.com', '/home');

/// Serves [files] by URL, and records what was asked for.
class _FakeX {
  final Map<String, String> files;
  final List<Uri> requested = [];

  _FakeX(this.files);

  Future<String> fetch(Uri uri) async {
    requested.add(uri);
    final text = files['$uri'];
    if (text == null) throw HttpException('404', uri: uri);
    return text;
  }
}

String _scriptTag(String url) => '<script type="module" src="$url"></script>';

void main() {
  test('Should find the sign module of the September 2026 build, behind the sentry-filter importer', () async {
    final x = _FakeX({
      'https://abs.twimg.com/x-web/x-web/entry-client-A1.js': 'import("./assets/sentry-filter-B2.js")',
      'https://abs.twimg.com/x-web/x-web/assets/sentry-filter-B2.js': 'import(`./sign.o-C3.js`)',
      'https://abs.twimg.com/x-web/x-web/assets/sign.o-C3.js': _signModule,
    });
    final page = _scriptTag('https://abs.twimg.com/x-web/x-web/entry-client-A1.js');

    expect(await SignModuleLocator(x.fetch).find(_page, page), _signModule,
        reason: 'The importer was named sentry-filter until October 2026');
  });

  test('Should find the sign module of the former webpack build, from the ondemand.s chunk map', () async {
    final x = _FakeX({'https://abs.twimg.com/responsive-web/client-web/ondemand.s.3f2e1da.js': _signModule});
    const page = '<script>var chunks={,20113:"ondemand.s",};var hashes={,20113:"3f2e1d",}</script>';

    expect(await SignModuleLocator(x.fetch).find(_page, page), _signModule,
        reason: 'X served the sign module as an ondemand.s chunk until September 2026');
  });

  test('Should find the sign module whatever X renames the files leading to it', () async {
    final x = _FakeX({
      'https://abs.twimg.com/app/boot-Z9.js': 'import "./a-1.js"; import "./b-2.js"; import "./c-3.js";',
      'https://abs.twimg.com/app/a-1.js': 'export const a = 1',
      'https://abs.twimg.com/app/b-2.js': 'export const b = 2',
      'https://abs.twimg.com/app/c-3.js': 'import("../lazy/k-4.js")',
      'https://abs.twimg.com/lazy/k-4.js': _signModule,
    });
    final page = _scriptTag('https://abs.twimg.com/app/boot-Z9.js');

    expect(await SignModuleLocator(x.fetch).find(_page, page), _signModule,
        reason: 'The sign module is recognised by its content, so no name should matter');
  });

  test('Should download the scripts whose name hints at signing first', () async {
    final x = _FakeX({
      'https://abs.twimg.com/x/entry-client-A1.js':
          'import "./consent-signal-util-B.js"; import "./icon-D.js"; import "./client-transaction-id-plugin-E.js"',
      'https://abs.twimg.com/x/client-transaction-id-plugin-E.js': 'import(`./sign.o-F.js`)',
      'https://abs.twimg.com/x/sign.o-F.js': _signModule,
    });
    await SignModuleLocator(x.fetch).find(_page, _scriptTag('https://abs.twimg.com/x/entry-client-A1.js'));

    expect(x.requested.map((uri) => uri.pathSegments.last), [
      'entry-client-A1.js',
      'client-transaction-id-plugin-E.js',
      'sign.o-F.js',
    ], reason: 'Each script costs a download when the app starts, the usual path should cost no more');
  });

  test('Should stop after its budget of downloads', () async {
    final scripts = {for (var i = 0; i < 100; i++) 'https://abs.twimg.com/x/s$i.js': 'import "./s${i + 1}.js"'};
    final x = _FakeX(scripts);

    await expectLater(SignModuleLocator(x.fetch, budget: 10).find(_page, _scriptTag('https://abs.twimg.com/x/s0.js')),
        throwsA(isA<ClientTransactionIdException>()),
        reason: 'There is no sign module to find');
    expect(x.requested, hasLength(10), reason: 'X must not be flooded with downloads when it changed too much');
  });

  test('Should raise the download error, not a ClientTransactionIdException, when scripts could not be downloaded',
      () async {
    final x = _FakeX({});

    await expectLater(SignModuleLocator(x.fetch).find(_page, _scriptTag('https://abs.twimg.com/x/entry-A1.js')),
        throwsA(isA<HttpException>()),
        reason: 'Being offline must not open a bug report saying that X changed its sign module');
  });

  test('Should raise a ClientTransactionIdException when no script holds the sign module', () async {
    final x = _FakeX({'https://abs.twimg.com/x/entry-A1.js': 'export const nothing = 0'});

    await expectLater(SignModuleLocator(x.fetch).find(_page, _scriptTag('https://abs.twimg.com/x/entry-A1.js')),
        throwsA(isA<ClientTransactionIdException>()),
        reason: 'Bug reports about this failure are recognised by the type of the exception');
  });

  test('Should only download scripts from abs.twimg.com', () async {
    final x = _FakeX({'https://abs.twimg.com/x/entry-A1.js': _signModule});
    const page = '<script src="https://evil.example/sign.js"></script><script src="/sign.js"></script>'
        '<script src="https://abs.twimg.com/x/entry-A1.js"></script>';
    await SignModuleLocator(x.fetch).find(_page, page);

    expect(x.requested.map((uri) => uri.host).toSet(), {'abs.twimg.com'},
        reason: 'The page could point anywhere, but X only serves its scripts from abs.twimg.com');
  });
}
