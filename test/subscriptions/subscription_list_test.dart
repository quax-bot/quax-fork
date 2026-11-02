import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pref/pref.dart';
import 'package:provider/provider.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/database/repository.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/subscriptions/_search_field.dart';
import 'package:quax/subscriptions/group_editor.dart';
import 'package:quax/subscriptions/subscriptions.dart';
import 'package:quax/subscriptions/users_model.dart';
import 'package:quax/ui/back_interceptors.dart';

import '../group/open_feed.dart';
import '../ui/pump_app.dart';

const _orderPrefs = {
  optionSubscriptionOrderByField: 'custom',
  optionSubscriptionOrderByAscending: true,
  optionSubscriptionOrderCustom: '',
  optionSubscriptionOrderCustomKeys: '[]',
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
        Provider(create: (_) => BackInterceptors()),
      ],
      child: app,
    );

void main() {
  useFreshDatabase();

  testWidgets('Should move a subscription dragged by its handle, and keep that order', (tester) async {
    await pumpInApp(tester, SubscriptionsScreen(scrollController: ScrollController()),
        prefs: _orderPrefs, aboveApp: _withModels(['first', 'second', 'third'].map(_account).toList()));
    final handles = find.descendant(of: find.byType(ListTile), matching: find.byIcon(Icons.drag_indicator));
    final rowHeight = tester.getCenter(handles.at(1)).dy - tester.getCenter(handles.at(0)).dy;

    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 0; step < 15; step++) {
      await gesture.moveBy(Offset(0, rowHeight / 10));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tester.takeException(), isNull, reason: 'The drag proxy should have a Material ancestor for its row');
    await gesture.up();
    await tester.pumpAndSettle();

    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('second'), lessThan(top('first')), reason: '"first" should now be below "second"');
    expect(top('first'), lessThan(top('third')), reason: '"first" should stay above "third"');
    final context = tester.element(find.byType(SubscriptionsScreen));
    expect(PrefService.of(context, listen: false).get(optionSubscriptionOrderCustomKeys),
        '["user:id-second","user:id-first","user:id-third"]',
        reason: 'The new order should be stored');
  });

  testWidgets('Should close the search on back, without closing the app', (tester) async {
    var appClosed = false;
    await pumpInApp(
        tester,
        Builder(
          builder: (context) => PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) =>
                appClosed = !didPop && !context.read<BackInterceptors>().intercept(),
            child: SubscriptionsScreen(scrollController: ScrollController()),
          ),
        ),
        prefs: _orderPrefs,
        aboveApp: _withModels([_account('alice')]));
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(CompactSearchField), findsNothing, reason: 'Back should close the search');
    expect(appClosed, isFalse, reason: 'Back should not reach the app, which would close it');

    await tester.binding.handlePopRoute();
    expect(appClosed, isTrue, reason: 'Once the search is closed, back should reach the app again');
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
