const std = @import("std");
const Market = @import("engine/market.zig").Market;
const Portfolio = @import("engine/portfolio.zig").Portfolio;
const Strategy = @import("strategy/strategy.zig").Strategy;
const DumbStrategy = @import("strategy/dumb.zig").DumbStrategy;
const Engine = @import("engine/engine.zig").Engine;
const BacktestResult = @import("result.zig").BacktestResult;

pub fn main() !void {
    var prices = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var start: usize = 0;
    _ = &start;
    const mkt = Market{ .prices = prices[start..] };
    const portfolio = Portfolio.init(300);
    var engine = Engine{ .market = mkt, .portfolio = portfolio, .strategy = DumbStrategy{}, .time = 0 };
    const result = engine.run();
    _ = result;
}
