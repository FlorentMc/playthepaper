import 'package:flutter/material.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/quiz/quiz_engine.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';
import 'quiz_progress_strip.dart';
import 'quiz_question_view.dart';

/// The Quiz: five questions from the day's stories, one wager.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'The Quiz',
    paragraphs: [
      'Five questions, each taken from one of today\'s stories. Pick one of the four answers; '
          'a right answer scores one point.',
      'After each answer you see whether you were right, a short explanation, and a link to the '
          'story it came from.',
      'Before question five you can stake a point, if you have one. A right answer then scores two; '
          'a wrong one loses the stake. Six points is full marks.',
    ],
  );

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final QuizPuzzle _puzzle;
  late QuizState _state;
  late int _shown;
  GameResult? _result;
  bool _finishing = false;

  PlayContext get play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = QuizPuzzle.parse(play.record.payload, play.record.reveal);
    _result = play.existingResult();
    _state = _restore();
    _shown = _state.isFinished ? _puzzle.questions.length - 1 : _state.current;
  }

  QuizState _restore() {
    final saved = play.loadProgress();
    if (saved == null) return QuizState.initial(_puzzle);
    try {
      return QuizState.fromJson(_puzzle, saved);
    } on FormatException {
      return QuizState.initial(_puzzle);
    }
  }

  bool get _canPlay => _result == null && !_finishing;

  void _answer(int option) {
    if (!_canPlay || _state.isAnswered(_shown)) return;
    final next = _state.answer(option);
    setState(() => _state = next);
    play.saveProgress(next.toJson());
  }

  void _setStake(bool stake) {
    if (!_canPlay) return;
    final next = stake ? _state.stake() : _state.unstake();
    if (next == _state) return;
    setState(() => _state = next);
    play.saveProgress(next.toJson());
  }

  void _next() {
    if (!_canPlay) return;
    if (_state.isFinished) {
      _finish();
    } else {
      setState(() => _shown = _state.current);
    }
  }

  Future<void> _finish() async {
    if (_finishing || _result != null) return;
    _finishing = true;
    final result = GameResult(
      puzzleId: play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: true,
      points: _state.points,
      maxPoints: _puzzle.maxPoints,
      shareLines: [_state.shareLine()],
      isArchivePlay: play.isArchivePlay,
    );
    setState(() => _result = result);
    await play.complete(
      context,
      result,
      revealTitle: 'The answers',
      reveal: _AnswersReveal(puzzle: _puzzle),
    );
  }

  /// Marks come from the state while it is known, else from the saved
  /// result's share line, since a saved result clears the progress.
  QuizMarks get _marks {
    final result = _result;
    if (result == null || _state.isFinished) return QuizMarks.of(_state);
    return QuizMarks.parse(result.shareLines.firstOrNull ?? '');
  }

  QuizOutcome? _outcomeOf(int i, QuizMarks marks) {
    if (_result == null || _state.isFinished) {
      return _state.isAnswered(i) ? QuizOutcome(correct: _state.isCorrect(i), picked: _state.answers[i]) : null;
    }
    final mark = marks[i];
    return mark == null ? null : QuizOutcome(correct: mark);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final marks = _marks;
    return GameShell(
      game: play.record.game,
      date: play.record.date,
      difficulty: play.record.difficulty,
      help: QuizScreen.help,
      isArchivePlay: play.isArchivePlay,
      puzzleId: play.record.id.toString(),
      child: Column(
        children: [
          if (play.challenge != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Text('Friend: ${play.challenge!.summary()}', style: theme.textTheme.labelMedium),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: QuizProgressStrip(
              marks: marks,
              count: _puzzle.questions.length,
              wagerQuestion: _puzzle.wagerQuestion,
              current: result == null ? _shown : -1,
            ),
          ),
          Expanded(child: result == null ? _playing(context, marks) : _completed(result, marks)),
        ],
      ),
    );
  }

  Widget _playing(BuildContext context, QuizMarks marks) {
    final last = _shown == _puzzle.questions.length - 1;
    final answered = _state.isAnswered(_shown);
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
      child: ListView(
        key: ValueKey(_shown),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          QuizQuestionView(
            index: _shown,
            puzzle: _puzzle,
            outcome: _outcomeOf(_shown, marks),
            staked: _state.staked,
            story: play.storyById(_puzzle.questions[_shown].storyId),
            wagerPoints: _state.canStake ? _state.points : null,
            onAnswer: _answer,
            onStake: _setStake,
          ),
          if (answered) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: _next, child: Text(last ? 'See your score' : 'Next question')),
          ],
        ],
      ),
    );
  }

  Widget _completed(GameResult result, QuizMarks marks) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Text('YOUR SCORE', style: theme.textTheme.labelSmall),
              Text(result.summary(), style: DaypencilTheme.display(size: 26, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 16),
              for (var i = 0; i < _puzzle.questions.length; i++) ...[
                const Rule(),
                const SizedBox(height: 16),
                QuizQuestionView(
                  index: i,
                  puzzle: _puzzle,
                  outcome: _outcomeOf(i, marks),
                  staked: marks.staked,
                  story: play.storyById(_puzzle.questions[i].storyId),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => play.showResult(
                context,
                result,
                revealTitle: 'The answers',
                reveal: _AnswersReveal(puzzle: _puzzle),
              ),
              child: const Text('See result'),
            ),
          ),
        ),
      ],
    );
  }
}

/// The five prompts with their correct options, for the result screen.
class _AnswersReveal extends StatelessWidget {
  const _AnswersReveal({required this.puzzle});

  final QuizPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < puzzle.questions.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Text('${i + 1}. ${puzzle.questions[i].prompt}', style: theme.textTheme.bodySmall),
          Text(puzzle.questions[i].options[puzzle.answerOf(i)], style: theme.textTheme.titleSmall),
        ],
      ],
    );
  }
}
