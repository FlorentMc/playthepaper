import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Feedback state for a key, mirrored from the board.
enum KeyState { unknown, absent, misplaced, correct }

/// A QWERTY on-screen keyboard that also listens to the physical keyboard.
/// Used by Daily Word and the Mini Crossword. Keys are at least 44dp tall and
/// carry their letter as a semantic label.
class LetterKeyboard extends StatefulWidget {
  const LetterKeyboard({
    super.key,
    required this.onLetter,
    required this.onBackspace,
    this.onEnter,
    this.keyStates = const {},
    this.enabled = true,
    this.showEnter = true,
    this.autofocus = true,
    this.onArrow,
  });

  final void Function(String letter) onLetter;
  final VoidCallback onBackspace;
  final VoidCallback? onEnter;
  final Map<String, KeyState> keyStates;
  final bool enabled;
  final bool showEnter;
  final bool autofocus;

  /// Arrow keys and tab, for grid navigation.
  final void Function(LogicalKeyboardKey key)? onArrow;

  static const rows = ['QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM'];

  @override
  State<LetterKeyboard> createState() => _LetterKeyboardState();
}

class _LetterKeyboardState extends State<LetterKeyboard> {
  final FocusNode _focus = FocusNode(debugLabel: 'letter-keyboard');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      widget.onBackspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      widget.onEnter?.call();
      return KeyEventResult.handled;
    }
    if (widget.onArrow != null &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.tab ||
            key == LogicalKeyboardKey.space)) {
      widget.onArrow!(key);
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null && ch.length == 1 && RegExp(r'[A-Za-z]').hasMatch(ch)) {
      widget.onLetter(ch.toUpperCase());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: () => _focus.requestFocus(),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < LetterKeyboard.rows.length; r++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (r == 2 && widget.showEnter)
                        _Key(
                          label: 'ENTER',
                          flex: 3,
                          onTap: widget.enabled ? widget.onEnter : null,
                          background: colors.cellHighlight,
                          foreground: theme.colorScheme.onSurface,
                          semantics: 'Enter',
                        ),
                      for (final ch in LetterKeyboard.rows[r].split(''))
                        _Key(
                          label: ch,
                          flex: 2,
                          onTap: widget.enabled ? () => widget.onLetter(ch) : null,
                          background: _bg(widget.keyStates[ch] ?? KeyState.unknown, colors),
                          foreground: _fg(widget.keyStates[ch] ?? KeyState.unknown, colors, theme),
                          semantics: '$ch${_stateLabel(widget.keyStates[ch])}',
                        ),
                      if (r == 2)
                        _Key(
                          label: '⌫',
                          flex: 3,
                          onTap: widget.enabled ? widget.onBackspace : null,
                          background: colors.cellHighlight,
                          foreground: theme.colorScheme.onSurface,
                          semantics: 'Backspace',
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _stateLabel(KeyState? s) => switch (s) {
        KeyState.correct => ', in the word and in place',
        KeyState.misplaced => ', in the word, wrong place',
        KeyState.absent => ', not in the word',
        _ => '',
      };

  Color _bg(KeyState s, GameColors c) => switch (s) {
        KeyState.correct => c.correct,
        KeyState.misplaced => c.misplaced,
        KeyState.absent => c.absent,
        KeyState.unknown => c.cellHighlight,
      };

  Color _fg(KeyState s, GameColors c, ThemeData t) => s == KeyState.unknown ? t.colorScheme.onSurface : c.onFeedback;
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.flex,
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.semantics,
  });

  final String label;
  final int flex;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Semantics(
          button: true,
          label: semantics,
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(5),
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: onTap,
              child: SizedBox(
                height: 48,
                child: Center(
                  child: Text(
                    label,
                    style: PaperTheme.body(size: label.length > 1 ? 12 : 17, weight: 600, color: foreground),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
