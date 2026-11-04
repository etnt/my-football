//! Fast Rust port of `tools/stryktipset/reduce_system.py`.
//!
//! Same CLI, same output format, same guarantees. The RNG stream differs
//! from NumPy's PCG64 seeding, so the same `--seed` gives a different (but
//! equally guaranteed) result; see README.md.

pub mod anneal;
pub mod eval;
pub mod cli;
pub mod gformat;
pub mod greedy;
pub mod neighbours;
pub mod output;
pub mod pad;
pub mod system;
