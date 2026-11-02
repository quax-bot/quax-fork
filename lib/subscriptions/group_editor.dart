import 'dart:convert';

import 'package:flutter/material.dart' as fm;
import 'package:flutter_iconpicker/Models/configuration.dart';
import 'package:flutter_iconpicker/flutter_iconpicker.dart';
import 'package:flutter_triple/flutter_triple.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/generated/l10n.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/subscriptions/_groups.dart';
import 'package:quax/subscriptions/_list.dart';
import 'package:quax/subscriptions/_search_field.dart';
import 'package:quax/subscriptions/group_editor_model.dart';
import 'package:quax/subscriptions/subscription_kind.dart';
import 'package:quax/subscriptions/subscriptions_page_model.dart';
import 'package:quax/subscriptions/users_model.dart';

/// The default color, then the color of each Material hue.
final List<Color?> _palette = [null, ...Colors.primaries];

final List<Color?> _quickColors = [null, Colors.red, Colors.purple, Colors.blue, Colors.green, Colors.orange];

final _quickIcons = [
  defaultGroupIcon,
  ...[
    'memory',
    'newspaper',
    'sports_soccer',
    'photo_camera',
    'palette',
    'science',
    'music_note',
    'sports_esports',
    'public',
    'restaurant',
  ].map((key) => jsonEncode({'pack': 'material', 'key': key})),
];

/// A new group starts with [initialMembers]. Returns whether the group was saved.
Future<bool> openGroupEditor(BuildContext context, {String? id, Set<String> initialMembers = const {}}) async =>
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GroupEditorScreen(id: id, initialMembers: initialMembers),
      ),
    ) ??
    false;

class GroupEditorScreen extends StatefulWidget {
  final String? id;
  final Set<String> initialMembers;

  const GroupEditorScreen({super.key, required this.id, required this.initialMembers});

  @override
  State<GroupEditorScreen> createState() => _GroupEditorScreenState();
}

class _GroupEditorScreenState extends State<GroupEditorScreen> {
  late final GroupEditorModel _model = GroupEditorModel(context.read<GroupsModel>());
  final TextEditingController _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _model.load(widget.id, widget.initialMembers, context.read<SubscriptionsModel>().state).then((state) {
      if (mounted) {
        _name.text = state.draft.name;
        _model.update(state);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _model.destroy();
    super.dispose();
  }

  Future<void> _save() async {
    if (await _model.save() && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScopedBuilder<GroupEditorModel, GroupEditorState?>(
      store: _model,
      onState: (_, state) {
        if (state == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return PopScope(
          canPop: !state.dirty || state.closing,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop && await _confirmDiscard(context) && context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Scaffold(
            appBar: _appBar(context, state),
            body: _GroupEditorBody(model: _model, state: state, nameController: _name),
          ),
        );
      },
    );
  }

  AppBar _appBar(BuildContext context, GroupEditorState state) {
    final l10n = L10n.of(context);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l10n.close,
        onPressed: () => Navigator.maybePop(context),
      ),
      title: Text(state.draft.id == null ? l10n.new_group : state.original.name),
      actions: [
        FilledButton(onPressed: state.closing || !state.dirty ? null : _save, child: Text(l10n.save)),
        if (state.draft.id == null)
          const SizedBox(width: 12)
        else
          PopupMenuButton<void>(
            tooltip: l10n.more_options,
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => _delete(context, state.draft.name),
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  title: Text(l10n.delete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, String name) async {
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.are_you_sure),
        content: Text(l10n.are_you_sure_you_want_to_delete_the_subscription_group_name_of_group(name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _model.delete();
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }
}

Future<bool> _confirmDiscard(BuildContext context) async {
  final l10n = L10n.of(context);
  final discard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.discard_changes),
      content: Text(l10n.discard_changes_description),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.keep_editing)),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.discard)),
      ],
    ),
  );
  return discard ?? false;
}

class _GroupEditorBody extends StatelessWidget {
  final GroupEditorModel model;
  final GroupEditorState state;
  final TextEditingController nameController;

  const _GroupEditorBody({required this.model, required this.state, required this.nameController});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final subscriptions = state.subscriptions;
    final searched = searchedSubscriptions(subscriptions, state.query.trim().toLowerCase());
    final shown = ofKind(searched, state.kind);
    // The members of the group as it opened stay first, so that ticking a box never moves a row
    final wereIn = shown.where((s) => state.original.members.contains(s.id)).toList();
    final others = shown.where((s) => !state.original.members.contains(s.id)).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Identity(model: model, state: state, nameController: nameController),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            // Brought to the top, so that the results show above the keyboard
            child: Builder(
              builder: (field) => CompactSearchField(
                onChanged: model.search,
                onTap: () => Scrollable.ensureVisible(field, duration: const Duration(milliseconds: 200)),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: KindFilters(searched: searched, chosen: state.kind, onChosen: model.showKind),
        ),
        ..._section(context, l10n.section_with_count(l10n.in_the_group, state.draft.members.length), wereIn),
        ..._section(context, l10n.other_subscriptions, others),
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16)),
      ],
    );
  }

  List<Widget> _section(BuildContext context, String title, List<Subscription> subscriptions) {
    if (subscriptions.isEmpty) {
      return const [];
    }
    final theme = Theme.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        ),
      ),
      SliverList.builder(
        itemCount: subscriptions.length,
        itemBuilder: (_, index) {
          final subscription = subscriptions[index];
          return CheckboxListTile(
            key: ValueKey(subscriptionKey(subscription)),
            secondary: SubscriptionAvatar(subscription: subscription),
            title: Text(subscription.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              subscriptionLine(L10n.of(context), subscription),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            value: state.draft.members.contains(subscription.id),
            onChanged: (_) => model.toggleMember(subscription.id),
          );
        },
      ),
    ];
  }
}

class _Identity extends StatelessWidget {
  final GroupEditorModel model;
  final GroupEditorState state;
  final TextEditingController nameController;

  const _Identity({required this.model, required this.state, required this.nameController});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppearanceButton(
            tone: groupTone(context, state.draft.color),
            icon: state.draft.icon,
            onPressed: () => _openAppearance(context, model),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: nameController,
              onChanged: model.rename,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.name,
                border: const OutlineInputBorder(),
                errorText: state.showNameError ? l10n.please_enter_a_name : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The group's icon on its color. A small palette badge says it can be changed.
class _AppearanceButton extends StatelessWidget {
  final GroupTone tone;
  final String icon;
  final VoidCallback onPressed;

  const _AppearanceButton({required this.tone, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape = BorderRadius.circular(18);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Tooltip(
          message: L10n.of(context).color_and_icon,
          child: Material(
            color: tone.background,
            borderRadius: shape,
            child: InkWell(
              borderRadius: shape,
              onTap: onPressed,
              child: SizedBox.square(
                dimension: 56,
                child: Icon(deserializeIconData(icon), size: 28, color: tone.foreground),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          end: -4,
          bottom: -4,
          child: IgnorePointer(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surface, width: 2),
              ),
              child: Icon(Icons.palette_outlined, size: 14, color: colors.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

void _openAppearance(BuildContext context, GroupEditorModel model) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => ScopedBuilder<GroupEditorModel, GroupEditorState?>(
    store: model,
    onState: (context, state) => state == null ? const SizedBox.shrink() : _Appearance(model: model, state: state),
  ),
);

class _Appearance extends StatelessWidget {
  final GroupEditorModel model;
  final GroupEditorState state;

  const _Appearance({required this.model, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(l10n.color),
          _ColorChoices(
            selected: state.draft.color,
            all: state.allColors,
            onPicked: model.pickColor,
            onMore: model.showAllColors,
          ),
          const SizedBox(height: 16),
          _Label(l10n.icon),
          _IconChoices(
            selected: state.draft.icon,
            tone: groupTone(context, state.draft.color),
            onPicked: model.pickIcon,
          ),
        ],
      ),
    );
  }
}

Widget _grid(int columns, List<Widget> children) => GridView.count(
  crossAxisCount: columns,
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  padding: EdgeInsets.zero,
  mainAxisSpacing: 4,
  children: children.map((child) => Center(child: child)).toList(),
);

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

class _ColorChoices extends StatelessWidget {
  final Color? selected;
  final bool all;
  final ValueChanged<Color?> onPicked;
  final VoidCallback onMore;

  const _ColorChoices({required this.selected, required this.all, required this.onPicked, required this.onMore});

  bool _isSelected(Color? color) => color?.toARGB32() == selected?.toARGB32();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colors = Theme.of(context).colorScheme;
    // A color picked outside the palette, or outside the quick colors, is shown first
    final shown = all ? _palette : _quickColors;
    final choices = shown.any(_isSelected) ? shown : [selected, ...shown.take(shown.length - 1)];
    return _grid(7, [
      ...choices.map(
        (color) => _ColorDot(
          color: color,
          label: color == null ? l10n.default_color : l10n.color_number(_palette.indexOf(color) + 1),
          selected: _isSelected(color),
          onTap: () => onPicked(color),
        ),
      ),
      if (!all)
        IconButton(
          tooltip: l10n.more_colors,
          style: IconButton.styleFrom(
            foregroundColor: colors.primary,
            shape: CircleBorder(side: BorderSide(color: colors.outlineVariant)),
            fixedSize: const Size(44, 44),
          ),
          icon: const Icon(Icons.add),
          onPressed: onMore,
        ),
    ]);
  }
}

class _ColorDot extends StatelessWidget {
  final Color? color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({required this.color, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tone = groupTone(context, color);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: tone.background,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? tone.foreground : Colors.transparent, width: 2),
          ),
          child: selected ? Icon(Icons.check, size: 20, color: tone.foreground) : null,
        ),
      ),
    );
  }
}

class _IconChoices extends StatelessWidget {
  final String selected;
  final GroupTone tone;
  final ValueChanged<String> onPicked;

  const _IconChoices({required this.selected, required this.tone, required this.onPicked});

  Future<void> _pickAnother(BuildContext context) async {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final icon = await showIconPicker(
      context,
      configuration: SinglePickerConfiguration(
        iconPackModes: [IconPack.material],
        preSelected: _pickerIcon(selected),
        title: Text(l10n.icon, style: theme.textTheme.headlineSmall),
        closeChild: Text(l10n.close, style: TextStyle(color: theme.colorScheme.primary)),
        searchHintText: l10n.search,
        noResultsText: l10n.no_results_for,
        iconPickerShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        iconSize: 38,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        iconBuilder: (context, icon, isSelected, onTap) => _PickerIcon(
          icon: icon,
          selected: isSelected,
          tone: tone,
          onTap: () => onTap(icon, onSelected: () => Navigator.pop(context, icon)),
        ),
      ),
    );
    if (icon != null) {
      onPicked(jsonEncode(serializeIcon(icon)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icons = [if (!_quickIcons.contains(selected)) selected, ..._quickIcons];
    return _grid(6, [
      ...icons.indexed.map((entry) {
        final (index, icon) = entry;
        final isSelected = icon == selected;
        return IconButton(
          isSelected: isSelected,
          style: IconButton.styleFrom(
            backgroundColor: isSelected ? tone.background : colors.surfaceContainerHigh,
            foregroundColor: isSelected ? tone.foreground : colors.onSurfaceVariant,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            fixedSize: const Size(48, 48),
          ),
          icon: Icon(deserializeIconData(icon), semanticLabel: L10n.of(context).icon_number(index + 1)),
          onPressed: () => onPicked(icon),
        );
      }),
      // The icon picker uses Flutter's own material library, so it needs its own theme
      fm.Theme(
        data: _pickerTheme(Theme.of(context)),
        child: Builder(
          builder: (themed) => IconButton(
            tooltip: L10n.of(context).pick_an_icon,
            style: IconButton.styleFrom(
              foregroundColor: colors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colors.outlineVariant),
              ),
              fixedSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.more_horiz),
            onPressed: () => _pickAnother(themed),
          ),
        ),
      ),
    ]);
  }
}

IconPickerIcon? _pickerIcon(String serialized) {
  try {
    return deserializeIcon(Map<String, dynamic>.from(jsonDecode(serialized) as Map));
  } catch (_) {
    return null;
  }
}

class _PickerIcon extends StatelessWidget {
  final IconPickerIcon icon;
  final bool selected;
  final GroupTone tone;
  final VoidCallback onTap;

  const _PickerIcon({required this.icon, required this.selected, required this.tone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? tone.background : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Icon(
          icon.data,
          size: 26,
          semanticLabel: icon.name.replaceAll('_', ' '),
          color: selected ? tone.foreground : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

fm.ThemeData _pickerTheme(ThemeData theme) {
  final colors = theme.colorScheme;
  return fm.ThemeData(
    colorScheme: fm.ColorScheme.fromSeed(seedColor: colors.primary, brightness: theme.brightness),
    inputDecorationTheme: fm.InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      border: fm.OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
    ),
  );
}
