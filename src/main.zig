const std = @import("std");
const Market = @import("engine/market.zig").Market;
const Portfolio = @import("engine/portfolio.zig").Portfolio;
const Strategy = @import("strategy/strategy.zig").Strategy;
const Dumb = @import("strategy/dumb.zig");
const Engine = @import("engine/engine.zig").Engine;
const BacktestResult = @import("result.zig").BacktestResult;
const BacktestConfig = @import("backtest/config.zig").BacktestConfig;
const BuyEveryTick = @import("strategy/buy_every_tick.zig");

pub fn main() !void {
    var prices = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var start: usize = 0;
    _ = &start;
    const mkt = Market{ .prices = prices[start..] };
    const backtest_config = BacktestConfig{ .starting_cash = 100 };
    const portfolio = Portfolio.init(backtest_config.starting_cash);
    var dumbStrategy = Dumb.DumbStrategy{};
    var engine = Engine{ .market = mkt, .portfolio = portfolio, .strategy = Dumb.toStrategy(&dumbStrategy), .time = 0 };
    //var buy_every_tick = BuyEveryTick.BuyEveryTick{};
    //var engine = Engine{ .market = mkt, .portfolio = portfolio, .strategy = BuyEveryTick.toStrategy(&buy_every_tick), .time = 0 };
    const result = engine.run();
    const last_price = mkt.price_at(prices.len - 1);
    std.debug.print("Backtest Result: {any}\n", .{result});
    std.debug.print("Final Equity: ${d}\n", .{result.finalEquity(last_price)});
    std.debug.print("PnL: ${d}\n", .{result.pnl(backtest_config.starting_cash, last_price)});
}
