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
import 'package:visibility_detector/visibility_detector.dart';

class SubscriptionsScreen extends StatefulWidget {
  final ScrollController scrollController;

  const SubscriptionsScreen({super.key, required this.scrollController});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late final SubscriptionsPageModel _pageModel = SubscriptionsPageModel(PrefService.of(context, listen: false));
  late final BackInterceptors _backInterceptors = context.read<BackInterceptors>();
  final TextEditingController _searchController = TextEditingController();

  // The page stays alive in another tab while its search field has the focus
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _backInterceptors.add(_onBack);
  }

  @override
  void dispose() {
    _backInterceptors.remove(_onBack);
    _searchController.dispose();
    _pageModel.destroy();
    super.dispose();
  }

  bool _onBack() {
    if (!_visible) {
      return false;
    }
    if (_pageModel.state.selecting) {
      _pageModel.clearSelection();
      return true;
    }
    if (_pageModel.state.searching) {
      _closeSearch();
      return true;
    }
    return false;
  }

  void _closeSearch() {
    _searchController.clear();
    _pageModel.closeSearch();
  }

  @override
  Widget build(BuildContext context) {
    return ScopedBuilder<SubscriptionsModel, List<Subscription>>(
      store: context.read<SubscriptionsModel>(),
      onError: (_, e) => Scaffold(
        body: FullPageErrorWidget(
          error: e,
          stackTrace: null,
          prefix: (l10n) => l10n.unable_to_refresh_the_subscriptions,
        ),
      ),
      onState: (_, subscriptions) => ScopedBuilder<SubscriptionsPageModel, SubscriptionsPageState>(
        store: _pageModel,
        onState: (_, page) => VisibilityDetector(
          key: const Key('subscriptions-page'),
          onVisibilityChanged: (info) => _visible = info.visibleFraction > 0,
          child: Scaffold(
            appBar: _appBar(context, page, subscriptions),
            body: _SubscriptionsBody(
              pageModel: _pageModel,
              page: page,
              subscriptions: subscriptions,
              scrollController: widget.scrollController,
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, SubscriptionsPageState page, List<Subscription> subscriptions) {
    final l10n = L10n.of(context);
    if (page.selecting) {
      final selected = subscriptions.where((s) => page.selected.contains(subscriptionKey(s))).toList();
      return SelectionAppBar(selected: selected, onClear: _pageModel.clearSelection);
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
        title: CompactSearchField(controller: _searchController, onChanged: _pageModel.search, autofocus: true),
        actions: [settings],
      );
    }
    return AppBar(
      title: Text(l10n.subscriptions),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: l10n.search_your_subscriptions,
          onPressed: _pageModel.openSearch,
        ),
        IconButton(
          icon: const Icon(Icons.input),
          tooltip: l10n.import_subscriptions,
          onPressed: () => openImport(context),
        ),
        settings,
      ],
    );
  }
}

class _SubscriptionsBody extends StatelessWidget {
  final SubscriptionsPageModel pageModel;
  final SubscriptionsPageState page;
  final List<Subscription> subscriptions;
  final ScrollController scrollController;

  const _SubscriptionsBody({
    required this.pageModel,
    required this.page,
    required this.subscriptions,
    required this.scrollController,
  });

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
    final (:matching, :shown) = filterSubscriptions(subscriptions, page.normalizedQuery, page.kind);
    final matchingGroups = groupsMatchingSearch(groups, members, matching, page.normalizedQuery);
    final order = context.read<SubscriptionsModel>().order;
    final showGroupsSection = !page.searching || matchingGroups.isNotEmpty;

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        if (showGroupsSection) ..._groupSlivers(matchingGroups),
        SliverToBoxAdapter(child: _listHeader(context, order)),
        if (matching.isNotEmpty)
          SliverToBoxAdapter(
            child: KindFilters(subscriptions: matching, chosen: page.kind, onChosen: pageModel.showKind),
          ),
        // When other filters hold matches of the search, their chips already say so
        if (shown.isEmpty && (page.normalizedQuery.isEmpty || matching.isEmpty))
          SliverToBoxAdapter(child: _emptyState(context))
        else
          _rows(context, shown, groupsBySubscription(groups, members), canReorder: _canReorder(order, shown)),
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16)),
      ],
    );
  }

  /// Dragging works in the custom order only, with the whole list shown and nothing selected.
  bool _canReorder(SubscriptionOrder order, List<Subscription> shown) =>
      order.sort == SubscriptionSort.custom && !page.selecting && !page.searching && shown.length > 1;

  List<Widget> _groupSlivers(List<SubscriptionGroup> groups) {
    // Groups matching a search show even when the section is collapsed
    final expanded = page.searching || !page.groupsCollapsed;
    return [
      SliverToBoxAdapter(
        child: GroupsHeader(collapsed: !expanded, onToggleCollapsed: pageModel.toggleGroupsCollapsed),
      ),
      if (expanded) SliverToBoxAdapter(child: GroupsGrid(groups: groups)),
    ];
  }

  Widget _listHeader(BuildContext context, SubscriptionOrder order) {
    final model = context.read<SubscriptionsModel>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Expanded(child: SectionTitle(L10n.of(context).followed)),
          SortControls(order: order, onNextSort: model.showNextSort, onReverse: model.reverseOrder),
        ],
      ),
    );
  }

  Widget _rows(
    BuildContext context,
    List<Subscription> shown,
    Map<String, List<SubscriptionGroup>> groupsOf, {
    required bool canReorder,
  }) {
    final model = context.read<SubscriptionsModel>();
    Widget row(int index) {
      final subscription = shown[index];
      return SubscriptionRow(
        key: ValueKey(subscriptionKey(subscription)),
        subscription: subscription,
        groups: groupsOf[subscription.id] ?? const [],
        selected: page.selected.contains(subscriptionKey(subscription)),
        selecting: page.selecting,
        onToggleSelected: () => pageModel.toggleSelected(subscription),
        reorderIndex: canReorder ? index : null,
        onMoveUp: canReorder && index > 0 ? () => model.moveSubscription(shown, index, index - 1) : null,
        onMoveDown: canReorder && index < shown.length - 1
            ? () => model.moveSubscription(shown, index, index + 1)
            : null,
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
    final query = page.query?.trim() ?? '';
    if (query.isNotEmpty) {
      final tab = page.kind == SubscriptionKind.user ? SearchTab.people : SearchTab.top;
      return EmptySubscriptions(
        icon: Icons.search_off,
        message: l10n.no_subscription_matches(query),
        actionIcon: Icons.travel_explore,
        actionLabel: l10n.search_on_x(query),
        onAction: () => Navigator.pushNamed(context, routeSearch, arguments: SearchArguments(tab, query: query)),
      );
    }
    if (page.kind == SubscriptionKind.search) {
      return EmptySubscriptions(
        icon: SubscriptionKind.search.icon,
        message: l10n.no_saved_searches,
        actionIcon: Icons.search,
        actionLabel: l10n.search,
        onAction: () => Navigator.pushNamed(
          context,
          routeSearch,
          arguments: SearchArguments(SearchTab.top, focusInputOnOpen: true),
        ),
      );
    }
    return EmptySubscriptions(
      icon: Icons.inbox_outlined,
      message: l10n.no_subscriptions_try_searching_or_importing_some,
      actionIcon: Icons.input,
      actionLabel: l10n.import_subscriptions,
      onAction: () => openImport(context),
    );
  }
}

void openImport(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionImportScreen()));
