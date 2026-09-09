#!/usr/bin/env python3
"""Prepares Word Compass rank files from GloVe word vectors.

    python3 tool/compass_prepare.py --vectors PATH/glove-wiki-gigaword-300.gz \
        --from 2026-09-10 --to 2026-10-31 [--out content_src/compass/ranks] [--force] [--stats]

Reads the GloVe 6B 300d vectors (gensim-data ``glove-wiki-gigaword-300.gz``,
word2vec text format: a "count dim" header, then "word v1 ... v300" per line),
restricts the vocabulary to common dictionary words, and for every date writes
``<out>/<date>.json`` with the target word and its 5,000 nearest vocabulary
words ranked by cosine similarity. Only numpy is needed. The file holds
``ranks`` (word to rank, 1 = nearest, the target itself excluded), ``similarity``
(cosine values in rank order, 3 decimals, kept as a list so the file stays
under 120 KB), ``vocabularySize`` (the number of ranked words), ``poolSize``
(the size of the vocabulary the ranks were drawn from) and the licence line.

The vectors (394,362,229 bytes) are not kept in the repository. Download them
outside it, run the script, then delete them:

    curl -L -o /path/to/glove-wiki-gigaword-300.gz \
      https://github.com/piskvorky/gensim-data/releases/download/glove-wiki-gigaword-300/glove-wiki-gigaword-300.gz

Licence: the GloVe pre-trained vectors are released by the Stanford NLP Group
under the Open Data Commons Public Domain Dedication and License v1.0
(https://nlp.stanford.edu/projects/glove/). See docs/compass-feasibility.md.
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import json
import os
import re
import sys

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENABLE_PATH = os.path.join(REPO, "tool", "data", "enable1.txt")
FREQUENCY_PATH = os.path.join(REPO, "tool", "data", "en_50k.txt")
TARGETS_PATH = os.path.join(REPO, "content_src", "compass", "targets.txt")
DEFAULT_OUT = os.path.join(REPO, "content_src", "compass", "ranks")
VECTORS_URL = (
    "https://github.com/piskvorky/gensim-data/releases/download/"
    "glove-wiki-gigaword-300/glove-wiki-gigaword-300.gz"
)

FREQUENCY_LIMIT = 40_000
MIN_LENGTH = 3
MAX_LENGTH = 12
TOP = 5_000
REPEAT_WINDOW_DAYS = 60
# The first edition date with a Word Compass puzzle. Target selection walks
# forward from here so a date's target never depends on the range requested.
EPOCH = dt.date(2026, 9, 10)

LICENCE = (
    "Ranks derived from GloVe 6B 300d (Wikipedia 2014 + Gigaword 5), Stanford NLP Group, "
    "Open Data Commons Public Domain Dedication and License v1.0, via gensim-data glove-wiki-gigaword-300"
)

# Slurs and the crudest profanity, kept out of the vocabulary so they are never
# shown as hints or counted as close guesses.
BLOCKLIST = frozenset(
    """
    nigger nigga niggers niggas negro negroes faggot faggots fag fags dyke dykes kike kikes
    spic spics chink chinks gook gooks wetback wetbacks raghead towelhead tranny trannies
    retard retards retarded cunt cunts whore whores slut sluts cocksucker motherfucker
    motherfuckers fuck fucks fucked fucking fucker fuckers shit shits shitty bullshit
    asshole assholes bitch bitches bastard bastards pussy pussies dick dicks cock cocks
    twat wanker wankers jap japs paki pakis coon coons darkie darkies honky honkies
    rape raped rapist rapists molest molested molester pedophile paedophile
    """.split()
)

WORD = re.compile(r"^[a-z]+$")


def fnv1a(text: str) -> int:
    """Stable 32-bit FNV-1a, the same function tool/_common.dart uses for seeds."""
    h = 0x811C9DC5
    for b in text.encode("utf-8"):
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def parse_date(text: str) -> dt.date:
    try:
        return dt.date.fromisoformat(text)
    except ValueError:
        raise SystemExit(f"error: bad date {text!r}, expected YYYY-MM-DD")


def read_enable(path: str) -> set[str]:
    with open(path, encoding="utf-8") as f:
        return {line.strip().lower() for line in f if line.strip()}


def read_frequent(path: str, limit: int) -> set[str]:
    words: set[str] = set()
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f):
            if n >= limit:
                break
            parts = line.split()
            if parts:
                words.add(parts[0].lower())
    return words


def candidate_vocabulary() -> set[str]:
    enable = read_enable(ENABLE_PATH)
    frequent = read_frequent(FREQUENCY_PATH, FREQUENCY_LIMIT)
    return {
        w
        for w in enable & frequent
        if WORD.match(w) and MIN_LENGTH <= len(w) <= MAX_LENGTH and w not in BLOCKLIST
    }


def load_vectors(path: str, wanted: set[str]) -> tuple[list[str], np.ndarray]:
    """Streams the gzipped word2vec text file and keeps only [wanted] words."""
    if not os.path.exists(path):
        raise SystemExit(f"error: vectors not found at {path}; download {VECTORS_URL}")
    words: list[str] = []
    rows: list[np.ndarray] = []
    seen: set[str] = set()
    dim = None
    with gzip.open(path, "rt", encoding="utf-8", errors="strict") as f:
        for line in f:
            space = line.find(" ")
            if space <= 0:
                continue
            word = line[:space]
            if word not in wanted or word in seen:
                continue
            values = np.array(line[space + 1 :].split(), dtype=np.float32)
            if dim is None:
                dim = values.size
            elif values.size != dim:
                raise SystemExit(f"error: vector for {word!r} has {values.size} values, expected {dim}")
            seen.add(word)
            words.append(word)
            rows.append(values)
    if not rows:
        raise SystemExit("error: no vocabulary words found in the vector file")
    matrix = np.vstack(rows)
    norms = np.linalg.norm(matrix, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    return words, matrix / norms


def read_targets(path: str, vocabulary: set[str]) -> list[str]:
    targets: list[str] = []
    with open(path, encoding="utf-8") as f:
        for n, raw in enumerate(f, start=1):
            line = raw.strip().lower()
            if not line or line.startswith("#"):
                continue
            if not WORD.match(line):
                raise SystemExit(f"error: {path}:{n}: target {line!r} is not lowercase a-z")
            if line in targets:
                raise SystemExit(f"error: {path}:{n}: duplicate target {line!r}")
            if line not in vocabulary:
                raise SystemExit(f"error: {path}:{n}: target {line!r} is not in the vocabulary")
            targets.append(line)
    if len(targets) < REPEAT_WINDOW_DAYS:
        raise SystemExit(f"error: need at least {REPEAT_WINDOW_DAYS} targets, found {len(targets)}")
    return targets


def schedule(targets: list[str], until: dt.date) -> dict[dt.date, str]:
    """Target per date from EPOCH to [until]: FNV-1a of "compass-<date>" mod the
    list, stepping forward past any word used in the previous 59 days."""
    chosen: dict[dt.date, str] = {}
    day = EPOCH
    while day <= until:
        recent = {chosen[d] for d in chosen if (day - d).days < REPEAT_WINDOW_DAYS}
        index = fnv1a(f"compass-{day.isoformat()}") % len(targets)
        for step in range(len(targets)):
            word = targets[(index + step) % len(targets)]
            if word not in recent:
                break
        else:
            raise SystemExit(f"error: no unused target for {day}")
        chosen[day] = word
        day += dt.timedelta(days=1)
    return chosen


def rank_file(target: str, words: list[str], matrix: np.ndarray, index: dict[str, int]) -> dict:
    t = index[target]
    sims = matrix @ matrix[t]
    sims[t] = -np.inf
    top = min(TOP, len(words) - 1)
    nearest = np.argpartition(-sims, top - 1)[:top]
    nearest = nearest[np.argsort(-sims[nearest], kind="stable")]
    ranks = {words[i]: r + 1 for r, i in enumerate(nearest)}
    similarity = [round(float(sims[i]), 3) for i in nearest]
    return {
        "target": target,
        "vocabularySize": top,
        "poolSize": len(words),
        "ranks": ranks,
        "similarity": similarity,
        "similarityNote": "similarity[i] is the cosine similarity between the target and the word at rank i+1",
        "licence": LICENCE,
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--from", dest="start", required=True, help="first date, YYYY-MM-DD")
    ap.add_argument("--to", dest="end", required=True, help="last date, YYYY-MM-DD")
    ap.add_argument("--vectors", required=True, help="path to glove-wiki-gigaword-300.gz")
    ap.add_argument("--out", default=DEFAULT_OUT, help="directory for <date>.json files")
    ap.add_argument("--force", action="store_true", help="overwrite existing files")
    ap.add_argument("--stats", action="store_true", help="print the vocabulary size and exit")
    args = ap.parse_args(argv)

    start, end = parse_date(args.start), parse_date(args.end)
    if end < start:
        raise SystemExit("error: --to is before --from")
    if start < EPOCH:
        raise SystemExit(f"error: --from is before the schedule epoch {EPOCH}")

    wanted = candidate_vocabulary()
    print(f"candidate vocabulary: {len(wanted)} words (enable1 ∩ top {FREQUENCY_LIMIT} en_50k)")
    words, matrix = load_vectors(args.vectors, wanted)
    index = {w: i for i, w in enumerate(words)}
    print(f"vectors loaded: {len(words)} words × {matrix.shape[1]} dims")
    if args.stats:
        return 0

    targets = read_targets(TARGETS_PATH, set(words))
    plan = schedule(targets, end)

    os.makedirs(args.out, exist_ok=True)
    written = skipped = 0
    largest = 0
    day = start
    while day <= end:
        path = os.path.join(args.out, f"{day.isoformat()}.json")
        if os.path.exists(path) and not args.force:
            skipped += 1
        else:
            data = rank_file(plan[day], words, matrix, index)
            data["date"] = day.isoformat()
            text = json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=False)
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
                f.write("\n")
            size = len(text.encode("utf-8")) + 1
            largest = max(largest, size)
            written += 1
            nearest = list(data["ranks"])[:5]
            print(f"{day}  {plan[day]:<12} {size / 1024:6.1f} KB  nearest: {', '.join(nearest)}")
        day += dt.timedelta(days=1)

    print(f"written {written}, skipped {skipped}, largest file {largest / 1024:.1f} KB, out {args.out}")
    if largest > 120 * 1024:
        print("warning: a file exceeds 120 KB", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
