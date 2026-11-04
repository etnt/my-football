//! Parsing and the full-system model (mixed-radix indexing).
//!
//! Port of the corresponding parts of `tools/stryktipset/reduce_system.py`.

pub const NUM_MATCHES: usize = 13;
pub const SIGNS: [char; 3] = ['1', 'X', '2'];

/// Python-style single-quoted `repr` for the two parse error messages.
pub fn py_repr(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('\'');
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\'' => out.push_str("\\'"),
            _ => out.push(c),
        }
    }
    out.push('\'');
    out
}

/// Parse `"1,x,x2,..."` into normalised entries like `["1", "X", "X2"]`.
///
/// Each entry must contain one to three different signs out of 1, X and 2.
/// The signs are returned in the order 1, X, 2.
pub fn parse_system(text: &str) -> Result<Vec<String>, String> {
    let parts: Vec<String> = text.split(',').map(|p| p.trim().to_uppercase()).collect();
    if parts.len() != NUM_MATCHES {
        return Err(format!(
            "the system must have {} entries, got {}: {}",
            NUM_MATCHES,
            parts.len(),
            py_repr(text)
        ));
    }
    let mut entries = Vec::with_capacity(NUM_MATCHES);
    for (i, part) in parts.iter().enumerate() {
        let m = i + 1;
        if part.is_empty() {
            return Err(format!("match {}: empty entry", m));
        }
        let mut bad: Vec<char> = part.chars().filter(|c| !SIGNS.contains(c)).collect();
        bad.sort_unstable();
        bad.dedup();
        if !bad.is_empty() {
            let bad_s: String = bad.iter().collect();
            return Err(format!(
                "match {}: invalid sign(s) {} in {}; use 1, X and 2",
                m,
                py_repr(&bad_s),
                py_repr(part)
            ));
        }
        let mut seen = [false; 3];
        for c in part.chars() {
            let idx = SIGNS.iter().position(|&s| s == c).unwrap();
            if seen[idx] {
                return Err(format!("match {}: repeated sign in {}", m, py_repr(part)));
            }
            seen[idx] = true;
        }
        let norm: String = SIGNS
            .iter()
            .filter(|s| part.contains(**s))
            .copied()
            .collect();
        entries.push(norm);
    }
    Ok(entries)
}

/// The full system: every combination of the entries.
pub struct FullSystem {
    pub entries: Vec<String>,
    /// Options per match, most significant match first.
    pub radix: Vec<i64>,
    /// Mixed-radix place values.
    pub weights: Vec<i64>,
    /// Row-major `(size, 13)`: option index per match.
    pub digits: Vec<u8>,
    pub size: usize,
}

impl FullSystem {
    pub fn build(entries: Vec<String>) -> FullSystem {
        assert_eq!(entries.len(), NUM_MATCHES);
        let radix: Vec<i64> = entries.iter().map(|e| e.chars().count() as i64).collect();
        let size: i64 = radix.iter().product::<i64>();
        assert!(size >= 1);
        // Match 1 is the most significant digit.
        let mut weights = vec![1i64; NUM_MATCHES];
        for i in (0..NUM_MATCHES - 1).rev() {
            weights[i] = weights[i + 1] * radix[i + 1];
        }
        let size = size as usize;
        let mut digits = vec![0u8; size * NUM_MATCHES];
        for i in 0..size {
            for m in 0..NUM_MATCHES {
                digits[i * NUM_MATCHES + m] = ((i as i64 / weights[m]) % radix[m]) as u8;
            }
        }
        FullSystem {
            entries,
            radix,
            weights,
            digits,
            size,
        }
    }

    #[inline]
    pub fn digit(&self, row: usize, m: usize) -> u8 {
        self.digits[row * NUM_MATCHES + m]
    }

    pub fn row_signs(&self, index: usize) -> String {
        let mut out = String::with_capacity(NUM_MATCHES);
        for m in 0..NUM_MATCHES {
            let d = self.digit(index, m) as usize;
            out.push(self.entries[m].chars().nth(d).unwrap());
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const EXAMPLE: &str = "1,x,x2,2,1,1x2,1,x,1,2,1x,1,1x";

    #[test]
    fn parse_normalises() {
        assert_eq!(parse_system(EXAMPLE).unwrap()[..3], ["1", "X", "X2"]);
        assert_eq!(parse_system(&("2x1,".repeat(12) + "x")).unwrap()[0], "1X2");
    }

    #[test]
    fn parse_rejects() {
        let texts: Vec<String> = vec![
            "1,2".to_string(),
            EXAMPLE.to_string() + ",1",
            EXAMPLE[..EXAMPLE.len() - 1].to_string() + "y",
            EXAMPLE.replace("x2", "xx"),
            ",".to_string() + &EXAMPLE[1..],
        ];
        for text in texts {
            assert!(parse_system(&text).is_err(), "should reject: {text}");
        }
    }

    #[test]
    fn parse_error_texts() {
        assert_eq!(
            parse_system("1,2").unwrap_err(),
            "the system must have 13 entries, got 2: '1,2'"
        );
        assert_eq!(
            parse_system(&(EXAMPLE[..EXAMPLE.len() - 1].to_string() + "y")).unwrap_err(),
            "match 13: invalid sign(s) 'Y' in '1Y'; use 1, X and 2"
        );
    }

    #[test]
    fn build_matches_mixed_radix() {
        let fs = FullSystem::build(parse_system(EXAMPLE).unwrap());
        assert_eq!(fs.size, 24);
        assert_eq!(fs.radix, vec![1, 1, 2, 1, 1, 3, 1, 1, 1, 1, 2, 1, 2]);
        // Row 0 is all first options; row 23 matches the last reference row.
        assert_eq!(fs.row_signs(0), "1XX2111X12111");
        assert_eq!(fs.row_signs(23), "1X22121X12X1X");
        // Digits stay consistent with the mixed-radix weights.
        for i in 0..fs.size {
            let i64 = i as i64;
            for m in 0..NUM_MATCHES {
                assert_eq!(
                    fs.digit(i, m) as i64,
                    (i64 / fs.weights[m]) % fs.radix[m]
                );
            }
        }
    }
}
