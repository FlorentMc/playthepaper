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
    news/          NewsEditionScreen (the quiz, then the Front Page), FrontPageScreen
    home/ archive/ stats/ settings/ about/
  shared/widgets/  GameShell, showHelpSheet, Rule, LetterKeyboard
tool/              Dart CLI generators and the validator (dart run tool/<x>.dart)
content/           the published content tree (index.json, editions/, puzzles/)
content_src/       hand-written sources: evergreen edition templates, crossword clue bank; news/<date>.json written by the publisher
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
  "date": "2026-09-08", "kind": "news" | "evergreen", "label": "Today" | "Evergreen · Nature",
  "version": 1, "publishedAt": "2026-09-08T02:20:00Z",
  "puzzles": ["word-2026-09-08-en-v1", "sudoku-2026-09-08-en-easy-v1", "sudoku-2026-09-08-en-medium-v1",
              "sudoku-2026-09-08-en-hard-v1", "letters-2026-09-08-en-v1", "crossword-2026-09-08-en-v1",
              "quiz-2026-09-08-en-v1"],
  "stories": [{"id": "nature-1-whale", "headline": "...", "summary": "...",
               "publisher": "...", "url": "https://...", "publishedAt": "2026-09-07"}],
  "seeds": {"nature-1-whale": ["quiz:1", "quiz:4", "word"], "nature-1-falls": ["quiz:2", "crossword:5 Across"]}
}
```
`seeds` maps a story id to what it fed: `quiz:<question number>`, `word`, `letters`, `crossword:<entry label>`.
An edition is complete with the four classics (sudoku three times), the quiz, and at least three stories.

`content/puzzles/<id>.json` (common envelope, see `PuzzleRecord`)
```json
{
  "id": "word-2026-09-08-en-v1", "game": "word", "editionDate": "2026-09-08", "locale": "en-GB",
  "contentVersion": 1, "scoringVersion": 1, "dictionaryVersion": "enable1-2026-09",
  "payload": {...}, "reveal": {...},
  "storyId": "the story that seeded this puzzle, if any", "sources": [{"publisher": "", "url": "", "excerpt": ""}]
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

**quiz** (five questions from the day's stories, one wager)
```json
payload: {"questions": [{"lead": "The blue whale is the largest animal known to have existed, and one stranded in the North Atlantic gave scientists a rare chance to weigh its heart.",
                         "prompt": "How much did it weigh?",
                         "options": ["18 kg", "180 kg", "1,800 kg", "18,000 kg"],
                         "level": "easy", "storyId": "nature-1-whale"}],
          "wagerQuestion": 4}
reveal:  {"answers": [1, 0, 2, 3, 1],
          "explanations": ["180 kg, the largest heart known in any animal. When the whale dives it can slow to two beats a minute."]}
```
Exactly five questions, four distinct options each, `answers[i]` is the index of the correct option, one
explanation per question (two plain sentences, warm not wry), every question names its story. Every
question carries a `lead`: one or two sentences that give a reader who has not seen the story the context
they need, never the answer (the validator rejects a lead containing the correct option). `level` is
`easy`, `medium` or `hard` (default medium). The mix is three easy questions on the biggest headlines
of the day, one medium and one hard; questions run easy to hard and the wager is the last. One point per
correct answer. Before the wager question (index `wagerQuestion`, default 4) a player with at least one
point may stake one: correct scores 2 for that question, wrong loses the stake. `maxPoints` is 6.
Result: `points`, `maxPoints: 6`, `solved: true` (a finished quiz is always a result), one `shareLines`
entry of 🟩/🟥 per question with ⭐ before the wager mark when staked.

### Story seeding of the classics

The same stories seed the classics so the paper reads as one edition. Seeding is optional per puzzle;
an unseeded puzzle is a plain classic. When seeded:

* `storyId` at record level names the story.
* **word**: `payload.teaser` ("Today's word comes from a story about the deep sea."), `reveal.excerpt`
  (the sentence from the story containing the answer). The answer must appear verbatim in the excerpt
  and be in the shipped guess list.
* **letters**: `payload.teaser`, `reveal.excerpt` containing the pangram. The pangram must be one of
  `reveal.pangrams`.
* **crossword**: seeded clues carry `storyId`; `payload.teaser`; `reveal.seeded` lists
  `{"label": "5 Across", "storyId": "...", "excerpt": "..."}` and each answer appears verbatim in its excerpt.

The validator checks every one of those rules mechanically.

### Edition templates (`content_src/evergreen/<slug>.json`, `content_src/news/<date>.json`)

```json
{
  "slug": "nature-1", "label": "Evergreen · Nature",
  "stories": [ {Story}, {Story}, {Story} ],
  "quiz": {"payload": {...}, "reveal": {...}},
  "seeds": {
    "word":      {"answer": "WHALES", "storyId": "...", "teaser": "...", "excerpt": "..."},
    "letters":   {"pangram": "EXPLORE", "storyId": "...", "teaser": "...", "excerpt": "..."} | null,
    "crossword": [{"answer": "ANGEL", "clue": "Falls in Venezuela, 979 metres tall", "storyId": "...", "excerpt": "..."}]
  }
}
```
`tool/build_content.dart` stamps a template onto each date (news file if present, else evergreen by
rotation), generates the seeded classics through the engine generators, writes the quiz, computes
`seeds`, and bumps a puzzle's version when its content differs from an existing file.

## Game screen contract

Each `lib/features/games/<game>/<game>_screen.dart` exports (the quiz likewise, `QuizScreen`):

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
