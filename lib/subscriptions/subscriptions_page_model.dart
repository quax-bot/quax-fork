import 'package:flutter_triple/flutter_triple.dart';
import 'package:pref/pref.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/subscriptions/subscription_kind.dart';

class SubscriptionsPageState {
  /// Null while the search bar is closed.
  final String? query;

  /// Null shows every kind.
  final SubscriptionKind? kind;

  /// The keys of the selected subscriptions.
  final Set<String> selected;

  final bool groupsCollapsed;

  const SubscriptionsPageState({this.query, this.kind, this.selected = const {}, this.groupsCollapsed = false});

  bool get searching => query != null;

  bool get selecting => selected.isNotEmpty;

  String get trimmedQuery => query?.trim().toLowerCase() ?? '';

  SubscriptionsPageState copyWith({SubscriptionKind? Function()? kind, Set<String>? selected, bool? groupsCollapsed}) =>
      SubscriptionsPageState(
        query: query,
        kind: kind == null ? this.kind : kind(),
        selected: selected ?? this.selected,
        groupsCollapsed: groupsCollapsed ?? this.groupsCollapsed,
      );

  SubscriptionsPageState withQuery(String? query) =>
      SubscriptionsPageState(query: query, kind: kind, selected: selected, groupsCollapsed: groupsCollapsed);
}

class SubscriptionsPageModel extends Store<SubscriptionsPageState> {
  final BasePrefService prefs;

  SubscriptionsPageModel(this.prefs)
      : super(SubscriptionsPageState(groupsCollapsed: prefs.get(optionSubscriptionGroupsCollapsed) ?? false));

  void openSearch() => update(state.withQuery(''));

  void closeSearch() => update(state.withQuery(null));

  void search(String query) => update(state.withQuery(query));

  /// Clears the selection, which could hold subscriptions the new filter hides.
  void showKind(SubscriptionKind? kind) => update(state.copyWith(kind: () => kind, selected: const {}));

  void toggleSelected(Subscription subscription) {
    final key = subscriptionKey(subscription);
    final selected = state.selected.contains(key)
        ? state.selected.where((k) => k != key).toSet()
        : {...state.selected, key};
    update(state.copyWith(selected: selected));
  }

  void clearSelection() => update(state.copyWith(selected: const {}));

  Future<void> toggleGroupsCollapsed() async {
    final collapsed = !state.groupsCollapsed;
    update(state.copyWith(groupsCollapsed: collapsed));
    await prefs.set(optionSubscriptionGroupsCollapsed, collapsed);
  }
}

bool matchesQuery(Subscription subscription, String query) =>
    query.isEmpty ||
    subscription.name.toLowerCase().contains(query) ||
    subscription.screenName.toLowerCase().contains(query);

/// [query] is trimmed and lower case.
List<Subscription> searchedSubscriptions(List<Subscription> all, String query) =>
    all.where((s) => matchesQuery(s, query)).toList();

/// A null [kind] shows every kind.
List<Subscription> ofKind(List<Subscription> subscriptions, SubscriptionKind? kind) =>
    subscriptions.where((s) => kind == null || SubscriptionKind.of(s) == kind).toList();

/// While searching, a group shows if its name matches or if it holds a matching subscription.
List<SubscriptionGroup> shownGroups(List<SubscriptionGroup> groups, Map<String, Set<String>> members,
    List<Subscription> searched, String query) {
  if (query.isEmpty) {
    return groups;
  }
  final ids = searched.map((s) => s.id).toSet();
  return groups
      .where((g) => g.name.toLowerCase().contains(query) || (members[g.id] ?? const {}).any(ids.contains))
      .toList();
}

/// A filter shows only for kinds with subscriptions, plus the one chosen.
List<SubscriptionKind> filterKinds(Iterable<Subscription> subscriptions, SubscriptionKind? chosen) {
  final present = countByKind(subscriptions).keys;
  return SubscriptionKind.values.where((kind) => kind == chosen || present.contains(kind)).toList();
}
