import 'package:flutter_test/flutter_test.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/subscriptions/subscription_kind.dart';
import 'package:quax/subscriptions/subscription_order.dart';

UserSubscription _account(String screenName) => UserSubscription(
    id: 'id-$screenName',
    screenName: screenName,
    name: screenName,
    profileImageUrlHttps: null,
    verified: false,
    createdAt: DateTime(2026),
    inFeed: true);

void main() {
  test('Should put the subscriptions followed after the custom order was set at its end', () {
    final order = SubscriptionOrder(
        sort: SubscriptionSort.custom,
        ascending: true,
        custom: [subscriptionKey(_account('zoe')), subscriptionKey(_account('bob'))]);

    final names = order.apply([_account('bob'), _account('new'), _account('zoe'), _account('alice')]).map((s) => s.name);

    expect(names, ['zoe', 'bob', 'alice', 'new'],
        reason: 'The chosen order should stay as set, the subscriptions it does not know follow by name');
  });

  test('Should keep the hidden subscriptions in place when a filtered one is moved', () {
    final all = ['a', 'hidden', 'b', 'c'];

    expect(reorderedKeys(all, ['a', 'b', 'c'], 0, 2), ['hidden', 'b', 'c', 'a'],
        reason: 'Moving "a" after "c" among the shown ones should not move "hidden"');
    expect(reorderedKeys(all, ['a', 'b', 'c'], 2, 1), ['a', 'hidden', 'c', 'b'],
        reason: 'Moving "c" before "b" should put it right before "b", after "hidden"');
  });

  test('Should read the custom order stored by older versions', () {
    final subscriptions = [_account('bob'), SearchSubscription(id: 'flutter', createdAt: DateTime(2026)), _account('zoe')];

    expect(keysOfLegacyCustomOrder('zoe,flutter,gone,bob', subscriptions), ['user:id-zoe', 'search:flutter', 'user:id-bob'],
        reason: 'Screen names should become keys, and unfollowed ones should be dropped');
  });
}
