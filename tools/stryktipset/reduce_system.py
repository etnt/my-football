#!/usr/bin/env python3
"""Build a reduced Stryktipset system ("reducerat system") from a full system.

A full system is 13 entries such as "1", "X", "1X", "X2" or "1X2". Its rows
are every combination of the entries. The full system can cost a lot. A
reduced system is a smaller set of single rows ("enkelrader") with a
guarantee: if the real result is one of the rows of the full system, then at
least one row in the reduced system has at least G correct matches.

In coding-theory terms this is a covering code: every row of the full system
must be within Hamming distance R = 13 - G of a selected row.

Algorithms:
  greedy  Pick the row that covers the most uncovered rows, repeat. Uses
          random tie-breaks and several restarts. Then drops redundant rows.
  anneal  Start with the greedy result, then use simulated annealing to try
          to cover the full system with fewer rows. Slower, often smaller.

The output file follows the Svenska Spel "Externa systemspel" format:

    Stryktipset
    E,1,X,2,1,X,2,1,X,2,1,X,2,1
    ...
"""
from __future__ import annotations

import argparse
import itertools
import math
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np

NUM_MATCHES = 13
SIGNS = ("1", "X", "2")
MAX_FILE_ROWS = 10_000          # Svenska Spel limit for single rows per file
MAX_STAKE_SEK = 20_000          # Svenska Spel limit for total stake
DEFAULT_MAX_NEIGHBOUR_CELLS = 250_000_000  # ~1 GB of int32


# --------------------------------------------------------------------------
# Input parsing
# --------------------------------------------------------------------------
def parse_system(text: str, num_matches: int = NUM_MATCHES) -> list[str]:
    """Parse "1,x,x2,..." into a list of normalised entries like ["1","X","X2"].

    Each entry must contain one to three different signs out of 1, X and 2.
    The signs are returned in the order 1, X, 2.
    """
    parts = [p.strip().upper() for p in text.split(",")]
    if len(parts) != num_matches:
        raise ValueError(
            f"the system must have {num_matches} entries, got {len(parts)}: {text!r}"
        )
    entries: list[str] = []
    for i, part in enumerate(parts, start=1):
        if not part:
            raise ValueError(f"match {i}: empty entry")
        bad = set(part) - set(SIGNS)
        if bad:
            raise ValueError(
                f"match {i}: invalid sign(s) {''.join(sorted(bad))!r} in {part!r};"
                " use 1, X and 2"
            )
        if len(set(part)) != len(part):
            raise ValueError(f"match {i}: repeated sign in {part!r}")
        entries.append("".join(s for s in SIGNS if s in part))
    return entries


# --------------------------------------------------------------------------
# Full system model (mixed-radix indexing)
# --------------------------------------------------------------------------
@dataclass
class FullSystem:
    entries: list[str]          # e.g. ["1", "X", "1X2", ...]
    radix: np.ndarray           # options per match, shape (13,)
    weights: np.ndarray         # mixed-radix place values, shape (13,)
    digits: np.ndarray          # (N, 13) uint8: option index per match
    size: int

    @classmethod
    def build(cls, entries: list[str]) -> "FullSystem":
        radix = np.array([len(e) for e in entries], dtype=np.int64)
        size = int(np.prod(radix))
        # Match 1 is the most significant digit.
        weights = np.ones(len(entries), dtype=np.int64)
        for i in range(len(entries) - 2, -1, -1):
            weights[i] = weights[i + 1] * radix[i + 1]
        idx = np.arange(size, dtype=np.int64)
        digits = ((idx[:, None] // weights[None, :]) % radix[None, :]).astype(np.uint8)
        return cls(entries, radix, weights, digits, size)

    def row_signs(self, index: int) -> list[str]:
        return [self.entries[m][d] for m, d in enumerate(self.digits[index])]


def ball_patterns(radix: np.ndarray, radius: int):
    """Yield (positions, shifts) for every change of 1..radius matches.

    Patterns are produced by increasing distance, so the first ones in the
    neighbour table are the distance-1 neighbours.
    """
    free = [i for i, m in enumerate(radix) if m > 1]
    for k in range(1, radius + 1):
        for positions in itertools.combinations(free, k):
            ranges = [range(1, int(radix[p])) for p in positions]
            for shifts in itertools.product(*ranges):
                yield positions, shifts


def ball_size(radix: np.ndarray, radius: int) -> int:
    free = [int(m) - 1 for m in radix if m > 1]
    total = 1
    for k in range(1, radius + 1):
        for combo in itertools.combinations(free, k):
            total += math.prod(combo)
    return total


def neighbour_table(fs: FullSystem, radius: int) -> tuple[np.ndarray, int]:
    """Return (table, n_dist1) where table[i] lists all rows within `radius`.

    Column 0 is the row itself. Columns 1..n_dist1 are distance-1 neighbours.
    """
    b = ball_size(fs.radix, radius)
    table = np.empty((fs.size, b), dtype=np.int32)
    idx = np.arange(fs.size, dtype=np.int64)
    table[:, 0] = idx
    digits = fs.digits.astype(np.int64)
    col = 1
    n_dist1 = 0
    for positions, shifts in ball_patterns(fs.radix, radius):
        nb = idx.copy()
        for p, s in zip(positions, shifts):
            d = digits[:, p]
            nb += (((d + s) % fs.radix[p]) - d) * fs.weights[p]
        table[:, col] = nb
        if len(positions) == 1:
            n_dist1 += 1
        col += 1
    assert col == b
    return table, n_dist1


# --------------------------------------------------------------------------
# Algorithms
# --------------------------------------------------------------------------
def greedy_cover(nbr: np.ndarray, rng: np.random.Generator,
                 max_rows: int | None, randomise: bool,
                 initial: list[int] | None = None) -> list[int]:
    """Greedy covering. Stops when all rows are covered or at max_rows.

    `initial` rows are kept and count towards max_rows.
    """
    n, b = nbr.shape
    chosen: list[int] = list(dict.fromkeys(initial or []))
    if chosen:
        covered = coverage_counts(nbr, chosen) > 0
        gain = (~covered)[nbr].sum(axis=1, dtype=np.int32)
    else:
        covered = np.zeros(n, dtype=bool)
        gain = np.full(n, b, dtype=np.int32)
    remaining = int(n - covered.sum())
    while remaining > 0 and (max_rows is None or len(chosen) < max_rows):
        best = gain.max()
        if randomise:
            cands = np.flatnonzero(gain == best)
            c = int(cands[rng.integers(len(cands))])
        else:
            c = int(gain.argmax())
        chosen.append(c)
        ball = nbr[c]
        new = ball[~covered[ball]]
        covered[new] = True
        remaining -= len(new)
        # Every candidate whose ball holds a newly covered row loses 1 gain.
        # The ball relation is symmetric, so these are the balls of `new`.
        np.subtract.at(gain, nbr[new].ravel(), 1)
    return chosen


def pad_rows(fs: "FullSystem", chosen: list[int], target: int, radius: int,
             rng: np.random.Generator, max_cells: int, log) -> list[int]:
    """Add rows until there are `target` rows.

    The guarantee is already met, so the new rows aim at a better result:
    first cover as many outcomes as possible with radius-1 (one more correct
    match), then radius-2, and so on. At radius 0 any unused row is added.
    """
    chosen = list(dict.fromkeys(chosen))
    for rr in range(radius - 1, -1, -1):
        if len(chosen) >= target:
            break
        if rr == 0:
            used = np.zeros(fs.size, dtype=bool)
            used[chosen] = True
            free = np.flatnonzero(~used)
            extra = rng.choice(free, size=target - len(chosen), replace=False)
            chosen += [int(x) for x in extra]
            log(f"  padding: +{len(extra)} unused rows")
            break
        if fs.size * ball_size(fs.radix, rr) > max_cells:
            log(f"  padding: table for {NUM_MATCHES - rr} correct too large, "
                "skipping that level")
            continue
        nbr_rr, _ = neighbour_table(fs, rr)
        before = len(chosen)
        chosen = greedy_cover(nbr_rr, rng, target, True, initial=chosen)
        cov = int((coverage_counts(nbr_rr, chosen) > 0).sum())
        log(f"  padding: +{len(chosen) - before} rows for "
            f"{NUM_MATCHES - rr} correct, now covering {cov}/{fs.size}")
    return chosen


def coverage_counts(nbr: np.ndarray, chosen) -> np.ndarray:
    return np.bincount(nbr[np.asarray(chosen, dtype=np.int64)].ravel(),
                       minlength=nbr.shape[0]).astype(np.int32)


def drop_redundant(nbr: np.ndarray, chosen: list[int],
                   rng: np.random.Generator) -> list[int]:
    """Remove rows whose whole ball is also covered by other rows."""
    chosen = list(dict.fromkeys(chosen))  # remove duplicates, keep order
    cnt = coverage_counts(nbr, chosen)
    order = list(rng.permutation(len(chosen)))
    keep = [True] * len(chosen)
    for i in order:
        ball = nbr[chosen[i]]
        if cnt[ball].min() >= 2:
            cnt[ball] -= 1
            keep[i] = False
    return [c for c, k in zip(chosen, keep) if k]


def anneal(nbr: np.ndarray, n_dist1: int, start: list[int], iterations: int,
           rng: np.random.Generator, t_start: float, t_end: float,
           log=None, sample: int = 12,
           deadline: float | None = None) -> tuple[list[int], int]:
    """Simulated annealing with a fixed number of rows.

    Minimises the number of uncovered outcomes and stops at zero.

    Each step picks a random uncovered outcome u. Candidate moves change one
    sign of a selected row c so that the new row v covers u (c is then at
    distance radius+1 from u). Up to `sample` candidates are scored and the
    best is proposed. The proposal is accepted with the Metropolis rule.
    Returns (best rows, uncovered outcomes for those rows).
    """
    n, b = nbr.shape
    chosen = np.array(list(dict.fromkeys(start)), dtype=np.int64)
    k = len(chosen)
    where = np.full(n, -1, dtype=np.int64)    # row -> index in chosen
    where[chosen] = np.arange(k)
    cnt = coverage_counts(nbr, chosen)
    uncovered = int((cnt == 0).sum())
    best, best_unc = chosen.copy(), uncovered
    if uncovered == 0 or k == 0 or n_dist1 == 0:
        return list(map(int, best)), best_unc

    def delta_of(old: int, new: int) -> int:
        b_old, b_new = nbr[old], nbr[new]
        cnt[b_old] -= 1
        d = int((cnt[b_old] == 0).sum()) - int((cnt[b_new] == 0).sum())
        cnt[b_old] += 1
        return d

    unc_cache = np.flatnonzero(cnt == 0)
    for it in range(iterations):
        t = t_start * (t_end / t_start) ** (it / max(1, iterations - 1))
        if it % 200 == 0 or not len(unc_cache):
            if deadline is not None and time.perf_counter() > deadline:
                break
            unc_cache = np.flatnonzero(cnt == 0)
        u = int(unc_cache[rng.integers(len(unc_cache))])
        if cnt[u] != 0:
            unc_cache = np.flatnonzero(cnt == 0)
            u = int(unc_cache[rng.integers(len(unc_cache))])

        ball_u = nbr[u]                                  # rows v covering u
        near = nbr[ball_u, 1:1 + n_dist1]                # (b, n_dist1)
        jj, kk = np.nonzero(where[near] >= 0)
        if len(jj):
            pick = rng.choice(len(jj), size=min(sample, len(jj)), replace=False)
            moves = [(int(near[jj[p], kk[p]]), int(ball_u[jj[p]])) for p in pick]
        else:
            # No selected row is close to u: move a random row onto u's ball.
            moves = [(int(chosen[rng.integers(k)]),
                      int(ball_u[rng.integers(b)]))]
        moves = [(o, v) for o, v in moves if where[v] < 0]
        if not moves:
            continue
        scored = [(delta_of(o, v), rng.random(), o, v) for o, v in moves]
        delta, _, old, new = min(scored)
        if delta <= 0 or rng.random() < math.exp(-delta / t):
            i = int(where[old])
            cnt[nbr[old]] -= 1
            cnt[nbr[new]] += 1
            where[old], where[new] = -1, i
            chosen[i] = new
            uncovered += delta
            if uncovered < best_unc:
                best, best_unc = chosen.copy(), uncovered
                if best_unc == 0:
                    break
    if log:
        log(f"    anneal {k} rows: best uncovered={best_unc} "
            f"after {it + 1} iterations")
    return list(map(int, best)), best_unc


# --------------------------------------------------------------------------
# Evaluation
# --------------------------------------------------------------------------
def hit_distribution(fs: FullSystem, chosen: list[int],
                     max_ops: float = 3e9) -> dict[int, int] | None:
    """For each row of the full system, find the best number of correct
    matches among the chosen rows. Return {correct: number of outcomes}.

    Returns None if the work would be too large.
    """
    k = len(chosen)
    if k == 0 or fs.size * k * fs.digits.shape[1] > max_ops:
        return None
    code = fs.digits[np.asarray(chosen)]
    best = np.empty(fs.size, dtype=np.int16)
    chunk = max(1, int(2e7 // (k * fs.digits.shape[1])))
    for s in range(0, fs.size, chunk):
        part = fs.digits[s:s + chunk]
        eq = (part[:, None, :] == code[None, :, :]).sum(axis=2)
        best[s:s + chunk] = eq.max(axis=1)
    values, counts = np.unique(best, return_counts=True)
    return {int(v): int(c) for v, c in zip(values, counts)}


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------
def write_file(path: Path, product: str, rows: list[list[str]],
               newline: str) -> None:
    lines = [product] + ["E," + ",".join(r) for r in rows]
    path.write_text(newline.join(lines) + newline, encoding="ascii")


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Create a reduced Stryktipset system of single rows "
                    "with a guaranteed number of correct matches.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("system",
                   help='13 comma-separated entries, e.g. '
                        '"1,x,x2,2,1,1x2,1,x,1,2,1x,1,1x"')
    p.add_argument("-g", "--guarantee", type=int, default=12,
                   help="guaranteed correct matches if the result is in the "
                        "full system (13 = no reduction)")
    size = p.add_mutually_exclusive_group()
    size.add_argument("-n", "--max-rows", type=int, default=None,
                      help="upper limit on rows. If the guarantee needs more "
                           "rows, the best partial cover is written and the "
                           "real coverage is reported")
    size.add_argument("-k", "--rows", type=int, default=None,
                      help="exact number of rows. If the guarantee needs "
                           "more, the best partial cover is written; if it "
                           "needs fewer, extra rows are added that aim for "
                           "more correct matches")
    p.add_argument("-a", "--algorithm", choices=("greedy", "anneal"),
                   default="greedy", help="reduction algorithm")
    p.add_argument("-r", "--restarts", type=int, default=10,
                   help="greedy restarts with random tie-breaks; the "
                        "smallest result is kept")
    p.add_argument("-i", "--iterations", type=int, default=200_000,
                   help="anneal: iterations per attempt")
    p.add_argument("--time-limit", type=float, default=None,
                   help="anneal: stop searching after this many seconds")
    p.add_argument("--sample", type=int, default=12,
                   help="anneal: candidate moves scored per iteration")
    p.add_argument("--t-start", type=float, default=0.6,
                   help="anneal: start temperature")
    p.add_argument("--t-end", type=float, default=0.1,
                   help="anneal: end temperature")
    p.add_argument("--seed", type=int, default=None,
                   help="random seed for reproducible output")
    p.add_argument("-o", "--output", type=Path, default=None,
                   help="output file, or an existing directory for the "
                        "automatic name. Default: an automatic name in the "
                        "current directory that shows the input criteria, "
                        "e.g. stryktipset_1-X-X2-..._g12_k100_greedy.txt")
    p.add_argument("--product", default="Stryktipset",
                   choices=("Stryktipset", "Europatipset"),
                   help="product name on the first line of the file")
    p.add_argument("--crlf", action="store_true",
                   help="write Windows line endings (CRLF)")
    p.add_argument("--row-price", type=float, default=1.0,
                   help="price per row in SEK, used for the cost report")
    p.add_argument("--no-verify", action="store_true",
                   help="skip the hit-distribution report")
    p.add_argument("--max-memory-cells", type=int,
                   default=DEFAULT_MAX_NEIGHBOUR_CELLS,
                   help="limit for the neighbour table (rows x ball size)")
    p.add_argument("-v", "--verbose", action="store_true",
                   help="write search progress to stderr")
    p.add_argument("-q", "--quiet", action="store_true",
                   help="do not print the summary on stdout")
    return p


def default_filename(product: str, entries: list[str], guarantee: int,
                     rows: int | None, max_rows: int | None,
                     algorithm: str, seed: int | None) -> str:
    """File name that shows the input criteria, e.g.
    stryktipset_1-X-X2-2-1-1X2-1-X-1-2-1X-1-1X_g12_k100_greedy.txt"""
    parts = [product.lower(), "-".join(entries), f"g{guarantee}"]
    if rows is not None:
        parts.append(f"k{rows}")
    if max_rows is not None:
        parts.append(f"n{max_rows}")
    parts.append(algorithm)
    if seed is not None:
        parts.append(f"s{seed}")
    return "_".join(parts) + ".txt"


def resolve_output(args, entries: list[str]) -> Path:
    name = default_filename(args.product, entries, args.guarantee, args.rows,
                            args.max_rows, args.algorithm, args.seed)
    if args.output is None:
        return Path(name)
    if args.output.is_dir():
        return args.output / name
    return args.output


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    def log(*a):
        """Search progress: stderr, only with --verbose."""
        if args.verbose:
            print(*a, file=sys.stderr)

    def warn(msg: str):
        print(f"warning: {msg}", file=sys.stderr)

    try:
        entries = parse_system(args.system)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    if not 1 <= args.guarantee <= NUM_MATCHES:
        print(f"error: --guarantee must be 1..{NUM_MATCHES}", file=sys.stderr)
        return 2
    limit = args.rows if args.rows is not None else args.max_rows
    if limit is not None and limit < 1:
        print("error: --rows/--max-rows must be at least 1", file=sys.stderr)
        return 2

    rng = np.random.default_rng(args.seed)
    fs = FullSystem.build(entries)
    radius = NUM_MATCHES - args.guarantee
    if args.rows is not None and args.rows > fs.size:
        print(f"error: --rows {args.rows} is more than the {fs.size} rows "
              "of the full system", file=sys.stderr)
        return 2

    t0 = time.perf_counter()
    deadline = None if args.time_limit is None else t0 + args.time_limit
    lower_bound: int | None = None
    needed: int | None = None       # rows needed for the full guarantee
    if radius == 0 or fs.size == 1:
        needed = fs.size
        chosen = list(range(fs.size))
        if limit is not None and limit < fs.size:
            chosen = [int(x) for x in rng.choice(fs.size, size=limit,
                                                 replace=False)]
    else:
        b = ball_size(fs.radix, radius)
        if fs.size * b > args.max_memory_cells:
            print(f"error: neighbour table too large ({fs.size} x {b} cells). "
                  "Use a smaller system, a higher --guarantee, or raise "
                  "--max-memory-cells.", file=sys.stderr)
            return 2
        nbr, n_dist1 = neighbour_table(fs, radius)
        lower_bound = math.ceil(fs.size / b)
        log(f"Each row covers {b} rows. Lower bound (sphere covering): "
            f"{lower_bound} rows")

        # Greedy with restarts, always to full cover.
        best: list[int] | None = None
        for r in range(max(1, args.restarts)):
            cand = greedy_cover(nbr, rng, None, randomise=r > 0)
            cand = drop_redundant(nbr, cand, rng)
            log(f"  greedy run {r + 1}: {len(cand)} rows")
            if best is None or len(cand) < len(best):
                best = cand
        assert best is not None

        partial = limit is not None and len(best) > limit
        if args.algorithm == "anneal" and not partial:
            # Remove one row at a time and repair the cover with annealing.
            target_min = math.ceil(fs.size / b)
            current = best
            while len(current) > target_min and (
                    deadline is None or time.perf_counter() < deadline):
                cnt = coverage_counts(nbr, current)
                # Drop the row that alone covers the fewest outcomes.
                unique = [(int((cnt[nbr[c]] == 1).sum()), j)
                          for j, c in enumerate(current)]
                _, j = min(unique)
                start = current[:j] + current[j + 1:]
                cand, unc = anneal(nbr, n_dist1, start, args.iterations, rng,
                                   args.t_start, args.t_end, None,
                                   args.sample, deadline)
                if unc != 0:
                    log(f"  anneal: no full cover found with {len(start)} rows")
                    break
                current = drop_redundant(nbr, cand, rng)
                log(f"  anneal: full cover with {len(current)} rows")
            best = current

        chosen = best
        needed = len(best)
        if partial:
            log(f"Full guarantee needs about {len(best)} rows; limiting to "
                f"{limit} (partial cover).")
            # Greedy max-coverage with restarts; keep the best coverage.
            best_cov = -1
            for r in range(max(1, args.restarts)):
                cand = greedy_cover(nbr, rng, limit, randomise=r > 0)
                cov = int((coverage_counts(nbr, cand) > 0).sum())
                if cov > best_cov:
                    chosen, best_cov = cand, cov
            if args.algorithm == "anneal":
                chosen, _ = anneal(nbr, n_dist1, chosen, args.iterations, rng,
                                   args.t_start, args.t_end, log,
                                   args.sample, deadline)
            chosen = list(dict.fromkeys(chosen))
            if len(chosen) < limit:  # anneal may merge duplicate rows
                chosen = greedy_cover(nbr, rng, limit, True, initial=chosen)
        if args.rows is not None and len(chosen) < args.rows:
            log(f"Guarantee needs {len(chosen)} rows; adding "
                f"{args.rows - len(chosen)} rows to reach {args.rows}.")
            chosen = pad_rows(fs, chosen, args.rows, radius, rng,
                              args.max_memory_cells, log)

    elapsed = time.perf_counter() - t0
    chosen = sorted(set(int(c) for c in chosen))
    rows = [fs.row_signs(c) for c in chosen]
    cost = len(rows) * args.row_price
    if radius == 0 or fs.size == 1:
        covered = len(chosen)
    else:
        covered = int((coverage_counts(nbr, chosen) > 0).sum())

    if len(rows) > MAX_FILE_ROWS:
        warn(f"{len(rows)} rows exceeds the file limit of {MAX_FILE_ROWS} "
             "single rows")
    if cost > MAX_STAKE_SEK:
        warn(f"cost {cost:g} SEK exceeds the limit of {MAX_STAKE_SEK} SEK")

    out = resolve_output(args, entries)
    write_file(out, args.product, rows, "\r\n" if args.crlf else "\n")

    if args.quiet:
        return 0
    if args.rows is not None:
        size_rule = f"exactly {args.rows} rows (--rows)"
    elif args.max_rows is not None:
        size_rule = f"at most {args.max_rows} rows (--max-rows)"
    else:
        size_rule = "as few rows as possible"
    algo = args.algorithm + (f", seed {args.seed}" if args.seed is not None
                             else "")
    summary = [
        f"{args.product} reduced system",
        f"  System:        {','.join(entries)}",
        f"  Full system:   {fs.size} rows",
        f"  Guarantee:     {args.guarantee} correct, {size_rule}",
        f"  Algorithm:     {algo}",
    ]
    if needed is not None:
        bound = (f" (best found; lower bound {lower_bound})"
                 if lower_bound else "")
        summary.append(f"  Rows needed:   {needed} for the full guarantee"
                       f"{bound}")
    summary += [
        f"  Rows written:  {len(rows)}, cost {cost:g} SEK",
        f"  Guarantee {args.guarantee} holds for {covered}/{fs.size} outcomes "
        f"({100.0 * covered / fs.size:.2f} %)",
    ]
    if not args.no_verify:
        dist = hit_distribution(fs, chosen)
        if dist is None:
            summary.append("  Best result:   skipped (too large)")
        else:
            summary.append("  Best result over all outcomes of the full "
                           "system:")
            for correct in sorted(dist, reverse=True):
                summary.append(
                    f"    {correct:2d} correct: {dist[correct]:8d} outcomes "
                    f"({100.0 * dist[correct] / fs.size:6.2f} %)")
    summary += [f"  Time:          {elapsed:.2f} s",
                f"  Output file:   {out}"]
    print("\n".join(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
