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
| Word Compass | semantic guessing | Semantle, Contexto | Generic name and copy; neither name appears in the app, help text or share line ("🧭 solved in N guesses"); 2026-09-09 |

## Datasets and assets

| Resource | Source | Licence | Attribution | Used for |
|---|---|---|---|---|
| ENABLE word list | dolph/dictionary (enable1.txt) | public domain | none required; credited in About | Daily Word, Letters, crossword bank check, seed helper |
| en_50k frequency list | hermitdave/FrequencyWords (OpenSubtitles 2018) | CC BY-SA 4.0 | credit required (About) | frequency filtering only (Daily Word, Letters, Word Compass vocabulary); no list text is shipped |
| Natural Earth coastlines | naturalearthdata.com | public domain | none required | no longer used (Where removed) |
| Playfair Display | Google Fonts | SIL OFL 1.1 | licence file shipped in assets/fonts | typography |
| Source Sans 3 | Google Fonts | SIL OFL 1.1 | licence file shipped in assets/fonts | typography |
| Crossword clue bank | written for this app | ours | none | Mini Crossword |
| Evergreen editions | written for this app; facts from Wikipedia pages cited per story | text ours; facts CC BY-SA 4.0 sources | story links and publisher shown in app; excerpts quoted with source | The Quiz, seeds |
| GloVe word vectors, 6B tokens (Wikipedia 2014 + Gigaword 5), 300d, 400k vocabulary | Stanford NLP Group, https://nlp.stanford.edu/projects/glove/ ; file `glove-wiki-gigaword-300.gz` (394,362,229 bytes, SHA-256 `0a7aebbe…39e00`) from the gensim-data release https://github.com/piskvorky/gensim-data/releases/tag/glove-wiki-gigaword-300 | Open Data Commons Public Domain Dedication and License (PDDL) v1.0, stated on the Stanford page and the gensim-data release; verified 2026-09-09, see `docs/compass-feasibility.md` | none required; a courtesy line "Word vectors: GloVe (Stanford NLP Group)" is pending in About (outside the compass module), paper cited in `docs/compass-feasibility.md` | Word Compass: cosine-similarity ranks precomputed by `tool/compass_prepare.py` into `content_src/compass/ranks/<date>.json`; the vectors themselves are never shipped or kept in the repository |
| Word Compass targets | written for this app (`content_src/compass/targets.txt`) | ours | none | Word Compass daily target words |

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
