import 'package:flutter_test/flutter_test.dart';
import 'package:pref/pref.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/saved/saved_tweet_order.dart';

void main() {
  SavedTweet post(String id) => SavedTweet(id: id, user: 'dogs', content: '{}');

  // As the database lists them: the newest saved first, an old post saved last
  final newestSavedFirst = [post('1900000000000000000'), post('2095919166830084474'), post('2026390853309063292')];

  group('SavedTweetOrder.apply()', () {
    test('Should keep the newest saved post first by default', () {
      const order = SavedTweetOrder(sort: SavedTweetSort.savedAt, ascending: false);

      expect(order.apply(newestSavedFirst).map((t) => t.id), newestSavedFirst.map((t) => t.id),
          reason: 'Sorting by the date saved, newest first, is the order the saved posts always had');
    });

    test('Should put the newest post first when sorted by the date posted', () {
      const order = SavedTweetOrder(sort: SavedTweetSort.postedAt, ascending: false);

      expect(order.apply(newestSavedFirst).map((t) => t.id),
          ['2095919166830084474', '2026390853309063292', '1900000000000000000'],
          reason: 'A post id grows with the time it was posted, so the highest id should come first, whenever it was '
              'saved');
    });

    test('Should reverse the order when ascending', () {
      const order = SavedTweetOrder(sort: SavedTweetSort.postedAt, ascending: true);

      expect(order.apply(newestSavedFirst).map((t) => t.id),
          ['1900000000000000000', '2026390853309063292', '2095919166830084474'],
          reason: 'The arrow should show the oldest post first');
    });
  });

  group('SavedTweetOrderStore', () {
    test('Should keep the order in the preferences', () async {
      final prefs = PrefServiceCache(defaults: {optionSavedOrderByField: 'saved_at', optionSavedOrderByAscending: false});
      final store = SavedTweetOrderStore(prefs);

      await store.showNextSort();
      await store.reverseOrder();
      final reopened = SavedTweetOrderStore(prefs);

      expect(reopened.state.sort, SavedTweetSort.postedAt,
          reason: 'The sort chosen should still be the one shown after the app restarts');
      expect(reopened.state.ascending, isTrue,
          reason: 'The direction chosen should still be the one shown after the app restarts');
    });
  });
}
