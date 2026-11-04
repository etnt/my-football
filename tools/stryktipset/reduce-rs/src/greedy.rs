//! Greedy covering and redundant-row removal.
//!
//! Port of `reduce_system.greedy_cover` / `drop_redundant` /
//! `coverage_counts`. `nbr` is a `NeighbourTable`: `ball(i)` is the set of
//! rows within `radius` of row `i` (the ball relation is symmetric).
//!
//! Candidate selection uses gain buckets: `buckets[g]` holds every row whose
//! gain is `g`. A gain only ever drops by one, so each update moves one row
//! one bucket down in O(1). The maximum gain never rises, so the search for
//! it is a single downward walk over the whole run.
//! Randomised picks draw uniformly among the top bucket. Deterministic picks
//! take the lowest row index in the top bucket (like `numpy.argmax`).
//! `tests::greedy_matches_naive_scan` checks the deterministic mode against
//! a plain O(N) scan.

use crate::neighbours::NeighbourTable;
use rand::seq::SliceRandom;
use rand::Rng;
use rand_pcg::Pcg64;

pub fn coverage_counts(nbr: &NeighbourTable, chosen: &[u32]) -> Vec<i32> {
    let mut cnt = vec![0i32; nbr.n];
    for &c in chosen {
        for &w in nbr.ball(c as usize) {
            cnt[w as usize] += 1;
        }
    }
    cnt
}

/// Remove duplicates from `chosen`, keeping the first occurrence.
pub fn dedupe(chosen: &[u32]) -> Vec<u32> {
    let mut seen = std::collections::HashSet::with_capacity(chosen.len());
    let mut out = Vec::with_capacity(chosen.len());
    for &c in chosen {
        if seen.insert(c) {
            out.push(c);
        }
    }
    out
}

/// Rows grouped by their current gain.
struct GainBuckets {
    gain: Vec<u32>,
    /// `pos[row]` is the index of `row` inside `buckets[gain[row]]`.
    pos: Vec<u32>,
    buckets: Vec<Vec<u32>>,
    /// No bucket above this index is non-empty.
    max: usize,
}

impl GainBuckets {
    fn new(gain: Vec<u32>, max_gain: usize) -> Self {
        let mut buckets = vec![Vec::new(); max_gain + 1];
        let mut pos = vec![0u32; gain.len()];
        for (i, &g) in gain.iter().enumerate() {
            let b = &mut buckets[g as usize];
            pos[i] = b.len() as u32;
            b.push(i as u32);
        }
        GainBuckets { gain, pos, buckets, max: max_gain }
    }

    /// Lower the gain of `row` by one.
    fn decrement(&mut self, row: u32) {
        let i = row as usize;
        let g = self.gain[i] as usize;
        let p = self.pos[i] as usize;
        let from = &mut self.buckets[g];
        from.swap_remove(p);
        if p < from.len() {
            let moved = from[p];
            self.pos[moved as usize] = p as u32;
        }
        let to = &mut self.buckets[g - 1];
        self.pos[i] = to.len() as u32;
        to.push(row);
        self.gain[i] = (g - 1) as u32;
    }

    /// Choose the next row: a row with the maximum gain.
    fn pick(&mut self, randomise: bool, rng: &mut Pcg64) -> usize {
        while self.buckets[self.max].is_empty() {
            self.max -= 1;
        }
        let top = &self.buckets[self.max];
        let row = if randomise {
            top[rng.random_range(0..top.len())]
        } else {
            *top.iter().min().unwrap()
        };
        row as usize
    }
}

/// Greedy covering. Stops when all rows are covered or at `max_rows`.
///
/// `initial` rows are kept and count towards `max_rows`.
pub fn greedy_cover(
    nbr: &NeighbourTable,
    rng: &mut Pcg64,
    max_rows: Option<usize>,
    randomise: bool,
    initial: &[u32],
) -> Vec<u32> {
    let n = nbr.n;
    let b = nbr.b;
    let mut chosen = dedupe(initial);
    let mut covered = vec![false; n];
    let gain: Vec<u32> = if chosen.is_empty() {
        vec![b as u32; n]
    } else {
        for &c in &chosen {
            for &w in nbr.ball(c as usize) {
                covered[w as usize] = true;
            }
        }
        // For every row, how many rows of its ball are still uncovered.
        (0..n)
            .map(|i| {
                nbr.ball(i)
                    .iter()
                    .filter(|&&w| !covered[w as usize])
                    .count() as u32
            })
            .collect()
    };
    let mut remaining = covered.iter().filter(|&&c| !c).count();
    let mut gains = GainBuckets::new(gain, b);
    while remaining > 0 && max_rows.is_none_or(|mr| chosen.len() < mr) {
        let c = gains.pick(randomise, rng);
        chosen.push(c as u32);
        let new: Vec<u32> = nbr
            .ball(c)
            .iter()
            .copied()
            .filter(|&w| !covered[w as usize])
            .collect();
        for &w in &new {
            covered[w as usize] = true;
        }
        remaining -= new.len();
        // Every candidate whose ball holds a newly covered row loses 1 gain.
        // The ball relation is symmetric, so these are the balls of `new`.
        for &w in &new {
            for &i in nbr.ball(w as usize) {
                gains.decrement(i);
            }
        }
    }
    chosen
}

/// Remove rows whose whole ball is also covered by other rows.
pub fn drop_redundant(nbr: &NeighbourTable, chosen: &[u32], rng: &mut Pcg64) -> Vec<u32> {
    let chosen = dedupe(chosen);
    let mut cnt = coverage_counts(nbr, &chosen);
    let mut order: Vec<usize> = (0..chosen.len()).collect();
    order.shuffle(rng);
    let mut keep = vec![true; chosen.len()];
    for &i in &order {
        let ball = nbr.ball(chosen[i] as usize);
        let min_cnt = ball.iter().map(|&w| cnt[w as usize]).min().unwrap();
        if min_cnt >= 2 {
            for &w in ball {
                cnt[w as usize] -= 1;
            }
            keep[i] = false;
        }
    }
    chosen
        .iter()
        .zip(keep)
        .filter(|&(_, k)| k)
        .map(|(&c, _)| c)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::neighbours::neighbour_table;
    use crate::system::{parse_system, FullSystem};
    use rand::SeedableRng;

    const EXAMPLE: &str = "1,x,x2,2,1,1x2,1,x,1,2,1x,1,1x";

    fn min_cover(nbr: &NeighbourTable, chosen: &[u32], radius: usize) -> usize {
        coverage_counts(nbr, chosen)
            .iter()
            .map(|&c| if c > 0 { 13 - radius } else { 0 })
            .min()
            .unwrap()
    }

    /// Reference implementation with a plain O(N) scan per step.
    fn greedy_cover_naive(
        nbr: &NeighbourTable,
        rng: &mut Pcg64,
        max_rows: Option<usize>,
        randomise: bool,
        initial: &[u32],
    ) -> Vec<u32> {
        let n = nbr.n;
        let b = nbr.b;
        let mut chosen = dedupe(initial);
        let mut covered = vec![false; n];
        let mut gain: Vec<i32> = if chosen.is_empty() {
            vec![b as i32; n]
        } else {
            for &c in &chosen {
                for &w in nbr.ball(c as usize) {
                    covered[w as usize] = true;
                }
            }
            (0..n)
                .map(|i| {
                    nbr.ball(i).iter().filter(|&&w| !covered[w as usize]).count() as i32
                })
                .collect()
        };
        let mut remaining = covered.iter().filter(|&&c| !c).count();
        while remaining > 0 && max_rows.is_none_or(|mr| chosen.len() < mr) {
            let best = *gain.iter().max().unwrap();
            let c: usize = if randomise {
                let cands: Vec<usize> = (0..n).filter(|&i| gain[i] == best).collect();
                cands[rng.random_range(0..cands.len())]
            } else {
                gain.iter().position(|&g| g == best).unwrap()
            };
            chosen.push(c as u32);
            let new: Vec<u32> = nbr
                .ball(c)
                .iter()
                .copied()
                .filter(|&w| !covered[w as usize])
                .collect();
            for &w in &new {
                covered[w as usize] = true;
            }
            remaining -= new.len();
            for &w in &new {
                for &i in nbr.ball(w as usize) {
                    gain[i as usize] -= 1;
                }
            }
        }
        chosen
    }

    #[test]
    fn greedy_matches_naive_scan() {
        let fs = FullSystem::build(parse_system(EXAMPLE).unwrap());
        for radius in [1usize, 2] {
            let nbr = neighbour_table(&fs, radius).unwrap();
            for seed in 0..20u64 {
                for initial in [&[][..], &[3u32, 7], &[fs.size as u32 - 1]] {
                    let mut rng_a = Pcg64::seed_from_u64(seed);
                    let mut rng_b = Pcg64::seed_from_u64(seed);
                    let a = greedy_cover(&nbr, &mut rng_a, None, false, initial);
                    let b = greedy_cover_naive(&nbr, &mut rng_b, None, false, initial);
                    assert_eq!(a, b, "radius {radius} seed {seed} initial {initial:?}");
                    assert_eq!(min_cover(&nbr, &a, radius), 13 - radius);
                    // Randomised ties: still a full cover.
                    let mut rng_c = Pcg64::seed_from_u64(seed);
                    let r = greedy_cover(&nbr, &mut rng_c, None, true, initial);
                    assert_eq!(min_cover(&nbr, &r, radius), 13 - radius);
                }
            }
        }
    }

    #[test]
    fn greedy_reaches_full_cover() {
        let fs = FullSystem::build(parse_system(EXAMPLE).unwrap());
        let nbr = neighbour_table(&fs, 1).unwrap();
        let mut rng = Pcg64::seed_from_u64(1);
        let chosen = greedy_cover(&nbr, &mut rng, None, true, &[]);
        assert_eq!(min_cover(&nbr, &chosen, 1), 12);
        // Restart 0 is deterministic (no random tie-break).
        let mut rng2 = Pcg64::seed_from_u64(7);
        let det = greedy_cover(&nbr, &mut rng2, None, false, &[]);
        assert_eq!(min_cover(&nbr, &det, 1), 12);
        // drop_redundant keeps the cover.
        let reduced = drop_redundant(&nbr, &det, &mut rng2);
        assert!(reduced.len() <= det.len());
        assert_eq!(min_cover(&nbr, &reduced, 1), 12);
    }

    #[test]
    fn max_rows_stops_greedy() {
        let fs = FullSystem::build(parse_system(EXAMPLE).unwrap());
        let nbr = neighbour_table(&fs, 1).unwrap();
        let mut rng = Pcg64::seed_from_u64(1);
        let chosen = greedy_cover(&nbr, &mut rng, Some(3), true, &[]);
        assert_eq!(chosen.len(), 3);
    }
}
