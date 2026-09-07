# Daypencil architecture and module contract

Daypencil is a Flutter app (iOS, Android, web/PWA) with no server-side code.
All play is local. Content is static JSON served from `https://daypencil.com/content/`
and mirrored in the app bundle under `assets/content/`.

Read this before writing any game module. Everything in `lib/core`, `lib/content`,
`lib/storage`, `lib/features/play`, `lib/features/results` and `lib/shared` is the
shared platform. Game modules build on it and do not modify it.

## Layout

```
lib/
  core/            edition_clock, game_kind, puzzle_id, game_result, theme
  content/         models (ContentIndex, EditionManifest, Story, PuzzleRecord), content_repository
  storage/         local_store (Hive boxes: progress, results, prefs, content cache)
  engines/<game>/  pure Dart rules. NO flutter imports. Used by the app, tool/ and tests.
  features/
    play/          PlayContext, GameRegistry, PlayScreen (opens any puzzle id)
    results/       ResultScreen, ShareService
    games/<game>/  <game>_screen.dart exports <Game>Screen({required PlayContext play}) and static help
    news/          NewsEditionScreen (flow), FrontPageScreen
    home/ archive/ stats/ settings/ about/
  shared/widgets/  GameShell, showHelpSheet, Rule, LetterKeyboard
tool/              Dart CLI generators and the validator (dart run tool/<x>.dart)
content/           the published content tree (index.json, editions/, puzzles/)
content_src/       hand-written sources: evergreen news templates, crossword clue bank
assets/content/    a subset of content/ bundled with the app (starter editions)
assets/dictionaries/words6_en.txt   6-letter valid guesses, uppercase, one per line (ENABLE)
assets/map/ne_110m_land.geojson     Natural Earth coastlines
tool/data/enable1.txt, 20k.txt      full dictionary and common-word list, for generators only
```

## Identity and time

* Edition dates roll at **04:00 UTC**. Use `EditionClock`; never the device or server clock directly.
* Puzzle id: `word-2026-09-08-en-v1`, `sudoku-2026-09-08-en-hard-v1`. See `PuzzleId`.
* A puzzle file is immutable. A correction is a new version with a new id.

## Content files

`content/index.json`
```json
{"dates": ["2026-09-01", "2026-09-02"], "latest": "2026-09-02"}
```

`content/editions/2026-09-08.json`
```json
{
  "date": "2026-09-08", "kind": "news" | "evergreen", "label": "Today" | "Evergreen · Science",
  "version": 1, "publishedAt": "2026-09-08T02:20:00Z",
  "puzzles": ["word-2026-09-08-en-v1", "sudoku-2026-09-08-en-easy-v1", "sudoku-2026-09-08-en-medium-v1",
              "sudoku-2026-09-08-en-hard-v1", "letters-2026-09-08-en-v1", "crossword-2026-09-08-en-v1",
              "correct-2026-09-08-en-v1", "number-2026-09-08-en-v1", "where-2026-09-08-en-v1"],
  "stories": [{"id": "...", "game": "correct", "headline": "...", "summary": "...",
               "publisher": "...", "url": "https://...", "publishedAt": "2026-09-07"}]
}
```

`content/puzzles/<id>.json` (common envelope, see `PuzzleRecord`)
```json
{
  "id": "word-2026-09-08-en-v1", "game": "word", "editionDate": "2026-09-08", "locale": "en-GB",
  "contentVersion": 1, "scoringVersion": 1, "dictionaryVersion": "enable1-2026-09",
  "payload": {...}, "reveal": {...},
  "storyId": "only for news games", "sources": [{"publisher": "", "url": "", "excerpt": ""}]
}
```

### Payload and reveal per game

**word** (Motus-style, 6 letters, first letter given, 6 guesses)
```json
payload: {"length": 6, "firstLetter": "S", "maxGuesses": 6}
reveal:  {"answer": "STREAM"}
```
Valid guesses: `assets/dictionaries/words6_en.txt` (must contain the answer). A guess must start
with `firstLetter`. Feedback per position: correct / misplaced / absent. Repeated letters:
consume exact matches first, then allocate misplaced from the remaining letter counts.
Result: `attempts` (1–6), `solved`, `shareLines` as 🟩🟨⬜ rows.

**sudoku**
```json
payload: {"givens": "81 chars row-major, 1-9 or 0 for blank"}
reveal:  {"solution": "81 chars"}
```
Difficulty is in the id. Givens must be a subset of the solution; the solution must be the unique
solution. Result: `seconds`, `hints`, `solved`.

**letters** (bee-style)
```json
payload: {"center": "A", "outer": "BCDEFG", "minLength": 4}
reveal:  {"answers": ["ABACA", ...], "pangrams": ["..."], "maxScore": 123}
```
7 distinct uppercase letters. Scoring: 4 letters = 1 point, longer = its length, pangram = length + 7.
`maxScore` is the sum over `answers`. Ranks by fraction of max: 0 Beginner, 0.02 Good start,
0.05 Moving up, 0.08 Good, 0.15 Solid, 0.25 Nice, 0.40 Great, 0.50 Amazing, 0.70 Genius.
Result: `points`, `maxPoints`, `solved` = reached Genius.

**crossword** (5×5)
```json
payload: {"size": 5, "grid": ["....#", ".....", ...],
          "clues": {"across": [{"number": 1, "row": 0, "col": 0, "length": 4, "clue": "..."}],
                    "down":   [{"number": 1, "row": 0, "col": 0, "length": 5, "clue": "..."}]}}
reveal:  {"solution": ["ABCD#", "EFGHI", ...]}
```
`#` is a block. Numbering follows standard rules (a cell starts an entry when the cell before it,
in that direction, is a block or edge, and the entry is at least 2 cells). Clue numbers in the
payload must equal the derived numbering. Result: `seconds`, `hints` (checks and reveals used), `solved`.

**correct** (find the altered detail, then repair it)
```json
payload: {"dispatch": "text containing every detail verbatim",
          "details": ["1889", "230 metres", "Paris"],
          "options": ["330 metres", "300 metres", "430 metres", "230 metres"],
          "evidence": [{"title": "...", "text": "...", "source": "Wikipedia"}],
          "maxAttempts": 3}
reveal:  {"alteredDetail": 1, "correctOption": 0, "explanation": "..."}
```
Step 1: pick the altered detail. Step 2: pick the repair. Each wrong pick uses one attempt.
`attempts` = wrong picks + 1. `solved` if both steps done within `maxAttempts`.

**number**
```json
payload: {"question": "How tall is the Eiffel Tower, to the tip?", "unit": "metres",
          "min": 100, "max": 600, "step": 1, "comparison": "The Shard in London is 310 metres."}
reveal:  {"answer": 330, "context": "...", "scoring": {"perfectPct": 2, "zeroPct": 50}}
```
`errorPct = |guess − answer| / answer × 100`. `solved` = errorPct ≤ zeroPct.

**where**
```json
payload: {"clues": ["...", "..."]}
reveal:  {"lat": 48.858, "lon": 2.294, "placeName": "Paris, France", "acceptRadiusKm": 300, "explanation": "..."}
```
Distance by haversine (Earth radius 6371 km). `solved` = distance ≤ acceptRadiusKm.

## Game screen contract

Each `lib/features/games/<game>/<game>_screen.dart` exports:

```dart
class WordScreen extends StatefulWidget {
  const WordScreen({super.key, required this.play});
  final PlayContext play;
  static const GameHelp help = GameHelp(title: ..., paragraphs: [...]);
}
```

Rules every screen follows:

1. Wrap in `GameShell(game:, date:, difficulty:, help:, isArchivePlay:, puzzleId: play.record.id.toString(), child:)`.
2. Parse `play.record.payload` and `reveal` with the engine's typed parser. Throw `FormatException` on bad data.
3. Restore state from `play.loadProgress()` in `initState`; call `play.saveProgress(state)` after **every**
   meaningful action (a guess, a cell edit, a found word, a pin move).
4. If `play.existingResult() != null`, show the finished board read-only with a **See result** button that
   calls `play.showResult(context, result, revealTitle:, reveal:)`.
5. When play ends, build a `GameResult(isArchivePlay: play.isArchivePlay, ...)` and call
   `play.complete(context, result, revealTitle:, reveal:)` exactly once. Do not push the result screen yourself.
6. Colour never carries meaning alone: pair each state with a symbol or label. Touch targets ≥ 44dp.
   Honour `MediaQuery.disableAnimationsOf(context)`. Add `Semantics` labels to board cells.
7. Physical keyboard works on web and desktop where letters are typed (`LetterKeyboard` handles this).
8. Use theme colours from `context.gameColors` and text styles from `Theme.of(context).textTheme` /
   `DaypencilTheme.display()`. No hard-coded colours.
9. No new dependencies. No edits outside your module, your engine, your tool script, your tests
   and `content_src/<game>/`.

## Engine contract

`lib/engines/<game>/` is pure Dart: parse payload/reveal into typed classes, hold immutable state,
expose pure transitions, compute scores, serialize progress to/from `Map<String, dynamic>`.
Tests live in `test/engines/<game>/`. Generators in `tool/` produce puzzle files from a seed so the
same date always yields the same puzzle, and validate their own output with the engine.

## Verification bar

`flutter analyze` must report no issues. `flutter test` must pass. Every rule stated above
for a game has a test.
