# tickforge — Correctness Audit (numerical & logical)

Scope: every file under `src/` (≈720 lines) at commit `60d065f`, plus `build.zig`.
Toolchain: Zig 0.14.1. Every "Confirmed" item below was reproduced by running an
instrumented copy of the repo (scratch copy under
`scratchpad/audit-correctness/repo`, tests in `src/audit_tests.zig`, panic probes in
`src/audit_empty.zig`, `src/audit_lb0.zig`, compile probe `src/audit_reset.zig`).
Nothing under `src/` or `build.zig` was modified.

Baseline: `zig build run` prints 45 rows per table (15 strategies × 3 repeated runs);
Debug and ReleaseFast output are byte-identical. `zig build test` runs 0 tests.

---

## 1. Executive summary (severity-ranked)

1. **Critical — `gross_pnl` marks the residual position at the price of the *last trade tick*, not the last market tick** (`metrics.zig:37`). This is the root cause of `Momentum(lb=5, th=0.03)` showing Gross 5.00 < Net 10.98 with Fees 2.00. Correct gross is 13.00; `13.00 − 10.9793 = 2.0207 = fees (2.00) + slippage (0.0207)` exactly. `gross_pnl` and `net_pnl` are therefore not mark-to-market consistent; the identity `gross − net = fees + slippage` fails whenever the final position is non-zero and the last fill is not on the last tick (2 of 30 sweep runs on this data).
2. **High — `Momentum` has `resetFn = null`, so its ring buffer (`prices/count/head`) survives across `engine.run()` calls and across markets.** 6 of 15 sweep strategies are not run-to-run deterministic (e.g. `rejected_sells` 1→4→4). Reusing one instance in-sample→out-of-sample changes the OOS result: `Momentum(lb=9, th=0.02)` fresh = net −1.01, 1 trade; reused = net −7.03, 3 trades. `main.zig` dodges this only because it happens to call `buildStrategies` twice.
3. **High — the runner's "run every strategy 3 times" is not a determinism check**: results are never compared, only printed (45 rows), and the fields that differ (`rejected_sells`) are not printed, so finding #2 is invisible in the output.
4. **Medium — engine robustness**: an empty market panics (Debug: index OOB at `synthetic.zig:10`; ReleaseFast: SIGSEGV, exit 139) via `priceAt(0)` and `self.time - 1`; `Momentum(lookback=0)` likewise (OOB / segfault). Neither is validated.
5. **Medium — execution model gaps**: sell path deducts the commission without a cash check (cash goes to −0.4901 in a reproduction); non-positive/non-finite quantities are not rejected (`Buy(-1)` and `Sell(-1)` both *execute* and invert the trade); the two `std.debug.assert`s are tautological given the guards and vanish (become UB) in ReleaseFast, so they protect nothing.
6. **Medium — half the Momentum sweep is degenerate**: `lookback=1` can never signal (average == current price) and `threshold=10.0` means 1000%; 6 of 12 parameter combinations emit zero signals on all 40 ticks. The moving average also *includes* the current price, which dilutes the signal.
7. **Medium — dead code that is wrong**: `Strategy.reset()` does not compile if ever referenced (`cannot call optional type`); `params.zig` imports the *file* `momentum.zig` as the union payload type (a zero-size namespace struct, `!= MomentumParams`). Both are unreferenced so lazy analysis hides them.
8. **Low — reporting/abstraction**: the final tick's intent in NextTick mode is silently dropped with no counter; `Market.prices` is a never-read duplicate of the vtable; unstable heap sort interleaves tied rows; "Cost %" excludes slippage and its denominator (`gross_value`) *includes* slippage — "gross" means two different things in `metrics.zig`; `start_time` is a hard-coded 0 that would underflow if changed.

What is *not* broken: the NextTick pipeline genuinely delays fills by one tick with no look-ahead, `net_pnl`, fee and turnover totals, drawdown arithmetic, buy-side rejection, MeanReversion's reset and the in-sample/out-of-sample split are all correct (see §4).

---

## 2. Findings table

| ID | Sev | Location | Description | Status |
|----|-----|----------|-------------|--------|
| C-01 | Critical | `src/engine/metrics.zig:37` | `calcGrossPnL` marks residual position at `priceAt(last_trade.time)` instead of `priceAt(len-1)` → gross < net; gross/net not MTM-consistent | Confirmed |
| H-02 | High | `src/strategy/momentum.zig:47` | `resetFn = null`: ring-buffer state leaks across `run()` calls and IS→OOS | Confirmed |
| H-03 | High | `src/research/runner.zig:17-22` | Triple run never compared; prints 3 rows/strategy; hides H-02 | Confirmed |
| M-04 | Medium | `src/engine/metrics.zig:21-23` | `gross_pnl` ignores non-zero initial position (starts `gross_position=0`, returns 0 with no trades) while `net_pnl` includes it | Confirmed |
| M-05 | Medium | `src/engine/engine.zig:44,48,88` | Empty market: `priceAt(0)` OOB panic (Debug) / SIGSEGV (ReleaseFast); `self.time - 1` underflow | Confirmed |
| M-06 | Medium | `src/engine/engine.zig:106-131` | Sell fee can drive cash negative; negative/zero/NaN quantities accepted; asserts tautological and UB-in-ReleaseFast | Confirmed (NaN: Suspected) |
| M-07 | Medium | `src/strategy/momentum.zig:17-34`, `src/main.zig:89-90` | `lookback=1` and `threshold=10.0` are no-ops (6/12 sweep configs); `lookback=0` panics/segfaults; avg includes current price | Confirmed |
| M-08 | Medium | `src/strategy/strategy.zig:15`, `src/strategy/params.zig:1` | `Strategy.reset` fails to compile when referenced; `StrategyParams.Momentum` payload is the file namespace, not `MomentumParams` | Confirmed |
| L-09 | Low | `src/engine/engine.zig:49-86` | Final tick's NextTick intent silently dropped; no `dropped_intents` metric | Confirmed |
| L-10 | Low | `src/engine/engine.zig:36,48,76,90` | `start_time` hard-coded 0; loop ignores it (underflow if changed); `end_time` exclusive vs `start_time` inclusive; drawdown sign convention (negative fraction) undocumented and never printed | Suspected (design) |
| L-11 | Low | `src/engine/market.zig:5`, `src/market/synthetic.zig:25` | `Market.prices` snapshot duplicates vtable, never read, can desync | Confirmed |
| L-12 | Low | `src/main.zig:51,58-62,103`, `src/engine/engine.zig:116,129` | Unstable heap sort interleaves tied rows; "Cost %" excludes slippage while `gross_value` (denominator) includes it; `gross_value` uses exec price but `gross_pnl` uses market price; Mean Reversion/Dumb labels lack params; `{s:14}` narrower than labels | Confirmed |
| L-13 | Low | `src/engine/execution.zig:11-13` | `quantity` ignored: flat $1 commission regardless of size (0.005 units pays the same as 1 unit) | Confirmed |
| L-14 | Low | `build.zig:64-66`, `src/main.zig` | `zig build test` runs zero tests; no file is reachable from a `test` block | Confirmed |

---

## 3. Detailed findings

### C-01 — `calcGrossPnL` marks the open position at the last *trade* tick (Critical, Confirmed)

`src/engine/metrics.zig:20-40`:

```zig
pub fn calcGrossPnL(initial_equity: f64, trades: []const Trade, market: *const Market) f64 {
    var gross_cash = initial_equity;
    var gross_position: f64 = 0;
    if (trades.len == 0) return 0;
    for (trades) |trade| {
        const market_price = market.priceAt(trade.time);
        ...
    }
    const final_price = market.priceAt(trades[(trades.len - 1)].time);   // <-- BUG
    const gross_equity = gross_cash + gross_position * final_price;
    return gross_equity - initial_equity;
}
```

`net_pnl` (engine.zig:88-90) marks `final_position` at `priceAt(len - 1)`. `gross_pnl` marks it at
the price of the tick on which the *last fill* happened. Any price move after the last fill is
counted in net but not in gross, so gross can be smaller than net despite non-negative costs.

**Reproduction** (in-sample data, 28 ticks, last price 110, `Momentum(lb=5, th=0.03)`):

```
trade t=21 Buy exec=101.0101 market=101   fee=1
trade t=25 Buy exec=106.0106 market=106   fee=1
final_position=2  final_cash=9790.9793  final_equity=10010.9793
engine gross_pnl = (-101 -106) + 2*106 =  5.00     <-- marks at p[25]=106
correct gross    = (-101 -106) + 2*110 = 13.00     <-- marks at p[27]=110
net_pnl          = 10.9793
13.00 - 10.9793  = 2.0207 = fees 2.00 + slippage 0.0207   (identity holds only with the fix)
```

Second instance in the same table: `Momentum(lb=3, th=0.02)` Gross 0.00 vs Net 6.99 (correct gross 8.00).
Over all 30 sweep runs (15 strategies × IS/OOS) the identity `gross − net == fees + slippage`
holds with the fixed marking in 30/30 and with the shipped code in 28/30. The bug is masked
whenever the final position is zero (Dumb, Mean Reversion here) or the last fill lands on the
last tick (Buy Every Tick).

**Fix** (also folds in M-04, see below):

```diff
--- a/src/engine/metrics.zig
+++ b/src/engine/metrics.zig
 const Market = @import("market.zig").Market;
 const Trade = @import("trade.zig").Trade;
+const Portfolio = @import("portfolio.zig").Portfolio;

-pub fn calcGrossPnL(initial_equity: f64, trades: []const Trade, market: *const Market) f64 {
-    var gross_cash = initial_equity;
-    var gross_position: f64 = 0;
-    if (trades.len == 0) return 0;
+/// PnL at market prices (no slippage, no commission), marked at the last market tick.
+/// Invariant: gross_pnl - net_pnl == total_fees + total_slippage.
+pub fn calcGrossPnL(initial: Portfolio, trades: []const Trade, market: *const Market) f64 {
+    const n = market.len();
+    if (n == 0) return 0;
+    var gross_cash = initial.cash;
+    var gross_position = initial.position;
+    const initial_equity = initial.cash + initial.position * market.priceAt(0);
     for (trades) |trade| {
         const market_price = market.priceAt(trade.time);
         switch (trade.side) {
             .Buy => {
                 gross_cash -= market_price * trade.quantity;
                 gross_position += trade.quantity;
             },
             .Sell => {
                 gross_cash += market_price * trade.quantity;
                 gross_position -= trade.quantity;
             },
         }
     }
-    const final_price = market.priceAt(trades[(trades.len - 1)].time);
+    const final_price = market.priceAt(n - 1);
     const gross_equity = gross_cash + gross_position * final_price;
     return gross_equity - initial_equity;
 }
--- a/src/engine/engine.zig
+++ b/src/engine/engine.zig
-            .gross_pnl = Metrics.calcGrossPnL(initial_equity, tradesAsSlice, &self.market),
+            .gross_pnl = Metrics.calcGrossPnL(self.initial_portfolio, tradesAsSlice, &self.market),
```

### H-02 — `Momentum` never resets; state leaks across runs and datasets (High, Confirmed)

`src/strategy/momentum.zig:46-48`:

```zig
pub fn toStrategy(self: *Momentum) Strategy {
    return Strategy{ .ctx = self, .decideFn = momentumDecideAdapter, .name = "Momentum", .resetFn = null };
}
```

`Engine.run` (engine.zig:41-43) only calls `resetFn` if present. `MeanReversion` implements one
(`mean_reversion.zig:41-45`); `Momentum` — the only other stateful strategy — does not. After the
first run the ring buffer is full (`count == lookback`), so the second run starts emitting signals
from tick 0 using the *previous dataset's* tail prices.

**Reproduction 1 — three consecutive `engine.run()` calls, in-sample (what `runner.zig` does):**

```
Momentum(lb=3, th=0.02): run0 rej_sells=0 | run1 rej_sells=2 | run2 rej_sells=2
Momentum(lb=5, th=0.02): run0 rej_sells=1 | run1 rej_sells=4 | run2 rej_sells=4
Momentum(lb=5, th=0.03): run0 rej_sells=1 | run1 rej_sells=4 | run2 rej_sells=4
Momentum(lb=9, th=0.02): run0 rej_sells=2 | run1 rej_sells=9 | run2 rej_sells=9
Momentum(lb=9, th=0.03): run0 rej_sells=2 | run1 rej_sells=7 | run2 rej_sells=7
6 of 15 strategies are NOT run-to-run deterministic   (all other fields equal here only because
the leaked signals were Sells with zero position, i.e. rejected — this is luck, not design)
```

**Reproduction 2 — one instance reused in-sample → out-of-sample, `Momentum(lb=9, th=0.02)`:**

```
fresh instance on OOS : net = -1.01, 1 trade  (Buy t=11 @112.0112)
reused after IS on OOS: net = -7.03, 3 trades (Buy t=1 @107.0107, Sell t=5 @102.9897, Buy t=11 @112.0112)
```

The reused instance trades at t=1 with a 9-tick lookback — an impossibility for a strategy that
has only seen 2 OOS prices. `MeanReversion` under the same experiment is identical fresh vs reused.
`main.zig` avoids the leak only because it constructs a second set of strategies for the test split.

**Fix:**

```diff
--- a/src/strategy/momentum.zig
+++ b/src/strategy/momentum.zig
@@ pub const Momentum = struct {
         _ = portfolio_snap;
         return Intent.Hold;
     }
+
+    pub fn reset(self: *Momentum) void {
+        self.count = 0;
+        self.head = 0;
+        @memset(self.prices, 0);
+    }
 };
@@
+pub fn momentumResetAdapter(ctx: *anyopaque) void {
+    const momentum: *Momentum = @ptrCast(@alignCast(ctx));
+    momentum.reset();
+}
+
 pub fn toStrategy(self: *Momentum) Strategy {
-    return Strategy{ .ctx = self, .decideFn = momentumDecideAdapter, .name = "Momentum", .resetFn = null };
+    return Strategy{ .ctx = self, .decideFn = momentumDecideAdapter, .name = "Momentum", .resetFn = momentumResetAdapter };
 }
```

Structural recommendation: make `resetFn` non-optional in `Strategy` so a stateful strategy cannot
forget it; stateless strategies pass a no-op.

### H-03 — Runner's triple run is not a check (High, Confirmed)

`src/research/runner.zig:16-22` runs `engine.run` three times and appends three `SweepResult`s with the same
label. Nothing compares them; `printResults` sorts all 45 rows by `net_pnl`. Since `rejected_*`
is never printed, H-02 is invisible in the report even though it is present in the data.
`runBatch` on 15 strategies returns 45 rows (confirmed).

**Fix:**

```diff
--- a/src/research/runner.zig
+++ b/src/research/runner.zig
+const verify_determinism = true;
+
 pub fn runBatch(allocator: std.mem.Allocator, market: Market, config: BacktestConfig, strategies: []Strategy) ![]SweepResult {
     var results = std.ArrayList(SweepResult).init(allocator);
     for (strategies) |strategy| {
         const portfolio = Portfolio.init(config.starting_cash);
         var engine = Engine.init(market, portfolio, strategy, ExecutionMode.NextTick, ExecutionModel.initDefault());
         const result = try engine.run(allocator);
+        if (verify_determinism) {
+            const again = try engine.run(allocator);
+            if (!resultsEqual(result, again)) return error.NonDeterministicStrategy;
+        }
         try results.append(SweepResult{ .label = strategy.name, .result = result });
-        const result1 = try engine.run(allocator);
-        try results.append(SweepResult{ .label = strategy.name, .result = result1 });
-        const result2 = try engine.run(allocator);
-        try results.append(SweepResult{ .label = strategy.name, .result = result2 });
     }
     return results.toOwnedSlice();
 }
+
+fn resultsEqual(a: BacktestResult, b: BacktestResult) bool {
+    if (a.trades.len != b.trades.len) return false;
+    for (a.trades, b.trades) |x, y| {
+        if (x.time != y.time or x.side != y.side or x.price != y.price or x.quantity != y.quantity) return false;
+    }
+    return a.final_cash == b.final_cash and a.final_position == b.final_position and
+        a.rejected_buys == b.rejected_buys and a.rejected_sells == b.rejected_sells and
+        a.net_pnl == b.net_pnl and a.gross_pnl == b.gross_pnl and a.max_drawdown == b.max_drawdown;
+}
```

### M-04 — `gross_pnl` ignores a non-zero initial position (Medium, Confirmed)

`metrics.zig:21-23` seeds `gross_cash = initial_equity` and `gross_position = 0`, and returns 0 when
there are no trades. `net_pnl` marks the real position. `Engine.init` accepts any
`initial_portfolio`, so this is reachable.

Reproduction: `Portfolio{.cash=1000, .position=1}`, prices `[100, 110]`, strategy holds:
`net_pnl = 10`, `gross_pnl = 0`. Fixed by the C-01 diff (seed from `initial_portfolio`).

### M-05 — Empty market panics / segfaults (Medium, Confirmed)

`engine.zig:44` calls `priceAt(0)` before the loop; `engine.zig:88` computes `priceAt(self.time - 1)`
with `self.time == 0` after the loop. `synthetic.zig:10` indexes `prices[t]` unchecked.

```
Debug:       thread panic: index out of bounds: index 0, len 0   (synthetic.zig:10)   exit 134
ReleaseFast: exit 139 (SIGSEGV)
```

**Fix:**

```diff
--- a/src/engine/engine.zig
+++ b/src/engine/engine.zig
     pub fn run(self: *Engine, allocator: std.mem.Allocator) !BacktestResult {
+        if (self.market.len() == 0) return error.EmptyMarket;
```

### M-06 — Execution model: sell-side cash check missing, quantity unvalidated, asserts inert (Medium, Confirmed)

`engine.zig:106-131`:

```zig
.Buy => |qty| {
    const total_cost = execution_result.exec_price * qty + execution_result.fee;
    if (total_cost > self.portfolio.cash) { rejected_buys.* += 1; return; }
    ...
    std.debug.assert(self.portfolio.cash >= 0);
},
.Sell => |qty| {
    if (self.portfolio.position < qty) { rejected_sells.* += 1; return; }
    self.portfolio.cash += execution_result.exec_price * qty;
    self.portfolio.cash -= execution_result.fee;        // <-- no check that proceeds+cash cover the fee
    ...
    std.debug.assert(self.portfolio.position >= 0);
},
```

Reproductions (SameTick, flat 100 prices, default $1 commission / 1 bp slippage):

* Cash 101.02; `Buy 1` (cost 100.01 + 1) → cash 0.0100; `Sell 0.005` (proceeds 0.49995 − fee 1)
  → **final_cash = −0.4901, rejected_sells = 0**. The buy-side invariant "cash ≥ 0" is not enforced on the sell side.
* Cash 10; `Buy −1` then `Sell −1`: **both execute** (`executed_buys=1, executed_sells=1`), final cash 8.02,
  position 0 — a negative "buy" credits cash and shorts; the checks `total_cost > cash` and
  `position < qty` pass trivially for negative `qty`. `qty = 0` also "executes" and pays commission.
* Suspected (not run): `qty = NaN` passes both comparisons (`NaN > x` is false) and poisons cash and every metric; `std.sort.heap` with NaN keys is then unspecified.
* The asserts on lines 117 and 130 are implied by the guards two lines earlier and so never fire; in
  ReleaseFast `std.debug.assert` lowers to `unreachable`, i.e. UB rather than a check. They give no protection.

Partial fills are not modelled (all-or-nothing rejection) — acceptable, but `rejected_*` is not printed.

**Fix:**

```diff
--- a/src/engine/engine.zig
+++ b/src/engine/engine.zig
+fn validQty(qty: f64) bool {
+    return std.math.isFinite(qty) and qty > 0;
+}
@@ fn execute(
             .Buy => |qty| {
+                if (!validQty(qty)) { rejected_buys.* += 1; return; }
                 const execution_result = self.execution_model.compute(.Buy, price, qty);
@@
             .Sell => |qty| {
+                if (!validQty(qty)) { rejected_sells.* += 1; return; }
                 const execution_result = self.execution_model.compute(.Sell, price, qty);
-                if (self.portfolio.position < qty) {
+                const proceeds = execution_result.exec_price * qty;
+                if (self.portfolio.position < qty or self.portfolio.cash + proceeds < execution_result.fee) {
                     rejected_sells.* += 1;
                     return;
                 }
-                self.portfolio.cash += execution_result.exec_price * qty;
+                self.portfolio.cash += proceeds;
                 self.portfolio.cash -= execution_result.fee;
```

### M-07 — Momentum ring buffer: degenerate parameters, no validation (Medium, Confirmed)

`momentum.zig:17-34`: the current price is written into the buffer *before* the average is taken,
so `avg` always contains `current_price`.

* `lookback = 1`: `avg == current_price`, so `current < avg*(1-th)` and `current > avg*(1+th)` are
  both false for any `th > 0`. Confirmed: `Momentum(lb=1, th=0.0001)` on all 40 ticks → 0 executed, 0 rejected.
* `threshold = 10.0` means ±1000 %: `Momentum(lb=9, th=10.0)` → 0 executed, 0 rejected.
* Net: 6 of the 12 sweep configurations (`lb=1 ×3`, `th=10 ×4`, overlap 1) are no-ops; they show as
  the block of all-zero rows in the report.
* `lookback = 0`: `alloc(0)` then `prices[0]` → Debug OOB panic at `momentum.zig:18` (exit 134),
  ReleaseFast SIGSEGV (exit 139). (`% 0` would also trap.)
* Including the current price in the mean dilutes the signal: `Momentum(lb=3, th=0)` on
  `[100,100,200,200]` first signals at t=2 (as expected for warm-up), but the trigger condition is
  effectively `c > (S_prev + c)/L · (1+th)`, i.e. `c·(L−1−th) > S_prev·(1+th)` — a stricter test than the
  intended `c > mean(previous L)·(1+th)`. Same structure in `mean_reversion.zig:19-30`.

**Fix (validation + exclude current price from the mean):**

```diff
--- a/src/strategy/momentum.zig
+++ b/src/strategy/momentum.zig
     pub fn init(allocator: std.mem.Allocator, params: MomentumParams) !Momentum {
+        if (params.lookback == 0) return error.InvalidLookback;
+        if (!(params.threshold > 0.0 and params.threshold < 1.0)) return error.InvalidThreshold;
         const prices = try allocator.alloc(f64, params.lookback);
@@ pub fn decide(...)
-        self.prices[self.head] = current_price;
-        self.head = (self.head + 1) % self.params.lookback;
-        if (self.count < self.params.lookback) {
-            self.count += 1;
-        }
-        if (self.count < self.params.lookback) {
-            return Intent.Hold;
-        }
-        var sum: f64 = 0;
-        for (self.prices) |p| sum += p;
-        const len_as_float: f64 = @floatFromInt(self.prices.len);
-        const avg = sum / len_as_float;
+        // mean of the previous `lookback` prices (excludes current_price)
+        const warm = self.count >= self.params.lookback;
+        var sum: f64 = 0;
+        for (self.prices) |p| sum += p;
+        const avg = sum / @as(f64, @floatFromInt(self.prices.len));
+        self.prices[self.head] = current_price;
+        self.head = (self.head + 1) % self.params.lookback;
+        if (self.count < self.params.lookback) self.count += 1;
+        if (!warm) return Intent.Hold;
```

and in `main.zig:89-90` use a meaningful grid, e.g. `lookbacks = {3, 5, 9}`, `thresholds = {0.01, 0.02, 0.03}`.

### M-08 — `Strategy.reset` does not compile; `params.zig` imports a file as a type (Medium, Confirmed)

`strategy.zig:14-16`:

```zig
pub fn reset(self: Strategy) void {
    return self.resetFn(self.ctx);   // resetFn is ?*const fn
}
```

Compile probe (any caller of `s.reset()`):

```
src/strategy/strategy.zig:15:20: error: cannot call optional type '?*const fn (*anyopaque) void'
```

It only builds today because nothing calls it (Zig analyses lazily); `engine.zig:41-43` re-implements the null check inline.

`params.zig:1`: `const MomentumParams = @import("momentum.zig");` binds the *file* (a struct with
declarations and no fields). Confirmed: `std.meta.FieldType(StrategyParams, .Momentum)` is
`strategy.momentum`, `@sizeOf == 0`, `!= Momentum.MomentumParams`; `StrategyParams{ .Momentum = .{} }`
compiles and can carry no parameters. Nothing imports `params.zig`.

**Fix:**

```diff
--- a/src/strategy/strategy.zig
+++ b/src/strategy/strategy.zig
     pub fn reset(self: Strategy) void {
-        return self.resetFn(self.ctx);
+        if (self.resetFn) |f| f(self.ctx);
     }
--- a/src/engine/engine.zig
+++ b/src/engine/engine.zig
-        if (self.strategy.resetFn) |reset| {
-            reset(self.strategy.ctx);
-        }
+        self.strategy.reset();
--- a/src/strategy/params.zig
+++ b/src/strategy/params.zig
-const MomentumParams = @import("momentum.zig");
+const MomentumParams = @import("momentum.zig").MomentumParams;
```

### L-09 — Final-tick intent silently dropped in NextTick mode (Low, Confirmed)

`engine.zig:66-68` parks the last decision in `pending_intent`; the loop ends and the run-start
reset (line 39) discards it. `BuyEveryTick` over 28 ticks → `executed_buys = 27`, nothing records
the 28th. This is the *correct* no-look-ahead behaviour, but a strategy that fires on the last
bar looks identical to one that never fired.

**Fix:** add `dropped_intents: usize` to `BacktestResult`; after the loop:
`if (self.pending_intent) |pi| { if (pi != .Hold) dropped += 1; }`.

### L-10 — `start_time` is decorative; conventions undocumented (Low, Suspected)

`start_time` is a `const 0` (engine.zig:36) used in `alloc(len - start_time)` and
`equity_curve[self.time - start_time]`, but the loop always starts at `self.time = 0`, so any
non-zero value would underflow. `end_time = self.time` is exclusive (`== len`) while `start_time`
is inclusive. `max_drawdown` is a negative fraction of the running peak (verified: prices
`[100,110,99,120]`, buy 1 at t0 → `−0.0010989…`, exact against hand calculation) but the sign
convention is documented nowhere and it is not printed. Remove `start_time` or make the loop honour it.

### L-11 — `Market.prices` duplicate (Low, Confirmed)

`market.zig:5` carries a `prices: []const f64` snapshot copied in `synthetic.zig:25`; no code reads it
(grep confirms). A market whose `prices` slice is later reassigned would leave `Market.prices` stale.
Delete the field.

### L-12 — Reporting inconsistencies (Low, Confirmed)

* `main.zig:51`: `std.sort.heap` is unstable; the 27 all-zero rows interleave labels arbitrarily
  (visible in the baseline output). Use `std.mem.sort` (stable block sort) with a secondary key on label.
* `main.zig:58-62`: `Cost % = total_fees / total_gross_value`. `total_gross_value` sums
  `exec_price * qty` (engine.zig:116,129), which *includes* slippage, while the numerator excludes
  slippage. Meanwhile `calcGrossPnL` uses *market* price. "Gross" has two definitions in the same
  module. Suggest `gross_value = market_price * qty` and `total_slippage` as a separate metric,
  `Cost % = (fees + slippage) / turnover`.
* Labels: "Mean Reversion" (window 3, 1 %) and "Dumb" carry no parameters; Momentum labels are 23
  chars but the column is `{s:14}`.

### L-13 — Commission ignores quantity (Low, Confirmed)

`execution.zig:11-13` discards `quantity`; the fee is a flat `commission_per_trade` (1.0). Selling
0.005 units costs the same $1 as selling 1 unit (see M-06). Fine as a model, but the signature
implies per-quantity pricing; either document or add `commission_per_unit`.

### L-14 — Zero tests are compiled (Low, Confirmed)

`build.zig` runs tests of `exe_mod` (root `main.zig`), which has no `test` block and references no
test-bearing file; `zig build test` reports success with 0 tests. Add
`test { std.testing.refAllDeclsRecursive(@This()); }` (or explicit `_ = @import(...)`) to `main.zig`.

---

## 4. What is correct and well done

* **No look-ahead in NextTick mode.** A decision at tick *t* is filled at `p[t+1]` (+slippage):
  `Dumb` decides Buy at t=0 and fills at t=1 @ 101.0101, Sell at t=2 @ 98.9901; net
  `−4.02 = −2.00 gross − 2.00 fees − 0.02 slippage` matches the printed row exactly. The
  strategy never sees its own fill price. SameTick is an explicit, opt-in mode.
* **Engine re-run hygiene** (commit `60d065f`): `run()` resets `time`, `portfolio`,
  `pending_intent`, `pending_decision_time` and calls `resetFn` — the engine side of determinism is right; only Momentum's missing reset breaks it.
* **Drawdown arithmetic** is correct: peak seeded with initial equity (so entry costs register as a
  drawdown), fractional, computed from post-execution equity at each tick; matches a hand
  computation to 1e-12.
* **`net_pnl`, `total_fees`, `total_gross_value`** are computed correctly and consistently with
  the trade log; `final_equity` marks at the last tick.
* **Buy-side rejection** includes the fee, so cash never goes negative on a buy; sells check
  position; all-or-nothing fills are simple and honest.
* **Slippage/commission arithmetic** is right (1 bp → 100 → 100.01 / 99.99).
* **MeanReversion.reset** fully clears state; reused-instance IS→OOS is identical to a fresh instance.
* **IS/OOS split** (`split = 28`, `prices[0..28]` / `prices[28..]`) is correct, strategies are rebuilt per split, and Debug vs ReleaseFast output is identical.
* The vtable-style `Strategy`/`Market` abstraction and arena allocation keep the code small and easy to audit.

---

## 5. Proposed regression tests

Wire-up: add `test { _ = @import("engine/engine.zig"); _ = @import("engine/metrics.zig"); _ = @import("strategy/momentum.zig"); _ = @import("strategy/params.zig"); ... }` to `main.zig` so `zig build test` compiles them (L-14).

| Test name | Asserts |
|-----------|---------|
| `metrics.gross_marks_last_market_tick` | Scripted Buy 1 at t=1 on `[100,100,120]`: `gross_pnl == 20` (not 0). |
| `metrics.gross_net_identity_all_sweep_strategies` | For every sweep strategy on IS and OOS: `gross_pnl − net_pnl ≈ total_fees + Σ|exec−market|·qty` (1e-9). |
| `metrics.gross_includes_initial_position` | `Portfolio{cash=1000,position=1}`, `[100,110]`, no trades: `gross_pnl == net_pnl == 10`. |
| `metrics.gross_zero_when_flat_and_no_trades` | Position 0, no trades: `gross_pnl == net_pnl == 0`. |
| `engine.rerun_is_bitwise_identical` | For every strategy, 3× `engine.run()` compares *all* fields incl. `rejected_*` and the trade list. |
| `momentum.reset_clears_ring_buffer` | Momentum reused IS→OOS equals a fresh instance on OOS (trades, PnL, rejections). |
| `strategy.reset_is_noop_when_null` | `Strategy.reset()` on `resetFn = null` compiles and returns. |
| `engine.nexttick_fills_at_next_tick_price` | `trade.time == decision_time + 1`, `trade.price == p[t+1]·(1+bps/1e4)`. |
| `engine.sametick_fills_at_same_tick_price` | `trade.time == 0`, `trade.price == p[0]·(1+bps/1e4)`. |
| `engine.final_tick_intent_is_counted` | BuyEveryTick over n ticks: `executed_buys == n−1`, `dropped_intents == 1`. |
| `engine.empty_market_returns_error` | `run()` on 0 prices → `error.EmptyMarket`, no panic in Debug or ReleaseFast. |
| `execution.sell_fee_cannot_drive_cash_negative` | Cash 0.01, position 1, `Sell 0.005`: `rejected_sells == 1`, `cash == 0.01`. |
| `execution.rejects_nonpositive_or_nonfinite_qty` | `Buy −1`, `Sell 0`, `Buy NaN`, `Buy inf` → all rejected, portfolio unchanged. |
| `execution.buy_rejected_when_cost_incl_fee_exceeds_cash` | Cash 101.00, `Buy 1 @100`: rejected (cost 101.01). |
| `momentum.init_rejects_lookback_zero` | `init(lookback=0)` → `error.InvalidLookback`. |
| `momentum.init_rejects_threshold_out_of_range` | `threshold ∈ {0, 10.0, −0.1}` → `error.InvalidThreshold`. |
| `momentum.lookback_one_can_signal` | With the "exclude current price" fix, `lb=1, th=0.01` on `[100,102]` emits a Buy. |
| `momentum.warmup_holds_until_lookback_prices_seen` | First non-Hold intent at `t == lookback`. |
| `mean_reversion.same_warmup_and_reset_semantics` | Mirror of the two tests above for MeanReversion. |
| `engine.drawdown_hand_computed` | `[100,110,99,120]`, buy 1 at t0: `max_drawdown ≈ −0.0010989` (1e-12); monotonic up → 0. |
| `engine.equity_curve_len_and_bounds` | `equity_curve.len == market.len()`, `start_time == 0`, `end_time == len`. |
| `params.momentum_payload_is_momentum_params` | `std.meta.FieldType(StrategyParams,.Momentum) == MomentumParams`. |
| `runner.one_row_per_strategy` | `runBatch(15 strategies).len == 15` and `error.NonDeterministicStrategy` on a stateful strategy without reset. |
| `report.sort_is_stable_on_ties` | Rows with equal `net_pnl` keep input (label) order. |
| `metrics.cost_pct_includes_slippage` | If adopted: `Cost % == (fees + slippage) / Σ market_price·qty`. |
