const std = @import("std");
const Market = @import("../engine/market.zig").Market;
const BacktestConfig = @import("../backtest/config.zig").BacktestConfig;
const Strategy = @import("../strategy/strategy.zig").Strategy;
const Engine = @import("../engine/engine.zig").Engine;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;
const ExecutionMode = @import("../engine/engine.zig").ExecutionMode;
const Intent = @import("../strategy/intent.zig").Intent;
const ExecutionModel = @import("../engine/execution.zig").ExecutionModel;

pub fn run_batch(allocator: std.mem.Allocator, market: Market, config: BacktestConfig, strategies: []Strategy) !void {
    for (strategies) |strategy| {
        const portfolio = Portfolio.init(config.starting_cash);
        var engine = Engine{ .market = market, .portfolio = portfolio, .strategy = strategy, .time = 0, .execution_mode = ExecutionMode.NextTick, .pending_intent = null, .pending_decision_time = null, .execution_model = ExecutionModel.initDefault() };
        const result = try engine.run(allocator);
        const last_price = market.priceAt(market.prices.len - 1);
        //const final_equity = result.finalEquity(last_price);
        const pnl = result.pnl(config.starting_cash, last_price);
        std.debug.print(
            \\Strategy: {s}
            \\Initial Equity: {d:.2}
            \\Final Equity: {d:.2}
            \\PnL: {d:.2}
            \\Return: {d:.2}%
            \\Trades: {}
            \\Max drawdown: {d:.2}%
            \\
        , .{ result.strategy_name, result.initial_equity, result.final_equity, pnl, (result.final_equity - result.initial_equity) / result.initial_equity * 100.0, result.trade_count, result.max_drawdown * 100 });
    }
}
