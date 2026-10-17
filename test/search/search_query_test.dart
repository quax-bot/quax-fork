import 'package:flutter_test/flutter_test.dart';
import 'package:quax/search/search_filters.dart';
import 'package:quax/search/search_query.dart';

const _appLanguage = 'fr';

SearchFilters _parsedFilters(String raw) => SearchQuery.parse(raw, _appLanguage).filters;

void main() {
  group('compose', () {
    test('Should send the bar text alone when no filter is set', () {
      expect(const SearchQuery('élections').compose(_appLanguage), 'élections',
          reason: 'A plain search must reach X unchanged');
    });

    test('Should write every filter in the order of X advanced search', () {
      final filters = SearchFilters(
        exactPhrase: 'hot reload',
        anyWords: const ['flutter', 'dart'],
        noneWords: const ['kotlin', 'java'],
        hashtags: const ['Flutter', 'Dart'],
        fromAccounts: const ['FlutterDev', 'dart_lang'],
        toAccounts: const ['quax_tests'],
        mentions: const ['quax_tests_2'],
        language: LanguageChoice.other,
        otherLanguage: 'en',
        replies: ContentFilter.exclude,
        links: ContentFilter.only,
        media: MediaFilter.images,
        reposts: true,
        minReplies: 5,
        minFaves: 50,
        minRetweets: 10,
        since: DateTime(2025, 1, 1),
        until: DateTime(2025, 7, 1),
      );

      expect(
        SearchQuery('news', filters).compose(_appLanguage),
        'news "hot reload" (flutter OR dart) -kotlin -java (#Flutter OR #Dart) (from:FlutterDev OR from:dart_lang) '
        'to:quax_tests @quax_tests_2 lang:en -filter:replies filter:links filter:images include:nativeretweets '
        'min_replies:5 min_faves:50 min_retweets:10 since:2025-01-01 until:2025-07-01',
        reason: 'Each filter should become the operator X documents for it',
      );
    });

    test('Should filter on the app language when the user picks their language', () {
      const filters = SearchFilters(language: LanguageChoice.mine, otherLanguage: 'de');
      expect(const SearchQuery('flutter', filters).compose('pt'), 'flutter lang:pt',
          reason: 'My language should follow the language of the app, not the one picked in the list');
    });

    test('Should not filter on a language when every language is allowed', () {
      const filters = SearchFilters(otherLanguage: 'de');
      expect(const SearchQuery('flutter', filters).compose(_appLanguage), 'flutter',
          reason: 'The language list only matters once Other is picked');
    });
  });

  group('parse', () {
    test('Should move the operators out of the bar and keep the words', () {
      final query = SearchQuery.parse('élections from:journal_ex lang:de -filter:replies', _appLanguage);

      expect(query.text, 'élections', reason: 'Only the words should stay in the bar');
      expect(query.filters.fromAccounts, ['journal_ex'], reason: 'from: should fill the accounts');
      expect(query.filters.language, LanguageChoice.other, reason: 'A language other than the app one is Other');
      expect(query.filters.otherLanguage, 'de', reason: 'The language code should be kept');
      expect(query.filters.replies, ContentFilter.exclude, reason: '-filter:replies should hide the replies');
    });

    test('Should read the app language as my language', () {
      expect(_parsedFilters('lang:fr').language, LanguageChoice.mine,
          reason: 'A saved search in the app language should stay on My language');
    });

    test('Should read the groups of accounts, hashtags and words', () {
      final filters = _parsedFilters('(from:a OR from:b) (to:c OR to:d) (@e OR @f) (#g OR #h) (i OR j)');

      expect(filters.fromAccounts, ['a', 'b'], reason: 'A group of from: should fill the accounts');
      expect(filters.toAccounts, ['c', 'd'], reason: 'A group of to: should fill the replied accounts');
      expect(filters.mentions, ['e', 'f'], reason: 'A group of mentions should fill the mentions');
      expect(filters.hashtags, ['g', 'h'], reason: 'A group of hashtags should fill the hashtags');
      expect(filters.anyWords, ['i', 'j'], reason: 'A group of words should fill Any of these words');
    });

    test('Should read the counts and the dates', () {
      final filters = _parsedFilters('min_replies:5 min_faves:50 min_retweets:10 since:2025-01-01 until:2025-07-01');

      expect(filters.minReplies, 5, reason: 'min_replies: should be read');
      expect(filters.minFaves, 50, reason: 'min_faves: should be read');
      expect(filters.minRetweets, 10, reason: 'min_retweets: should be read');
      expect(filters.since, DateTime(2025, 1, 1), reason: 'since: should be read');
      expect(filters.until, DateTime(2025, 7, 1), reason: 'until: should be read');
    });

    test('Should leave in the bar what the filters page cannot show', () {
      const raw = 'flutter #dart @FlutterDev near:Paris -from:spam (a OR from:b) min_faves:many since:2025-13-01 lang:FR';
      final query = SearchQuery.parse(raw, _appLanguage);

      expect(query.text, raw, reason: 'An unknown or malformed operator must reach X as the user typed it');
      expect(query.filters.active, isEmpty, reason: 'Nothing should be moved to the filters');
    });

    test('Should keep a second exact phrase in the bar', () {
      final query = SearchQuery.parse('"first one" "second one"', _appLanguage);

      expect(query.filters.exactPhrase, 'first one', reason: 'The filters page holds one exact phrase');
      expect(query.text, '"second one"', reason: 'The other phrase should still be searched');
    });

    test('Should give back the query it read', () {
      const queries = [
        'from:FlutterDev filter:images',
        'from:FlutterDev -filter:links',
        'flutter lang:fr',
        'from:FlutterDev since:2025-01-01 until:2025-07-01',
        'from:FlutterDev min_replies:5 min_faves:50 min_retweets:10',
        '"hot reload" (flutter OR dart) -kotlin',
        '(#Flutter OR #Dart) from:FlutterDev',
        'dart (from:FlutterDev OR from:dart_lang) lang:en -filter:replies filter:links since:2025-01-01',
      ];
      for (final raw in queries) {
        expect(SearchQuery.parse(raw, _appLanguage).compose(_appLanguage), raw,
            reason: 'Opening a saved search must not change what is sent to X');
      }
    });
  });

  group('filters', () {
    test('Should add the typed filters to the ones already set', () {
      const current = SearchFilters(fromAccounts: ['a'], replies: ContentFilter.exclude, minFaves: 10);
      final merged = current.merge(_parsedFilters('from:b min_faves:20'));

      expect(merged.fromAccounts, ['a', 'b'], reason: 'A typed account should join the accounts already set');
      expect(merged.replies, ContentFilter.exclude, reason: 'A filter not typed should be kept');
      expect(merged.minFaves, 20, reason: 'A typed value should replace the one set');
    });

    test('Should remove only the chip that was closed', () {
      const filters = SearchFilters(fromAccounts: ['a', 'b'], minFaves: 10);
      final removed = filters.without(const FromFilter('a'));

      expect(removed.fromAccounts, ['b'], reason: 'The other account should stay');
      expect(removed.minFaves, 10, reason: 'The other filters should stay');
      expect(removed.without(const MinFavesFilter(10)).minFaves, isNull, reason: 'A count should be removable');
    });

    test('Should list one chip per account and per value', () {
      const filters = SearchFilters(fromAccounts: ['a', 'b'], language: LanguageChoice.mine, since: null);
      expect(filters.active.length, 3, reason: 'Two accounts and the language make three chips');
    });
  });
}
