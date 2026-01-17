const std = @import("std");
const Market = @import("engine/market.zig").Market;
const Portfolio = @import("engine/portfolio.zig").Portfolio;
const Strategy = @import("strategy/strategy.zig").Strategy;
const Engine = @import("engine/engine.zig").Engine;

pub fn main() !void {
    var prices = [_]f64{ 1.0, 2.0, 3.0 };
    var start: usize = 0;
    _ = &start;
    const mkt = Market{ .prices = prices[start..] };
    const portfolio = Portfolio.init(0);
    var engine = Engine{ .market = mkt, .portfolio = portfolio, .strategy = .{}, .time = 0 };
    _ = engine.run();
}
