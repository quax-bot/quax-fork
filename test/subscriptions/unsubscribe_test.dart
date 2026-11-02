import 'package:flutter_test/flutter_test.dart';
import 'package:pref/pref.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/database/repository.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/subscriptions/users_model.dart';

import '../group/open_feed.dart';

void main() {
  useFreshDatabase();

  final prefs = PrefServiceCache(defaults: {
    optionSubscriptionOrderByField: 'name',
    optionSubscriptionOrderByAscending: true,
    optionSubscriptionOrderCustom: '',
    optionSubscriptionOrderCustomKeys: '[]',
    optionSubscriptionGroupsOrderByField: 'name',
    optionSubscriptionGroupsOrderByAscending: true,
  });

  test('Should bring back the subscriptions and their groups when unsubscribing is undone', () async {
    final groups = GroupsModel(prefs);
    final memberships = GroupMembershipsModel(groups);
    final subscriptions = SubscriptionsModel(prefs, groups);
    final search = SearchSubscription(id: 'flutter', createdAt: DateTime(2026));
    final database = await Repository.writable();
    await database.insert(tableSubscription, flutterDev.toMap());
    await database.insert(tableSearchSubscription, search.toMap());
    await groups.saveGroup(null, 'Tech', defaultGroupIcon, null, {flutterDev.id, search.id});
    await subscriptions.reloadSubscriptions();

    final removed = await subscriptions.unsubscribeAll(subscriptions.state);
    await memberships.reload();
    expect(subscriptions.state, isEmpty, reason: 'Both subscriptions should be gone');
    expect(memberships.state.values.expand((m) => m), isEmpty, reason: 'The group should have lost its members');

    await subscriptions.restore(removed);
    await memberships.reload();
    expect(subscriptions.state.map((s) => s.id), unorderedEquals([flutterDev.id, search.id]),
        reason: 'Undo should follow both again');
    expect(memberships.state.values.single, {flutterDev.id, search.id},
        reason: 'Undo should put them back in the group they were in');
  });
}
