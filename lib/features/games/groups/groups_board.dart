import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/groups/groups.dart';

/// One word tile. Selection is shown by a tick and a heavier border as well
/// as by the fill, so the state never rests on colour alone.
class GroupsTile extends StatelessWidget {
  const GroupsTile({
    super.key,
    required this.text,
    required this.selected,
    required this.focused,
    required this.position,
    required this.count,
    this.onTap,
  });

  final String text;
  final bool selected;
  final bool focused;

  /// One-based place in the grid, for the spoken label.
  final int position;
  final int count;
  final VoidCallback? onTap;

  /// A two-word tile sets on two lines, so the longest word decides how far
  /// the text has to shrink rather than the whole phrase.
  static List<String> _lines(String text) {
    final words = text.toUpperCase().split(' ');
    if (words.length < 2) return [text.toUpperCase()];
    return [words.first, words.sublist(1).join(' ')];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final instant = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$text, tile $position of $count, ${selected ? 'picked' : 'not picked'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : const Duration(milliseconds: 120),
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? colors.cellSelected : colors.cell,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: focused ? theme.colorScheme.onSurface : colors.cellBorder,
              width: focused || selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected)
                Icon(Icons.check, size: 14, color: theme.colorScheme.onSurface)
              else
                const SizedBox(height: 14),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final line in _lines(text))
                        Text(
                          line,
                          textAlign: TextAlign.center,
                          style: PaperTheme.body(size: 13, weight: 600, color: theme.colorScheme.onSurface),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group that has been found, or revealed at the end: its mark, its title,
/// its four words and one sentence saying why they belong together.
class GroupsBand extends StatelessWidget {
  const GroupsBand({super.key, required this.group, required this.index, required this.found});

  final GroupsGroup group;

  /// The group's place in the content, which fixes its mark and its tint.
  final int index;

  /// False when the game ended before the player found it.
  final bool found;

  static const List<Color> _tints = [Color(0x332E7D5B), Color(0x33C08A1E), Color(0x333A6EA5)];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    return Container(
      key: ValueKey('groups-band-$index'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: _tints[index],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: found ? theme.colorScheme.onSurface : colors.cellBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(GroupsState.markFor(index), style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(group.title, style: PaperTheme.display(size: 17, color: theme.colorScheme.onSurface)),
              ),
              if (!found)
                Text('Not found', style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 2),
          Text(group.members.join(' · '), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 2),
          Text(group.explanation, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
