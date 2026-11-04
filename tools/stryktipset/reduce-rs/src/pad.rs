//! Padding for `--rows`: add rows that aim for more correct matches.
//!
//! Literal port of `reduce_system.pad_rows`.

use crate::anneal::Logger;
use crate::greedy::{coverage_counts, dedupe, greedy_cover};
use crate::neighbours::{ball_size, neighbour_table};
use crate::system::{FullSystem, NUM_MATCHES};
use rand::Rng;
use rand_pcg::Pcg64;

/// Add rows until there are `target` rows.
///
/// The guarantee is already met, so the new rows aim at a better result:
/// first cover as many outcomes as possible with radius-1 (one more correct
/// match), then radius-2, and so on. At radius 0 any unused row is added.
pub fn pad_rows(
    fs: &FullSystem,
    chosen: &[u32],
    target: usize,
    radius: usize,
    rng: &mut Pcg64,
    max_cells: i64,
    log: &Logger,
) -> Vec<u32> {
    let mut chosen = dedupe(chosen);
    for rr in (0..radius).rev() {
        if chosen.len() >= target {
            break;
        }
        if rr == 0 {
            let mut used = vec![false; fs.size];
            for &c in &chosen {
                used[c as usize] = true;
            }
            let mut free: Vec<u32> = (0..fs.size as u32)
                .filter(|i| !used[*i as usize])
                .collect();
            let m = target - chosen.len();
            for i in 0..m {
                let j = rng.random_range(i..free.len());
                free.swap(i, j);
            }
            let extra = free.len().min(m);
            chosen.extend_from_slice(&free[..extra]);
            log.log(&format!("  padding: +{extra} unused rows"));
            break;
        }
        if (fs.size as i64) * ball_size(&fs.radix, rr) > max_cells {
            log.log(&format!(
                "  padding: table for {} correct too large, skipping that level",
                NUM_MATCHES - rr
            ));
            continue;
        }
        let nbr_rr = match neighbour_table(fs, rr) {
            Ok(t) => t,
            Err(_) => continue,
        };
        let before = chosen.len();
        chosen = greedy_cover(&nbr_rr, rng, Some(target), true, &chosen);
        let cov = coverage_counts(&nbr_rr, &chosen)
            .iter()
            .filter(|&&c| c > 0)
            .count();
        log.log(&format!(
            "  padding: +{} rows for {} correct, now covering {}/{}",
            chosen.len() - before,
            NUM_MATCHES - rr,
            cov,
            fs.size
        ));
    }
    chosen
}
