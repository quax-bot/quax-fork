import 'dart:math';

import 'client_transaction_id_exception.dart';
import 'constants.dart';

typedef TextFetcher = Future<String> Function(Uri uri);

/// Finds the sign module from the x.com page by what it contains, never by
/// the names of the files that lead to it: X renames them every few weeks.
///
/// Scripts are explored best-first, the ones whose name hints at signing
/// first, so the usual path costs a handful of downloads and a renamed one a
/// few more, up to [budget].
class SignModuleLocator {
  final TextFetcher fetch;
  final int budget;

  const SignModuleLocator(this.fetch, {this.budget = signModuleSearchBudget});

  Future<String> find(Uri pageUrl, String pageText) => _search(scriptLinks(pageUrl, pageText), {}, const []);

  Future<String> _search(Map<Uri, int> found, Set<Uri> explored, List<Object> errors) async {
    final wave = nextWave(Map.fromEntries(found.entries.where((e) => !explored.contains(e.key))), budget - explored.length);
    if (wave.isEmpty) throw _notFound(explored.length, errors);

    final results = await Future.wait(wave.map(_tryFetch));
    final fetched = results.whereType<_Fetched>();
    final signModule = fetched.where((r) => isSignModule(r.text)).firstOrNull;
    if (signModule != null) return signModule.text;

    return _search(
      fetched.map((r) => scriptLinks(r.url, r.text)).fold(found, mergeScores),
      {...explored, ...wave},
      [...errors, ...results.whereType<_Failed>().map((r) => r.error)],
    );
  }

  Future<_Result> _tryFetch(Uri url) async {
    try {
      return _Fetched(url, await fetch(url));
    } catch (error) {
      return _Failed(error);
    }
  }

  /// A failed download most likely means the network is down, which must not
  /// be reported as X having changed.
  static Object _notFound(int explored, List<Object> errors) =>
      errors.firstOrNull ??
      ClientTransactionIdException("Couldn't find the sign module among the $explored scripts of x.com");
}

bool isSignModule(String text) => indicesRegex.hasMatch(text);

/// Every script [text] refers to, whatever the way X loads it: a `<script>`
/// tag, an ES module import, or the chunk map of the former webpack build,
/// with how likely it is to lead to the sign module.
Map<Uri, int> scriptLinks(Uri base, String text) {
  final links = [
    ...scriptPathRegex.allMatches(text).map((m) => (uri: base.resolve(m.group(2)!), loaded: m.group(1) != null)),
    ...legacyOndemandScripts(text).map((uri) => (uri: uri, loaded: true)),
  ].where((link) => link.uri.host == scriptsHost);
  return [...links.where((link) => link.loaded), ...links.where((link) => !link.loaded)]
      .map((link) => {link.uri: relevance(link.uri, loaded: link.loaded)})
      .fold({}, mergeScores);
}

Iterable<Uri> legacyOndemandScripts(String text) => legacyOndemandIndexRegex
    .allMatches(text)
    .map((m) => RegExp(',${RegExp.escape(m.group(1)!)}:["\']([0-9a-f]+)["\']').firstMatch(text)?.group(1))
    .nonNulls
    .map((hash) => Uri.parse(legacyOndemandUrlTemplate.replaceAll('{hash}', hash)));

/// Keeps the best score of a script found several times.
Map<Uri, int> mergeScores(Map<Uri, int> a, Map<Uri, int> b) => {
      ...a,
      for (final MapEntry(:key, :value) in b.entries) key: max(value, a[key] ?? value),
    };

/// The scripts to download next: the most likely to lead to the sign module,
/// closest to the page and in the order they are loaded, at most [signModuleSearchWave] and [left].
List<Uri> nextWave(Map<Uri, int> candidates, int left) {
  final best = candidates.values.fold(0, max);
  return candidates.entries
      .where((e) => e.value == best)
      .map((e) => e.key)
      .take(left.clamp(0, signModuleSearchWave))
      .toList();
}

/// The hints in its name first, then whether the page actually loads it: x.com
/// also mentions, to preload them, many scripts it only loads on other pages.
int relevance(Uri script, {required bool loaded}) {
  final name = script.pathSegments.lastOrNull?.toLowerCase() ?? '';
  final hints = signModuleNameHints.entries.where((hint) => hint.key.hasMatch(name)).fold(0, (sum, hint) => sum + hint.value);
  return hints * 2 + (loaded ? 1 : 0);
}

sealed class _Result {}

class _Fetched extends _Result {
  final Uri url;
  final String text;

  _Fetched(this.url, this.text);
}

class _Failed extends _Result {
  final Object error;

  _Failed(this.error);
}
