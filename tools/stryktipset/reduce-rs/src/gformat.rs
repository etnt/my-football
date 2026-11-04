//! `%g` number formatting (Python's `f"{x:g}"`).
//!
//! Rust has no `{cost:g}` equivalent, so this ports printf `%g`: 6
//! significant digits, fixed notation when the (rounded) decimal exponent
//! is in -4..5, trailing zeros removed, exponent zero-padded to 2 digits.

/// Format like Python's `f"{x:g}"`.
pub fn format_g(x: f64) -> String {
    if x.is_nan() {
        return "nan".into();
    }
    if x.is_infinite() {
        return if x < 0.0 { "-inf".into() } else { "inf".into() };
    }
    // 6 significant digits: mantissa "d.ddddd" with the sign, exponent e.
    let s = format!("{:.5e}", x);
    let (mant, exp) = s.split_once('e').unwrap();
    let e: i32 = exp.parse().unwrap();
    let digits: Vec<u8> = mant
        .chars()
        .filter(|c| c.is_ascii_digit())
        .map(|c| c as u8)
        .collect();
    let sign = if mant.starts_with('-') { "-" } else { "" };
    let dig = |i: usize| -> char { digits.get(i).map(|&d| d as char).unwrap_or('0') };

    if !(-4..6).contains(&e) {
        // Scientific: trim trailing zeros from the mantissa, keep one digit
        // left of the dot, zero-pad the exponent to two digits.
        let mut m: String = mant.trim_end_matches('0').to_string();
        if m.ends_with('.') {
            m.pop();
        }
        let es = if e < 0 {
            format!("-{:02}", -e)
        } else {
            format!("+{:02}", e)
        };
        format!("{sign}{m}e{es}")
    } else if e >= 0 {
        // Fixed with up to 6 integer digits and the rest after the dot.
        let int_len = (e + 1) as usize;
        let mut int: String = (0..int_len).map(dig).collect();
        if int == "0" {
            // Not reachable for e >= 0 with a non-zero x, kept for safety.
            int = "0".into();
        }
        let frac: String = (int_len..digits.len()).map(dig).collect();
        let frac = frac.trim_end_matches('0');
        if frac.is_empty() {
            format!("{sign}{int}")
        } else {
            format!("{sign}{int}.{frac}")
        }
    } else {
        // 0.000...digits
        let mut out = format!("0.{}{}", "0".repeat((-e - 1) as usize), mant_digits(&digits));
        out = out.trim_end_matches('0').trim_end_matches('.').to_string();
        if out == "0" {
            out = "0".into();
        }
        format!("{sign}{out}")
    }
}

fn mant_digits(digits: &[u8]) -> String {
    digits.iter().map(|&d| d as char).collect()
}

#[cfg(test)]
mod tests {
    use super::format_g;

    #[test]
    fn matches_python_g() {
        // Reference: python3 -c 'for x in ...: print(f"{x:g}")'
        let cases: Vec<(f64, &str)> = vec![
            (1.0, "1"),
            (3.0, "3"),
            (20001.0, "20001"),
            (1e6, "1e+06"),
            (1234567.0, "1.23457e+06"),
            (0.001, "0.001"),
            (1.23456789e-5, "1.23457e-05"),
            (17.5, "17.5"),
            (100000.0, "100000"),
            (1e-5, "1e-05"),
            (123.456, "123.456"),
            (0.0, "0"),
            (-2.5, "-2.5"),
            (-0.0, "-0"),
            (1e12, "1e+12"),
            (999999.0, "999999"),
            (999999.5, "1e+06"),
        ];
        for (x, want) in cases {
            assert_eq!(format_g(x), want, "format_g({x})");
        }
    }
}
