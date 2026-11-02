import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pref/pref.dart';
import 'package:provider/provider.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/database/repository.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/subscriptions/subscription_kind.dart';
import 'package:quax/subscriptions/users_model.dart';
import 'package:quax/ui/back_interceptors.dart';

const subscriptionPrefs = {
  optionSubscriptionOrderByField: 'name',
  optionSubscriptionOrderByAscending: true,
  optionSubscriptionOrderCustom: '',
  optionSubscriptionOrderCustomKeys: '[]',
  optionSubscriptionGroupsCollapsed: false,
};

UserSubscription account(String name) => UserSubscription(
    id: 'id-$name',
    screenName: name,
    name: name,
    profileImageUrlHttps: null,
    verified: false,
    createdAt: DateTime(2026),
    inFeed: true);

Future<void> follow(List<Subscription> subscriptions) async {
  final database = await Repository.writable();
  for (final subscription in subscriptions) {
    await database.insert(SubscriptionKind.of(subscription).table, subscription.toMap());
  }
}

/// Returns the id of the new group.
Future<String> createGroup(String name, Set<String> members) async {
  await GroupsModel(PrefServiceCache(defaults: subscriptionPrefs)).saveGroup(null, name, defaultGroupIcon, null, members);
  final database = await Repository.readOnly();
  final rows = await database.query(tableSubscriptionGroup, where: 'name = ?', whereArgs: [name]);
  return rows.single['id'] as String;
}

/// The models sit above the app, as in the real one, since the drag proxy and the editor route live there.
/// They load what [follow] and [createGroup] stored.
Widget Function(Widget) withSubscriptionModels() => (app) => MultiProvider(
      providers: [
        Provider(create: (context) => GroupsModel(PrefService.of(context, listen: false))..reloadGroups()),
        Provider(lazy: false, create: (context) => GroupMembershipsModel(context.read<GroupsModel>())..reload()),
        Provider(
          lazy: false,
          create: (context) =>
              SubscriptionsModel(PrefService.of(context, listen: false), context.read<GroupsModel>())
                ..reloadSubscriptions(),
        ),
        Provider(create: (_) => BackInterceptors()),
      ],
      child: app,
    );

/// Lets the database answer and the screen show what it answered.
Future<void> waitForDatabase(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
