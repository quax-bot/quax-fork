import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/generated/l10n.dart';
import 'package:quax/profile/profile.dart';
import 'package:quax/search/search.dart';
import 'package:quax/subscriptions/_groups.dart';
import 'package:quax/subscriptions/subscription_kind.dart';
import 'package:quax/subscriptions/subscription_order.dart';
import 'package:quax/subscriptions/subscriptions_page_model.dart';
import 'package:quax/user.dart';

void openSubscription(BuildContext context, Subscription subscription) {
  if (subscription is UserSubscription) {
    Navigator.pushNamed(context, routeProfile,
        arguments: ProfileScreenArguments(subscription.id, subscription.screenName, null));
  } else {
    Navigator.pushNamed(context, routeSearch,
        arguments: SearchArguments(SearchTab.top, focusInputOnOpen: false, query: subscription.id));
  }
}

class SubscriptionAvatar extends StatelessWidget {
  final Subscription subscription;
  final bool selected;

  const SubscriptionAvatar({super.key, required this.subscription, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (selected) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: colors.primary,
        child: Icon(Icons.check, color: colors.onPrimary),
      );
    }
    if (subscription is UserSubscription) {
      return UserAvatar(uri: subscription.profileImageUrlHttps, size: 40);
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: colors.tertiaryContainer,
      child: Icon(SubscriptionKind.of(subscription).icon, color: colors.onTertiaryContainer),
    );
  }
}

class SubscriptionRow extends StatelessWidget {
  final Subscription subscription;
  final List<SubscriptionGroup> groups;
  final bool selected;
  final bool selecting;
  final VoidCallback onToggleSelected;

  final int? reorderIndex;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const SubscriptionRow(
      {super.key,
      required this.subscription,
      required this.groups,
      required this.selected,
      required this.selecting,
      required this.onToggleSelected,
      this.reorderIndex,
      this.onMoveUp,
      this.onMoveDown});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.move_up): ?onMoveUp,
        CustomSemanticsAction(label: l10n.move_down): ?onMoveDown,
      },
      child: ListTile(
        selected: selected,
        selectedTileColor: colors.secondaryContainer.withValues(alpha: 0.6),
        leading: Semantics(
          button: true,
          selected: selected,
          label: l10n.select_subscription(subscription.name),
          excludeSemantics: true,
          child: InkResponse(
            onTap: onToggleSelected,
            radius: 24,
            child: SizedBox.square(
              dimension: 48,
              child: Center(child: SubscriptionAvatar(subscription: subscription, selected: selected)),
            ),
          ),
        ),
        title: _SubscriptionTitle(subscription: subscription),
        subtitle: _SubscriptionSubtitle(subscription: subscription, groups: groups),
        trailing: reorderIndex == null
            ? null
            : ReorderableDragStartListener(
                index: reorderIndex!, child: const ExcludeSemantics(child: Icon(Icons.drag_indicator))),
        onTap: selecting ? onToggleSelected : () => openSubscription(context, subscription),
        onLongPress: onToggleSelected,
      ),
    );
  }
}

String subscriptionHandle(L10n l10n, Subscription subscription) => switch (subscription) {
      UserSubscription() => '@${subscription.screenName}',
      SearchSubscription() => l10n.search_term,
    };

class _SubscriptionTitle extends StatelessWidget {
  final Subscription subscription;

  const _SubscriptionTitle({required this.subscription});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(child: Text(subscription.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (subscription.verified) ...[
          const SizedBox(width: 6),
          Icon(Icons.verified, size: 14, color: Theme.of(context).colorScheme.primary),
        ],
      ],
    );
  }
}

class _SubscriptionSubtitle extends StatelessWidget {
  final Subscription subscription;
  final List<SubscriptionGroup> groups;

  const _SubscriptionSubtitle({required this.subscription, required this.groups});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final hiddenFromFeed = subscription is UserSubscription && !subscription.inFeed;
    return Row(
      children: [
        Flexible(child: Text(subscriptionHandle(l10n, subscription), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (hiddenFromFeed) ...[
          const SizedBox(width: 6),
          Icon(Icons.visibility_off_outlined, size: 16, semanticLabel: l10n.hidden_from_main_feed),
        ],
        if (groups.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(child: GroupTags(groups: groups)),
        ],
      ],
    );
  }
}

const _maxShownGroupTags = 2;

class GroupTags extends StatelessWidget {
  final List<SubscriptionGroup> groups;

  const GroupTags({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        ...groups.take(_maxShownGroupTags).map((group) {
          final tone = groupTone(context, group.color);
          return Flexible(
            child: _Tag(icon: group.iconData, label: group.name, background: tone.background, foreground: tone.foreground),
          );
        }),
        if (groups.length > _maxShownGroupTags)
          _Tag(label: '+${groups.length - _maxShownGroupTags}', background: colors.surfaceContainerHighest, foreground: colors.onSurfaceVariant),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color background;
  final Color foreground;

  const _Tag({this.icon, required this.label, required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: foreground), const SizedBox(width: 4)],
          Flexible(child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class KindFilters extends StatelessWidget {
  final List<Subscription> subscriptions;
  final SubscriptionKind? chosen;
  final ValueChanged<SubscriptionKind?> onChosen;

  const KindFilters({super.key, required this.subscriptions, required this.chosen, required this.onChosen});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final counts = countByKind(subscriptions);
    Widget chip(String label, int count, SubscriptionKind? kind) => FilterChip(
          label: Text(l10n.label_with_count(label, count)),
          labelStyle: Theme.of(context).textTheme.labelMedium,
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          // Keeps the spacing around the chips to the padding below
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selected: chosen == kind,
          onSelected: (_) => onChosen(kind),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Wrap(
        spacing: 8,
        children: [
          chip(l10n.all, subscriptions.length, null),
          for (final kind in kindsToFilterBy(subscriptions, chosen))
            chip(kindLabel(l10n, kind), counts[kind] ?? 0, kind),
        ],
      ),
    );
  }
}

String kindLabel(L10n l10n, SubscriptionKind kind) => switch (kind) {
      SubscriptionKind.user => l10n.kind_accounts,
      SubscriptionKind.search => l10n.kind_searches,
    };

class SortControls extends StatelessWidget {
  final SubscriptionOrder order;
  final VoidCallback onNextSort;
  final VoidCallback onReverse;

  const SortControls({super.key, required this.order, required this.onNextSort, required this.onReverse});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final label = switch (order.sort) {
      SubscriptionSort.name => l10n.name,
      SubscriptionSort.screenName => l10n.username,
      SubscriptionSort.createdAt => l10n.date_subscribed,
      SubscriptionSort.custom => l10n.custom_order,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (order.sort != SubscriptionSort.custom)
          IconButton(
            onPressed: onReverse,
            tooltip: l10n.reverse_order,
            icon: Icon(order.ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 20),
          ),
        Tooltip(
          message: l10n.sort_by,
          child: TextButton.icon(
            onPressed: onNextSort,
            icon: const Icon(Icons.swap_vert, size: 18),
            label: Text(label, semanticsLabel: l10n.sort_by_value(label)),
          ),
        ),
      ],
    );
  }
}

class EmptySubscriptions extends StatelessWidget {
  final IconData icon;
  final String message;
  final IconData actionIcon;
  final String actionLabel;
  final VoidCallback onAction;

  const EmptySubscriptions(
      {super.key,
      required this.icon,
      required this.message,
      required this.actionIcon,
      required this.actionLabel,
      required this.onAction});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: color)),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(onPressed: onAction, icon: Icon(actionIcon, size: 18), label: Text(actionLabel)),
        ],
      ),
    );
  }
}
