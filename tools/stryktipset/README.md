# Stryktipset reduced system

`reduce_system.py` turns a Stryktipset system into a smaller set of single
rows ("enkelrader"). It writes the rows in the Svenska Spel "Externa
systemspel" file format (see
[README-external-stryktipset-format.md](README-external-stryktipset-format.md)).

## What the guarantee means

The input has 13 entries, one for each match. Each entry is `1`, `X`, `2` or a
combination such as `1X`, `X2` or `1X2`. The full system is every row that you
can make from the entries. The full system can be very expensive.

The reduced system has fewer rows. It has a guarantee `G`: if the real result
is one of the rows of the full system, then at least one row in the reduced
system has `G` or more correct matches. If the real result is outside the full
system, there is no guarantee.

## Set up

Run these commands from the repository root:

```sh
python3 -m venv tools/.venv
tools/.venv/bin/pip install -r tools/requirements.txt
```

## Use

```sh
tools/.venv/bin/python tools/stryktipset/reduce_system.py \
    "1,x,x2,2,1,1x2,1,x,1,2,1x,1,1x" -g 12 -k 5
```

The script writes the rows to a file. By default the file name shows the
input criteria: product, system, guarantee (`g`), row option (`k` for
`--rows`, `n` for `--max-rows`), algorithm and seed (`s`), if given. For
example:

```text
stryktipset_1-X-X2-2-1-1X2-1-X-1-2-1X-1-1X_g12_k5_greedy.txt
```

The script then prints a summary on stdout:

```text
Stryktipset reduced system
  System:        1,X,X2,2,1,1X2,1,X,1,2,1X,1,1X
  Full system:   24 rows
  Guarantee:     12 correct, exactly 5 rows (--rows)
  Algorithm:     greedy
  Rows needed:   6 for the full guarantee (best found; lower bound 4)
  Rows written:  5, cost 5 SEK
  Guarantee 12 holds for 23/24 outcomes (95.83 %)
  Best result over all outcomes of the full system:
    13 correct:        5 outcomes ( 20.83 %)
    12 correct:       18 outcomes ( 75.00 %)
    11 correct:        1 outcomes (  4.17 %)
  Time:          0.00 s
  Output file:   stryktipset_1-X-X2-2-1-1X2-1-X-1-2-1X-1-1X_g12_k5_greedy.txt
```

Warnings and errors go to stderr. With `-v`, the search progress also goes
to stderr.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `system` | | 13 comma-separated entries. Upper or lower case. |
| `-g`, `--guarantee` | 12 | Guaranteed correct matches. 13 gives the full system. |
| `-n`, `--max-rows` | none | Upper limit on rows. If the guarantee needs more rows, the script writes the best partial system and reports the real coverage. |
| `-k`, `--rows` | none | Exact number of rows. See "Fixed number of rows" below. Cannot be used with `--max-rows`. |
| `-a`, `--algorithm` | `greedy` | `greedy` or `anneal`. See below. |
| `-r`, `--restarts` | 10 | Greedy runs with random tie-breaks. The smallest result is kept. |
| `-i`, `--iterations` | 200000 | Anneal: iterations for each attempt. |
| `--time-limit` | none | Anneal: stop the search after this many seconds. |
| `--sample` | 12 | Anneal: candidate moves scored per iteration. |
| `--t-start`, `--t-end` | 0.6, 0.1 | Anneal: start and end temperature. |
| `--seed` | random | Random seed. Use it to get the same output again. |
| `-o`, `--output` | automatic name | Output file. If this is an existing directory, the file gets the automatic name in that directory. |
| `--product` | `Stryktipset` | First line of the file. `Stryktipset` or `Europatipset`. |
| `--crlf` | off | Write Windows line endings. |
| `--row-price` | 1.0 | Price for each row in SEK. Used for the cost report. |
| `--no-verify` | off | Do not compute the "best result" table in the summary. |
| `--max-memory-cells` | 250000000 | Limit for the neighbour table. |
| `-v`, `--verbose` | off | Write the search progress to stderr. |
| `-q`, `--quiet` | off | Do not print the summary on stdout. |

The script warns if the file has more than 10 000 rows or the cost is more
than 20 000 SEK. These are the Svenska Spel limits.

## Algorithms

The problem is a covering problem: every row of the full system must differ
in at most `13 - G` matches from a selected row.

- `greedy`: Select the row that covers the most uncovered outcomes. Do this
  again until all outcomes are covered. Then remove rows that other rows
  make unnecessary. This is fast.
- `anneal`: Start with the greedy result. Remove one row, then use simulated
  annealing to cover all outcomes again. Do this again until it fails or the
  time limit ends. This is slower, but it often gives fewer rows.

With `--max-rows`, both algorithms try to cover as many outcomes as possible
with the given number of rows. `anneal` usually covers more.

### Fixed number of rows

`-k N` (or `--rows N`) always writes exactly `N` rows.

- If the guarantee needs more than `N` rows, the script works as with
  `--max-rows N`. The guarantee then holds only for part of the outcomes. The
  report shows how large that part is.
- If the guarantee needs fewer than `N` rows, the script adds rows. The added
  rows aim at one more correct match (`G + 1`). They cover as many outcomes as
  possible at that level. If all outcomes are covered at `G + 1`, the script
  goes on with `G + 2`, and so on.
- `N` cannot be more than the number of rows in the full system.

Example: a 500 SEK system with guarantee 11:

```sh
tools/.venv/bin/python tools/stryktipset/reduce_system.py \
    "1x2,1x2,1x2,1x2,1x2,1x2,1x,1x,1x,x2,x2,1,1" -g 11 -k 500
```

The report also shows a lower bound: the full system size divided by the
number of outcomes that one row covers. No system can have fewer rows.

## Limits

The script keeps a table of all near rows in memory. For very large systems
with a low guarantee the table is too large, for example 13 full matches
with guarantee 11. The script then stops with an error.

## Tests

```sh
tools/.venv/bin/python -m pytest tools/stryktipset/tests
```
