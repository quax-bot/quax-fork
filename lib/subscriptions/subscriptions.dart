import 'package:flutter_triple/flutter_triple.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pref/pref.dart';
import 'package:provider/provider.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/generated/l10n.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/search/search.dart';
import 'package:quax/subscriptions/_groups.dart';
import 'package:quax/subscriptions/_import.dart';
import 'package:quax/subscriptions/_list.dart';
import 'package:quax/subscriptions/_search_field.dart';
import 'package:quax/subscriptions/_selection.dart';
import 'package:quax/subscriptions/subscription_kind.dart';
import 'package:quax/subscriptions/subscription_order.dart';
import 'package:quax/subscriptions/subscriptions_page_model.dart';
import 'package:quax/subscriptions/users_model.dart';
import 'package:quax/ui/back_interceptors.dart';
import 'package:quax/ui/errors.dart';

class SubscriptionsScreen extends StatefulWidget {
  final ScrollController scrollController;

  const SubscriptionsScreen({super.key, required this.scrollController});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late final SubscriptionsPageModel _page = SubscriptionsPageModel(PrefService.of(context, listen: false));
  late final BackInterceptors _backInterceptors = context.read<BackInterceptors>();
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _backInterceptors.add(_onBack);
  }

  @override
  void dispose() {
    _backInterceptors.remove(_onBack);
    _query.dispose();
    _page.destroy();
    super.dispose();
  }

  bool _onBack() {
    if (_page.state.selecting) {
      _page.clearSelection();
      return true;
    }
    if (_page.state.searching) {
      _closeSearch();
      return true;
    }
    return false;
  }

  void _closeSearch() {
    _query.clear();
    _page.closeSearch();
  }

  @override
  Widget build(BuildContext context) {
    return ScopedBuilder<SubscriptionsModel, List<Subscription>>(
      store: context.read<SubscriptionsModel>(),
      onError: (_, e) => Scaffold(
        body: FullPageErrorWidget(
            error: e, stackTrace: null, prefix: (l10n) => l10n.unable_to_refresh_the_subscriptions),
      ),
      onState: (_, subscriptions) => ScopedBuilder<SubscriptionsPageModel, SubscriptionsPageState>(
        store: _page,
        onState: (_, page) => Scaffold(
          appBar: _appBar(context, page, subscriptions),
          body: _SubscriptionsBody(
            page: _page,
            pageState: page,
            subscriptions: subscriptions,
            scrollController: widget.scrollController,
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, SubscriptionsPageState page, List<Subscription> subscriptions) {
    final l10n = L10n.of(context);
    if (page.selecting) {
      final selected = subscriptions.where((s) => page.selected.contains(subscriptionKey(s))).toList();
      return SelectionAppBar(selected: selected, onClear: _page.clearSelection);
    }
    final settings = IconButton(
      icon: const Icon(Icons.settings),
      tooltip: l10n.settings,
      onPressed: () => Navigator.pushNamed(context, routeSettings),
    );
    if (page.searching) {
      return AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: l10n.close, onPressed: _closeSearch),
        titleSpacing: 0,
        title: CompactSearchField(controller: _query, onChanged: _page.search, autofocus: true),
        actions: [settings],
      );
    }
    return AppBar(
      title: Text(l10n.subscriptions),
      actions: [
        IconButton(icon: const Icon(Icons.search), tooltip: l10n.search_your_subscriptions, onPressed: _page.openSearch),
        IconButton(icon: const Icon(Icons.download), tooltip: l10n.import_subscriptions, onPressed: () => openImport(context)),
        settings,
      ],
    );
  }
}

class _SubscriptionsBody extends StatelessWidget {
  final SubscriptionsPageModel page;
  final SubscriptionsPageState pageState;
  final List<Subscription> subscriptions;
  final ScrollController scrollController;

  const _SubscriptionsBody(
      {required this.page, required this.pageState, required this.subscriptions, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return ScopedBuilder<GroupsModel, List<SubscriptionGroup>>(
      store: context.read<GroupsModel>(),
      onState: (_, groups) => ScopedBuilder<GroupMembershipsModel, Map<String, Set<String>>>(
        store: context.read<GroupMembershipsModel>(),
        onState: (_, members) => _content(context, groups, members),
      ),
    );
  }

  Widget _content(BuildContext context, List<SubscriptionGroup> groups, Map<String, Set<String>> members) {
    final searched = searchedSubscriptions(subscriptions, pageState.trimmedQuery);
    final shown = ofKind(searched, pageState.kind);
    final visibleGroups = shownGroups(groups, members, searched, pageState.trimmedQuery);
    final groupsOf = _groupsBySubscription(groups, members);
    final order = context.read<SubscriptionsModel>().order;
    final canReorder =
        order.sort == SubscriptionSort.custom && !pageState.selecting && !pageState.searching && shown.length > 1;

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        if (visibleGroups.isNotEmpty || !pageState.searching) ..._groupSlivers(groups, visibleGroups, members),
        SliverToBoxAdapter(child: _listHeader(context, searched.length, order)),
        if (searched.isNotEmpty)
          SliverToBoxAdapter(
            child: KindFilters(searched: searched, chosen: pageState.kind, onChosen: page.showKind),
          ),
        if (shown.isEmpty)
          SliverToBoxAdapter(child: _emptyState(context))
        else
          _rows(context, shown, groupsOf, canReorder),
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16)),
      ],
    );
  }

  List<Widget> _groupSlivers(
      List<SubscriptionGroup> all, List<SubscriptionGroup> visible, Map<String, Set<String>> members) {
    final collapsed = pageState.groupsCollapsed && !pageState.searching;
    return [
      SliverToBoxAdapter(
        child: GroupsHeader(count: visible.length, collapsed: collapsed, onToggleCollapsed: page.toggleGroupsCollapsed),
      ),
      if (!collapsed)
        SliverToBoxAdapter(
          child: GroupsCarousel(
            groups: visible,
            members: members,
            subscriptionsById: {for (final s in subscriptions) s.id: s},
          ),
        ),
      const SliverToBoxAdapter(child: Divider(indent: 16, endIndent: 16, height: 1)),
    ];
  }

  Widget _listHeader(BuildContext context, int count, SubscriptionOrder order) {
    final model = context.read<SubscriptionsModel>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Expanded(child: SectionTitle(title: L10n.of(context).followed, count: count)),
          SortControls(order: order, onCycle: model.cycleSort, onReverse: model.reverseOrder),
        ],
      ),
    );
  }

  Widget _rows(BuildContext context, List<Subscription> shown, Map<String, List<SubscriptionGroup>> groupsOf,
      bool canReorder) {
    final model = context.read<SubscriptionsModel>();
    Widget row(int index) {
      final subscription = shown[index];
      return SubscriptionRow(
        key: ValueKey(subscriptionKey(subscription)),
        subscription: subscription,
        groups: groupsOf[subscription.id] ?? const [],
        selected: pageState.selected.contains(subscriptionKey(subscription)),
        selecting: pageState.selecting,
        onToggleSelected: () => page.toggleSelected(subscription),
        dragIndex: canReorder ? index : null,
        onMoveUp: canReorder && index > 0 ? () => model.moveSubscription(shown, index, index - 1) : null,
        onMoveDown:
            canReorder && index < shown.length - 1 ? () => model.moveSubscription(shown, index, index + 1) : null,
      );
    }

    if (!canReorder) {
      return SliverList.builder(itemCount: shown.length, itemBuilder: (_, index) => row(index));
    }
    return SliverReorderableList(
      itemCount: shown.length,
      proxyDecorator: (child, _, _) => Material(type: MaterialType.transparency, child: child),
      itemBuilder: (_, index) => row(index),
      onReorderItem: (oldIndex, newIndex) => model.moveSubscription(shown, oldIndex, newIndex),
    );
  }

  Widget _emptyState(BuildContext context) {
    final l10n = L10n.of(context);
    final query = pageState.query?.trim() ?? '';
    if (query.isNotEmpty) {
      final tab = pageState.kind == SubscriptionKind.user ? SearchTab.people : SearchTab.top;
      return EmptySubscriptions(
        icon: Icons.search_off,
        message: l10n.no_subscription_matches(query),
        actionIcon: Icons.travel_explore,
        actionLabel: l10n.search_on_x(query),
        onAction: () => Navigator.pushNamed(context, routeSearch, arguments: SearchArguments(tab, query: query)),
      );
    }
    if (pageState.kind == SubscriptionKind.search) {
      return EmptySubscriptions(
        icon: SubscriptionKind.search.icon,
        message: l10n.no_saved_searches,
        actionIcon: Icons.search,
        actionLabel: l10n.search,
        onAction: () => Navigator.pushNamed(context, routeSearch,
            arguments: SearchArguments(SearchTab.top, focusInputOnOpen: true)),
      );
    }
    return EmptySubscriptions(
      icon: Icons.inbox_outlined,
      message: l10n.no_subscriptions_try_searching_or_importing_some,
      actionIcon: Icons.download,
      actionLabel: l10n.import_subscriptions,
      onAction: () => openImport(context),
    );
  }
}

Map<String, List<SubscriptionGroup>> _groupsBySubscription(
        List<SubscriptionGroup> groups, Map<String, Set<String>> members) =>
    groups.fold({}, (bySubscription, group) {
      for (final id in members[group.id] ?? const <String>{}) {
        bySubscription.putIfAbsent(id, () => []).add(group);
      }
      return bySubscription;
    });

void openImport(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionImportScreen()));
