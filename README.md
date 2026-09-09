# Play the Paper

Play the Paper is a free daily puzzle paper for phones and the web. Every edition has:

* **The Quiz** — five questions on the day's stories, one wager, then the Front Page.
* **The classics** — Daily Word, Sudoku, Letters, Mini Crossword, seeded from the same stories.
* **Logic** — Bridges, Binary, Nonogram, Kakuro, Regions, Loop, Target (generated, unique solutions).
* **Play** — Tangram, 2048 (daily challenge plus free play).
* **From the stories** — Uncover, Five Clues, Groups, Linked Clues, Before & After, Crossmatch,
  Word Compass (written from stories or an evergreen reserve).

Logic, play and editorial games are optional per edition; the core is the classics and the quiz.

* Product brief: `docs/playthepaper-concept-and-implementation.md`
* Architecture and module contract: `docs/ARCHITECTURE.md`
* Publishing and hosting runbook: `infra/README.md`
* Content provenance and naming checks: `docs/content-and-rights.md`

## Develop

```
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
flutter build web --release --pwa-strategy none   # web/sw.js provides offline reopening; Flutter's own worker is disabled
```

## Content

```
dart run tool/gen_sudoku.dart --from 2026-09-01 --to 2026-12-31 --out content/puzzles   # sudoku only
dart run tool/build_content.dart --from 2026-09-01 --to 2026-12-31                       # everything else
dart run tool/validate.dart content
dart run tool/bundle_starter.dart
```

The builder generates the seeded classics, the quiz from the edition template, every logic and
play game from its date seed, and every editorial game from the template or its reserve
(`content_src/editorial/<slug>/`). Optional games are added only inside the window
`kOptionalGamesFrom`..`kOptionalGamesTo` in `tool/build_content.dart` (currently 10 September to
31 October 2026, the span the reserves and Word Compass ranks cover); extend the window after
replenishing. Each game also has a standalone CLI, `dart run tool/gen_<slug>.dart --from --to --out`,
useful for checking a generator. Word Compass ranks come from `tool/compass_prepare.py`
(see `docs/compass-feasibility.md`).

`content/` is what the web host serves. `assets/content/` is the starter subset bundled
into the app so a fresh install can play offline.
