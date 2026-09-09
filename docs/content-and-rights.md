# Content and rights

This file records where every game mechanic, dataset, font, picture and piece of text comes from,
the licence it carries, what attribution it requires, and what is unresolved. It is a working
record, not legal advice or a certification.

## Naming checks

Working labels in the app and their checks (a changed name is not clearance; each entry says what
was checked and when):

| Label in app | Mechanic | Names avoided | Check |
|---|---|---|---|
| Daily Word | Motus-style word guessing | Wordle, Motus | Generic description used; 2026-09-07 |
| Letters | bee-style spelling | Spelling Bee | Generic description used; 2026-09-07 |
| Mini Crossword | 5×5 crossword | none (generic) | 2026-09-07 |
| Sudoku | sudoku | none (generic term) | 2026-09-07 |
| The Quiz | news quiz | none | 2026-09-08 |
| Bridges | Hashiwokakero | Hashi (Nikoli) | pending: module author records check |
| Binary | Takuzu / binary puzzle | Binero, Takuzu | pending |
| Nonogram | picture logic | Picross (Nintendo), Griddlers | pending |
| Kakuro | cross sums | none (generic) | pending |
| Regions | Suguru | Tectonic | pending |
| Loop | Slitherlink | Slitherlink (Nikoli) | pending |
| Target | arithmetic target | Countdown numbers game | pending |
| Tangram | tangram | none (public domain puzzle) | pending |
| 2048 | tile merging | 2048 (original MIT code by Gabriele Cirulli) | pending: attribution if code adapted |
| Uncover | hidden-story | Redactle | pending |
| Five Clues | word association | Only Connect and other TV formats | pending |
| Groups | category grouping | Connections (NYT) | pending |
| Linked Clues | layered associations | none | pending |
| Before & After | chronology | Wikitrivia | pending |
| Crossmatch | criteria grid | Immaculate Grid | pending |
| Word Compass | semantic guessing | Semantle, Contexto | pending |

## Datasets and assets

| Resource | Source | Licence | Attribution | Used for |
|---|---|---|---|---|
| ENABLE word list | dolph/dictionary (enable1.txt) | public domain | none required; credited in About | Daily Word, Letters, crossword bank check, seed helper |
| en_50k frequency list | hermitdave/FrequencyWords (OpenSubtitles 2018) | CC BY-SA 4.0 | credit required (About) | frequency filtering only; no list text is shipped |
| Natural Earth coastlines | naturalearthdata.com | public domain | none required | no longer used (Where removed) |
| Playfair Display | Google Fonts | SIL OFL 1.1 | licence file shipped in assets/fonts | typography |
| Source Sans 3 | Google Fonts | SIL OFL 1.1 | licence file shipped in assets/fonts | typography |
| Crossword clue bank | written for this app | ours | none | Mini Crossword |
| Evergreen editions | written for this app; facts from Wikipedia pages cited per story | text ours; facts CC BY-SA 4.0 sources | story links and publisher shown in app; excerpts quoted with source | The Quiz, seeds |

Module authors add rows below for anything they introduce (pictures, silhouettes, word vectors,
event sources).

## Wikipedia text

Quiz explanations, story summaries and leads are written in our own words. Where a sentence is
quoted verbatim in a `sources[].excerpt` it is shown in the app with the page linked as the source.
If any module ships adapted Wikipedia prose as player-facing text, it must state so here and
carry the CC BY-SA 4.0 notice in the About screen.

## Unresolved

Recorded by module authors; each entry names the feature, the evidence, and whether the feature
is isolated from release.
