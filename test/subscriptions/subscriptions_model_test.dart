import 'package:flutter_test/flutter_test.dart';
import 'package:pref/pref.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/subscriptions/group_editor_model.dart';
import 'package:quax/subscriptions/users_model.dart';

import '../group/open_feed.dart';
import 'fixtures.dart';

PrefServiceCache _prefs({String legacyCustomOrder = ''}) =>
    PrefServiceCache(defaults: {...subscriptionPrefs, optionSubscriptionOrderCustom: legacyCustomOrder});

final _search = SearchSubscription(id: 'flutter', createdAt: DateTime(2026));

void main() {
  useFreshDatabase();

  test('Should keep the custom order set in an older version', () async {
    final prefs = _prefs(legacyCustomOrder: 'flutter,FlutterDev');
    final subscriptions = SubscriptionsModel(prefs, GroupsModel(prefs));
    await follow([flutterDev, _search]);

    await subscriptions.reloadSubscriptions();
    expect(subscriptions.state.map((s) => s.id), [_search.id, flutterDev.id],
        reason: 'The order chosen in an older version should show at once, as when a backup is restored');

    await subscriptions.reloadSubscriptions();
    expect(subscriptions.state.map((s) => s.id), [_search.id, flutterDev.id],
        reason: 'The order should still show after a reload');
  });

  test('Should create a single group when Save is pressed twice', () async {
    final groups = GroupsModel(_prefs());
    final editor = GroupEditorModel(groups);
    editor.update(await editor.load(null, const {}, const []));
    editor.rename('Tech');

    await Future.wait([editor.save(), editor.save()]);
    await groups.reloadGroups();

    expect(groups.state.map((g) => g.name), ['Tech'], reason: 'Only one group should be created');
  });
}
