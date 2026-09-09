import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/tangram/tangram.dart';
import 'tangram_board.dart';

/// The seven pieces waiting to be used. A piece already on the board keeps
/// its place in the row, greyed and ticked, so the row never shifts about.
class TangramTray extends StatelessWidget {
  const TangramTray({
    super.key,
    required this.state,
    required this.onSelect,
  });

  final TangramState state;
  final void Function(TangramPiece piece) onSelect;

  static const double maxSlot = 54;
  static const double minSlot = 44;
  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final pieces = TangramPiece.values;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = (constraints.maxWidth - (pieces.length - 1) * _gap) / pieces.length;
          final perRow = wide >= minSlot ? pieces.length : (pieces.length / 2).ceil();
          final width = (constraints.maxWidth - (perRow - 1) * _gap) / perRow;
          final slot = width > maxSlot ? maxSlot : width;
          final rows = [
            for (var start = 0; start < pieces.length; start += perRow)
              pieces.sublist(start, start + perRow > pieces.length ? pieces.length : start + perRow),
          ];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: _gap),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < row.length; i++) ...[
                        if (i > 0) const SizedBox(width: _gap),
                        _Slot(
                          piece: row[i],
                          size: slot,
                          placed: state.isPlaced(row[i]),
                          selected: state.selected == row[i],
                          colors: colors,
                          onSelect: () => onSelect(row[i]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.piece,
    required this.size,
    required this.placed,
    required this.selected,
    required this.colors,
    required this.onSelect,
  });

  final TangramPiece piece;
  final double size;
  final bool placed;
  final bool selected;
  final GameColors colors;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final icon = TangramPieceIcon(
      piece: piece,
      size: size - 8,
      selected: selected,
      faded: placed,
    );
    final body = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? Theme.of(context).colorScheme.secondary : colors.rule),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          icon,
          if (placed)
            Positioned(
              right: 2,
              bottom: 2,
              child: Icon(Icons.check, size: 14, color: colors.correct),
            ),
        ],
      ),
    );
    return Semantics(
      key: ValueKey('tangram-tray-${piece.slug}'),
      button: true,
      enabled: !placed,
      selected: selected,
      label: placed
          ? '${piece.label}, on the board'
          : '${piece.label}, in the tray. Drag it onto the figure, or select it and press Enter.',
      excludeSemantics: true,
      child: placed
          ? body
          : Draggable<TangramPiece>(
              data: piece,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: _Feedback(piece: piece),
              childWhenDragging: Opacity(opacity: 0.3, child: body),
              onDragStarted: onSelect,
              child: GestureDetector(onTap: onSelect, child: body),
            ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.piece});

  final TangramPiece piece;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(-40, -40),
      child: Material(
        color: Colors.transparent,
        child: TangramPieceIcon(piece: piece, size: 80, selected: true),
      ),
    );
  }
}

/// Turn, turn over, send back, undo, hint and reset. Every target is at
/// least 44dp.
class TangramControls extends StatelessWidget {
  const TangramControls({
    super.key,
    required this.canTurn,
    required this.canFlip,
    required this.canTakeBack,
    required this.canUndo,
    required this.canReset,
    required this.onTurn,
    required this.onFlip,
    required this.onTakeBack,
    required this.onUndo,
    required this.onHint,
    required this.onReset,
  });

  final bool canTurn;
  final bool canFlip;
  final bool canTakeBack;
  final bool canUndo;
  final bool canReset;
  final VoidCallback onTurn;
  final VoidCallback onFlip;
  final VoidCallback onTakeBack;
  final VoidCallback onUndo;
  final VoidCallback onHint;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          _Action(id: 'turn', icon: Icons.rotate_right, label: 'Turn', onPressed: canTurn ? onTurn : null),
          _Action(id: 'flip', icon: Icons.flip, label: 'Over', onPressed: canFlip ? onFlip : null),
          _Action(id: 'tray', icon: Icons.undo_outlined, label: 'Tray', onPressed: canTakeBack ? onTakeBack : null),
          _Action(id: 'undo', icon: Icons.replay, label: 'Undo', onPressed: canUndo ? onUndo : null),
          _Action(id: 'hint', icon: Icons.lightbulb_outline, label: 'Hint', onPressed: onHint),
          _Action(id: 'reset', icon: Icons.clear_all, label: 'Reset', onPressed: canReset ? onReset : null),
        ],
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
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        key: ValueKey('tangram-$id'),
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            minimumSize: const Size(44, 52),
            splashFactory: MediaQuery.disableAnimationsOf(context) ? NoSplash.splashFactory : null,
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
