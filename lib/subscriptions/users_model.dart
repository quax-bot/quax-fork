import 'dart:ui';

import 'package:flutter_triple/flutter_triple.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/database/repository.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/subscriptions/refreshed_profiles.dart';
import 'package:quax/user.dart';
import 'package:quax/subscriptions/subscription_kind.dart';
import 'package:quax/subscriptions/subscription_order.dart';
import 'package:sqflite/sqflite.dart';
import 'package:logging/logging.dart';
import 'package:pref/pref.dart';

class SubscriptionsModel extends Store<List<Subscription>> {
  static final log = Logger('SubscriptionsModel');

  final BasePrefService prefs;
  final GroupsModel groupModel;
  final Map<String, VoidCallback> _onSubscriptionsReloaded = {};

  SubscriptionsModel(this.prefs, this.groupModel) : super([]);

  void addReloadListener(String key, VoidCallback callback) {
    _onSubscriptionsReloaded[key] = callback;
  }

  void removeReloadListener(String key) {
    _onSubscriptionsReloaded.remove(key);
  }

  late SubscriptionOrder _order = _storedOrder();

  SubscriptionOrder get order => _order;

  SubscriptionOrder _storedOrder() => SubscriptionOrder(
        sort: SubscriptionSort.fromPref(prefs.get(optionSubscriptionOrderByField)),
        ascending: prefs.get(optionSubscriptionOrderByAscending),
        custom: decodeCustomOrder(prefs.get(optionSubscriptionOrderCustomKeys)),
      );

  Future<void> reloadSubscriptions() async {
    log.info('Listing subscriptions');

    await execute(() async {
      var database = await Repository.readOnly();

      List<Subscription> users = (await database.query(tableSubscription)).map((e) => UserSubscription.fromMap(e)).toList();
      List<Subscription> searches = (await database.query(tableSearchSubscription)).map((e) => SearchSubscription.fromMap(e)).toList();
      final subscriptions = [...users, ...searches];

      // A restored backup replaces the preferences
      _order = _storedOrder();
      await _migrateLegacyCustomOrder(subscriptions);
      return _order.apply(subscriptions);
    });
    for(final callback in _onSubscriptionsReloaded.values) {
      callback();
    }
  }

  /// Older versions stored the custom order as screen names, only while it was the chosen sort.
  Future<void> _migrateLegacyCustomOrder(List<Subscription> subscriptions) async {
    final String legacy = prefs.get(optionSubscriptionOrderCustom) ?? '';
    if (legacy.isEmpty) {
      return;
    }
    await _storeOrder(_order.copyWith(sort: SubscriptionSort.custom, custom: keysOfLegacyCustomOrder(legacy, subscriptions)));
    await prefs.set(optionSubscriptionOrderCustom, '');
  }

  /// Shows the new order at once, before it is stored.
  Future<void> _saveOrder(SubscriptionOrder order) async {
    update(order.apply(state));
    await _storeOrder(order);
  }

  Future<void> _storeOrder(SubscriptionOrder order) async {
    _order = order;
    await prefs.set(optionSubscriptionOrderByField, order.sort.pref);
    await prefs.set(optionSubscriptionOrderByAscending, order.ascending);
    await prefs.set(optionSubscriptionOrderCustomKeys, encodeCustomOrder(order.custom));
  }

  /// Switches to the next sort. The custom order starts from the order shown.
  Future<void> cycleSort() {
    final next = _order.sort.next;
    final startsCustomOrder = next == SubscriptionSort.custom && _order.custom.isEmpty;
    return _saveOrder(_order.copyWith(sort: next, custom: startsCustomOrder ? state.map(subscriptionKey).toList() : null));
  }

  Future<void> reverseOrder() => _saveOrder(_order.copyWith(ascending: !_order.ascending));

  Future<void> moveSubscription(List<Subscription> visible, int oldIndex, int newIndex) => _saveOrder(_order.copyWith(
      custom: reorderedKeys(state.map(subscriptionKey).toList(), visible.map(subscriptionKey).toList(), oldIndex, newIndex)));

  /// Returns what [restore] needs to undo it.
  Future<RemovedSubscriptions> unsubscribeAll(List<Subscription> subscriptions) async {
    final database = await Repository.writable();
    final ids = subscriptions.map((s) => s.id).toSet();
    final memberships = (await database.query(tableSubscriptionGroupMember))
        .map(SubscriptionGroupMember.fromMap)
        .where((m) => ids.contains(m.profile))
        .toList();

    final batch = database.batch();
    for (final subscription in subscriptions) {
      batch.delete(SubscriptionKind.of(subscription).table, where: 'id = ?', whereArgs: [subscription.id]);
      batch.delete(tableSubscriptionGroupMember, where: 'profile_id = ?', whereArgs: [subscription.id]);
    }
    await batch.commit(noResult: true);

    await reloadSubscriptions();
    await groupModel.reloadGroups();
    return RemovedSubscriptions(subscriptions, memberships);
  }

  Future<void> restore(RemovedSubscriptions removed) async {
    final database = await Repository.writable();
    final batch = database.batch();
    for (final subscription in removed.subscriptions) {
      batch.insert(SubscriptionKind.of(subscription).table, subscription.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final membership in removed.memberships) {
      batch.insert(tableSubscriptionGroupMember, membership.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);

    await reloadSubscriptions();
    await groupModel.reloadGroups();
  }

  /// Only accounts can be hidden from the main feed.
  Future<void> setInFeed(Iterable<Subscription> subscriptions, bool inFeed) async {
    final batch = (await Repository.writable()).batch();
    for (final account in subscriptions.whereType<UserSubscription>()) {
      batch.update(tableSubscription, {'in_feed': inFeed ? 1 : 0}, where: 'id = ?', whereArgs: [account.id]);
    }
    await batch.commit(noResult: true);
    await reloadSubscriptions();
  }

  Future<void> _toggleSearchSubscribe(SearchSubscription user, bool currentlyFollowed) async {
    var database = await Repository.writable();

    await execute(() async {
      if (currentlyFollowed) {
        await database.delete(tableSearchSubscription, where: 'id = ?', whereArgs: [user.id]);
        await database.delete(tableSearchSubscriptionGroupMember, where: 'search_id = ?', whereArgs: [user.id]);

        state.removeWhere((e) => e.id == user.id);
      } else {
        database.insert(tableSearchSubscription, {
          'id': user.id,
        });
      }

      // TODO: This is hardcore, but we need to resort the list and this is the easiest way
      await reloadSubscriptions();

      return state;
    });
  }

  /// Saves the new name and picture of the subscriptions among [users], fresh from X
  Future<void> refreshSubscriptions(Iterable<UserWithExtra> users) async {
    final refreshed = refreshedSubscriptions(state, users);
    if (refreshed.isEmpty) {
      return;
    }
    log.info('Refreshing ${refreshed.length} subscriptions');

    final database = await Repository.writable();
    final batch = database.batch();
    for (final subscription in refreshed.values) {
      batch.update(tableSubscription,
          {'name': subscription.name, 'profile_image_url_https': subscription.profileImageUrlHttps},
          where: 'id = ?', whereArgs: [subscription.id]);
    }
    await batch.commit(noResult: true);

    // Not reloadSubscriptions(): its listeners would drop the feeds kept in memory
    update(state.map((subscription) => refreshed[subscription.id] ?? subscription).toList());
  }

  Future<void> _toggleUserSubscribe(UserSubscription user, bool currentlyFollowed) async {
    var database = await Repository.writable();

    await execute(() async {
      if (currentlyFollowed) {
        await database.delete(tableSubscription, where: 'id = ?', whereArgs: [user.id]);
        await database.delete(tableSubscriptionGroupMember, where: 'profile_id = ?', whereArgs: [user.id]);

        state.removeWhere((e) => e.id == user.id);
      } else {
        database.insert(tableSubscription, {
          'id': user.id,
          'screen_name': user.screenName,
          'name': user.name,
          'profile_image_url_https': user.profileImageUrlHttps,
          'verified': user.verified ? 1 : 0
        });
      }

      // TODO: This is hardcore, but we need to resort the list and this is the easiest way
      await reloadSubscriptions();

      return state;
    });

    await groupModel.reloadGroups();
  }

  Future<void> toggleSubscribe(Subscription user, bool currentlyFollowed) async {
    if (user is UserSubscription) {
      await _toggleUserSubscribe(user, currentlyFollowed);
    } else if (user is SearchSubscription) {
      await _toggleSearchSubscribe(user, currentlyFollowed);
    }

    await groupModel.reloadGroups();
  }

  Future<void> toggleInFeed(Subscription user, bool wasInFeed) async {
    var database = await Repository.writable();
    await execute(() async {
      database.update(tableSubscription, {
        'in_Feed': wasInFeed ? 0 : 1
      }, where: 'id = ?', whereArgs: [user.id]);

      await reloadSubscriptions();

      return state;
    });
  }
}

class RemovedSubscriptions {
  final List<Subscription> subscriptions;
  final List<SubscriptionGroupMember> memberships;

  const RemovedSubscriptions(this.subscriptions, this.memberships);
}
