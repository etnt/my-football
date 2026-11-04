//! Hit-distribution report ("Best result over all outcomes").

use crate::system::{FullSystem, NUM_MATCHES};
use rayon::prelude::*;
use std::collections::BTreeMap;

/// For each row of the full system, find the best number of correct matches
/// among the chosen rows. Return {correct: number of outcomes}.
///
/// Returns None if the work would be too large.
pub fn hit_distribution(
    fs: &FullSystem,
    chosen: &[u32],
    max_ops: f64,
) -> Option<BTreeMap<u32, u64>> {
    let k = chosen.len();
    if k == 0 || (fs.size as i128) * (k as i128) * (NUM_MATCHES as i128) > max_ops as i128 {
        return None;
    }
    let code: Vec<u8> = chosen
        .iter()
        .flat_map(|&c| {
            fs.digits[c as usize * NUM_MATCHES..(c as usize + 1) * NUM_MATCHES]
                .iter()
                .copied()
        })
        .collect();
    let best: Vec<i16> = (0..fs.size)
        .into_par_iter()
        .map(|i| {
            let row = &fs.digits[i * NUM_MATCHES..(i + 1) * NUM_MATCHES];
            let mut m: i16 = 0;
            for ci in 0..k {
                let code_row = &code[ci * NUM_MATCHES..(ci + 1) * NUM_MATCHES];
                let hits = row
                    .iter()
                    .zip(code_row)
                    .filter(|(a, b)| a == b)
                    .count() as i16;
                m = m.max(hits);
            }
            m
        })
        .collect();
    let mut counts = [0u64; NUM_MATCHES + 1];
    for &v in &best {
        counts[v as usize] += 1;
    }
    let mut out = BTreeMap::new();
    for (v, c) in counts.iter().enumerate() {
        if *c > 0 {
            out.insert(v as u32, *c);
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::system::parse_system;

    #[test]
    fn full_system_all_correct() {
        let fs = FullSystem::build(parse_system("1,x,2,1,x,2,1,x,2,1,x,2,1").unwrap());
        let dist = hit_distribution(&fs, &[0], 3e9).unwrap();
        assert_eq!(dist.get(&13), Some(&1));
        assert_eq!(dist.len(), 1);
    }

    #[test]
    fn too_large_returns_none() {
        let fs = FullSystem::build(parse_system("1,x,2,1,x,2,1,x,2,1,x,2,1").unwrap());
        assert!(hit_distribution(&fs, &[0], 10.0).is_none());
        assert!(hit_distribution(&fs, &[], 3e9).is_none());
    }
}
