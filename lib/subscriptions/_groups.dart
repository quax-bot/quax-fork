import 'package:material_ui/material_ui.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/generated/l10n.dart';
import 'package:quax/group/group_screen.dart';
import 'package:quax/subscriptions/group_editor.dart';
import 'package:quax/subscriptions/subscription_kind.dart';

typedef GroupTone = ({Color background, Color foreground});

final _schemes = <(int, Brightness), ColorScheme>{};

GroupTone groupTone(BuildContext context, Color? color) {
  final theme = Theme.of(context);
  if (color == null) {
    return (background: theme.colorScheme.secondaryContainer, foreground: theme.colorScheme.onSecondaryContainer);
  }
  final scheme = _schemes.putIfAbsent((color.toARGB32(), theme.brightness),
      () => ColorScheme.fromSeed(seedColor: color, brightness: theme.brightness));
  return (background: scheme.primaryContainer, foreground: scheme.onPrimaryContainer);
}

/// "3 accounts · 1 search"
String membersSummary(BuildContext context, Iterable<Subscription> members) {
  final l10n = L10n.of(context);
  final parts = countByKind(members).entries.map((e) => switch (e.key) {
        SubscriptionKind.user => l10n.n_accounts(e.value),
        SubscriptionKind.search => l10n.n_searches(e.value),
      });
  return parts.isEmpty ? l10n.no_members_yet : parts.join(' · ');
}

class GroupsHeader extends StatelessWidget {
  final int count;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  const GroupsHeader({super.key, required this.count, required this.collapsed, required this.onToggleCollapsed});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
      child: Row(
        children: [
          Expanded(child: SectionTitle(title: l10n.groups, count: count)),
          TextButton.icon(
            onPressed: () => openGroupEditor(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.new_group_short, semanticsLabel: l10n.new_group),
          ),
          IconButton(
            onPressed: onToggleCollapsed,
            tooltip: collapsed ? l10n.show_groups : l10n.hide_groups,
            icon: AnimatedRotation(
              turns: collapsed ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.expand_less),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const SectionTitle({super.key, required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Flexible(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        const SizedBox(width: 8),
        Badge.count(
          count: count,
          maxCount: 99999,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          textColor: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class GroupsCarousel extends StatelessWidget {
  final List<SubscriptionGroup> groups;
  final Map<String, Set<String>> members;
  final Map<String, Subscription> subscriptionsById;

  const GroupsCarousel({super.key, required this.groups, required this.members, required this.subscriptionsById});

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 12),
        child: Text(L10n.of(context).groups_description,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 12),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final group = groups[index];
          final groupMembers = (members[group.id] ?? const {}).map((id) => subscriptionsById[id]).nonNulls;
          return GroupCard(group: group, members: groupMembers.toList());
        },
      ),
    );
  }
}

class GroupCard extends StatelessWidget {
  final SubscriptionGroup group;
  final List<Subscription> members;

  const GroupCard({super.key, required this.group, required this.members});

  @override
  Widget build(BuildContext context) {
    final tone = groupTone(context, group.color);
    return SizedBox(
      width: 148,
      child: Material(
        color: tone.background,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: InkWell(
                onTap: () => Navigator.pushNamed(context, routeGroup,
                    arguments: GroupScreenArguments(id: group.id, name: group.name)),
                child: Semantics(
                  label: group.name,
                  value: membersSummary(context, members),
                  excludeSemantics: true,
                  child: _GroupCardContent(group: group, members: members, color: tone.foreground),
                ),
              ),
            ),
            PositionedDirectional(
              top: 2,
              end: 2,
              child: IconButton(
                icon: Icon(Icons.edit, size: 20, color: tone.foreground),
                tooltip: L10n.of(context).edit_group,
                onPressed: () => openGroupEditor(context, id: group.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCardContent extends StatelessWidget {
  final SubscriptionGroup group;
  final List<Subscription> members;
  final Color color;

  const _GroupCardContent({required this.group, required this.members, required this.color});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(group.iconData, size: 28, color: color),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(color: color)),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final entry in countByKind(members).entries) ...[
                    Icon(entry.key.icon, size: 15, color: color),
                    const SizedBox(width: 2),
                    Text('${entry.value}', style: textTheme.labelMedium?.copyWith(color: color)),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
