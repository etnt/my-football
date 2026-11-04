//! Neighbour (ball) table: for every row, all rows within `radius` changes.
//!
//! Column 0 is the row itself; columns `1..=n_dist1` are distance-1
//! neighbours. Patterns are produced in the same order as
//! `reduce_system.ball_patterns` (itertools combinations then product), so
//! column order is identical to the Python reference.

use crate::system::{FullSystem, NUM_MATCHES};
use rayon::prelude::*;

pub struct Pattern {
    pub positions: Vec<usize>,
    pub shifts: Vec<i64>,
}

pub struct NeighbourTable {
    pub n: usize,
    pub b: usize,
    pub n_dist1: usize,
    /// Row-major `(n, b)` u32 row indices.
    pub table: Vec<u32>,
}

impl NeighbourTable {
    #[inline]
    pub fn ball(&self, i: usize) -> &[u32] {
        &self.table[i * self.b..(i + 1) * self.b]
    }
}

/// Positions with more than one option (the matches one can change).
pub fn free_positions(radix: &[i64]) -> Vec<usize> {
    (0..NUM_MATCHES).filter(|&m| radix[m] > 1).collect()
}

/// Lexicographic combinations of `0..n` taken `k` at a time
/// (same order as `itertools.combinations`).
fn each_combination(n: usize, k: usize) -> Vec<Vec<usize>> {
    let mut out = Vec::new();
    if k == 0 {
        out.push(Vec::new());
        return out;
    }
    if k > n {
        return out;
    }
    let mut c: Vec<usize> = (0..k).collect();
    loop {
        out.push(c.clone());
        let mut i = k as isize - 1;
        while i >= 0 && c[i as usize] == n - k + i as usize {
            i -= 1;
        }
        if i < 0 {
            break;
        }
        c[i as usize] += 1;
        for j in (i as usize + 1)..k {
            c[j] = c[j - 1] + 1;
        }
    }
    out
}

/// Cartesian product of the per-position shift ranges, last position varying
/// fastest (same order as `itertools.product(*ranges)`).
fn product_ranges(ranges: &[Vec<i64>]) -> Vec<Vec<i64>> {
    let mut out: Vec<Vec<i64>> = vec![Vec::new()];
    for r in ranges {
        let mut next = Vec::with_capacity(out.len() * r.len());
        for combo in &out {
            for &s in r {
                let mut c = combo.clone();
                c.push(s);
                next.push(c);
            }
        }
        out = next;
    }
    out
}

pub fn ball_patterns(radix: &[i64], radius: usize) -> Vec<Pattern> {
    let free = free_positions(radix);
    let mut out = Vec::new();
    for k in 1..=radius {
        for combo in each_combination(free.len(), k) {
            let positions: Vec<usize> = combo.iter().map(|&i| free[i]).collect();
            let ranges: Vec<Vec<i64>> =
                positions.iter().map(|&p| (1..radix[p]).collect()).collect();
            for shifts in product_ranges(&ranges) {
                out.push(Pattern {
                    positions: positions.clone(),
                    shifts,
                });
            }
        }
    }
    out
}

pub fn ball_size(radix: &[i64], radius: usize) -> i64 {
    let free: Vec<i64> = radix.iter().filter(|&&m| m > 1).map(|&m| m - 1).collect();
    let mut total = 1i64;
    for k in 1..=radius {
        for combo in each_combination(free.len(), k) {
            total += combo.iter().map(|&i| free[i]).product::<i64>();
        }
    }
    total
}

/// Error text shared with `reduce_system.main` for oversized tables.
pub fn too_large_error(size: usize, b: i64) -> String {
    format!(
        "neighbour table too large ({} x {} cells). Use a smaller system, \
         a higher --guarantee, or raise --max-memory-cells.",
        size, b
    )
}

pub fn neighbour_table(fs: &FullSystem, radius: usize) -> Result<NeighbourTable, String> {
    let patterns = ball_patterns(&fs.radix, radius);
    let b = 1 + patterns.len();
    let n = fs.size;
    let n_dist1 = patterns.iter().filter(|p| p.positions.len() == 1).count();
    // Guards: row indices must fit u32 and the table must fit in memory.
    if n > u32::MAX as usize {
        return Err(too_large_error(n, b as i64));
    }
    let cells = (n as u64) * (b as u64);
    if cells > (usize::MAX as u64 / 4) {
        return Err(too_large_error(n, b as i64));
    }
    let mut table = vec![0u32; n * b];
    let radix = &fs.radix;
    let weights = &fs.weights;
    table
        .par_chunks_mut(b)
        .enumerate()
        .for_each(|(i, row)| {
            row[0] = i as u32;
            for (col, p) in patterns.iter().enumerate() {
                let mut v = i as i64;
                for (&pos, &s) in p.positions.iter().zip(&p.shifts) {
                    let d = fs.digit(i, pos) as i64;
                    v += (((d + s) % radix[pos]) - d) * weights[pos];
                }
                row[col + 1] = v as u32;
            }
        });
    Ok(NeighbourTable {
        n,
        b,
        n_dist1,
        table,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::system::parse_system;

    const EXAMPLE: &str = "1,x,x2,2,1,1x2,1,x,1,2,1x,1,1x";

    #[test]
    fn ball_size_examples() {
        let fs = FullSystem::build(parse_system(EXAMPLE).unwrap());
        assert_eq!(ball_size(&fs.radix, 1), 6); // 1 + 3 x (2-1) + (3-1)
        assert_eq!(ball_size(&fs.radix, 2), 15);
        // 4 ternary positions, radius 1: the perfect code ball.
        let ternary =
            FullSystem::build(parse_system("1x2,1x2,1x2,1x2,1,1,1,1,1,1,1,1,1").unwrap());
        assert_eq!(ball_size(&ternary.radix, 1), 9);
        assert_eq!(ball_size(&ternary.radix, 2), 33);
    }

    #[test]
    fn neighbour_table_matches_hamming() {
        let fs = FullSystem::build(parse_system(EXAMPLE).unwrap());
        let nbr = neighbour_table(&fs, 2).unwrap();
        assert_eq!(nbr.n, fs.size);
        assert_eq!(nbr.b, 15); // 1 + 14 patterns
        assert_eq!(nbr.n_dist1, 5); // the ternary entry has two shift columns
        for i in 0..fs.size {
            let ball = nbr.ball(i);
            // The ball is a set of distinct rows containing i itself first.
            assert_eq!(ball[0] as usize, i);
            let mut sorted = ball.to_vec();
            sorted.sort_unstable();
            sorted.dedup();
            assert_eq!(sorted.len(), ball.len());
            // Every neighbour differs in at most 2 digits, and the
            // distance-1 columns differ in exactly 1.
            let dist = |j: usize| {
                (0..NUM_MATCHES)
                    .filter(|&m| fs.digit(i, m) != fs.digit(j, m))
                    .count()
            };
            assert!(ball.iter().all(|&j| dist(j as usize) <= 2));
            for &j in &ball[1..1 + nbr.n_dist1] {
                assert_eq!(dist(j as usize), 1);
            }
            // The ball holds exactly the rows within distance 2.
            let within: Vec<u32> = (0..fs.size as u32)
                .filter(|&j| dist(j as usize) <= 2)
                .collect();
            let mut ball_sorted = ball.to_vec();
            ball_sorted.sort_unstable();
            assert_eq!(ball_sorted, within);
        }
    }

    #[test]
    fn pattern_order_matches_itertools() {
        // Two binary positions, radius 2: k=1 gives (0),(1); k=2 gives (0,1).
        let radix = [2i64, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];
        let pats = ball_patterns(&radix, 2);
        assert_eq!(pats.len(), 3);
        assert_eq!(pats[0].positions, vec![0]);
        assert_eq!(pats[0].shifts, vec![1]);
        assert_eq!(pats[1].positions, vec![1]);
        assert_eq!(pats[1].shifts, vec![1]);
        assert_eq!(pats[2].positions, vec![0, 1]);
        assert_eq!(pats[2].shifts, vec![1, 1]);
    }
}
