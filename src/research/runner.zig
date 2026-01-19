const std = @import("std");
const Market = @import("../engine/market.zig").Market;
const BacktestConfig = @import("../backtest/config.zig").BacktestConfig;
const Strategy = @import("../strategy/strategy.zig").Strategy;
const Engine = @import("../engine/engine.zig").Engine;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;

pub fn run_batch(allocator: std.mem.Allocator, market: Market, config: BacktestConfig, strategies: []Strategy) !void {
    std.debug.print("Strategy, Final Equity, PnL, Trade Count\n", .{});
    for (strategies, 0..) |strategy, i| {
        const portfolio = Portfolio.init(config.starting_cash);
        var engine = Engine{ .market = market, .portfolio = portfolio, .strategy = strategy, .time = 0 };
        const result = try engine.run(allocator);
        const last_price = market.price_at(market.prices.len - 1);
        const final_equity = result.finalEquity(last_price);
        const pnl = result.pnl(config.starting_cash, last_price);
        const trade_count = result.trades.len;
        std.debug.print("{d}", .{result.max_drawdown});
        std.debug.print("{d}, {d}, {d}, {d} \n", .{ i, final_equity, pnl, trade_count });
    }
}
