import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pref/pref.dart';
import 'package:provider/provider.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/database/repository.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/subscriptions/group_editor.dart';
import 'package:quax/subscriptions/subscriptions.dart';
import 'package:quax/subscriptions/users_model.dart';

import '../group/open_feed.dart';
import '../ui/pump_app.dart';

const _orderPrefs = {
  optionSubscriptionOrderByField: 'custom',
  optionSubscriptionOrderByAscending: true,
  optionSubscriptionOrderCustom: '',
  optionSubscriptionOrderCustomKeys: '[]',
  optionSubscriptionGroupsOrderByField: 'name',
  optionSubscriptionGroupsOrderByAscending: true,
  optionSubscriptionGroupsCollapsed: false,
};

UserSubscription _account(String name) => UserSubscription(
    id: 'id-$name',
    screenName: name,
    name: name,
    profileImageUrlHttps: null,
    verified: false,
    createdAt: DateTime(2026),
    inFeed: true);

/// The models sit above the app, as in the real one, since the drag proxy and the editor route live there.
Widget Function(Widget) _withModels(List<Subscription> subscriptions) => (app) => MultiProvider(
      providers: [
        Provider(create: (context) => GroupsModel(PrefService.of(context, listen: false))),
        Provider(create: (context) => GroupMembershipsModel(context.read<GroupsModel>())),
        Provider(
          create: (context) =>
              SubscriptionsModel(PrefService.of(context, listen: false), context.read<GroupsModel>())..update(subscriptions),
        ),
      ],
      child: app,
    );

void main() {
  useFreshDatabase();

  testWidgets('Should keep rendering a subscription while it is dragged by its handle', (tester) async {
    await pumpInApp(tester, SubscriptionsScreen(scrollController: ScrollController()),
        prefs: _orderPrefs, aboveApp: _withModels(['first', 'second', 'third'].map(_account).toList()));

    final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Icons.drag_indicator).at(1)));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull, reason: 'The drag proxy should have a Material ancestor for its row');
    expect(find.text('first'), findsWidgets, reason: 'The dragged subscription should still be shown');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('Should not move a member of the group while it is unticked in the editor', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final subscriptions = ['alice', 'bob', 'zoe'].map(_account).toList();
    final groupId = await tester.runAsync(() async {
      await GroupsModel(PrefServiceCache(defaults: _orderPrefs))
          .saveGroup(null, 'Friends', defaultGroupIcon, null, {'id-zoe'});
      final database = await Repository.readOnly();
      return (await database.query(tableSubscriptionGroup, where: "id != '-1'")).single['id'] as String;
    });
    await pumpInApp(tester, Builder(builder: (context) => GroupEditorScreen(id: groupId, initialMembers: const {})),
        prefs: _orderPrefs, aboveApp: _withModels(subscriptions), settle: false);
    await settleFeed(tester);

    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('zoe'), lessThan(top('alice')), reason: 'The members of the group should come first (#282)');

    await tester.tap(find.text('zoe'));
    await tester.pump();

    expect(top('zoe'), lessThan(top('alice')), reason: 'Unticking a member should not move it before saving');
    expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'zoe')).value, isFalse,
        reason: 'The member should be unticked');
  });
}
