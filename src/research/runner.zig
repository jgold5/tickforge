const std = @import("std");
const Market = @import("../engine/market.zig").Market;
const BacktestConfig = @import("../backtest/config.zig").BacktestConfig;
const Strategy = @import("../strategy/strategy.zig").Strategy;
const Engine = @import("../engine/engine.zig").Engine;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;
const ExecutionMode = @import("../engine/engine.zig").ExecutionMode;
const Intent = @import("../strategy/intent.zig").Intent;
const ExecutionModel = @import("../engine/execution.zig").ExecutionModel;
const BacktestResult = @import("../result.zig").BacktestResult;

pub fn runBatch(allocator: std.mem.Allocator, market: Market, config: BacktestConfig, strategies: []Strategy) ![]SweepResult {
    var results = std.ArrayList(SweepResult).init(allocator);
    for (strategies) |strategy| {
        const portfolio = Portfolio.init(config.starting_cash);
        var engine = Engine{ .market = market, .portfolio = portfolio, .strategy = strategy, .time = 0, .execution_mode = ExecutionMode.NextTick, .pending_intent = null, .pending_decision_time = null, .execution_model = ExecutionModel.initDefault() };
        const result = try engine.run(allocator);
        try results.append(SweepResult{ .label = strategy.name, .result = result });
    }
    return results.toOwnedSlice();
}

pub const SweepResult = struct {
    label: []const u8,
    result: BacktestResult,
};
