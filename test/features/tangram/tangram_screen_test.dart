import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/tangram/tangram.dart';
import 'package:playthepaper/features/games/tangram/tangram_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:provider/provider.dart';

import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each move, and that file I/O can only complete with a real
/// event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final record = TangramGenerator().generate(DateTime.utc(2026, 9, 10));
  final id = record.id;
  final puzzle = TangramPuzzle.parse(record.payload, record.reveal);
  final last = puzzle.solutionFor(TangramPiece.square);

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_tangram');
    store = await LocalStore.open(subDir: dir.path);
  });

  setUp(() => store.clearAll());

  tearDownAll(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  /// The game timer schedules a frame every second, so pumpAndSettle would
  /// never return while play is in progress.
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
          home: TangramScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
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

  Finder trayPiece(TangramPiece piece) => find.byKey(ValueKey('tangram-tray-${piece.slug}'));
  Finder board() => find.byKey(const ValueKey('tangram-board'));

  Offset boardPoint(WidgetTester tester, num x, num y) {
    final rect = tester.getRect(board());
    final scale = rect.width / TangramGeometry.boardUnits;
    return rect.topLeft + Offset(x * scale, y * scale);
  }

  Future<void> tapThenPump(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> placeAllBut(TangramPiece missing) async {
    var state = TangramState.initial(puzzle);
    for (final placement in puzzle.solution) {
      if (placement.piece == missing) continue;
      state = state.place(placement.piece, placement.x, placement.y,
          rotation: placement.rotation, flipped: placement.flipped);
    }
    await store.saveProgress(id, state.select(null).tick(58).toJson());
  }

  testWidgets('shows the seven pieces and puts a tapped one on the board', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      for (final piece in TangramPiece.values) {
        expect(trayPiece(piece), findsOneWidget, reason: piece.slug);
      }
      expect(find.text('0 of 7 placed'), findsOneWidget);

      await tapThenPump(tester, trayPiece(TangramPiece.square));
      await tester.tapAt(boardPoint(tester, 4, 4));
      await tester.pump();

      expect(find.text('1 of 7 placed'), findsOneWidget);
      await pumpUntil(tester, () => store.progress(id) != null, reason: 'progress saved');
      final placed = store.progress(id)!['placed'] as List;
      expect(placed, hasLength(1));
      expect(placed.first, {'piece': 'square', 'x': 4, 'y': 4, 'rotation': 0, 'flipped': false});
      await tearDownScreen(tester);
    });
  });

  testWidgets('a placed piece can be dragged to a new spot', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, trayPiece(TangramPiece.mediumTriangle));
      await tester.tapAt(boardPoint(tester, 3, 5));
      await tester.pump();
      expect(find.text('1 of 7 placed'), findsOneWidget);

      final gesture = await tester.startGesture(boardPoint(tester, 2.5, 5.5));
      await gesture.moveBy(boardPoint(tester, 5, 4) - boardPoint(tester, 3, 5));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      await pumpUntil(tester, () {
        final placed = (store.progress(id)?['placed'] as List?) ?? const [];
        return placed.isNotEmpty && (placed.first as Map)['x'] == 5;
      }, reason: 'the move is saved');
      expect((store.progress(id)!['placed'] as List).first,
          {'piece': 'mediumTriangle', 'x': 5, 'y': 4, 'rotation': 0, 'flipped': false});
      await tearDownScreen(tester);
    });
  });

  testWidgets('the keyboard turns and nudges the picked-up piece', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, trayPiece(TangramPiece.parallelogram));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('1 of 7 placed'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      await pumpUntil(tester, () {
        final placed = (store.progress(id)?['placed'] as List?) ?? const [];
        return placed.isNotEmpty && (placed.first as Map)['rotation'] == 45;
      }, reason: 'the turn is saved');
      final placement = (store.progress(id)!['placed'] as List).first as Map;
      expect(placement['piece'], 'parallelogram');
      expect(placement['flipped'], isTrue);
      expect(placement['x'], 5);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(find.text('0 of 7 placed'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('the last piece finishes the figure and saves one result', (tester) async {
    await tester.runAsync(() async {
      await placeAllBut(TangramPiece.square);
      await pumpScreen(tester, isArchivePlay: true);
      expect(find.text('6 of 7 placed'), findsOneWidget);

      await tapThenPump(tester, trayPiece(TangramPiece.square));
      await tester.tapAt(boardPoint(tester, last.x, last.y));
      await tester.pump();

      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id),
          reason: 'result saved');
      await pumpUntil(tester, () => find.text('Shape made').evaluate().isNotEmpty,
          reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.seconds, 58);
      expect(result.hints, 0);
      expect(result.isArchivePlay, isTrue);
      expect(result.note, '${puzzle.name} in 0:58');
      expect(result.shareLines, ['🧩 0:58']);
      expect(result.shareLines.first, isNot(contains(puzzle.name)));
      expect(find.text(puzzle.name), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('the board and the tray fit a phone', (tester) async {
    await tester.runAsync(() async {
      for (final size in const [Size(390, 844), Size(320, 568), Size(430, 932)]) {
        await tester.binding.setSurfaceSize(size);
        await pumpScreen(tester);
        expect(tester.takeException(), isNull, reason: '$size');
        final rect = tester.getRect(board());
        expect(rect.width, greaterThan(size.width * 0.7), reason: '$size');
        expect(rect.width, lessThanOrEqualTo(size.width), reason: '$size');
        for (final piece in TangramPiece.values) {
          expect(tester.getSize(trayPiece(piece)).shortestSide, greaterThanOrEqualTo(44),
              reason: '${piece.slug} at $size');
        }
        expect(tester.getSize(find.byKey(const ValueKey('tangram-turn'))).height,
            greaterThanOrEqualTo(44));
        await tearDownScreen(tester);
      }
      await tester.binding.setSurfaceSize(null);
    });
  });

  testWidgets('a finished puzzle opens read-only with a See result button', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(GameResult(
        puzzleId: id,
        completedAt: DateTime.utc(2026, 9, 10),
        solved: true,
        seconds: 240,
        hints: 1,
        note: '${puzzle.name} in 4:00',
      ));
      await pumpScreen(tester);
      expect(find.text('See result'), findsOneWidget);
      expect(find.text('${puzzle.name} in 4:00'), findsOneWidget);
      expect(trayPiece(TangramPiece.square), findsNothing);
      expect(find.byKey(const ValueKey('tangram-turn')), findsNothing);

      await tester.tapAt(boardPoint(tester, last.x, last.y));
      await tester.pump();
      expect(store.hasProgress(id), isFalse);

      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('Shape made'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });
}
