# Daypencil

A free daily puzzle paper for phones and the web: Mini Crossword, Letters, Daily Word,
Sudoku, and a short playable news edition (Correct, The Number, Where, Front Page).

* Product brief: `docs/daypencil-concept-and-implementation.md`
* Architecture and module contract: `docs/ARCHITECTURE.md`
* Publishing and hosting runbook: `infra/README.md`

## Develop

```
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

## Content

```
dart run tool/gen_sudoku.dart    --from 2026-09-01 --to 2026-12-31 --out content/puzzles
dart run tool/gen_word.dart      --from 2026-09-01 --to 2026-12-31 --out content/puzzles
dart run tool/gen_letters.dart   --from 2026-09-01 --to 2026-12-31 --out content/puzzles
dart run tool/gen_crossword.dart --from 2026-09-01 --to 2026-12-31 --out content/puzzles
dart run tool/build_content.dart --from 2026-09-01 --to 2026-12-31
dart run tool/validate.dart content
dart run tool/bundle_starter.dart
```

`content/` is what the web host serves. `assets/content/` is the starter subset bundled
into the app so a fresh install can play offline.
