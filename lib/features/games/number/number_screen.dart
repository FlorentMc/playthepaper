import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/number/number_engine.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../news/story_link.dart';
import '../../play/play_context.dart';

/// The Number: estimate the figure behind the story on a bounded slider.
class NumberScreen extends StatefulWidget {
  const NumberScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'The Number',
    paragraphs: [
      'One question, one figure. Set your estimate with the slider or type it in, then submit.',
      'A comparison figure is given for scale. It is true, and it is there to help.',
      'You are scored on how far off you are, as a percentage of the real figure. Within the band counts as solved.',
    ],
  );

  @override
  State<NumberScreen> createState() => _NumberScreenState();
}

class _NumberScreenState extends State<NumberScreen> {
  late final NumberPuzzle _puzzle;
  late final NumberReveal _reveal;
  late NumberState _state;
  late final TextEditingController _controller;
  final FocusNode _fieldFocus = FocusNode();
  GameResult? _result;
  String? _fieldError;
  bool _completing = false;

  PlayContext get play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = NumberPuzzle.parse(play.record.payload);
    _reveal = NumberReveal.parse(play.record.reveal, _puzzle);
    _result = play.existingResult();
    final saved = _result == null ? play.loadProgress() : null;
    if (saved == null) {
      _state = NumberState(value: _puzzle.snap((_puzzle.min + _puzzle.max) / 2));
    } else {
      final restored = NumberState.fromJson(saved);
      _state = NumberState(value: _puzzle.snap(restored.value), submitted: restored.submitted);
    }
    _controller = TextEditingController(text: _plain(_state.value));
    _fieldFocus.addListener(() {
      if (!_fieldFocus.hasFocus) _normaliseField();
    });
    if (_result == null && _state.submitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  String _plain(double v) => v.toStringAsFixed(_puzzle.decimals);

  double? _parseField() {
    final raw = _controller.text.replaceAll(',', '').replaceAll(' ', '').trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  void _normaliseField() {
    final text = _plain(_state.value);
    if (_controller.text != text) {
      _controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    if (_fieldError != null) setState(() => _fieldError = null);
  }

  Future<void> _setValue(double v, {bool fromSlider = false}) async {
    if (_state.submitted) return;
    final snapped = _puzzle.snap(v);
    setState(() {
      _state = _state.withValue(snapped);
      _fieldError = null;
    });
    if (fromSlider) _normaliseField();
    await play.saveProgress(_state.toJson());
  }

  void _onFieldChanged(String _) {
    final parsed = _parseField();
    if (parsed == null) {
      setState(() => _fieldError = 'Enter a number');
      return;
    }
    if (parsed < _puzzle.min || parsed > _puzzle.max) {
      setState(() => _fieldError = 'Between ${_puzzle.format(_puzzle.min)} and ${_puzzle.format(_puzzle.max)}');
      return;
    }
    _setValue(parsed);
  }

  Future<void> _submit() async {
    if (_state.submitted) return;
    final parsed = _parseField();
    if (parsed != null && _puzzle.snap(parsed) != _state.value) {
      await _setValue(parsed);
    }
    _normaliseField();
    setState(() => _state = _state.submit());
    await play.saveProgress(_state.toJson());
    await _finish();
  }

  Future<void> _finish() async {
    if (_completing || _result != null || !_state.submitted) return;
    _completing = true;
    final guess = _state.value;
    final result = GameResult(
      puzzleId: play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: _reveal.solved(guess),
      errorPct: _reveal.errorPct(guess),
      isArchivePlay: play.isArchivePlay,
    );
    setState(() => _result = result);
    await play.complete(context, result, revealTitle: 'The real figure', reveal: _revealView(guess));
  }

  Widget _revealView(double? guess) => NumberRevealView(
        puzzle: _puzzle,
        reveal: _reveal,
        guess: guess,
        errorPct: _result?.errorPct,
        url: storyUrlFor(play),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final finished = _result != null;
    final locked = finished || _state.submitted;

    return GameShell(
      game: play.record.game,
      date: play.record.date,
      difficulty: play.record.difficulty,
      help: NumberScreen.help,
      isArchivePlay: play.isArchivePlay,
      puzzleId: play.record.id.toString(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          FriendLine(challenge: play.challenge),
          Text(_puzzle.question, style: DaypencilTheme.display(size: 24, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FOR SCALE', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 4),
                  Text(_puzzle.comparison, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (finished) ...[
            Text(
              _result!.errorPct == null ? 'Finished' : '${_result!.errorPct!.round()}% off',
              style: DaypencilTheme.display(size: 30, color: theme.colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _result!.solved ? 'Within the band · solved' : 'Outside the band',
              style: theme.textTheme.labelMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => play.showResult(context, _result!, revealTitle: 'The real figure', reveal: _revealView(null)),
              child: const Text('See result'),
            ),
          ] else ...[
            Semantics(
              label: 'Your estimate: ${_puzzle.formatWithUnit(_state.value)}',
              excludeSemantics: true,
              child: Text(
                _puzzle.formatWithUnit(_state.value),
                style: DaypencilTheme.display(size: 32, color: theme.colorScheme.onSurface),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Slider(
              value: _state.value,
              min: _puzzle.min,
              max: _puzzle.max,
              divisions: _puzzle.divisions,
              label: _puzzle.format(_state.value),
              semanticFormatterCallback: (v) => _puzzle.formatWithUnit(v),
              onChanged: locked ? null : (v) => _setValue(v, fromSlider: true),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_puzzle.format(_puzzle.min), style: theme.textTheme.labelSmall),
                Text(_puzzle.format(_puzzle.max), style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              focusNode: _fieldFocus,
              enabled: !locked,
              keyboardType: TextInputType.numberWithOptions(decimal: _puzzle.decimals > 0),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\- ]'))],
              textInputAction: TextInputAction.done,
              onChanged: _onFieldChanged,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Estimate in ${_puzzle.unit}',
                suffixText: _puzzle.unit,
                errorText: _fieldError,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.rule)),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: locked ? null : _submit,
              child: const Text('Submit estimate'),
            ),
          ],
        ],
      ),
    );
  }
}

String _pct(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// The real figure, the player's estimate, the context, and a story link.
class NumberRevealView extends StatelessWidget {
  const NumberRevealView({
    super.key,
    required this.puzzle,
    required this.reveal,
    required this.guess,
    required this.errorPct,
    required this.url,
  });

  final NumberPuzzle puzzle;
  final NumberReveal reveal;
  final double? guess;
  final double? errorPct;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final off = errorPct ?? (guess == null ? null : reveal.errorPct(guess!));
    final String estimate;
    if (guess != null) {
      estimate = 'Your estimate: ${puzzle.formatWithUnit(guess!)} · ${off!.round()}% off';
    } else if (off != null) {
      estimate = 'Your estimate was ${off.round()}% off';
    } else {
      estimate = 'No estimate recorded';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The real figure: ${puzzle.formatWithUnit(reveal.answer)}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(estimate, style: theme.textTheme.bodyMedium),
        Text(
          'Solved within ${_pct(reveal.zeroPct)}% of the real figure.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Text(reveal.context, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        StoryLink(url: url),
      ],
    );
  }
}
