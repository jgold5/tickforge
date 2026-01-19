const std = @import("std");
const Market = @import("engine/market.zig").Market;
const Portfolio = @import("engine/portfolio.zig").Portfolio;
const Strategy = @import("strategy/strategy.zig").Strategy;
const Dumb = @import("strategy/dumb.zig");
const Engine = @import("engine/engine.zig").Engine;
const BacktestResult = @import("result.zig").BacktestResult;
const BacktestConfig = @import("backtest/config.zig").BacktestConfig;
const BuyEveryTick = @import("strategy/buy_every_tick.zig");
const MeanReversion = @import("strategy/mean_reversion.zig");
const runner = @import("research/runner.zig");

pub fn main() !void {
    var prices = [_]f64{ 100, 101, 102, 103, 104, 105, 106 };
    const allocator = std.heap.page_allocator;
    const market = Market{ .prices = prices[0..] };
    const backtest_config = BacktestConfig{ .starting_cash = 1000 };
    //var dumb = Dumb.DumbStrategy{};
    //const dumb_strategy = Dumb.toStrategy(&dumb);
    var mean_reversion = try MeanReversion.MeanReversion.init(allocator, 5, 0.03);
    const mean_reversion_strategy = MeanReversion.toStrategy(&mean_reversion);
    //var buy_every_tick = BuyEveryTick.BuyEveryTick{};
    //const buy_every_tick_strategy = BuyEveryTick.toStrategy(&buy_every_tick);
    //var strategies = [_]Strategy{ dumb_strategy, buy_every_tick_strategy, mean_reversion_strategy };
    var strategies = [_]Strategy{mean_reversion_strategy};
    try runner.run_batch(allocator, market, backtest_config, strategies[0..]);
}
