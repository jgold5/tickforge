# tickforge — Quantitative Research Methodology Audit

**Scope:** `src/` at commit `60d065f` ("enforce deterministic engine execution"), ~720 lines of Zig.
**Method:** every file under `src/` read in full; `zig build run` executed twice (bit-identical output); an instrumented copy of the tree was built in scratch space to expose the `BacktestResult` fields the CLI does not print; an independent pure-Python re-implementation of the engine was written and reproduced every Net / Gross / Fees cell of the Zig output exactly for all 15 strategies × 2 samples, and was then used to compute the metrics the tool omits. No file under `src/` or `build.zig` was modified.
**Lens:** would a systematic-trading PM or research lead accept conclusions produced by this tool today?

---

## 1. Verdict

tickforge is a small, clean, deterministic **event-loop skeleton** with a sound decision/execution split, but it is not yet a quant research tool: nothing the current example run prints can support a research conclusion, and two of the headline numbers it does print are wrong. The "in-sample / out-of-sample" study runs on **40 hand-typed integer prices** (28 train / 12 test) with no time axis, sizes every trade at exactly **one unit against $10,000** (so all PnL is 0.01–2% of capital and "Cost %" is a tautology of the $1 flat commission), sweeps 12 momentum parameter pairs of which **7 are structurally unable to trade**, prints each result **three times** (a determinism smoke test that leaked into the results table), and ranks everything by **net dollar PnL** with no return, risk, significance, or benchmark column. The gross-vs-net decomposition, the tool's most distinctive feature, is mis-marked whenever a position is open at the end of the run, producing rows where `Net > Gross`. The one strategy in the parameter sweep (`Momentum`) is the one strategy that is **not reset** between repeats, so its rejected-order counts silently differ across the three "identical" rows. The engine core is worth keeping; the research layer around it needs to be rebuilt before any output is shown to a decision-maker.

### Scorecard (0 = absent, 5 = professional-grade)

| Dimension | Score | One-line justification |
|---|:---:|---|
| Research validity | **1** | 40 synthetic integer prices, single fixed 70/30 cut, no walk-forward, no multiple-testing control, ranking by $PnL, 3× duplicated rows; max t-stat of any strategy's mean tick return is 1.64. |
| Metrics completeness | **1** | Prints gross/net $PnL, fees, gross traded $ (mislabelled "Turnover"), cost %. Computes but never prints max DD and equity curve. No returns, vol, Sharpe, hit rate, exposure, benchmark. Gross PnL is wrong for open positions (`metrics.zig:37`). |
| Market realism | **1** | Flat $1 commission + fixed 1 bp slippage; quantity explicitly discarded (`execution.zig:13`); no spread, impact, latency, partial fills, shorting, leverage, calendar, volume, multi-asset. |
| Strategy expressiveness | **2** | Clean, look-ahead-safe `decide(price, portfolio, time) -> Intent` with reset hook; but no history/bars/volume access (each strategy re-implements a ring buffer), no multi-asset, no target-position, no limit/stop orders, no order state, pending intent on last tick silently dropped. |
| Risk / position sizing | **0** | `BacktestConfig` has one field (`starting_cash`). Every strategy hard-codes qty 1. No capital allocation, vol targeting, risk limits, leverage, or margin. |
| Reproducibility / provenance | **2** | Bit-identical across runs (verified) and reset semantics exist; but results keyed by a name string, printed to stderr only, no config/data hash, seed, run id, or persistence; no unit tests (`grep 'test "' src/` → none); `Momentum.resetFn = null` leaks state across repeats. |
| **Overall research effectiveness** | **1** | A correct toy loop wrapped in a study design that cannot distinguish a strategy from noise or from market beta. |

---

## 2. What is sound (credit where due)

These choices are correct and should be preserved through any rewrite:

- **Decision / execution separation** (`engine.zig:61` vs `engine.zig:93-133`): the strategy emits an `Intent`; the engine owns fills, cash, and position. Strategies cannot mutate the portfolio (`*const Portfolio`, `strategy.zig:6`).
- **`NextTick` fill mode** (`engine.zig:51-60, 66-68`, chosen at `runner.zig:16`): a decision at *t* fills at the price of *t+1*. This is the single most important anti-look-ahead safeguard a bar-based backtester can have, and it is on by default.
- **No look-ahead surface for strategies**: `decide` receives only the current price, a portfolio snapshot, and the tick index. A strategy cannot reach the price array. (Note the latent hazard: `Market.prices` at `market.zig:5` exposes the full future series to anything holding a `Market`; today only the engine and `Metrics` do.)
- **Gross vs net intent**: recording `fee` and `gross_value` per trade (`trade.zig:6-7`) and decomposing into gross/net/fees (`metrics.zig`) is the right instinct; the implementation just needs the mark-price fix in §4.
- **Reset semantics** (`engine.zig:37-43`): the engine re-initialises portfolio, time, pending intent, and calls the strategy's `resetFn` before each run. Correct design; incomplete adoption (see Gap 9).
- **Determinism intent**: no RNG, no wall-clock, no allocation-order dependence in results; two consecutive runs diffed identical.
- **Cash and inventory constraints enforced at execution** (`engine.zig:109-112, 121-124`) with `assert`s, and rejections counted rather than silently clamped.
- **Small, readable, single-pass code** with a stable extension point (`Market` and `Strategy` vtables), which makes every fix below cheap.

---

## 3. Top 10 gaps, ranked by impact on research conclusions

### Gap 1 — The "market" is 40 hand-typed integers with no time axis
**Where:** `main.zig:16-22` (prices), `main.zig:24` (`split = n*70/100` → 28/12), `market/synthetic.zig`.
**Why it matters:** with 28 training ticks and 12 test ticks there is no statistical power for any question. The series has 14 distinct integer price levels, tick-return mean +0.37% / sd 1.73% in-sample; if a tick were a day, that is a market with an annualised Sharpe of roughly 3.4 and a +93% drift, so *any* long exposure "works". The prices were typed by the same author who wrote the strategies, which is data snooping by construction. There is no timestamp, no calendar, no volume, no OHLC, no returns distribution to reason about, and no second asset. Survivorship and corporate actions cannot even be assessed because there is no data layer.
**Concrete example:** OOS is 12 ticks. `Momentum(lb=9, ...)` needs 9 ticks of warm-up (`momentum.zig:20-25`), leaving 3 decision ticks; its entire OOS record is one buy at t=9 and a −$1.01 result. `Momentum(lb=5, th=0.03)`, the in-sample winner, never trades OOS at all.
**Professional:** years of real (or seeded, documented synthetic / bootstrapped) data at a stated frequency; multiple instruments and regimes; timestamps and a trading calendar; OHLCV bars or tick data with a data-quality layer; a data hash recorded in the run manifest.

### Gap 2 — No position sizing; PnL in dollars on an arbitrary 1-unit convention, and no benchmark
**Where:** `intent.zig:1-5` (absolute qty), every strategy hard-codes `1` (`dumb.zig:11,14`, `buy_every_tick.zig:11`, `mean_reversion.zig:32,34`, `momentum.zig:31,33`), `config.zig:1-3` (`starting_cash` is the only knob), `main.zig:35` (`10000`).
**Why it matters:** with one $100 unit against $10,000 cash, every strategy is ~1% invested per lot, so all PnL is between −0.04% and +2.0% of capital and dollar PnL mostly measures *how many times the strategy bought in a rising market*. The $1 flat commission on ~$100 notional is a 100 bp per-side cost, an order of magnitude above institutional reality, which is why "Cost %" reads 0.89–1.00% on every row: it is `commission / notional` for a fixed-notional unit and carries no information about the strategy. There is no buy-and-hold row and no market return in the header.
**Concrete example:** In-sample "winner" `Buy Every Tick` nets $199.73 (+2.0%). A full-capital buy-and-hold of 100 units would have netted **$998** (+10.0%); OOS the comparison is $44.88 vs **$271**. The tool's best strategy trails the trivial benchmark 5–6× and nothing in the output reveals it.
**Professional:** returns on capital (not dollars); target-position or target-weight intents; volatility targeting; leverage/margin model; a benchmark row and alpha/beta vs it; costs in bps of notional with a realistic commission schedule.

### Gap 3 — Selection by net dollar PnL with no significance test or multiple-testing control
**Where:** `main.zig:46-48` (`lessThanByNetPnlDesc`), `main.zig:51` (`std.sort.heap`), `main.zig:89-90` (4 lookbacks × 3 thresholds), `runner.zig:17-22` (×3 repeats).
**Why it matters:** 12 parameter pairs are run, then the table is sorted descending so the top row is a "winner" by construction. No Sharpe, no confidence interval, no trial count. Recomputing per-tick equity returns: the highest t-statistic of any mean return in the whole study is **1.64** (`Momentum(lb=5, th=0.03)`, 27 observations); nothing is distinguishable from zero even before correcting for 12 (effectively 5) trials. Because the sort is on PnL and 0 > any loss, "never trade" configurations rank above every losing strategy: the ranking rewards inactivity.
**Concrete example:** rank-ordered in-sample momentum results and their OOS outcomes: (5, 0.03) IS +10.98 → OOS **0.00** (no trades); (9, 0.03) +10.92 → **−1.01**; (9, 0.02) +9.89 → **−1.01**; (5, 0.02) +8.90 → **−0.02**; (3, 0.02) +6.99 → **0.00**. Every in-sample winner is flat or negative out of sample, and the tool prints IS and OOS as two separately sorted tables with no join, so a reader must eyeball 90 rows to discover this.
**Professional:** Sharpe with standard error, deflated Sharpe ratio or White's reality check / Hansen SPA across the sweep, probability of backtest overfitting (CSCV), a trial registry that counts every configuration ever run, and IS/OOS reported side by side per configuration.

### Gap 4 — Single fixed split, no walk-forward, cold-start OOS
**Where:** `main.zig:24-26, 36-39` (one 70/30 cut; `train_strategies` and `test_strategies` built separately, so the OOS strategy starts with an empty ring buffer).
**Why it matters:** one split is one sample of one regime. Here both halves trend up (+10% and +2.75%), so the OOS "confirms" nothing about robustness. Because the OOS strategies are fresh objects, their warm-up burns 3–9 of the 12 OOS ticks; a real pipeline carries IS history into the OOS window so that the first OOS decision is made with full context.
**Concrete example:** `Momentum(lb=9)` has 3 OOS decision ticks; `Mean Reversion(3)` has 10. Comparing them OOS is comparing different sample sizes.
**Professional:** anchored or rolling walk-forward with re-optimisation each fold; purged/embargoed cross-validation; warm-up carry-over; results aggregated across folds with dispersion.

### Gap 5 — Missing return-based metrics; computed metrics not printed; "Turnover" mislabelled
**Where:** `main.zig:52-78` prints six columns; `result.zig:13,16` (`max_drawdown`, `equity_curve`) and `result.zig:6-9` (executed/rejected counts) are computed in `engine.zig:75-84` and then discarded by the printer. `main.zig:54` labels `total_gross_value` (sum of `exec_price × qty`, `metrics.zig:12-18`) as "Turnover".
**Why it matters:** a PM reads returns, vol, Sharpe/Sortino/Calmar, max DD and its duration, hit rate, average win/loss, profit factor, exposure, turnover as a ratio of capital, and trade count. None are shown. "Turnover" of `2743.27` is $ gross traded, not a ratio; as a ratio to average equity it is 0.27 in-sample for `Buy Every Tick` and 0.01–0.11 for the momentum rows.
**Concrete example (recomputed):** `Dumb` in-sample: max DD −0.04% looks benign, but the drawdown lasts **27 of 28 ticks** (never recovers). Momentum round-trip hit rates are **0/2, 0/2, 0/1**; the positive net PnL comes entirely from unrealised marks on 6–7 open units at the end. `Mean Reversion` has hit rate 4/6 and profit factor 9.3 but shows up fourth because its dollars are smaller.
**Professional:** a tearsheet per run (pyfolio/quantstats/vectorbt-style): return series, annualised return/vol, Sharpe/Sortino/Calmar, DD table with durations, trade-level stats, exposure, turnover ratio, benchmark alpha/beta.

### Gap 6 — Gross PnL is marked at the wrong price (bug)
**Where:** `metrics.zig:37`: `final_price = market.priceAt(trades[trades.len-1].time)`; net PnL uses the last market price (`engine.zig:88-89`).
**Why it matters:** gross marks any open position at the price of the *last trade*, net marks it at the *last tick*. The two differ whenever a position is open at the end, so `Gross − Net ≠ fees + slippage` and rows appear where **Net > Gross**, which a reader would interpret as negative costs. The decomposition is wrong for 4 of the 6 in-sample momentum rows that trade.
**Concrete example:** `Momentum(lb=3, th=0.02)` IS: one buy at t=20 @102.01, held to t=27 @110. Tool prints Gross **0.00**, Net **6.99**, Fees 1.00. Correct gross is **+8.00**. `Momentum(lb=5, th=0.03)`: printed Gross 5.00 vs Net 10.98; correct gross is **13.00** (= 10.98 + 2 fees + 0.02 slippage). Verified by trade dump and by the Python re-implementation.
**Professional:** one mark-to-market convention for all PnL variants, with a unit test asserting `gross − net == fees + slippage` on a synthetic fixture.

### Gap 7 — Execution model is a placeholder; quantity is discarded; shorting silently impossible
**Where:** `execution.zig:8` (defaults `commission_per_trade = 1`, `slippage_bps = 1`), `execution.zig:13` (`_ = quantity;`), `engine.zig:121-124` (sell rejected if `position < qty`), `engine.zig:66-68` + loop exit (pending intent on the final tick is never executed).
**Why it matters:** no spread, no market impact (a 1-unit and a 10,000-unit order fill at the same price), no latency beyond one tick, no partial fills, no order types, no borrow/short side, no margin. Momentum is written as a two-sided strategy (`momentum.zig:31` emits `Sell` on a downside break) but every sell signal with flat inventory is rejected and the rejection count is not printed, so the "momentum" being evaluated is *long-only momentum with unlimited pyramiding and no exit*. The last intent of every run is dropped (`Buy Every Tick` executes 27 of 28 buys), which is not reported.
**Concrete example:** instrumented run, `Momentum(lb=9, th=0.02)` IS: 9 buys, 2 sells executed, **2 sells rejected**, final position 7 units. OOS: the same configuration rejects 0–2 sells and ends long 1 unit.
**Professional:** spread + square-root impact model driven by quantity and ADV, participation limits, configurable latency, partial fills, limit/stop/market order types, short selling with borrow cost, margin and liquidation, and per-order fill reports.

### Gap 8 — Strategy interface is too narrow for real research
**Where:** `strategy.zig:6` (`decide(ctx, price: f64, *const Portfolio, time: usize)`), `intent.zig` (`Hold | Buy qty | Sell qty`), `portfolio.zig:3-6` (cash + one position).
**Why it matters:** the strategy sees a single scalar price and its own portfolio. No history (each of `mean_reversion.zig` and `momentum.zig` re-implements an identical ring buffer, ~25 duplicated lines), no bars/volume, no second instrument, no notion of its own pending order (it cannot know that yesterday's buy is still unfilled), no clock/calendar, no target-position semantics (so "be flat" requires the strategy to know its position and emit the exact quantity), no limit orders. Because `Intent` is an absolute market quantity, position management logic leaks into every strategy.
**Concrete example:** `Momentum` and `MeanReversion` are the same 20 lines with the buy/sell branches swapped (`momentum.zig:30-34` vs `mean_reversion.zig:31-34`); neither can express "close position" without reading `portfolio_snap.position`, and both currently ignore it (`_ = portfolio_snap`).
**Professional:** a data window / feature API (history of bars per instrument), multi-asset universe, `TargetPosition`/`TargetWeight` intents with the engine computing deltas, order types and order-state callbacks, calendar-aware time, and a shared indicator library.

### Gap 9 — Hidden state leakage across "repeats" (bug), and the repeats are a smoke test posing as research
**Where:** `momentum.zig:47` (`.resetFn = null`), `strategy.zig:7` (reset is optional), `runner.zig:17-22` (each strategy run three times on the same engine), commit `60d065f` (added both in the same change).
**Why it matters:** the commit that "enforces determinism" made reset optional, gave the swept strategy no reset, and printed each result three times. Repeats 2 and 3 of every `Momentum` configuration start with a ring buffer full of prices from the *end* of the previous run and `count == lookback`, so they make decisions from stale data on ticks 0..lookback−1. The printed PnL happens to match only because those stale-data decisions are sells against flat inventory, which are rejected and hidden. The moment shorting or a different price path is introduced, the three rows diverge. Meanwhile 45 rows per table for 15 strategies inflates the apparent breadth of the study.
**Concrete example:** instrumented run, rejected sells for repeat 1 → repeats 2–3: `(5,0.03)`: 1 → 4; `(9,0.02)`: 2 → 9; `(9,0.03)`: 2 → 7; `(3,0.02)`: 0 → 2; OOS `(5,0.02)`: 2 → 4. Same label, same printed PnL, different execution history.
**Professional:** reset is mandatory (or strategies are constructed fresh per run), a determinism test lives in `zig build test` and asserts equality of full `BacktestResult`s, and the results table contains one row per configuration.

### Gap 10 — No provenance, no persistence, no tests
**Where:** `main.zig:40-43` (stderr only), `result.zig:15` (`strategy_name: []const u8` is the only identity), `runner.zig:27-30` (`SweepResult{label, result}`), `params.zig` (a `StrategyParams` union that is never imported and imports the module rather than the struct), no `test` blocks anywhere, `README.md` is two lines.
**Why it matters:** a result cannot be tied to the code version, data version, fee model, execution mode, or parameter values that produced it; it cannot be reloaded, compared across runs, or audited. The label `"Momentum(lb=5, th=0.03)"` is a formatted string (`main.zig:103`), not a structured config; two runs with different `ExecutionModel` settings would print identical labels. The sort is unstable (`std.sort.heap`), so equal-PnL rows are shuffled: in the OOS table `Momentum(lb=5, th=0.03)`'s three rows appear at positions 26, 31, and 33.
**Professional:** a run manifest (git SHA, config struct hash, data hash, seed, engine settings, timestamp), structured output (JSON/CSV/Parquet) of results *and* trade blotters *and* equity curves, a results store queryable across runs, and a regression-test suite pinning engine behaviour.

---

## 4. Methodological red flags in the current example run

What the current `zig build run` output could mislead a reader into believing:

1. **"45 strategies were tested."** There are 15; each is printed 3 times (`runner.zig:17-22`). 7 of the 12 momentum configurations are structurally inert: with `lb=1` the rolling average equals the current price, so `price < avg·(1−th)` can never be true; with `th=10.0` a ±1000% move is required. Only 5 of 12 trade in-sample and 3 of 12 out-of-sample.
2. **"Buy Every Tick is the best strategy, in and out of sample."** It is the most *long* strategy on a series that rises 10% then 2.75%. That is beta, not alpha; a full-capital buy-and-hold beats it 5–6×. No benchmark is shown.
3. **"Momentum(lb=5, th=0.03) is the best momentum configuration."** It made two buys, never exited, and its +$10.98 is an unrealised mark on 2 units. OOS it made zero trades. The next three configurations lose money OOS. Ranks 1–5 IS → {0, −1.01, −1.01, −0.02, 0} OOS is a textbook overfit signature, invisible because IS and OOS are printed as two separate sorted tables.
4. **"Gross 5.00, Net 10.98, Fees 2.00" (and "Gross 0.00, Net 6.99, Fees 1.00").** Net exceeds gross; costs appear negative. This is the `metrics.zig:37` mark-price bug, not a property of the strategy.
5. **"Cost % ≈ 1% is the strategy's cost drag."** It is `$1 / (~$100 × 1 unit)` and would read ~1% for any strategy trading one unit at any frequency. It says nothing about the strategy and is 20–100× a realistic institutional cost.
6. **"Turnover 2743.27".** That is gross dollars traded on a $10,000 book, i.e. a turnover ratio of 0.27 over the whole sample, extremely low. The column name suggests a rate.
7. **"Dumb lost 0.04%, trivial."** Its drawdown lasted 27 of 28 ticks. Max DD and DD duration are never shown, so a strategy that goes underwater at t=2 and stays there looks identical to one that recovers.
8. **"Momentum is a symmetric long/short signal."** Every short signal is rejected (`engine.zig:121`) and the rejection count is hidden; between 1 and 9 sell decisions per configuration were discarded. The evaluated strategy is long-only, pyramiding, no-exit.
9. **"Rows with equal labels are identical runs."** They are not for `Momentum` (rejected-sell counts differ 1→4, 2→9, 2→7), because `resetFn = null` at `momentum.zig:47`.
10. **"The results are statistically meaningful."** The largest |t| of any strategy's mean per-tick return is 1.64 on 27 observations, before any correction for 12 trials, and all strategies have exposure-weighted beta to a series with +0.37%/tick drift.
11. **"All decisions were executed."** In `NextTick` mode the intent from the last tick is silently dropped; `Buy Every Tick` executed 27 of 28 decisions; nothing reports dropped intents.
12. **Row order carries information.** The heap sort is unstable; among tied rows the order is arbitrary, and the 0.00 rows (inert configs) interleave with each other and with trading configs whose OOS PnL is exactly 0.00 by coincidence.

---

## 5. Comparison with established tools

| Capability | backtrader | zipline | vectorbt | NautilusTrader | LEAN | in-house firm engine | **tickforge** |
|---|---|---|---|---|---|---|---|
| Time-stamped OHLCV / calendar | yes | yes (bundles, calendars) | yes | yes (tick/L2) | yes | yes | **no** (index only) |
| Multi-asset universe | yes | yes | yes | yes | yes | yes | **no** |
| Order types (limit/stop/target) | yes | yes | limited | yes | yes | yes | **market qty only** |
| Position sizing / target weights | sizers | `order_target_percent` | `size_type` | yes | yes | yes | **no** |
| Shorting, leverage, margin | yes | yes | yes | yes | yes | yes | **no** |
| Slippage / impact / spread models | yes | volume-share | fixed + custom | yes (L2) | yes | proprietary | **fixed bps, qty ignored** |
| Analyzers / tearsheet | yes | pyfolio | quantstats | yes | yes | yes | **6 columns** |
| Walk-forward / CV / overfit stats | community | no | yes (splitters) | partial | optimisation | yes (PBO/DSR) | **fixed 70/30** |
| Persistence / run manifest | pickle | HDF5 | pickle/parquet | Parquet catalog | cloud | results DB | **stderr** |
| Tests | yes | yes | yes | yes | yes | yes | **none** |
| Deterministic, no look-ahead | yes | yes | yes | yes | yes | yes | **yes** |

---

## 6. Recommendations

### Quick wins (each < 1 day)

1. **Fix gross PnL mark** (`metrics.zig:37`): mark the residual position at `market.priceAt(market.len()-1)`; add a test asserting `gross − net == fees + slippage`.
2. **Add `reset` to `Momentum`** (mirror `mean_reversion.zig:41-45`) and make `resetFn` non-optional in `strategy.zig:7`, or construct strategies fresh per run.
3. **Move the 3× repeat out of `runBatch`** (`runner.zig:19-22`) into a `test "engine is deterministic"` that compares whole `BacktestResult`s; print one row per configuration.
4. **Print what is already computed**: return % (`net_pnl / initial_equity`), `max_drawdown`, executed/rejected buys/sells, final position, and add DD duration from `equity_curve`.
5. **Rename "Turnover" to "Gross traded $"** and add `turnover_ratio = total_gross_value / mean(equity_curve)`.
6. **Add a benchmark row** (full-capital buy-and-hold at the first tick) and print the market's own return in the section header.
7. **Join IS and OOS by configuration** into one table (`label | IS net% | OOS net% | IS Sharpe | OOS Sharpe | trades IS/OOS`) and sort by a return-based metric, or by label.
8. **Compute per-tick returns from `equity_curve`** and print tick-level Sharpe with its standard error (`1/sqrt(T)`), plus FIFO round-trip hit rate and profit factor from `trades`.
9. **Use a stable sort** (e.g. `std.sort.insertion` or `std.mem.sort` with a label tiebreaker) so row order is meaningful and deterministic by construction rather than by accident.
10. **Prune or flag inert sweep points** (`lb=1`, `th=10.0` at `main.zig:89-90`); print "no trades" instead of `0.00`.
11. **Report dropped/pending intents** at end of run and the count of rejected sells prominently (or emit a warning when > 0).
12. **Replace hard-coded prices** with either a CSV loader or a seeded GBM/bootstrap generator with ≥ 1,000 ticks and the seed printed; keep the 40-price array as a unit-test fixture only.
13. **Emit a run manifest** (git SHA, `BacktestConfig`, `ExecutionModel`, `ExecutionMode`, data length/hash, parameter struct rather than formatted label) and write results + trades + equity curve to JSON/CSV under `zig-out/`.
14. **Delete or fix `params.zig`** (unused; imports the module where it means the struct).

### Structural changes (multi-day to multi-week)

1. **Data model:** timestamps, calendar, bar type (OHLCV) or tick, instrument identifiers, multi-asset `Market`; data-quality checks; corporate-action handling when real data arrives.
2. **Position sizing and risk layer:** `TargetPosition` / `TargetWeight` intents with the engine computing order deltas; volatility targeting; capital allocation across strategies; leverage, margin, borrow; pre-trade risk limits.
3. **Execution:** quantity-aware cost model (spread + square-root impact vs ADV), latency, partial fills, limit/stop orders, order-state feedback to the strategy, short selling.
4. **Strategy API:** history/feature access instead of per-strategy ring buffers; shared indicator library; access to own open orders; warm-up carry-over across sample boundaries.
5. **Research framework:** walk-forward and purged CV as first-class runners; trial registry; deflated Sharpe / PBO; bootstrap confidence intervals; standard tearsheet output.
6. **Persistence and reproducibility:** results store (Parquet/SQLite) keyed by config hash; seeded RNG for synthetic data; regression tests pinning engine numerics; CI running `zig build test`.

---

## 7. Evidence and reproduction

- Baseline output: `cd /home/user/tickforge && zig build run` (two runs diffed identical).
- Instrumented copy (exposes rejected/executed counts, final position, DD, trade lists; `src/` untouched):
  `/tmp/claude-0/-home-user-tickforge/0fca6df9-ace1-5822-bfb8-76d2e34ac9c4/scratchpad/audit-quant/tf/` → output in `.../audit-quant/instrumented.txt`.
- Independent Python re-implementation and professional-metric recomputation:
  `/tmp/claude-0/-home-user-tickforge/0fca6df9-ace1-5822-bfb8-76d2e34ac9c4/scratchpad/audit-quant/recompute.py` → `.../audit-quant/recompute.txt`. It reproduces every Net, tool-Gross and Fees cell of the Zig output for all 15 strategies in both samples, and additionally reports the corrected gross, per-tick Sharpe and t-stat, DD duration, exposure, turnover ratio, FIFO hit rate / profit factor, beta to the market, and the full-capital buy-and-hold benchmark.
- Key file:line references used above: `main.zig:16-24, 35, 46-51, 54, 58-62, 89-90, 103`; `runner.zig:16-22`; `engine.zig:37-43, 51-60, 61, 66-68, 75-84, 88-90, 109-112, 121-124`; `execution.zig:8, 12-13`; `metrics.zig:20-40 (37)`; `market.zig:5`; `strategy.zig:6-7`; `intent.zig:1-5`; `momentum.zig:20-34, 47`; `mean_reversion.zig:31-34, 41-45`; `result.zig:6-9, 13, 15-16`; `config.zig:1-3`; `params.zig`.
