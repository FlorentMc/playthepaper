import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Number pad and move controls. Every target is at least 44dp; the pad
/// wraps onto two rows when a single row would make keys too narrow.
class SudokuControls extends StatelessWidget {
  const SudokuControls({
    super.key,
    required this.remaining,
    required this.notesMode,
    required this.canUndo,
    required this.canRedo,
    required this.canEdit,
    required this.onDigit,
    required this.onNotes,
    required this.onUndo,
    required this.onRedo,
    required this.onErase,
    required this.onHint,
  });

  /// Digits left to place, indexed 1–9.
  final List<int> remaining;
  final bool notesMode;
  final bool canUndo;
  final bool canRedo;

  /// True when the selected cell can be edited.
  final bool canEdit;
  final void Function(int digit) onDigit;
  final VoidCallback onNotes;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onErase;
  final VoidCallback onHint;

  static const double _keyHeight = 52;
  static const double _minKeyWidth = 44;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final noSplash = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final oneRow = constraints.maxWidth >= 9 * _minKeyWidth + 8 * _gap;
              final rows = oneRow
                  ? [
                      [1, 2, 3, 4, 5, 6, 7, 8, 9]
                    ]
                  : [
                      [1, 2, 3, 4, 5],
                      [6, 7, 8, 9]
                    ];
              final perRow = oneRow ? 9 : 5;
              final width = (constraints.maxWidth - (perRow - 1) * _gap) / perRow;
              return Column(
                children: [
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: _gap),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var k = 0; k < row.length; k++) ...[
                            if (k > 0) const SizedBox(width: _gap),
                            _DigitKey(
                              digit: row[k],
                              remaining: remaining[row[k]],
                              width: width,
                              noSplash: noSplash,
                              onTap: remaining[row[k]] > 0 ? () => onDigit(row[k]) : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          Row(
            children: [
              _Action(
                id: 'undo',
                icon: Icons.undo,
                label: 'Undo',
                onPressed: canUndo ? onUndo : null,
              ),
              _Action(
                id: 'redo',
                icon: Icons.redo,
                label: 'Redo',
                onPressed: canRedo ? onRedo : null,
              ),
              _Action(
                id: 'erase',
                icon: Icons.backspace_outlined,
                label: 'Erase',
                onPressed: canEdit ? onErase : null,
              ),
              _Action(
                id: 'notes',
                icon: notesMode ? Icons.edit_note : Icons.edit_note_outlined,
                label: notesMode ? 'Notes on' : 'Notes off',
                onPressed: onNotes,
                selected: notesMode,
              ),
              _Action(
                id: 'hint',
                icon: Icons.lightbulb_outline,
                label: 'Hint',
                onPressed: canEdit ? onHint : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DigitKey extends StatelessWidget {
  const _DigitKey({
    required this.digit,
    required this.remaining,
    required this.width,
    required this.noSplash,
    required this.onTap,
  });

  final int digit;
  final int remaining;
  final double width;
  final bool noSplash;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final enabled = onTap != null;
    final ink = enabled ? theme.colorScheme.onSurface : colors.absent;
    return Semantics(
      key: ValueKey('sudoku-key-$digit'),
      button: true,
      enabled: enabled,
      label: '$digit, $remaining remaining',
      excludeSemantics: true,
      child: Material(
        color: enabled ? colors.cellHighlight : colors.cell,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          splashFactory: noSplash ? NoSplash.splashFactory : null,
          onTap: onTap,
          child: SizedBox(
            width: width,
            // Scales with the text so enlarged type never clips the count.
            height: SudokuControls._keyHeight * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$digit', style: PaperTheme.body(size: 22, weight: 600, color: ink)),
                Text('$remaining', style: PaperTheme.body(size: 11, weight: 500, color: colors.subtle)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        key: ValueKey('sudoku-$id'),
        button: true,
        enabled: onPressed != null,
        toggled: id == 'notes' ? selected : null,
        label: label,
        excludeSemantics: true,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            minimumSize: const Size(44, 52),
            backgroundColor: selected ? theme.colorScheme.surfaceContainerHighest : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 2),
              Text(label, style: PaperTheme.body(size: 12, weight: 600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
