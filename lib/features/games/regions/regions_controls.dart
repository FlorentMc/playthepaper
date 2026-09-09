import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Number pad and move controls. Every target is at least 44dp.
class RegionsControls extends StatelessWidget {
  const RegionsControls({
    super.key,
    required this.maxDigit,
    required this.digitEnabled,
    required this.notesMode,
    required this.canUndo,
    required this.canEdit,
    required this.canCheck,
    required this.onDigit,
    required this.onNotes,
    required this.onUndo,
    required this.onErase,
    required this.onCheck,
    required this.onReveal,
  });

  /// The largest region on the board, so the highest key shown.
  final int maxDigit;

  /// Whether a digit can go in the selected cell.
  final bool Function(int digit) digitEnabled;
  final bool notesMode;
  final bool canUndo;

  /// True when the selected cell can be edited.
  final bool canEdit;

  /// True when the player has filled at least one cell.
  final bool canCheck;
  final void Function(int digit) onDigit;
  final VoidCallback onNotes;
  final VoidCallback onUndo;
  final VoidCallback onErase;
  final VoidCallback onCheck;
  final VoidCallback onReveal;

  static const double _keyHeight = 52;
  static const double _maxKeyWidth = 72;
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
              final fit = (constraints.maxWidth - (maxDigit - 1) * _gap) / maxDigit;
              final width = fit < _maxKeyWidth ? fit : _maxKeyWidth;
              return Padding(
                padding: const EdgeInsets.only(bottom: _gap),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var d = 1; d <= maxDigit; d++) ...[
                      if (d > 1) const SizedBox(width: _gap),
                      _DigitKey(
                        digit: d,
                        width: width,
                        noSplash: noSplash,
                        onTap: digitEnabled(d) ? () => onDigit(d) : null,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          Row(
            children: [
              _Action(id: 'undo', icon: Icons.undo, label: 'Undo', onPressed: canUndo ? onUndo : null),
              _Action(id: 'erase', icon: Icons.backspace_outlined, label: 'Erase', onPressed: canEdit ? onErase : null),
              _Action(
                id: 'notes',
                icon: notesMode ? Icons.edit_note : Icons.edit_note_outlined,
                label: notesMode ? 'Notes on' : 'Notes off',
                onPressed: onNotes,
                selected: notesMode,
              ),
              _Action(id: 'check', icon: Icons.fact_check_outlined, label: 'Check', onPressed: canCheck ? onCheck : null),
              _Action(id: 'reveal', icon: Icons.lightbulb_outline, label: 'Reveal', onPressed: canEdit ? onReveal : null),
            ],
          ),
        ],
      ),
    );
  }
}

class _DigitKey extends StatelessWidget {
  const _DigitKey({required this.digit, required this.width, required this.noSplash, required this.onTap});

  final int digit;
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
      key: ValueKey('regions-key-$digit'),
      button: true,
      enabled: enabled,
      label: '$digit',
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
            height: RegionsControls._keyHeight,
            child: Center(child: Text('$digit', style: PaperTheme.body(size: 22, weight: 600, color: ink))),
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
        key: ValueKey('regions-$id'),
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
