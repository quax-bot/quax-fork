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

  Future<String> find(Uri pageUrl, String pageText) => _search(scriptLinks(pageUrl, pageText).toList(), {}, const []);

  Future<String> _search(List<Uri> found, Set<Uri> explored, List<Object> errors) async {
    final wave = nextWave(found.where((uri) => !explored.contains(uri)), budget - explored.length);
    if (wave.isEmpty) throw _notFound(explored.length, errors);

    final results = await Future.wait(wave.map(_tryFetch));
    final fetched = results.whereType<_Fetched>();
    final signModule = fetched.where((r) => isSignModule(r.text)).firstOrNull;
    if (signModule != null) return signModule.text;

    return _search(
      [...found, ...fetched.expand((r) => scriptLinks(r.url, r.text))],
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
/// tag, an ES module import, or the chunk map of the former webpack build.
Iterable<Uri> scriptLinks(Uri base, String text) => {
      ...scriptPathRegex.allMatches(text).map((m) => base.resolve(m.group(1)!)),
      ...legacyOndemandScripts(text),
    }.where((uri) => uri.host == scriptsHost);

Iterable<Uri> legacyOndemandScripts(String text) => legacyOndemandIndexRegex
    .allMatches(text)
    .map((m) => RegExp(',${RegExp.escape(m.group(1)!)}:["\']([0-9a-f]+)["\']').firstMatch(text)?.group(1))
    .nonNulls
    .map((hash) => Uri.parse(legacyOndemandUrlTemplate.replaceAll('{hash}', hash)));

/// The scripts to download next: those whose name hints the most at signing,
/// in the order they were found, at most [signModuleSearchWave] and [left].
List<Uri> nextWave(Iterable<Uri> candidates, int left) {
  final unique = candidates.toSet();
  final best = unique.map(relevance).fold(0, (a, b) => a > b ? a : b);
  return unique.where((uri) => relevance(uri) == best).take(left.clamp(0, signModuleSearchWave)).toList();
}

int relevance(Uri script) {
  final name = script.pathSegments.lastOrNull?.toLowerCase() ?? '';
  return signModuleNameHints.entries.where((hint) => hint.key.hasMatch(name)).fold(0, (sum, hint) => sum + hint.value);
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
