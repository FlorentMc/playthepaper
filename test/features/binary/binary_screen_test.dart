import 'dart:io';

import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/binary/binary.dart';
import 'package:playthepaper/features/games/binary/binary_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each move, and that file I/O needs a real event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('binary-2026-09-10-en-v1');
  final record = BinaryGenerator().generate(DateTime.utc(2026, 9, 10));
  final puzzle = BinaryPuzzle.parse(record.payload, record.reveal);
  final blank = puzzle.givens.indexOf(BinaryRules.empty);
  final answer = puzzle.solution[blank];
  final wrong = 1 - answer;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_binary');
    store = await LocalStore.open(subDir: dir.path);
  });

  setUp(() => store.clearAll());

  tearDownAll(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpScreen(WidgetTester tester, {bool isArchivePlay = false}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
        ],
        child: MaterialApp(
          theme: PaperTheme.light(),
          home: BinaryScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
        ),
      ),
    );
    await settle(tester);
    if (find.byType(BottomSheet).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(400, 20));
      await settle(tester);
    }
    expect(find.byType(BottomSheet), findsNothing, reason: 'the first-run help sheet must be dismissed');
  }

  Future<void> tearDownScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Finder cell(int index) => find.byKey(ValueKey('binary-cell-$index'));
  Finder cellText(int index, String text) => find.descendant(of: cell(index), matching: find.text(text));

  Future<void> tapThenPump(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  testWidgets('renders 64 cells, a tap cycles a cell and progress is saved', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      for (var i = 0; i < 64; i++) {
        expect(cell(i), findsOneWidget, reason: 'cell $i');
      }
      expect(cellText(blank, '●'), findsNothing);
      await tapThenPump(tester, cell(blank));
      expect(cellText(blank, '●'), findsOneWidget);
      await tapThenPump(tester, cell(blank));
      expect(cellText(blank, '○'), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((store.progress(id)!['values'] as String)[blank], '0');
      await tapThenPump(tester, cell(blank));
      expect(cellText(blank, '○'), findsNothing);
      expect(cellText(blank, '●'), findsNothing);

      final given = puzzle.givens.indexWhere((g) => g != BinaryRules.empty);
      final symbol = puzzle.givens[given] == 1 ? '●' : '○';
      await tapThenPump(tester, cell(given));
      expect(cellText(given, symbol), findsOneWidget, reason: 'givens do not change');
      await tearDownScreen(tester);
    });
  });

  testWidgets('the physical keyboard moves, sets, cycles and clears', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, cell(blank));
      await tapThenPump(tester, cell(blank));
      await tapThenPump(tester, cell(blank));
      expect(cellText(blank, '●'), findsNothing);
      await key(tester, LogicalKeyboardKey.digit1);
      expect(cellText(blank, '●'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.digit0);
      expect(cellText(blank, '○'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.space);
      expect(cellText(blank, '○'), findsNothing);
      await key(tester, LogicalKeyboardKey.space);
      expect(cellText(blank, '●'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.backspace);
      expect(cellText(blank, '●'), findsNothing);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      await key(tester, LogicalKeyboardKey.enter);
      expect(cellText(blank, '●'), findsOneWidget, reason: 'arrows move the selection and back');
      await tearDownScreen(tester);
    });
  });

  testWidgets('check marks a wrong cell with a cross, counts a hint, and undo clears it', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, cell(blank));
      if (wrong == 0) await tapThenPump(tester, cell(blank));
      expect(cellText(blank, wrong == 1 ? '●' : '○'), findsOneWidget);
      await tapThenPump(tester, find.byKey(const ValueKey('binary-check')));
      expect(find.descendant(of: cell(blank), matching: find.byIcon(Icons.close)), findsOneWidget);
      expect(find.text('1 cell is wrong.'), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.progress(id)!['hints'], 1);

      await tapThenPump(tester, find.byKey(const ValueKey('binary-undo')));
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('1 cell is wrong.'), findsNothing);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a completed puzzle is read-only with a See result button', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(
        GameResult(puzzleId: id, completedAt: DateTime.utc(2026, 9, 10), solved: true, seconds: 300, hints: 1),
      );
      await pumpScreen(tester);
      expect(find.text('See result'), findsOneWidget);
      expect(find.byKey(const ValueKey('binary-check')), findsNothing);
      expect(cellText(blank, answer == 1 ? '●' : '○'), findsOneWidget);
      await tapThenPump(tester, cell(blank));
      expect(cellText(blank, answer == 1 ? '●' : '○'), findsOneWidget, reason: 'the finished board ignores taps');
      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('Solved'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('filling the last cell completes the puzzle once', (tester) async {
    await tester.runAsync(() async {
      var state = BinaryState.initial(puzzle);
      for (var i = 0; i < 64; i++) {
        if (!puzzle.isGiven(i) && i != blank) state = state.setValue(i, puzzle.solution[i]);
      }
      await store.saveProgress(id, state.tick(42).toJson());
      await pumpScreen(tester, isArchivePlay: true);
      await tapThenPump(tester, cell(blank));
      if (answer == 0) await tapThenPump(tester, cell(blank));
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Solved').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.seconds, 42);
      expect(result.hints, 0);
      expect(result.isArchivePlay, isTrue);
      expect(result.shareLines, ['●○ 8×8']);
      expect(store.hasProgress(id), isFalse);
      await tearDownScreen(tester);
    });
  });
}
