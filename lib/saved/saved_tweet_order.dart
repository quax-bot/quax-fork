import 'package:flutter_triple/flutter_triple.dart';
import 'package:pref/pref.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';

enum SavedTweetSort {
  savedAt('saved_at'),
  postedAt('posted_at');

  const SavedTweetSort(this.prefValue);

  final String prefValue;

  static SavedTweetSort fromPrefValue(String? prefValue) =>
      values.firstWhere((sort) => sort.prefValue == prefValue, orElse: () => SavedTweetSort.savedAt);

  SavedTweetSort get next => values[(index + 1) % values.length];
}

class SavedTweetOrder {
  final SavedTweetSort sort;
  final bool ascending;

  const SavedTweetOrder({required this.sort, required this.ascending});

  SavedTweetOrder copyWith({SavedTweetSort? sort, bool? ascending}) =>
      SavedTweetOrder(sort: sort ?? this.sort, ascending: ascending ?? this.ascending);

  /// Sorts the saved posts, given newest saved first as the database lists them.
  List<SavedTweet> apply(List<SavedTweet> newestSavedFirst) {
    final newestFirst = switch (sort) {
      SavedTweetSort.savedAt => newestSavedFirst,
      // The id of a post grows with the time it was posted
      SavedTweetSort.postedAt => [...newestSavedFirst]..sort((a, b) => _postId(b).compareTo(_postId(a))),
    };
    return ascending ? newestFirst.reversed.toList() : newestFirst;
  }
}

BigInt _postId(SavedTweet tweet) => BigInt.tryParse(tweet.id) ?? BigInt.zero;

/// The order the saved posts show in, kept in the preferences.
class SavedTweetOrderStore extends Store<SavedTweetOrder> {
  final BasePrefService prefs;

  SavedTweetOrderStore(this.prefs)
      : super(SavedTweetOrder(
          sort: SavedTweetSort.fromPrefValue(prefs.get(optionSavedOrderByField)),
          ascending: prefs.get(optionSavedOrderByAscending) ?? false,
        ));

  Future<void> showNextSort() => _save(state.copyWith(sort: state.sort.next));

  Future<void> reverseOrder() => _save(state.copyWith(ascending: !state.ascending));

  Future<void> _save(SavedTweetOrder order) async {
    update(order);
    await prefs.set(optionSavedOrderByField, order.sort.prefValue);
    await prefs.set(optionSavedOrderByAscending, order.ascending);
  }
}
