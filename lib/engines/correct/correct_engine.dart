import 'package:equatable/equatable.dart';

/// Rules for Correct: a short dispatch in which exactly one detail has been
/// altered. The player first finds the altered detail, then picks the repair.
/// Every wrong pick, in either step, uses one attempt.

Never _bad(String message) => throw FormatException('correct: $message');

class CorrectEvidence extends Equatable {
  const CorrectEvidence({required this.title, required this.text, required this.source});

  final String title;
  final String text;
  final String source;

  static CorrectEvidence fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    final text = json['text'];
    final source = json['source'];
    if (title is! String || title.isEmpty) _bad('evidence needs a title');
    if (text is! String || text.isEmpty) _bad('evidence needs a text');
    if (source is! String || source.isEmpty) _bad('evidence needs a source');
    return CorrectEvidence(title: title, text: text, source: source);
  }

  Map<String, dynamic> toJson() => {'title': title, 'text': text, 'source': source};

  @override
  List<Object?> get props => [title, text, source];
}

/// A run of the dispatch: plain text, or the detail at [detail].
class DispatchSegment extends Equatable {
  const DispatchSegment(this.text, {this.detail});

  final String text;
  final int? detail;

  bool get isDetail => detail != null;

  @override
  List<Object?> get props => [text, detail];
}

class CorrectPuzzle extends Equatable {
  const CorrectPuzzle({
    required this.dispatch,
    required this.details,
    required this.options,
    required this.evidence,
    required this.maxAttempts,
  });

  final String dispatch;

  /// Candidate details, each occurring verbatim exactly once in [dispatch].
  final List<String> details;

  /// Candidate repairs offered in step two.
  final List<String> options;
  final List<CorrectEvidence> evidence;
  final int maxAttempts;

  static CorrectPuzzle parse(Map<String, dynamic> payload) {
    final dispatch = payload['dispatch'];
    if (dispatch is! String || dispatch.trim().isEmpty) _bad('dispatch must be a non-empty string');

    final rawDetails = payload['details'];
    if (rawDetails is! List || rawDetails.length < 2) _bad('details must list at least two strings');
    final details = <String>[];
    for (final d in rawDetails) {
      if (d is! String || d.isEmpty) _bad('details must be non-empty strings');
      if (details.contains(d)) _bad('detail "$d" is listed twice');
      final first = dispatch.indexOf(d);
      if (first < 0) _bad('detail "$d" does not occur in the dispatch');
      if (dispatch.indexOf(d, first + 1) >= 0) _bad('detail "$d" occurs more than once in the dispatch');
      details.add(d);
    }
    final spans = <(int, int)>[];
    for (final d in details) {
      final start = dispatch.indexOf(d);
      spans.add((start, start + d.length));
    }
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < spans.length; i++) {
      if (spans[i].$1 < spans[i - 1].$2) _bad('details overlap in the dispatch');
    }

    final rawOptions = payload['options'];
    if (rawOptions is! List || rawOptions.length < 3) _bad('options must list at least three strings');
    final options = <String>[];
    for (final o in rawOptions) {
      if (o is! String || o.isEmpty) _bad('options must be non-empty strings');
      if (options.contains(o)) _bad('option "$o" is listed twice');
      options.add(o);
    }

    final rawEvidence = payload['evidence'];
    if (rawEvidence is! List || rawEvidence.isEmpty || rawEvidence.length > 3) {
      _bad('evidence must list one to three cards');
    }
    final evidence = [
      for (final e in rawEvidence)
        if (e is Map) CorrectEvidence.fromJson(Map<String, dynamic>.from(e)) else _bad('evidence must be objects'),
    ];

    final maxAttempts = payload['maxAttempts'];
    if (maxAttempts is! int || maxAttempts < 1) _bad('maxAttempts must be a positive integer');

    return CorrectPuzzle(
      dispatch: dispatch,
      details: details,
      options: options,
      evidence: evidence,
      maxAttempts: maxAttempts,
    );
  }

  Map<String, dynamic> toJson() => {
        'dispatch': dispatch,
        'details': details,
        'options': options,
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'maxAttempts': maxAttempts,
      };

  /// The dispatch cut into plain runs and detail runs, in reading order.
  List<DispatchSegment> get segments {
    final starts = <(int, int)>[];
    for (var i = 0; i < details.length; i++) {
      starts.add((dispatch.indexOf(details[i]), i));
    }
    starts.sort((a, b) => a.$1.compareTo(b.$1));
    final out = <DispatchSegment>[];
    var cursor = 0;
    for (final (start, i) in starts) {
      if (start > cursor) out.add(DispatchSegment(dispatch.substring(cursor, start)));
      out.add(DispatchSegment(details[i], detail: i));
      cursor = start + details[i].length;
    }
    if (cursor < dispatch.length) out.add(DispatchSegment(dispatch.substring(cursor)));
    return out;
  }

  @override
  List<Object?> get props => [dispatch, details, options, evidence, maxAttempts];
}

class CorrectReveal extends Equatable {
  const CorrectReveal({required this.alteredDetail, required this.correctOption, required this.explanation});

  final int alteredDetail;
  final int correctOption;
  final String explanation;

  static CorrectReveal parse(Map<String, dynamic> reveal, CorrectPuzzle puzzle) {
    final altered = reveal['alteredDetail'];
    final option = reveal['correctOption'];
    final explanation = reveal['explanation'];
    if (altered is! int || altered < 0 || altered >= puzzle.details.length) {
      _bad('alteredDetail must index a detail');
    }
    if (option is! int || option < 0 || option >= puzzle.options.length) {
      _bad('correctOption must index an option');
    }
    if (puzzle.options[option] == puzzle.details[altered]) {
      _bad('the correct option must differ from the altered detail');
    }
    if (explanation is! String || explanation.isEmpty) _bad('explanation must be a non-empty string');
    return CorrectReveal(alteredDetail: altered, correctOption: option, explanation: explanation);
  }

  Map<String, dynamic> toJson() => {
        'alteredDetail': alteredDetail,
        'correctOption': correctOption,
        'explanation': explanation,
      };

  /// The dispatch with the altered detail replaced by the correct option.
  /// The repaired run carries [DispatchSegment.detail] = [alteredDetail].
  List<DispatchSegment> correctedSegments(CorrectPuzzle puzzle) => [
        for (final s in puzzle.segments)
          if (s.detail == alteredDetail) DispatchSegment(puzzle.options[correctOption], detail: alteredDetail) else DispatchSegment(s.text),
      ];

  String correctedDispatch(CorrectPuzzle puzzle) => correctedSegments(puzzle).map((s) => s.text).join();

  @override
  List<Object?> get props => [alteredDetail, correctOption, explanation];
}

enum CorrectStep { findDetail, chooseRepair, done }

enum CorrectStatus { playing, won, lost }

/// Immutable play state. Transitions return a new state; a pick that is not
/// allowed in the current step, or repeats an earlier wrong pick, is ignored.
class CorrectState extends Equatable {
  const CorrectState({
    required this.puzzle,
    required this.reveal,
    this.wrongDetails = const [],
    this.wrongOptions = const [],
    this.detailFound = false,
    this.repaired = false,
  });

  final CorrectPuzzle puzzle;
  final CorrectReveal reveal;
  final List<int> wrongDetails;
  final List<int> wrongOptions;
  final bool detailFound;
  final bool repaired;

  int get maxAttempts => puzzle.maxAttempts;
  int get wrongPicks => wrongDetails.length + wrongOptions.length;

  /// Attempts used so far, counting the current one.
  int get attempts => wrongPicks + 1 > maxAttempts ? maxAttempts : wrongPicks + 1;
  int get attemptsLeft => maxAttempts - wrongPicks;

  CorrectStatus get status {
    if (repaired) return CorrectStatus.won;
    if (wrongPicks >= maxAttempts) return CorrectStatus.lost;
    return CorrectStatus.playing;
  }

  CorrectStep get step {
    if (status != CorrectStatus.playing) return CorrectStep.done;
    return detailFound ? CorrectStep.chooseRepair : CorrectStep.findDetail;
  }

  bool get isOver => step == CorrectStep.done;

  CorrectState pickDetail(int index) {
    if (step != CorrectStep.findDetail) return this;
    if (index < 0 || index >= puzzle.details.length) throw RangeError.index(index, puzzle.details);
    if (wrongDetails.contains(index)) return this;
    if (index == reveal.alteredDetail) return _copy(detailFound: true);
    return _copy(wrongDetails: [...wrongDetails, index]);
  }

  CorrectState pickOption(int index) {
    if (step != CorrectStep.chooseRepair) return this;
    if (index < 0 || index >= puzzle.options.length) throw RangeError.index(index, puzzle.options);
    if (wrongOptions.contains(index)) return this;
    if (index == reveal.correctOption) return _copy(repaired: true);
    return _copy(wrongOptions: [...wrongOptions, index]);
  }

  CorrectState _copy({List<int>? wrongDetails, List<int>? wrongOptions, bool? detailFound, bool? repaired}) =>
      CorrectState(
        puzzle: puzzle,
        reveal: reveal,
        wrongDetails: wrongDetails ?? this.wrongDetails,
        wrongOptions: wrongOptions ?? this.wrongOptions,
        detailFound: detailFound ?? this.detailFound,
        repaired: repaired ?? this.repaired,
      );

  Map<String, dynamic> toJson() => {
        'wrongDetails': wrongDetails,
        'wrongOptions': wrongOptions,
        'detailFound': detailFound,
        'repaired': repaired,
      };

  static CorrectState fromJson(Map<String, dynamic> json, {required CorrectPuzzle puzzle, required CorrectReveal reveal}) {
    List<int> ints(String key) => ((json[key] as List?) ?? const []).map((v) => (v as num).toInt()).toList();
    return CorrectState(
      puzzle: puzzle,
      reveal: reveal,
      wrongDetails: ints('wrongDetails'),
      wrongOptions: ints('wrongOptions'),
      detailFound: json['detailFound'] as bool? ?? false,
      repaired: json['repaired'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [puzzle, reveal, wrongDetails, wrongOptions, detailFound, repaired];
}
