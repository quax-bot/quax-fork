import 'package:flutter_test/flutter_test.dart';
import 'package:pref/pref.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/database/repository.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/subscriptions/group_editor_model.dart';
import 'package:quax/subscriptions/users_model.dart';

import '../group/open_feed.dart';

PrefServiceCache _prefs({String legacyCustomOrder = ''}) => PrefServiceCache(defaults: {
      optionSubscriptionOrderByField: 'name',
      optionSubscriptionOrderByAscending: true,
      optionSubscriptionOrderCustom: legacyCustomOrder,
      optionSubscriptionOrderCustomKeys: '[]',
    });

final _search = SearchSubscription(id: 'flutter', createdAt: DateTime(2026));

Future<void> _follow(List<Subscription> subscriptions) async {
  final database = await Repository.writable();
  for (final subscription in subscriptions) {
    await database.insert(
        subscription is SearchSubscription ? tableSearchSubscription : tableSubscription, subscription.toMap());
  }
}

void main() {
  useFreshDatabase();

  test('Should bring back the subscriptions and their groups when unsubscribing is undone', () async {
    final prefs = _prefs();
    final groups = GroupsModel(prefs);
    final memberships = GroupMembershipsModel(groups);
    final subscriptions = SubscriptionsModel(prefs, groups);
    await _follow([flutterDev, _search]);
    await groups.saveGroup(null, 'Tech', defaultGroupIcon, null, {flutterDev.id, _search.id});
    await subscriptions.reloadSubscriptions();

    final removed = await subscriptions.unsubscribeAll(subscriptions.state);
    await memberships.reload();
    expect(subscriptions.state, isEmpty, reason: 'Both subscriptions should be gone');
    expect(memberships.state.values.expand((m) => m), isEmpty, reason: 'The group should have lost its members');

    await subscriptions.restore(removed);
    await memberships.reload();
    expect(subscriptions.state.map((s) => s.id), unorderedEquals([flutterDev.id, _search.id]),
        reason: 'Undo should follow both again');
    expect(memberships.state.values.single, {flutterDev.id, _search.id},
        reason: 'Undo should put them back in the group they were in');
  });

  test('Should keep the custom order of older versions once, as the chosen sort', () async {
    final prefs = _prefs(legacyCustomOrder: 'flutter,FlutterDev');
    final subscriptions = SubscriptionsModel(prefs, GroupsModel(prefs));
    await _follow([flutterDev, _search]);

    await subscriptions.reloadSubscriptions();
    await subscriptions.reloadSubscriptions();

    expect(subscriptions.state.map((s) => s.id), [_search.id, flutterDev.id],
        reason: 'The order chosen in an older version should still show, also after a reload');
    expect(prefs.get(optionSubscriptionOrderByField), 'custom', reason: 'The custom order should become the sort');
    expect(prefs.get(optionSubscriptionOrderCustom), '', reason: 'The old order should not be read again');
  });

  test('Should create a single group when Save is pressed twice', () async {
    final groups = GroupsModel(_prefs());
    final editor = GroupEditorModel(groups);
    editor.update(await editor.load(null, const {}, const []));
    editor.rename('Tech');

    final saved = await Future.wait([editor.save(), editor.save()]);
    await groups.reloadGroups();

    expect(saved, [true, false], reason: 'The second press should be ignored while the first one saves');
    expect(groups.state.map((g) => g.name), ['Tech'], reason: 'Only one group should be created');
  });
}
