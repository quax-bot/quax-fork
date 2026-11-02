import 'package:material_ui/material_ui.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/database/repository.dart';

/// What a subscription follows: an account or a saved search.
enum SubscriptionKind {
  user(Icons.person, tableSubscription),
  search(Icons.saved_search, tableSearchSubscription);

  const SubscriptionKind(this.icon, this.table);

  final IconData icon;
  final String table;

  static SubscriptionKind of(Subscription subscription) => switch (subscription) {
        UserSubscription() => user,
        SearchSubscription() => search,
      };
}

/// Identifies a subscription among those of every kind, such as `user:123`.
String subscriptionKey(Subscription subscription) =>
    // The custom order stores these keys: renaming a kind would lose its subscriptions' place
    '${SubscriptionKind.of(subscription).name}:${subscription.id}';

/// Kinds without any subscription are left out.
Map<SubscriptionKind, int> countByKind(Iterable<Subscription> subscriptions) => subscriptions.fold(
    {}, (counts, s) => counts..update(SubscriptionKind.of(s), (n) => n + 1, ifAbsent: () => 1));
