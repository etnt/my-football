//! Simulated annealing with a fixed number of rows.
//!
//! Literal port of `reduce_system.anneal`. Minimises the number of uncovered
//! outcomes and stops at zero. Each step picks a random uncovered outcome u;
//! candidate moves change one sign of a selected row c so that the new row v
//! covers u; up to `sample` candidates are scored and the best is proposed
//! with the Metropolis rule.

use crate::greedy::{coverage_counts, dedupe};
use crate::neighbours::NeighbourTable;
use rand::Rng;
use rand_pcg::Pcg64;
use std::time::Instant;

#[derive(Clone, Copy, Default)]
pub struct Logger {
    pub enabled: bool,
}

impl Logger {
    pub fn log(&self, msg: &str) {
        if self.enabled {
            eprintln!("{msg}");
        }
    }
}

/// Returns (best rows, uncovered outcomes for those rows).
#[allow(clippy::too_many_arguments)]
pub fn anneal(
    nbr: &NeighbourTable,
    n_dist1: usize,
    start: &[u32],
    iterations: usize,
    rng: &mut Pcg64,
    t_start: f64,
    t_end: f64,
    logger: Option<&Logger>,
    sample: usize,
    deadline: Option<Instant>,
) -> (Vec<u32>, usize) {
    let n = nbr.n;
    let b = nbr.b;
    let mut chosen = dedupe(start);
    let k = chosen.len();
    // row -> index in chosen (-1 if not chosen)
    let mut where_ = vec![-1i64; n];
    for (i, &c) in chosen.iter().enumerate() {
        where_[c as usize] = i as i64;
    }
    let mut cnt = coverage_counts(nbr, &chosen);
    let mut uncovered = cnt.iter().filter(|&&c| c == 0).count();
    let mut best = chosen.clone();
    let mut best_unc = uncovered;
    if uncovered == 0 || k == 0 || n_dist1 == 0 {
        return (best, best_unc);
    }

    let mut unc_cache: Vec<u32> = (0..n)
        .filter(|&i| cnt[i] == 0)
        .map(|i| i as u32)
        .collect();
    let mut iterations_run = 0usize;

    for it in 0..iterations {
        iterations_run = it + 1;
        let t = t_start * (t_end / t_start).powf(it as f64 / (iterations.max(2) - 1) as f64);
        if it % 200 == 0 || unc_cache.is_empty() {
            if let Some(d) = deadline {
                if Instant::now() > d {
                    break;
                }
            }
            unc_cache = (0..n).filter(|&i| cnt[i] == 0).map(|i| i as u32).collect();
            if unc_cache.is_empty() {
                break;
            }
        }
        let u = unc_cache[rng.random_range(0..unc_cache.len())] as usize;
        let u = if cnt[u] != 0 {
            unc_cache = (0..n).filter(|&i| cnt[i] == 0).map(|i| i as u32).collect();
            if unc_cache.is_empty() {
                break;
            }
            unc_cache[rng.random_range(0..unc_cache.len())] as usize
        } else {
            u
        };

        let ball_u: Vec<u32> = nbr.ball(u).to_vec(); // rows v covering u
        // Pairs (j, k) with ball_u[j]'s distance-1 neighbour kk being chosen.
        let mut pairs: Vec<(usize, usize)> = Vec::new();
        for (j, &v) in ball_u.iter().enumerate() {
            for kk in 0..n_dist1 {
                let near = nbr.ball(v as usize)[1 + kk];
                if where_[near as usize] >= 0 {
                    pairs.push((j, kk));
                }
            }
        }
        let moves: Vec<(u32, u32)> = if !pairs.is_empty() {
            // Up to `sample` distinct random pair indices.
            let mut idx: Vec<usize> = (0..pairs.len()).collect();
            let m = sample.min(idx.len());
            for i in 0..m {
                let j = rng.random_range(i..idx.len());
                idx.swap(i, j);
            }
            (0..m)
                .map(|i| {
                    let (j, kk) = pairs[idx[i]];
                    let old = nbr.ball(ball_u[j] as usize)[1 + kk];
                    (old, ball_u[j])
                })
                .collect()
        } else {
            // No selected row is close to u: move a random row onto u's ball.
            let old = chosen[rng.random_range(0..k)];
            let new = ball_u[rng.random_range(0..b)];
            vec![(old, new)]
        };
        let moves: Vec<(u32, u32)> =
            moves.into_iter().filter(|&(_, v)| where_[v as usize] < 0).collect();
        if moves.is_empty() {
            continue;
        }
        let mut scored: Vec<(i64, f64, u32, u32)> = Vec::with_capacity(moves.len());
        for &(old, new) in &moves {
            scored.push((delta_of(nbr, &mut cnt, old, new), rng.random(), old, new));
        }
        let (delta, _, old, new) = scored
            .iter()
            .min_by(|a, b| a.0.cmp(&b.0).then(a.1.partial_cmp(&b.1).unwrap()))
            .copied()
            .unwrap();
        if delta <= 0 || rng.random::<f64>() < (-delta as f64 / t).exp() {
            let i = where_[old as usize] as usize;
            for &w in nbr.ball(old as usize) {
                cnt[w as usize] -= 1;
            }
            for &w in nbr.ball(new as usize) {
                cnt[w as usize] += 1;
            }
            where_[old as usize] = -1;
            where_[new as usize] = i as i64;
            chosen[i] = new;
            uncovered = (uncovered as i64 + delta) as usize;
            if uncovered < best_unc {
                best = chosen.clone();
                best_unc = uncovered;
                if best_unc == 0 {
                    break;
                }
            }
        }
    }
    if let Some(l) = logger {
        l.log(&format!(
            "    anneal {k} rows: best uncovered={best_unc} after {iterations_run} iterations"
        ));
    }
    (best, best_unc)
}

/// Change in uncovered outcomes if row `old` is replaced by `new`.
/// Temporarily removes old's ball from `cnt` to reuse it for both sums.
fn delta_of(nbr: &NeighbourTable, cnt: &mut [i32], old: u32, new: u32) -> i64 {
    let b_old = nbr.ball(old as usize);
    let b_new = nbr.ball(new as usize);
    for &w in b_old {
        cnt[w as usize] -= 1;
    }
    let d = b_old.iter().filter(|&&w| cnt[w as usize] == 0).count() as i64
        - b_new.iter().filter(|&&w| cnt[w as usize] == 0).count() as i64;
    for &w in b_old {
        cnt[w as usize] += 1;
    }
    d
}
