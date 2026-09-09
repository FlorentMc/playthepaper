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
| Bridges | Hashiwokakero-style bridge puzzle | Hashiwokakero, Hashi (Nikoli) appear only in internal doc comments, never in the app | 2026-09-09; all boards generated |
| Binary | Takuzu-style binary grid | Binairo, Binero, Takuzu, Tic-Tac-Logic avoided in the app | 2026-09-09; all boards generated |
| Nonogram | picture logic | Picross (Nintendo), Griddlers, Paint by Numbers, Hanjie, O'ekaki avoided; "Nonogram" used as the generic term | 2026-09-09; 73 original pictures drawn for this app |
| Kakuro | cross sums | generic term; no Nikoli branding | 2026-09-09; all boards generated |
| Regions | Suguru-style region grid | Suguru, Tectonic, Number Blocks, Nanbaboru avoided | 2026-09-09; all boards generated |
| Loop | Slitherlink-style loop | Slitherlink (Nikoli) only in internal doc comments | 2026-09-09; all boards generated |
| Target | arithmetic target | Countdown, Des chiffres et des lettres, Le compte est bon avoided; own tile scheme and rules text | 2026-09-09; all puzzles generated |
| Tangram | tangram | the puzzle is centuries old and public domain; silhouettes designed for this app | 2026-09-09; see module notes below |
| 2048 | tile merging | "2048" used as the game's name (not a registered mark to our knowledge); Threes! avoided; implementation written from the public rules without consulting the MIT original's source, so no notice is carried; tile colours derived from our theme | 2026-09-09 |
| Uncover | hidden-story | Redactle, Semantle-style names avoided; own summaries (32), own masking rules | 2026-09-09 |
| Five Clues | word association | Only Connect, Pointless, Mastermind, Connections avoided; no host, prizes, buzzers or wall | 2026-09-09; 30 original items |
| Groups | category grouping | Connections (NYT), Only Connect avoided; no NYT colour-difficulty scheme; own scoring | 2026-09-09; 38 original items |
| Linked Clues | layered associations | no known brand; own format | 2026-09-09; 30 original items |
| Before & After | chronology | Wikitrivia, Chronophoto avoided; own presentation | 2026-09-09; 30 sourced items |
| Crossmatch | criteria grid | Immaculate Grid avoided; own criteria and tiles | 2026-09-09; 30 sourced items |
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

| Nonogram pictures | drawn for this app (content_src/nonogram/pictures.json) | ours | none | Nonogram |
| Tangram silhouettes | designed for this app (content_src/tangram/silhouettes.json) | ours | none | Tangram |
| Editorial reserves | written for this app (content_src/editorial/*); facts from English Wikipedia pages cited per item | text ours; excerpts CC BY-SA 4.0 | publisher and page linked in the reveal; see "Wikipedia text" | Uncover, Five Clues, Groups, Linked Clues, Before & After, Crossmatch |

## Wikipedia text

Quiz explanations, story summaries, leads, clues, Uncover summaries and all other player-facing
prose are written in our own words. Sentences quoted verbatim from Wikipedia live only in
`sources[].excerpt` fields and are shown in the app as attributed quotations with the page linked.
Wikipedia text is CC BY-SA 4.0; the About screen carries the attribution and licence notice.
No module ships adapted Wikipedia prose as its own text. Facts were verified against the live
pages at authoring time by each module's author (Uncover re-verified all 32 items and corrected
three claims; Groups spot-checked 16 of 456 excerpts verbatim; Five Clues and Linked Clues verified
every excerpt character for character with the MediaWiki extracts API).

## Unresolved

* The name "2048" is used for the tile game on the understanding that it is not a registered
  trade mark; this has not been checked against a trade mark register. If clearance fails, the
  label is a one-line change (`GameKind.merge` title) and nothing else in the app depends on it.
* Word Compass ships ranks derived from GloVe vectors (PDDL, no attribution required). The
  vocabulary was filtered by the en_50k frequency list (CC BY-SA 4.0), which is credited in About;
  no list text is shipped.
* Nothing is isolated from release on rights grounds at the time of writing.
