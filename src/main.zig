const std = @import("std");
const SyntheticMarket = @import("market/synthetic.zig");
const Portfolio = @import("engine/portfolio.zig").Portfolio;
const Strategy = @import("strategy/strategy.zig").Strategy;
const Dumb = @import("strategy/dumb.zig");
const Engine = @import("engine/engine.zig").Engine;
const BacktestResult = @import("result.zig").BacktestResult;
const BacktestConfig = @import("backtest/config.zig").BacktestConfig;
const BuyEveryTick = @import("strategy/buy_every_tick.zig");
const MeanReversion = @import("strategy/mean_reversion.zig");
const Momentum = @import("strategy/momentum.zig");
const Runner = @import("research/runner.zig");
const SweepTestResult = @import("research/runner.zig").SweepResult;

pub fn main() !void {
    var prices = [_]f64{
        100, 101, 99,  102, 100, 98,  99,  101,
        103, 102, 104, 103, 101, 100, 98,  99,
        97,  96,  98,  100, 102, 101, 103, 105,
        107, 106, 108, 110, 109, 107, 108, 106,
        104, 103, 105, 107, 106, 108, 110, 112,
    };
    const n = prices.len;
    const split: usize = (n * 70) / 100;
    const train_prices = prices[0..split];
    const test_prices = prices[split..];

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var synthetic_train_market = SyntheticMarket.SyntheticMarket{ .prices = train_prices[0..] };
    const train_market = SyntheticMarket.toMarket(&synthetic_train_market);
    var synthetic_test_market = SyntheticMarket.SyntheticMarket{ .prices = test_prices[0..] };
    const test_market = SyntheticMarket.toMarket(&synthetic_test_market);
    const backtest_config = BacktestConfig{ .starting_cash = 10000 };
    const train_strategies = try buildStrategies(allocator);
    const test_strategies = try buildStrategies(allocator);
    const train_results = try Runner.runBatch(allocator, train_market, backtest_config, train_strategies);
    const test_results = try Runner.runBatch(allocator, test_market, backtest_config, test_strategies);
    std.debug.print("===IN-SAMPLE===\n", .{});
    printResults(train_results);
    std.debug.print("===OUT-OF-SAMPLE===\n", .{});
    printResults(test_results);
}

pub fn lessThanByNetPnlDesc(_: void, lhs: SweepTestResult, rhs: SweepTestResult) bool {
    return lhs.result.net_pnl > rhs.result.net_pnl;
}

fn printResults(results: []SweepTestResult) void {
    std.sort.heap(SweepTestResult, results, {}, lessThanByNetPnlDesc);
    std.debug.print(
        "{s:14} | {s:14} | {s:14} | {s:14} | {s:14} | {s:8}\n",
        .{ "Strategy", "Gross", "Net", "Fees", "Turnover", "Cost %" },
    );
    for (results) |result| {
        const backtest_result = result.result;
        const cost_pct =
            if (backtest_result.total_gross_value > 0)
                (backtest_result.total_fees / backtest_result.total_gross_value) * 100
            else
                null;
        std.debug.print(
            "{s:14} | {d:14.2} | {d:14.2} | {d:14.2} | {d:14.2} | ",
            .{
                result.label,
                backtest_result.gross_pnl,
                backtest_result.net_pnl,
                backtest_result.total_fees,
                backtest_result.total_gross_value,
            },
        );
        if (cost_pct) |pct| {
            std.debug.print("{d:7.2}%\n", .{pct});
        } else {
            std.debug.print("{s:8}\n", .{"N/A"});
        }
    }
}

fn buildStrategies(allocator: std.mem.Allocator) ![]Strategy {
    var strategies = std.ArrayList(Strategy).init(allocator);
    const dumb_ptr = try allocator.create(Dumb.DumbStrategy);
    dumb_ptr.* = .{};
    const dumb_strategy = Dumb.toStrategy(dumb_ptr);
    const mean_reversion_ptr = try allocator.create(MeanReversion.MeanReversion);
    mean_reversion_ptr.* = try MeanReversion.MeanReversion.init(allocator, 3, 0.01);
    const mean_reversion_strategy = MeanReversion.toStrategy(mean_reversion_ptr);
    const lookbacks = [_]usize{ 1, 3, 5, 9 };
    const thresholds = [_]f64{ 0.02, 0.03, 10.0 };

    const buy_every_tick_ptr = try allocator.create(BuyEveryTick.BuyEveryTick);
    buy_every_tick_ptr.* = .{};
    const buy_every_tick_strategy = BuyEveryTick.toStrategy(buy_every_tick_ptr);
    const base_strategies = [_]Strategy{ dumb_strategy, buy_every_tick_strategy, mean_reversion_strategy };
    try strategies.appendSlice(&base_strategies);
    for (lookbacks) |lb| {
        for (thresholds) |th| {
            const momentum_params = Momentum.MomentumParams{ .threshold = th, .lookback = lb };
            const momentum_ptr = try allocator.create(Momentum.Momentum);
            momentum_ptr.* = try Momentum.Momentum.init(allocator, momentum_params);
            var momentum_strategy = Momentum.toStrategy(momentum_ptr);
            const label = try std.fmt.allocPrint(allocator, "Momentum(lb={}, th={d:.2})", .{ lb, th });
            momentum_strategy.name = label;
            try strategies.append(momentum_strategy);
        }
    }
    return strategies.toOwnedSlice();
}
