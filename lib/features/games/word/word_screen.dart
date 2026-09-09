import 'package:flutter/material.dart';

import '../../../content/models.dart';
import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/word/word_engine.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../../shared/widgets/letter_keyboard.dart';
import '../../play/play_context.dart';
import '../../../shared/widgets/story_widgets.dart';
import 'word_board.dart';
import 'word_dictionary.dart';

/// Daily Word: a six-letter word, the first letter given, six guesses.
class WordScreen extends StatefulWidget {
  const WordScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Daily Word',
    paragraphs: [
      'Find the six-letter word in six guesses. The first letter is given and every guess must start with it. '
          'Guesses must be real words.',
      'After each guess the tiles tell you how close you were. A tick means the letter is in the right place. '
          'A dot means it is in the word but somewhere else. A plain grey tile means it is not in the word.',
      'A letter is only marked as many times as it appears in the word. Exact matches count first; '
          'any extra copies in your guess are shown as grey.',
    ],
    example: _helpExample,
  );

  @override
  State<WordScreen> createState() => _WordScreenState();
}

Widget _helpExample(BuildContext context) {
  final theme = Theme.of(context);
  Widget item(String letter, LetterFeedback feedback, String caption) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      WordTile(size: 48, letter: letter, feedback: feedback, semanticsLabel: '$letter, $caption'),
      const SizedBox(height: 6),
      Text(caption, style: theme.textTheme.labelSmall),
    ],
  );
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      item('S', LetterFeedback.correct, 'Right place'),
      item('T', LetterFeedback.misplaced, 'Wrong place'),
      item('R', LetterFeedback.absent, 'Not in word'),
    ],
  );
}

class _WordScreenState extends State<WordScreen> with SingleTickerProviderStateMixin {
  late final WordPuzzle _puzzle;
  late final AnimationController _shake;
  final GlobalKey _keyboardKey = GlobalKey();
  late WordState _state;
  late String _typed;
  Set<String>? _dictionary;
  GameResult? _result;
  bool _finishing = false;

  PlayContext get play => widget.play;

  String? get _teaser => _text(play.record.payload['teaser']);
  String? get _excerpt => _text(play.record.reveal['excerpt']);

  static String? _text(Object? value) => value is String && value.isNotEmpty ? value : null;

  @override
  void initState() {
    super.initState();
    _puzzle = WordPuzzle.parse(play.record.payload, play.record.reveal);
    _typed = _puzzle.firstLetter;
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _result = play.existingResult();
    _state = _restore();
    WordDictionary.load().then((words) {
      if (mounted) setState(() => _dictionary = words);
    });
    if (_result == null && _state.isOver) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  WordState _restore() {
    final saved = play.loadProgress();
    if (saved == null) return WordState.initial(_puzzle);
    try {
      return WordState.fromJson(_puzzle, saved);
    } on FormatException {
      return WordState.initial(_puzzle);
    }
  }

  bool get _canType => _result == null && !_finishing && !_state.isOver;

  void _onLetter(String letter) {
    if (!_canType || _typed.length >= _puzzle.length) return;
    setState(() => _typed += letter);
  }

  void _onBackspace() {
    if (!_canType || _typed.length <= 1) return;
    setState(() => _typed = _typed.substring(0, _typed.length - 1));
  }

  void _onEnter() {
    if (!_canType) return;
    final dictionary = _dictionary;
    if (dictionary == null) {
      _reject('The word list is still loading');
      return;
    }
    final verdict = validateGuess(_typed, puzzle: _puzzle, dictionary: dictionary);
    if (verdict != GuessValidation.ok) {
      _reject(verdict.message!);
      return;
    }
    final next = _state.submit(_typed);
    setState(() {
      _state = next;
      _typed = _puzzle.firstLetter;
    });
    _persist(next);
  }

  void _reject(String message) {
    final keyboard = _keyboardKey.currentContext?.findRenderObject() as RenderBox?;
    final above = (keyboard?.size.height ?? 0) + 8;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1500),
          margin: EdgeInsets.fromLTRB(16, 0, 16, above),
        ),
      );
    if (!MediaQuery.disableAnimationsOf(context)) _shake.forward(from: 0);
  }

  Future<void> _persist(WordState state) async {
    await play.saveProgress(state.toJson());
    if (!mounted || !state.isOver) return;
    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing || _result != null) return;
    _finishing = true;
    final result = GameResult(
      puzzleId: play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: _state.status == WordStatus.won,
      attempts: _state.guesses.length,
      shareLines: _state.shareLines(),
      isArchivePlay: play.isArchivePlay,
    );
    if (!MediaQuery.disableAnimationsOf(context)) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
    }
    setState(() => _result = result);
    await play.complete(context, result, revealTitle: 'The word', reveal: _reveal());
  }

  Widget _reveal() => _AnswerReveal(answer: _puzzle.answer, excerpt: _excerpt, story: play.story);

  Map<String, KeyState> _keyStates() => {
    for (final e in _state.keyStates().entries)
      e.key: switch (e.value) {
        WordKeyState.correct => KeyState.correct,
        WordKeyState.misplaced => KeyState.misplaced,
        WordKeyState.absent => KeyState.absent,
      },
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final teaser = _teaser;
    final excerpt = _excerpt;
    return GameShell(
      game: play.record.game,
      date: play.record.date,
      difficulty: play.record.difficulty,
      help: WordScreen.help,
      isArchivePlay: play.isArchivePlay,
      puzzleId: play.record.id.toString(),
      child: Column(
        children: [
          if (teaser != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: StoryTeaser(teaser: teaser),
            ),
          if (play.challenge != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text('Friend: ${play.challenge!.summary()}', style: theme.textTheme.labelMedium),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: WordBoard(
                puzzle: _puzzle,
                state: _state,
                typed: _typed,
                finished: result != null,
                shake: _shake,
                shareLines: result?.shareLines ?? const [],
              ),
            ),
          ),
          if (result != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: [
                  Text('THE WORD', style: theme.textTheme.labelSmall),
                  Text(_puzzle.answer, style: PaperTheme.display(size: 26, color: theme.colorScheme.onSurface)),
                  if (excerpt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: StoryExcerpt(excerpt: excerpt, words: [_puzzle.answer], story: play.story),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => play.showResult(context, result, revealTitle: 'The word', reveal: _reveal()),
                    child: const Text('See result'),
                  ),
                ],
              ),
            )
          else
            LetterKeyboard(
              key: _keyboardKey,
              onLetter: _onLetter,
              onBackspace: _onBackspace,
              onEnter: _onEnter,
              keyStates: _keyStates(),
              enabled: _canType,
            ),
        ],
      ),
    );
  }
}

class _AnswerReveal extends StatelessWidget {
  const _AnswerReveal({required this.answer, this.excerpt, this.story});

  final String answer;
  final String? excerpt;
  final Story? story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final excerpt = this.excerpt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          answer,
          style: PaperTheme.display(size: 40, color: theme.colorScheme.onSurface).copyWith(letterSpacing: 4),
        ),
        if (excerpt != null) ...[
          const SizedBox(height: 12),
          StoryExcerpt(excerpt: excerpt, words: [answer], story: story),
        ],
      ],
    );
  }
}
