import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/generated/l10n.dart';
import 'package:quax/group/group_screen.dart';
import 'package:quax/subscriptions/group_editor.dart';
import 'package:quax/subscriptions/subscription_kind.dart';

typedef GroupTone = ({Color background, Color foreground});

final _schemes = <(int, int, Brightness), ColorScheme>{};

/// The color of a group, adapted to the theme: leaning toward its accent color, light or dark like it.
GroupTone groupTone(BuildContext context, Color? color) {
  final theme = Theme.of(context);
  final primary = theme.colorScheme.primary;
  if (color == null) {
    return (background: theme.colorScheme.secondaryContainer, foreground: theme.colorScheme.onSecondaryContainer);
  }
  final scheme = _schemes.putIfAbsent((color.toARGB32(), primary.toARGB32(), theme.brightness),
      () => ColorScheme.fromSeed(seedColor: color.harmonizeWith(primary), brightness: theme.brightness));
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
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  const GroupsHeader({super.key, required this.collapsed, required this.onToggleCollapsed});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
      child: Row(
        children: [
          Expanded(child: SectionTitle(l10n.groups)),
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

  const SectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant));
  }
}

class GroupsCarousel extends StatelessWidget {
  final List<SubscriptionGroup> groups;

  const GroupsCarousel({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _tileSize + 12,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 12),
        itemCount: groups.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) =>
            index < groups.length ? GroupTile(group: groups[index]) : const _NewGroupTile(),
      ),
    );
  }
}

const double _tileSize = 84;

/// Opens the feed of the group, or its editor on a long press.
class GroupTile extends StatelessWidget {
  final SubscriptionGroup group;

  const GroupTile({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final tone = groupTone(context, group.color);
    void edit() => openGroupEditor(context, id: group.id);
    return Semantics(
      customSemanticsActions: {CustomSemanticsAction(label: L10n.of(context).edit_group): edit},
      child: _Tile(
        icon: group.iconData,
        label: group.name,
        background: tone.background,
        foreground: tone.foreground,
        onTap: () => Navigator.pushNamed(context, routeGroup,
            arguments: GroupScreenArguments(id: group.id, name: group.name)),
        onLongPress: edit,
      ),
    );
  }
}

class _NewGroupTile extends StatelessWidget {
  const _NewGroupTile();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Tile(
      icon: Icons.add,
      label: L10n.of(context).new_group,
      foreground: colors.primary,
      border: BorderSide(color: colors.outlineVariant),
      onTap: () => openGroupEditor(context),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? background;
  final Color foreground;
  final BorderSide border;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _Tile(
      {required this.icon,
      required this.label,
      this.background,
      required this.foreground,
      this.border = BorderSide.none,
      required this.onTap,
      this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _tileSize,
      child: Material(
        color: background ?? Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: border),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: foreground),
                const SizedBox(height: 4),
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground, height: 1.25)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
