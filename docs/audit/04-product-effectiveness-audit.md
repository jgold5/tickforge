# 04 — Product Effectiveness & Usability Audit

**Project:** `tickforge` — "A quant trading research engine written in Zig" (README, in full)
**Audited revision:** `60d065f` (32 commits, 2026-01-17 → 2026-01-26, single author)
**Toolchain used:** Zig 0.14.1 (matches `minimum_zig_version` in `build.zig.zon`)
**Audit date:** 2026-09-22
**Lens:** fresh user (quant researcher / hobbyist algo trader / GitHub evaluator) and product manager. Nothing under `src/` or `build.zig` was modified.

---

## 1. Verdict

**Effectiveness today: 2 / 10.** tickforge compiles cleanly, runs deterministically in milliseconds, and its ~650 lines already contain the *right skeleton* for a research engine: a market abstraction, a strategy vtable, next-tick execution, a commission+slippage model, a trade log, an equity curve, drawdown, and an in-sample/out-of-sample split. That skeleton is why it is not a 0 or 1. But as a *product* it does not yet do the job its one-line README promises: a user cannot bring their own data, cannot choose a strategy or parameters, cannot change fees, and cannot get results out of the process in any machine-readable form without editing Zig source and recompiling. The only run mode is a hardcoded demo over 40 hand-typed prices whose output goes to **stderr**, prints every strategy **three times**, has no column definitions, and contains rows where **Gross < Net despite positive fees** — a visibly impossible number that any quant will spot in the first ten seconds and that undermines trust in every other number on the screen. There are zero unit tests and no documentation beyond the two-line README. The gap between "engine core exists" and "someone other than the author can use it" is the whole product, and none of the Zig-specific advantages that would justify choosing this over a Python tool (speed on large tick data, single-binary distribution, embeddability, WASM) are demonstrated or even reachable yet.

---

## 2. First-run walkthrough

### 2.1 Clone → README

The README is two lines:

```
# tickforge
A quant trading research engine written in Zig
```

There is no install instruction, no required Zig version (a user must open `build.zig.zon` to discover `minimum_zig_version = "0.14.1"`), no usage, no screenshot, no description of what "research engine" means here (backtester? data pipeline? live?), and no example. `build.zig` and `build.zig.zon` are the unmodified `zig init` templates, comments included. `.paths` in `build.zig.zon` even still has `LICENSE` and `README.md` commented out with `// For example...`. A GitHub evaluator who lands on this repo has no reason to clone it.

### 2.2 Build and run (timed)

| Step | Observed |
|---|---|
| Cold `zig build run` (no cache) | **9.7 s**, exit 0 |
| Warm `zig build run` | 0.02 s |
| `./zig-out/bin/tickforge` (Debug) | 6 ms, 3.0 MB binary |
| `zig build -Doptimize=ReleaseFast` | 1.1 s build, 3 ms run, 1.0 MB binary |
| `zig build test` | exit 0 — **but there are zero `test` blocks in `src/`**, so this is vacuous |

Time from clone to *some* output, for a user who already has Zig 0.14.1: under 15 seconds. That is genuinely good and is the one first-run strength. Time to a *meaningful* result: effectively never, because the only data is 40 synthetic prices (see 2.4).

### 2.3 What the user sees

Actual output excerpt (all 92 lines are on stderr; stdout is empty):

```
===IN-SAMPLE===
      Strategy |          Gross |            Net |           Fees |       Turnover |   Cost %
Buy Every Tick |         227.00 |         199.73 |          27.00 |        2743.27 |    0.98%
Buy Every Tick |         227.00 |         199.73 |          27.00 |        2743.27 |    0.98%
Buy Every Tick |         227.00 |         199.73 |          27.00 |        2743.27 |    0.98%
Mean Reversion |          29.00 |          16.88 |          12.00 |        1209.00 |    0.99%
Mean Reversion |          29.00 |          16.88 |          12.00 |        1209.00 |    0.99%
Mean Reversion |          29.00 |          16.88 |          12.00 |        1209.00 |    0.99%
Momentum(lb=5, th=0.03) |           5.00 |          10.98 |           2.00 |         207.02 |    0.97%
Momentum(lb=5, th=0.03) |           5.00 |          10.98 |           2.00 |         207.02 |    0.97%
Momentum(lb=5, th=0.03) |           5.00 |          10.98 |           2.00 |         207.02 |    0.97%
...
Momentum(lb=3, th=0.02) |           0.00 |           6.99 |           1.00 |         102.01 |    0.98%
...
Momentum(lb=1, th=0.03) |           0.00 |           0.00 |           0.00 |           0.00 |      N/A
Momentum(lb=1, th=0.03) |           0.00 |           0.00 |           0.00 |           0.00 |      N/A
Momentum(lb=3, th=10.00) |           0.00 |           0.00 |           0.00 |           0.00 |      N/A
Momentum(lb=1, th=0.03) |           0.00 |           0.00 |           0.00 |           0.00 |      N/A
...
          Dumb |          -2.00 |          -4.02 |           2.00 |         200.00 |    1.00%
===OUT-OF-SAMPLE===
      Strategy |          Gross |            Net |           Fees |       Turnover |   Cost %
Buy Every Tick |          56.00 |          44.88 |          11.00 |        1176.12 |    0.94%
...
```

### 2.4 Friction points, in the order a user hits them

1. **No way to know how to run it.** README gives no command. The user has to know Zig conventions (`zig build run`).
2. **Output is on stderr.** `std.debug.print` is used for results (`src/main.zig` lines 40–77). `./tickforge > results.txt` produces a **0-byte file** (verified). Any pipeline, notebook, or `grep` needs `2>&1`. This is the single most surprising behaviour for a CLI tool.
3. **Arguments are ignored.** `tickforge --help` runs the backtest. There is no argv handling anywhere in `src/` (grep for `argv`, `process`, `std.fs`, `std.io`, `std.json`, `csv` returns nothing).
4. **Every strategy is printed three times.** `src/research/runner.zig` lines 17–22 call `engine.run` three times per strategy and append all three results. 92 rows, only 24 distinct. Nothing tells the user this is a determinism check (the commit message says so; the output does not). It reads as a bug.
5. **The duplicates are scrambled.** `printResults` uses `std.sort.heap` (unstable) on `net_pnl`, so the many zero-PnL Momentum rows interleave — `Momentum(lb=1, th=0.03)` appears, then `lb=3, th=10.00`, then `lb=1, th=0.03` again. The eye cannot group them.
6. **Column alignment breaks** for the sweep labels: `Momentum(lb=5, th=0.03)` is 23 characters in a 14-character column, so the table shears exactly where the interesting rows are.
7. **No column definitions.** What is "Turnover" (it is total gross traded notional, `Metrics.calcTotalGrossValue`)? "Cost %" is `total_fees / total_gross_value`, and "Fees" is commission only — the 1 bp slippage is not in "Fees", so "Cost %" *understates* the actual cost the engine charged. None of this is explained anywhere.
8. **Metrics that were computed are not shown.** `BacktestResult` (`src/result.zig`) carries `max_drawdown`, `equity_curve`, `trades`, `executed_buys/sells`, `rejected_buys/sells`, `initial_equity`, `final_equity` — none are printed. The engine knows more than it tells you.
9. **Gross < Net.** Two in-sample rows (`Momentum(lb=3, th=0.02)`: Gross 0.00, Net 6.99, Fees 1.00; `Momentum(lb=5, th=0.03)`: Gross 5.00, Net 10.98, Fees 2.00) are arithmetically impossible under positive commission and adverse slippage. Root cause is out of scope for this audit; impact is discussed in §5.
10. **The data is 40 hand-typed integers** (`src/main.zig` lines 16–22) with integer tick indices (`time: usize`) and no timestamps. The 70/30 split leaves **12 out-of-sample ticks**; with lookback 9, a Momentum variant gets 3 decision points OOS. 7 of the 15 strategies never trade at all (all "N/A" rows). No conclusion drawn from this output has any statistical meaning, and the program cannot be pointed at anything else.
11. **No `--quiet`, no exit code semantics, no logging control.** Decision/execution logging exists (`logDecision`, `logExecution` in `src/engine/engine.zig`) but is gated by `const enable_decision_logging = false;` at lines 13–14 — compile-time, edit-source-to-enable.

---

## 3. Job-to-be-done table

Rating scale: **Not possible** / **Edit source** (requires modifying and recompiling Zig) / **Config/API** (achievable via CLI flags, config file, or a stable public API without touching engine source).

| # | Capability | Status | Evidence | What it would take |
|---|---|---|---|---|
| a | **Bring your own price data** | **Not possible** (as shipped) → *Edit source* to hack | Only data source is `SyntheticMarket` wrapping a hardcoded `[_]f64` in `main.zig:16`. No file I/O, no CSV/JSON parsing, no argv in the codebase. `Market` (`src/engine/market.zig`) exposes only `len()`/`priceAt(t)` on a bare `f64` — no timestamp, no OHLCV, no volume, no symbol. | A `CsvMarket` (~60 lines: read file, parse `ts,price` or OHLCV, expose `Bar`), a `--data <path>` flag, and widening `Market` to carry a timestamp so time-based metrics become possible. |
| b | **Write a strategy** | **Edit source** | Requires a struct with `decide`, a hand-written `*anyopaque` `@ptrCast` adapter, a `toStrategy` constructor, an import in `main.zig`, and registration inside `buildStrategies`. Worked example in §4. There is no `examples/` dir, no doc for the `Strategy` contract, and `src/strategy/params.zig` is dead code that imports the module as if it were the struct. | A `comptime` generic `Strategy(T)` wrapper that generates the adapter, a one-line registry, a documented `decide(ctx, bar, portfolio) Intent` contract, and one worked example in the README. |
| c | **Run a backtest with realistic costs** | **Edit source** | `ExecutionModel{ .commission_per_trade = 1, .slippage_bps = 1 }` is hardcoded in `initDefault()` (`src/engine/execution.zig:8`) and hardwired in `runner.zig:16`. `BacktestConfig` has one field (`starting_cash`). Slippage is a symmetric bps; commission is flat per trade regardless of size; no percentage commission, no spread, no partial fills, no position-size checks beyond cash/position sufficiency, no shorting (sells beyond position are rejected). | Expose `--commission`, `--slippage-bps`, `--starting-cash`; add a percentage commission option; put the whole `ExecutionModel` on `BacktestConfig`. Two hours of work; the model itself is fine as a starting point. |
| d | **Get trustworthy metrics** | **Not possible** today | Only Gross/Net/Fees/Turnover/Cost% are printed. No Sharpe, Sortino, CAGR, win rate, exposure, or per-trade stats; `max_drawdown` is computed but not shown. Gross < Net appears in the output. `time` is a tick index, so annualisation is impossible. Zero tests (`grep 'test "' src` → 0). | Fix the Gross/Net inconsistency and add an invariant test (`net <= gross` when fees > 0); add timestamps; print the computed drawdown/trade counts; add Sharpe/Sortino/CAGR once timestamps exist; add golden-result tests. |
| e | **Compare / sweep parameters** | **Edit source** | The Momentum sweep is two literal arrays in `main.zig:89–90` and a nested loop at 97–106. Only Momentum is swept; Mean Reversion is fixed at `(3, 0.01)`. Results are sorted by net PnL only. No sweep for fees, split ratio, or execution mode. | `--sweep lookback=5:50:5 --sweep threshold=0.01,0.02,0.03`, a generic parameter grid that works for any strategy, and a ranked output that keys on the parameter tuple. |
| f | **Persist and share results** | **Not possible** | No JSON/CSV export, no equity-curve dump, no trade log output, no plots, no run ID/config echo. Output is human-oriented text on stderr; redirecting stdout captures nothing. | `--out results.json` (strategy, params, metrics, equity curve, trades), `--format csv|json|table`, results on **stdout**, logs on stderr. `std.json` is in the standard library, so this is roughly a day. |

Also relevant to (d): the `Momentum` strategy registers `resetFn = null` (`momentum.zig:47`) while the runner runs each instance three times back-to-back; `MeanReversion` does implement a reset. A reader who notices this will wonder whether run 2 starts with run 1's ring buffer. The output happens to be identical across the three runs, but a user cannot know that without reading the engine.

---

## 4. Extensibility as a user would experience it

### 4.1 Adding a new strategy — Momentum as the worked example

What actually exists today for Momentum, counted from the source:

| Piece | File | Lines |
|---|---|---|
| Imports | `src/strategy/momentum.zig` 1–4 | 4 |
| Struct + `init` + `decide` (the actual trading logic is ~14 lines of this) | `momentum.zig` 6–39 | 34 |
| `momentumDecideAdapter` (`@ptrCast(@alignCast(ctx))` boilerplate) | `momentum.zig` 41–44 | 4 |
| `toStrategy` | `momentum.zig` 46–48 | 3 |
| `MomentumParams` | `momentum.zig` 50–53 | 4 |
| Import in main | `src/main.zig` 11 | 1 |
| Parameter grids + create/init/toStrategy/label/append loop in `buildStrategies` | `main.zig` 89–90, 97–106 | 12 |
| **Total** | **2 files** | **≈62 lines, of which ~20 are strategy logic and ~40 are ceremony** |

Ground truth from history: commit `00b4a98 feat(strategy): add momentum strategy` was **59 insertions across 2 files**; `165dbcc` (Mean Reversion) was **65 insertions across 3 files**. So the empirical cost of a new strategy is ~60 lines in 2–3 files, plus a recompile, plus understanding `*anyopaque` vtables — a Zig-specific idiom a quant will not know. Every strategy also has to re-implement its own ring buffer (`prices/count/head` is copy-pasted verbatim between `momentum.zig` and `mean_reversion.zig`), because there is no indicator library.

Compare: in backtrader a moving-average crossover is ~15 lines in one file; in vectorbt it is 3 lines.

### 4.2 Adding a new data source

Mirror `src/market/synthetic.zig`: a struct with `len`/`priceAt`, two `*anyopaque` adapter functions, a `toMarket`, then wire it in `main.zig` — ~30 lines of glue **plus** writing the file reader/parser yourself, since none exists. And because `Market.priceAt` returns a bare `f64`, any richer data (timestamps, OHLCV, multiple symbols) needs a change to the `Market` interface and every consumer. Realistically: edit 3–4 files.

### 4.3 Changing fees

Edit `src/engine/execution.zig:8` (the `initDefault` literals) or `src/research/runner.zig:16` (where `initDefault()` is called), recompile. One line, but it is engine source, not configuration, and there is no per-strategy or per-run override.

### 4.4 Enabling trade logs

Flip `const enable_decision_logging = false;` / `enable_execution_logging` in `src/engine/engine.zig:13–14`, recompile. Log lines go to stderr interleaved with results.

---

## 5. Output, reporting and trust

**Output & reporting.** No JSON, no CSV, no plots, no per-trade log by default, no equity curve output, no run metadata. Results and logs share stderr. The rendered table lacks a legend, breaks alignment on long labels, and triples every row. For a research tool, "persist and share" is not a nice-to-have — a researcher's unit of work is a comparison across runs, and tickforge gives them nothing to diff.

**Trust.** Would a quant believe these numbers? No, and for reasons that are visible *without* reading the code:

- **Gross < Net with positive fees** in two rows. Costs can only make Net ≤ Gross. A researcher who sees this will (correctly) assume the accounting is wrong somewhere and will not trust Gross, Net, or Cost% for any row. This is the most damaging single defect in the product because it is the one a user can verify by eye. Root cause is being handled by another audit; from the product side the fix must come with a permanent invariant test (`net_pnl <= gross_pnl` whenever `total_fees > 0`) that runs in CI.
- **Zero tests.** `zig build test` reports success on an empty test set. There is no golden backtest, no cost-model test, no drawdown test. A user evaluating on GitHub will check the test directory first and find none.
- **Vacuous "N/A" rows** for 7 of 15 strategies: with `threshold = 10.0` (1000%) no signal can fire, and with `lookback = 1` the average equals the current price so no signal can fire either. Half the sweep grid is a placeholder, which signals to a reader that the sweep was never used to make a decision.
- **Triplicate rows** read as a bug even though they were intended as a determinism check.
- **12 OOS ticks** on invented data means the IS/OOS headline is decorative.
- On the positive side: the engine *is* deterministic (three identical runs, verified), next-tick execution exists (no look-ahead on the fill), rejected orders are counted, and the trade log records fee and gross value per fill. The bones are honest; the reporting is not yet.

---

## 6. Feature / competitive matrix

Established tools chosen: **backtrader** (Python, event-driven, the hobbyist default), **vectorbt** (Python/Numba, vectorised, the parameter-sweep specialist), **NautilusTrader** (Rust core + Python API, tick-level, backtest↔live), **LEAN / QuantConnect** (C# engine, Python or C# algos, institutional-style multi-asset). zipline-reloaded is comparable to backtrader for this purpose and is omitted for space.

| Capability | tickforge (today) | backtrader | vectorbt | NautilusTrader | LEAN |
|---|---|---|---|---|---|
| Language / runtime | Zig, single static binary, no deps | Python | Python + Numba | Rust core, Python API | C# engine, Python/C# algos, Docker |
| Bring your own data (CSV/Parquet/DataFrame) | **No** (hardcoded 40 prices) | Yes (CSV, pandas, many feeds) | Yes (any pandas) | Yes (Parquet catalog, CSV, DB) | Yes (data folder + cloud data) |
| Data model | Single `f64` price per tick index; no timestamp | OHLCV bars, multi-feed | OHLCV / arbitrary arrays | Ticks, quotes, trades, order book, bars | Bars, ticks, options chains, futures |
| Multi-asset / portfolio | No (one position, one price) | Yes | Yes (columns) | Yes | Yes |
| Order types | Market only (implicit); no short | Market, limit, stop, stop-limit, brackets, OCO | Signals → market (with limit/stop-loss sim) | Full order types, TIF | Full order types |
| Cost model | Flat $/trade + symmetric bps slippage, hardcoded | Commission schemes, slippage, margin | Fees %, fixed, slippage | Fee models per venue, maker/taker | Fee/slippage/fill models, margin |
| Metrics | Gross, Net, Fees, Turnover, Cost% (drawdown computed, not shown) | Analyzers: Sharpe, DD, SQN, returns… | Full stats (Sharpe, Sortino, Calmar, exposure, trade stats) | Full stats + per-trade reports | Full stats + backtest report |
| Parameter sweeps | Momentum only, edit source | `optstrategy`, multiprocess | Native, vectorised across all params | Via scripting | Cloud optimiser / local CLI |
| Walk-forward / IS-OOS | 70/30 index split, hardcoded | Manual | Splitter helpers | Manual | Manual |
| Export / reporting | **None** (stderr text) | matplotlib plots, custom writers | Plotly, pandas, HTML | Reports, Parquet, JSON | HTML report, JSON, charts |
| CLI / config-driven runs | **No** (argv ignored) | Script-driven | Script/notebook | Config + Python | `lean` CLI + JSON config |
| Live trading path | No | Yes (IB, Oanda, etc.) | No (OSS) | Yes (many adapters) | Yes (many brokerages) |
| Tests / CI | **0 tests** | Yes | Yes | Extensive | Extensive |
| Docs / examples | 2-line README | Extensive | Extensive | Extensive | Extensive |
| Performance claim | None, unmeasured | Slow (pure Python) | Very fast for vectorisable strategies | Fast, tick-level, no GC in core | Moderate; cloud scale-out |

tickforge is currently behind every column, including the ones (performance, tick-level, no-GC, embeddability) where Zig could plausibly win.

---

## 7. Positioning and the minimum lovable product

### 7.1 Who is the target user?

Not the institutional quant — they need multi-asset, order books, and a live path, and Nautilus/LEAN exist. The credible target is the **developer-quant or serious hobbyist** who:

- has been burned by Python environments and wants a **single binary** they can `curl` onto a VPS or ship to a teammate;
- is running **large tick or 1-second datasets** where backtrader is too slow and vectorbt's vectorisation doesn't fit a path-dependent strategy;
- wants an engine **small enough to read end-to-end and audit** (tickforge's ~650 lines are a feature, if they are correct and tested);
- may want to **embed** the engine (C ABI from Python/Rust, or WASM in a browser) rather than adopt a framework.

### 7.2 Why Zig — what the differentiation could credibly be

| Zig angle | Realised today? | What "demonstrated" would look like |
|---|---|---|
| Tick-level speed, no GC, predictable latency | No — 40 ticks, function-pointer vtables, unmeasured | README benchmark: N million ticks/sec for a path-dependent strategy vs backtrader and vectorbt on the same CSV |
| `comptime` strategy specialisation (zero-overhead, monomorphised loop) | No — runtime `*anyopaque` vtables | `Strategy(T)` generic; adapter code generated by the compiler, not hand-written per strategy |
| Single static binary, trivial cross-compilation | Partly — 1 MB ReleaseFast binary exists, but no release process | `zig build -Dtarget=aarch64-macos`, release artifacts for 3 OSes, `curl | sh` install |
| Embeddable via C ABI | No | `libtickforge` with `tf_run(config, data, n) -> result`; a 30-line Python ctypes example |
| WASM / browser backtesting | No | `-Dtarget=wasm32-freestanding` build target and a demo page |
| Deterministic, reproducible runs | Yes in spirit (three identical runs) | A `--seed`/config hash printed in the results, and a test asserting bitwise-identical results across runs |

Recommendation: **tickforge should be "the small, auditable, embeddable tick-replay core"** — a fast deterministic engine with a clean CLI and a C ABI, benchmarked in the README, that people reach for when Python is too slow or too heavy and Nautilus is too big. It should *not* try to be a framework with brokers, data vendors, and a GUI. Everything that is not the loop, the cost model, the metrics, and the I/O should stay out.

### 7.3 Minimum lovable product

Concrete capability list, in priority order. Items 1–6 are the bar for "someone other than the author can use it"; 7–10 are the bar for "worth choosing over Python".

1. **Data in:** `--data prices.csv` (columns `timestamp,price` or OHLCV; ISO-8601 or epoch). Timestamps stored, not tick indices.
2. **Strategy selection & params:** `--strategy momentum --param lookback=20 --param threshold=0.02`; strategies registered in one place; a `comptime` `Strategy(T)` wrapper so a new strategy is one file with one `decide` function and no adapter.
3. **Costs as config:** `--commission 1.0 --commission-pct 0.0005 --slippage-bps 1 --cash 10000`.
4. **Trustworthy metrics:** Net, Gross, Fees, Slippage, Turnover, Max DD, CAGR, Sharpe, Sortino, trades, win rate, exposure; each strategy printed once; a legend or `--explain`; invariant tests (`net <= gross` under positive costs) and golden backtests in `zig build test`, run in CI.
5. **Results out:** results on **stdout**, logs on stderr; `--format table|json|csv`; `--out run.json` with config echo, metrics, equity curve, trade log; `--trades` for a per-fill log at runtime instead of a compile-time const.
6. **README:** install (`zig 0.14.1`), 30-second quickstart, one strategy example, metric glossary, and a real sample dataset in `examples/`.
7. **Sweeps:** `--sweep lookback=5:50:5 --sweep threshold=0.01,0.02,0.03` for any strategy; ranked JSON output keyed by parameter tuple.
8. **Walk-forward:** `--split 0.7` or `--walk-forward 5` windows, with IS/OOS reported side by side and clearly labelled.
9. **Benchmark:** a `bench` build step over a 10M-tick file; numbers in the README next to backtrader/vectorbt.
10. **Distribution & embedding:** release binaries for linux/macos/windows; `libtickforge` C ABI with a Python ctypes example; a wasm32 build target.

### 7.4 The README this product should grow into

```
## Quickstart

$ curl -L https://github.com/.../tickforge-x86_64-linux -o tickforge && chmod +x tickforge
$ tickforge run --data examples/btcusdt-1s.csv \
      --strategy momentum --param lookback=20 --param threshold=0.02 \
      --commission 1.0 --slippage-bps 1 --cash 10000 \
      --split 0.7 --out run.json

strategy                 sample  net_pnl  gross_pnl  fees  max_dd   sharpe  trades
momentum(lb=20,th=0.02)  IS       412.30     455.30  43.0  -3.1%    1.42       43
momentum(lb=20,th=0.02)  OOS      118.05     130.05  12.0  -2.4%    1.10       12

Wrote run.json (metrics, equity curve, 55 trades). 1,209,600 ticks in 41 ms.

$ tickforge sweep --data examples/btcusdt-1s.csv --strategy momentum \
      --sweep lookback=5:50:5 --sweep threshold=0.01,0.02,0.03 --format csv > sweep.csv
```

```zig
// src/strategy/my_crossover.zig — a complete user strategy
const tf = @import("tickforge");

pub const Params = struct { fast: usize = 10, slow: usize = 30 };

pub const MyCrossover = struct {
    fast: tf.ind.Sma,
    slow: tf.ind.Sma,

    pub fn init(alloc: std.mem.Allocator, p: Params) !MyCrossover {
        return .{ .fast = try tf.ind.Sma.init(alloc, p.fast), .slow = try tf.ind.Sma.init(alloc, p.slow) };
    }

    pub fn decide(self: *MyCrossover, bar: tf.Bar, pf: *const tf.Portfolio) tf.Intent {
        const f = self.fast.push(bar.close) orelse return .hold;
        const s = self.slow.push(bar.close) orelse return .hold;
        if (f > s and pf.position == 0) return .{ .buy = 1 };
        if (f < s and pf.position > 0) return .{ .sell = pf.position };
        return .hold;
    }
};

// registry.zig — one line per strategy; the adapter is generated at comptime
pub const strategies = .{ tf.Strategy(MyCrossover, "crossover"), tf.Strategy(Momentum, "momentum") };
```

Everything in that snippet is a straight-line extension of what already exists in `src/`: the `Intent` union, the `Portfolio`, the `ExecutionModel`, the equity curve and drawdown in `Engine.run`, and the IS/OOS split in `main.zig`. The distance is not architectural; it is the I/O, the CLI, the metrics, the tests, and the README.

---

## 8. Scorecard summary

| Dimension | Score (0–10) | One-line reason |
|---|---|---|
| First-run experience | 3 | Builds and runs in <15 s, but no README guidance, stderr output, triplicated unexplained table |
| Bring your own data | 0 | Hardcoded array; no I/O of any kind |
| Strategy authoring | 3 | Possible, ~60 lines / 2 files / recompile, Zig vtable idiom required |
| Realistic costs | 3 | A reasonable model exists but is hardcoded in engine source |
| Trustworthy metrics | 1 | Gross < Net visible in output; no tests; 5 metrics printed, none annualisable |
| Sweeps & comparison | 2 | Hardcoded Momentum grid; half the grid can never trade |
| Persist & share | 0 | Nothing leaves the process except stderr text |
| Documentation | 0 | Two lines |
| Zig differentiation realised | 1 | 1 MB static binary exists; nothing else demonstrated |
| **Overall** | **2** | Right skeleton, no product |
