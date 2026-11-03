// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:puppeteer/puppeteer.dart';
import 'chrome.dart';

/// Written by this script, not by capture.dart, which must leave it alone.
final transactionIdFixtures = Directory('test/fixtures/XClientTransactionId');

const _requests = [
  ('GET', '/i/api/graphql/lSMmQoIyV1rw8qoyU9pQ5g/SearchTimeline'),
  ('POST', '/i/api/graphql/6fDZvDa5qNz7RBq-iK4cXQ/FavoriteTweet'),
];

const _origin = 'https://quax.test';


const _signInPage = '''
async (html, nowMs, requests) => {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  parsed.querySelectorAll('script').forEach((script) => script.remove());
  document.replaceChild(document.adoptNode(parsed.documentElement), document.documentElement);
  Date.now = () => nowMs;
  const module = await import('/sign.js');
  const sign = await module.default();
  const ids = [];
  for (const [method, path] of requests) ids.push(await sign(path, method));
  return ids;
}
''';

/// Every script of the website: X names most of them by a bare hash, so the
/// files the page needs to sign requests are told apart by their content.
final _recordedScripts = RegExp(r'^https://abs\.twimg\.com/.*\.js$');

final _entryScript = RegExp(r'/entry-client[\w-]*\.js$');

/// The sign module is imported lazily, then its default export builds the signer.
final _signModuleImport = RegExp(r'import\(`([./\w-]+\.js)`\)\.then\(\w+=>\w+\.default\(\)\)');

const _port = 9334;
const _loadTimeout = Duration(seconds: 20);
const _homePage = 'https://x.com/home';

Future<void> main() async {
  transactionIdFixtures.createSync(recursive: true);
  print('Loading x.com in Chrome and recording the files it downloads…');
  final sources = await _recordInChrome();
  sources.writeTo(transactionIdFixtures);
  print('Recorded ${sources.files.length} file(s): ${sources.files.keys.join(', ')}');

  final signUrl = sources.signModuleUrl;
  if (signUrl == null) {
    print('\nChrome downloaded no sign module. Read the recorded files in ${transactionIdFixtures.path}/ to see how');
    print('X loads it now, then adapt _signModuleImport.');
    return;
  }
  await _recordSignedIds(sources.files[_homePage]!, sources.files[signUrl]!);
}

/// A real, logged-out Chrome: the app gets the same page, and X refuses a
/// browser started by puppeteer's launcher.
Future<_Sources> _recordInChrome() async {
  final profile = Directory.systemTemp.createTempSync('quax-transaction-id');
  final chrome = await startChrome(profile: profile, port: _port);
  final browser = await connectChrome(_port);
  try {
    final page = (await browser.pages).first;
    final bodies = <String, Future<String>>{};
    page.onResponse.listen((response) {
      final isPage = response.request.resourceType == ResourceType.document && response.status == 200;
      if (isPage && response.url.startsWith('https://x.com/')) bodies[_homePage] = response.text;
      if (_recordedScripts.hasMatch(response.url)) bodies[response.url] = response.text;
    });
    // Never Until.networkIdle: x.com keeps polling, so "idle" may never come.
    try {
      await page.goto(_homePage, wait: Until.domContentLoaded, timeout: _loadTimeout);
    } on Exception catch (error) {
      print('Page did not finish loading ($error), keeping what arrived.');
    }
    return await _waitForSignModule(bodies);
  } finally {
    browser.disconnect();
    chrome.kill();
    await chrome.exitCode;
    _deleteProfile(profile);
  }
}

/// Chrome's helper processes may still write to the profile a moment after
/// Chrome itself exited, which makes a single deletion fail.
void _deleteProfile(Directory profile) {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      return profile.deleteSync(recursive: true);
    } on FileSystemException {
      sleep(const Duration(milliseconds: 500));
    }
  }
}

/// The sign module is imported lazily, a moment after the page itself.
Future<_Sources> _waitForSignModule(Map<String, Future<String>> bodies) async {
  final deadline = DateTime.now().add(_loadTimeout);
  while (true) {
    final sources = _Sources.signChain(await _settled(bodies));
    if (sources.signModuleUrl != null || DateTime.now().isAfter(deadline)) return sources;
    await Future.delayed(const Duration(milliseconds: 250));
  }
}

Future<Map<String, String>> _settled(Map<String, Future<String>> bodies) async => {
      for (final entry in Map.of(bodies).entries)
        entry.key: await entry.value.timeout(_loadTimeout, onTimeout: () => '').catchError((_) => ''),
    };

class _Sources {
  const _Sources(this.files, {this.signModuleUrl});

  /// Keeps the page, the entry script and, once Chrome downloaded it, the sign
  /// module with the script importing it. Without the sign module, the page and
  /// the entry script still show how X loads it now.
  factory _Sources.signChain(Map<String, String> downloaded) {
    final page = {for (final url in downloaded.keys.where((url) => url == _homePage || _entryScript.hasMatch(url))) url: downloaded[url]!};
    final signChain = downloaded.entries
        .map((script) => (importer: script.key, match: _signModuleImport.firstMatch(script.value)))
        .where((candidate) => candidate.match != null)
        .map((candidate) => (importer: candidate.importer, sign: Uri.parse(candidate.importer).resolve(candidate.match!.group(1)!).toString()))
        .firstWhereOrNull((chain) => downloaded.containsKey(chain.sign));
    if (signChain == null) return _Sources(page);
    return _Sources({
      ...page,
      signChain.importer: downloaded[signChain.importer]!,
      signChain.sign: downloaded[signChain.sign]!,
    }, signModuleUrl: signChain.sign);
  }

  /// URL -> content. The x.com page is stored under the URL the app asks for.
  final Map<String, String> files;

  final String? signModuleUrl;

  void writeTo(Directory directory) {
    // Scripts of an earlier recording X no longer serves.
    directory.listSync().whereType<File>().where((file) => file.path.endsWith('.js')).forEach((file) => file.deleteSync());
    final names = {for (final url in files.keys) url: url == _homePage ? 'home.html' : Uri.parse(url).pathSegments.last};
    names.forEach((url, name) => File('${directory.path}/$name').writeAsStringSync(files[url]!));
    File('${directory.path}/sources.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(names));
  }
}

Future<void> _recordSignedIds(String homePageHtml, String signFileText) async {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  print('Signing ${_requests.length} requests in Chrome…');
  final ids = await _signInChrome(homePageHtml, signFileText, nowMs);
  File('${transactionIdFixtures.path}/expected.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'nowMs': nowMs,
    'cases': [
      for (final ((method, path), id) in _requests.indexed.map((e) => (e.$2, ids[e.$1])))
        {'method': method, 'path': path, 'transactionId': id},
    ],
  }));
  print('Written to ${transactionIdFixtures.path}. Now run:\n  fvm flutter test test/client/x_client_transaction_id/');
}

Future<List<String>> _signInChrome(String html, String signModule, int nowMs) async {
  final browser = await puppeteer.launch(executablePath: installedChrome());
  try {
    final page = await browser.newPage();
    await page.setRequestInterception(true);
    page.onRequest.listen((request) => request.url == '$_origin/sign.js'
        ? request.respond(contentType: 'text/javascript', body: signModule)
        : request.respond(contentType: 'text/html', body: ''));
    await page.goto('$_origin/');
    final ids = await page.evaluate<List<dynamic>>(_signInPage, args: [
      html,
      nowMs,
      [for (final (method, path) in _requests) [method, path]],
    ]);
    return ids.cast<String>();
  } finally {
    await browser.close();
  }
}
