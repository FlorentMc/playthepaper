# Word Compass: content feasibility

Word Compass (slug `compass`) needs, for every edition date, the 5,000 words nearest to a hidden
target word, ranked by cosine similarity in a real word-vector space. The ranking is computed once
at content-preparation time and shipped as static JSON; the app never computes similarity.

## Chosen resource

**GloVe, Wikipedia 2014 + Gigaword 5 (6B tokens, 400,000-word uncased vocabulary), 300 dimensions**,
Stanford NLP Group (Pennington, Socher and Manning, 2014), in the gensim-data redistribution.

| Item | Value |
|---|---|
| Original source | https://nlp.stanford.edu/projects/glove/ (the `glove.6B.zip` bundle, 822 MB, all four dimensionalities) |
| File used | `glove-wiki-gigaword-300.gz` from https://github.com/piskvorky/gensim-data/releases/tag/glove-wiki-gigaword-300 (the 300d member of glove.6B converted to word2vec text format; 400,000 vectors, 300 dimensions) |
| Download URL | https://github.com/piskvorky/gensim-data/releases/download/glove-wiki-gigaword-300/glove-wiki-gigaword-300.gz |
| Size | 394,362,229 bytes (376.1 MiB) as reported by the GitHub release API and verified after download; SHA-256 `0a7aebbe49097dc6e5ffff7a25e9aa20181a6e862050ca68bd2f36e056739e00` |
| Licence | Open Data Commons Public Domain Dedication and License (PDDL) v1.0, https://opendatacommons.org/licenses/pddl/1-0/ |
| Attribution requirement | None. PDDL is a public-domain dedication with no attribution or share-alike condition. A courtesy credit "Word vectors: GloVe (Stanford NLP Group)" is recorded in `docs/content-and-rights.md` and pending in the About screen (outside the compass module); the paper is cited below. |

Licence verification, 2026-09-09:

* The Stanford GloVe project page states, under "Pre-trained word vectors": "This data is made
  available under the Public Domain Dedication and License v1.0 whose full text can be found at:
  http://www.opendatacommons.org/licenses/pddl/1.0/". The GloVe *code* is Apache 2.0; we use only the
  vectors.
* The gensim-data release page for `glove-wiki-gigaword-300` lists `License | http://opendatacommons.org/licenses/pddl/`
  and links back to the Stanford page as the origin.
* The PDDL text at opendatacommons.org was fetched and read; it dedicates the data to the public
  domain (or grants an unconditional licence where a dedication is not possible) with no conditions.

Citation: Jeffrey Pennington, Richard Socher and Christopher D. Manning. 2014. *GloVe: Global Vectors
for Word Representation.* Proceedings of EMNLP.

## Alternatives considered

| Candidate | Why not |
|---|---|
| `glove-wiki-gigaword-100` (gensim-data, 134,300,434 bytes, PDDL) | Same licence and origin, a third of the size, but 100-dimensional neighbourhoods are noticeably noisier than 300d. The 300d file is within the 400 MB budget, so it was preferred. It remains the fallback if disk gets tighter. |
| Stanford `glove.6B.zip` direct | 822 MB, over budget (it bundles 50d, 100d, 200d and 300d). |
| Stanford `glove.2024.wikigiga.50d.zip` | 290 MB, on the source site, PDDL, but only 50 dimensions; the 100d 2024 file is 560 MB. |
| fastText English (`wiki-news-300d-1M`, `crawl-300d-2M`) | CC BY-SA 3.0 (share-alike on derived data) and 600 MB to 1.5 GB downloads. |
| word2vec GoogleNews 300d | ~1.6 GB and no clear licence statement. |

## What is derived and shipped

Only small derived data lives in the repository: `content_src/compass/targets.txt` (the curated
target list, ours) and `content_src/compass/ranks/<date>.json` (target, vocabulary size, the 5,000
nearest vocabulary words with their rank and cosine similarity rounded to 3 decimals, and the licence
line). The vector file is deleted from the scratch directory once the ranks are prepared. Re-running
`tool/compass_prepare.py` re-downloads it on demand.

Preparation is reproducible: the target for a date comes from FNV-1a of `compass-<date>` walked
forward from the 2026-09-10 epoch, so it does not depend on the range requested, and re-running the
script for a subset of dates (2026-09-25 to 2026-09-27, checked 2026-09-09 before the vectors were deleted)
reproduces the shipped files byte for byte. The candidate vocabulary is 27,103 words, of which 27,042
have a GloVe vector; each day ranks the nearest 5,000 of them, and the largest file is 102 KB.

The vocabulary the ranks are drawn from is the intersection of `tool/data/enable1.txt` (public
domain) and the first 40,000 entries of `tool/data/en_50k.txt` (CC BY-SA 4.0, used for filtering
only; no list text is shipped beyond the words that happen to appear in a day's ranks, which are
ordinary English words and not the list), lowercase alphabetic, 3 to 12 letters, minus a short
blocklist, and present in the GloVe vocabulary.

## Verdict

Feasible. Fully offline play from static JSON, real similarities from a public-domain vector set, no
new Dart dependencies, and about 100 KB per day of content.
