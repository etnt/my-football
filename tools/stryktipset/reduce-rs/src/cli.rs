//! Command-line interface, summary report and the top-level search flow.
//!
//! Literal port of `reduce_system.build_parser` / `main`.

use crate::anneal::{anneal, Logger};
use crate::eval::hit_distribution;
use crate::gformat::format_g;
use crate::greedy::{coverage_counts, dedupe, drop_redundant, greedy_cover};
use crate::neighbours::{ball_size, neighbour_table, too_large_error};
use crate::output::write_file;
use crate::pad::pad_rows;
use crate::system::{parse_system, FullSystem, NUM_MATCHES};
use clap::{Parser, ValueEnum};
use rand::{Rng, SeedableRng};
use rand_pcg::Pcg64;
use rayon::prelude::*;
use std::path::PathBuf;
use std::time::{Duration, Instant};

const MAX_FILE_ROWS: i64 = 10_000; // Svenska Spel limit for single rows per file
const MAX_STAKE_SEK: f64 = 20_000.0; // Svenska Spel limit for total stake
const DEFAULT_MAX_NEIGHBOUR_CELLS: i64 = 250_000_000; // ~1 GB of int32
/// Golden-ratio step between greedy-restart RNG seeds.
const RESTART_SEED_STEP: u64 = 0x9E37_79B9_7F4A_7C15;

#[derive(Clone, Copy, Debug, PartialEq, Eq, ValueEnum)]
pub enum Algorithm {
    Greedy,
    Anneal,
}

impl Algorithm {
    pub fn as_str(self) -> &'static str {
        match self {
            Algorithm::Greedy => "greedy",
            Algorithm::Anneal => "anneal",
        }
    }
}

#[derive(Parser, Debug)]
#[command(
    name = "reduce-rs",
    about = "Create a reduced Stryktipset system of single rows with a guaranteed number of correct matches."
)]
pub struct Args {
    /// 13 comma-separated entries, e.g. "1,x,x2,2,1,1x2,1,x,1,2,1x,1,1x"
    pub system: String,

    /// Guaranteed correct matches if the result is in the full system
    /// (13 = no reduction)
    #[arg(short = 'g', long = "guarantee", default_value_t = 12)]
    pub guarantee: i64,

    /// Upper limit on rows. If the guarantee needs more rows, the best
    /// partial cover is written and the real coverage is reported
    #[arg(short = 'n', long = "max-rows", conflicts_with = "rows")]
    pub max_rows: Option<i64>,

    /// Exact number of rows. If the guarantee needs more, the best partial
    /// cover is written; if it needs fewer, extra rows are added that aim
    /// for more correct matches
    #[arg(short = 'k', long = "rows")]
    pub rows: Option<i64>,

    /// Reduction algorithm
    #[arg(short = 'a', long = "algorithm", default_value = "greedy")]
    pub algorithm: Algorithm,

    /// Greedy restarts with random tie-breaks; the smallest result is kept
    #[arg(short = 'r', long = "restarts", default_value_t = 10)]
    pub restarts: i64,

    /// Anneal: iterations per attempt
    #[arg(short = 'i', long = "iterations", default_value_t = 200_000)]
    pub iterations: usize,

    /// Anneal: stop searching after this many seconds
    #[arg(long = "time-limit")]
    pub time_limit: Option<f64>,

    /// Anneal: candidate moves scored per iteration
    #[arg(long = "sample", default_value_t = 12)]
    pub sample: usize,

    /// Anneal: start temperature
    #[arg(long = "t-start", default_value_t = 0.6)]
    pub t_start: f64,

    /// Anneal: end temperature
    #[arg(long = "t-end", default_value_t = 0.1)]
    pub t_end: f64,

    /// Random seed for reproducible output
    #[arg(long = "seed")]
    pub seed: Option<i64>,

    /// Output file, or an existing directory for the automatic name.
    /// Default: an automatic name in the current directory that shows the
    /// input criteria, e.g. stryktipset_1-X-X2-..._g12_k100_greedy.txt
    #[arg(short = 'o', long = "output")]
    pub output: Option<PathBuf>,

    /// Product name on the first line of the file
    #[arg(long = "product", default_value = "Stryktipset")]
    pub product: String,

    /// Write Windows line endings (CRLF)
    #[arg(long = "crlf")]
    pub crlf: bool,

    /// Price per row in SEK, used for the cost report
    #[arg(long = "row-price", default_value_t = 1.0)]
    pub row_price: f64,

    /// Skip the hit-distribution report
    #[arg(long = "no-verify")]
    pub no_verify: bool,

    /// Limit for the neighbour table (rows x ball size)
    #[arg(long = "max-memory-cells", default_value_t = DEFAULT_MAX_NEIGHBOUR_CELLS)]
    pub max_memory_cells: i64,

    /// Write search progress to stderr
    #[arg(short = 'v', long = "verbose")]
    pub verbose: bool,

    /// Do not print the summary on stdout
    #[arg(short = 'q', long = "quiet")]
    pub quiet: bool,
}

/// File name that shows the input criteria, e.g.
/// `stryktipset_1-X-X2-2-1-1X2-1-X-1-2-1X-1-1X_g12_k100_greedy.txt`
pub fn default_filename(
    product: &str,
    entries: &[String],
    guarantee: i64,
    rows: Option<i64>,
    max_rows: Option<i64>,
    algorithm: Algorithm,
    seed: Option<i64>,
) -> String {
    let mut parts = vec![
        product.to_lowercase(),
        entries.join("-"),
        format!("g{guarantee}"),
    ];
    if let Some(k) = rows {
        parts.push(format!("k{k}"));
    }
    if let Some(n) = max_rows {
        parts.push(format!("n{n}"));
    }
    parts.push(algorithm.as_str().to_string());
    if let Some(s) = seed {
        parts.push(format!("s{s}"));
    }
    format!("{}.txt", parts.join("_"))
}

pub fn resolve_output(args: &Args, entries: &[String]) -> PathBuf {
    let name = default_filename(
        &args.product,
        entries,
        args.guarantee,
        args.rows,
        args.max_rows,
        args.algorithm,
        args.seed,
    );
    match &args.output {
        None => PathBuf::from(name),
        Some(out) => {
            if out.is_dir() {
                out.join(name)
            } else {
                out.clone()
            }
        }
    }
}

/// Per-restart RNG seed for the parallel greedy restarts.
fn restart_seed(base: u64, r: usize) -> u64 {
    base.wrapping_add((r as u64).wrapping_mul(RESTART_SEED_STEP))
}

/// Entry point: parse args from `argv` and run. Returns the exit code.
pub fn main_with<I, T>(argv: I) -> i32
where
    I: IntoIterator<Item = T>,
    T: Into<std::ffi::OsString> + Clone,
{
    let args = Args::parse_from(argv);
    run_args(args)
}

/// Entry point for the binary: parse args from the environment.
pub fn run() -> i32 {
    let args = Args::parse();
    run_args(args)
}

fn run_args(args: Args) -> i32 {
    let log = Logger {
        enabled: args.verbose,
    };
    let error = |msg: String| -> i32 {
        eprintln!("error: {msg}");
        2
    };
    let warn = |msg: String| eprintln!("warning: {msg}");

    let entries = match parse_system(&args.system) {
        Ok(e) => e,
        Err(e) => return error(e),
    };
    if !(1..=NUM_MATCHES as i64).contains(&args.guarantee) {
        return error(format!("--guarantee must be 1..{NUM_MATCHES}"));
    }
    let limit: Option<usize> = {
        let raw = args.rows.or(args.max_rows);
        match raw {
            Some(v) if v < 1 => {
                return error("--rows/--max-rows must be at least 1".to_string())
            }
            Some(v) => Some(v as usize),
            None => None,
        }
    };

    let base: u64 = match args.seed {
        Some(s) => s as u64, // wrapping, like a NumPy seed
        None => rand::random(),
    };
    // Sequential phases (anneal, padding, full-system sampling) use their own
    // stream so that parallel greedy restarts cannot reorder them.
    let mut main_rng = Pcg64::seed_from_u64(!base);

    let fs = FullSystem::build(entries.clone());
    if let Some(k) = args.rows {
        if k > fs.size as i64 {
            return error(format!(
                "--rows {} is more than the {} rows of the full system",
                k, fs.size
            ));
        }
    }

    let t0 = Instant::now();
    let deadline: Option<Instant> = args
        .time_limit
        .map(|tl| t0 + Duration::from_secs_f64(tl.max(0.0)));
    let radius = NUM_MATCHES - args.guarantee as usize;
    let mut chosen: Vec<u32>;
    let needed: usize;
    let covered: usize;
    let mut lower_bound: Option<i64> = None;

    if radius == 0 || fs.size == 1 {
        needed = fs.size;
        chosen = (0..fs.size as u32).collect();
        if let Some(lim) = limit {
            if lim < fs.size {
                let mut all: Vec<u32> = (0..fs.size as u32).collect();
                for i in 0..lim {
                    let j = main_rng.random_range(i..all.len());
                    all.swap(i, j);
                }
                all.truncate(lim);
                chosen = all;
            }
        }
        covered = chosen.len();
    } else {
        let b = ball_size(&fs.radix, radius);
        if (fs.size as i64) * b > args.max_memory_cells {
            return error(too_large_error(fs.size, b));
        }
        let nbr = match neighbour_table(&fs, radius) {
            Ok(t) => t,
            Err(e) => return error(e),
        };
        let lb = ((fs.size as i64) + b - 1) / b;
        lower_bound = Some(lb);
        log.log(&format!(
            "Each row covers {b} rows. Lower bound (sphere covering): {lb} rows"
        ));

        // Greedy with restarts, always to full cover. Restart r gets its own
        // seed; restart 0 keeps Python's deterministic tie-break.
        let restarts = args.restarts.max(1) as usize;
        let results: Vec<Vec<u32>> = (0..restarts)
            .into_par_iter()
            .map(|r| {
                let mut rng = Pcg64::seed_from_u64(restart_seed(base, r));
                let cand = greedy_cover(&nbr, &mut rng, None, r > 0, &[]);
                drop_redundant(&nbr, &cand, &mut rng)
            })
            .collect();
        for (r, cand) in results.iter().enumerate() {
            log.log(&format!("  greedy run {}: {} rows", r + 1, cand.len()));
        }
        let mut best: Vec<u32> = results[0].clone();
        for cand in &results[1..] {
            if cand.len() < best.len() {
                best = cand.clone();
            }
        }

        let partial = limit.is_some_and(|l| best.len() > l);
        if args.algorithm == Algorithm::Anneal && !partial {
            // Remove one row at a time and repair the cover with annealing.
            let target_min = ((fs.size as i64) + b - 1) / b;
            let mut current = best.clone();
            while current.len() > target_min as usize
                && deadline.is_none_or(|d| Instant::now() < d)
            {
                let cnt = coverage_counts(&nbr, &current);
                // Drop the row that alone covers the fewest outcomes.
                let mut best_j = 0usize;
                let mut best_u = i64::MAX;
                for (j, &c) in current.iter().enumerate() {
                    let u = nbr
                        .ball(c as usize)
                        .iter()
                        .filter(|&&w| cnt[w as usize] == 1)
                        .count() as i64;
                    if u < best_u {
                        best_u = u;
                        best_j = j;
                    }
                }
                let start: Vec<u32> = current
                    .iter()
                    .enumerate()
                    .filter(|&(j, _)| j != best_j)
                    .map(|(_, &c)| c)
                    .collect();
                let (cand, unc) = anneal(
                    &nbr,
                    nbr.n_dist1,
                    &start,
                    args.iterations,
                    &mut main_rng,
                    args.t_start,
                    args.t_end,
                    None,
                    args.sample,
                    deadline,
                );
                if unc != 0 {
                    log.log(&format!(
                        "  anneal: no full cover found with {} rows",
                        start.len()
                    ));
                    break;
                }
                current = drop_redundant(&nbr, &cand, &mut main_rng);
                log.log(&format!("  anneal: full cover with {} rows", current.len()));
            }
            best = current;
        }

        chosen = best.clone();
        needed = best.len();
        if partial {
            let lim = limit.unwrap();
            log.log(&format!(
                "Full guarantee needs about {} rows; limiting to {lim} (partial cover).",
                best.len()
            ));
            // Greedy max-coverage with restarts; keep the best coverage.
            let results: Vec<(Vec<u32>, usize)> = (0..restarts)
                .into_par_iter()
                .map(|r| {
                    let mut rng = Pcg64::seed_from_u64(restart_seed(base, r));
                    let cand = greedy_cover(&nbr, &mut rng, Some(lim), r > 0, &[]);
                    let cov = coverage_counts(&nbr, &cand)
                        .iter()
                        .filter(|&&c| c > 0)
                        .count();
                    (cand, cov)
                })
                .collect();
            let mut best_cov = results[0].1;
            chosen = results[0].0.clone();
            for (cand, cov) in &results[1..] {
                if *cov > best_cov {
                    best_cov = *cov;
                    chosen = cand.clone();
                }
            }
            if args.algorithm == Algorithm::Anneal {
                let (c, _) = anneal(
                    &nbr,
                    nbr.n_dist1,
                    &chosen,
                    args.iterations,
                    &mut main_rng,
                    args.t_start,
                    args.t_end,
                    Some(&log),
                    args.sample,
                    deadline,
                );
                chosen = c;
            }
            chosen = dedupe(&chosen);
            if chosen.len() < lim {
                // anneal may merge duplicate rows
                chosen = greedy_cover(&nbr, &mut main_rng, Some(lim), true, &chosen);
            }
        }
        if let Some(k) = args.rows {
            let k = k as usize;
            if chosen.len() < k {
                log.log(&format!(
                    "Guarantee needs {} rows; adding {} rows to reach {k}.",
                    chosen.len(),
                    k - chosen.len()
                ));
                chosen = pad_rows(
                    &fs, &chosen, k, radius, &mut main_rng, args.max_memory_cells, &log,
                );
            }
        }

        chosen.sort_unstable();
        chosen.dedup();
        covered = coverage_counts(&nbr, &chosen)
            .iter()
            .filter(|&&c| c > 0)
            .count();
    }

    let elapsed = t0.elapsed().as_secs_f64();
    let n_rows = chosen.len();
    let cost = n_rows as f64 * args.row_price;

    if n_rows as i64 > MAX_FILE_ROWS {
        warn(format!(
            "{n_rows} rows exceeds the file limit of {MAX_FILE_ROWS} single rows"
        ));
    }
    if cost > MAX_STAKE_SEK {
        warn(format!(
            "cost {} SEK exceeds the limit of {} SEK",
            format_g(cost),
            format_g(MAX_STAKE_SEK)
        ));
    }

    let out = resolve_output(&args, &entries);
    if let Err(e) = write_file(
        &out,
        &args.product,
        &fs,
        &chosen,
        if args.crlf { "\r\n" } else { "\n" },
    ) {
        eprintln!("error: cannot write {}: {e}", out.display());
        return 2;
    }

    if args.quiet {
        return 0;
    }

    let mut summary: Vec<String> = Vec::new();
    summary.push(format!("{} reduced system", args.product));
    summary.push(format!("  System:        {}", entries.join(",")));
    summary.push(format!("  Full system:   {} rows", fs.size));
    let size_rule = if args.rows.is_some() {
        format!("exactly {} rows (--rows)", args.rows.unwrap())
    } else if args.max_rows.is_some() {
        format!("at most {} rows (--max-rows)", args.max_rows.unwrap())
    } else {
        "as few rows as possible".to_string()
    };
    summary.push(format!(
        "  Guarantee:     {} correct, {size_rule}",
        args.guarantee
    ));
    let algo = match args.seed {
        Some(s) => format!("{}, seed {s}", args.algorithm.as_str()),
        None => args.algorithm.as_str().to_string(),
    };
    summary.push(format!("  Algorithm:     {algo}"));
    let bound = match lower_bound {
        Some(lb) => format!(" (best found; lower bound {lb})"),
        None => String::new(),
    };
    summary.push(format!("  Rows needed:   {needed} for the full guarantee{bound}"));
    summary.push(format!(
        "  Rows written:  {n_rows}, cost {} SEK",
        format_g(cost)
    ));
    summary.push(format!(
        "  Guarantee {} holds for {covered}/{} outcomes ({:.2} %)",
        args.guarantee,
        fs.size,
        100.0 * covered as f64 / fs.size as f64
    ));
    if !args.no_verify {
        match hit_distribution(&fs, &chosen, 3e9) {
            None => summary.push("  Best result:   skipped (too large)".to_string()),
            Some(dist) => {
                summary
                    .push("  Best result over all outcomes of the full system:".to_string());
                for (&correct, &count) in dist.iter().rev() {
                    summary.push(format!(
                        "    {correct:2} correct: {count:8} outcomes ({:6.2} %)",
                        100.0 * count as f64 / fs.size as f64
                    ));
                }
            }
        }
    }
    summary.push(format!("  Time:          {elapsed:.2} s"));
    summary.push(format!("  Output file:   {}", out.display()));
    println!("{}", summary.join("\n"));
    0
}
