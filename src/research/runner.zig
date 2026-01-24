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
    std.debug.print(
        "{s:14} | {s:14} | {s:14} | {s:14} | {s:14} | {s:8}\n",
        .{ "Strategy", "Gross", "Net", "Fees", "Turnover", "Cost %" },
    );
    std.debug.print(
        "{s:-<14}-+-{s:-<14}-+-{s:-<14}-+-{s:-<14}-+-{s:-<14}-+-{s:-<8}\n",
        .{ "", "", "", "", "", "" },
    );
    for (strategies) |strategy| {
        const portfolio = Portfolio.init(config.starting_cash);
        var engine = Engine{ .market = market, .portfolio = portfolio, .strategy = strategy, .time = 0, .execution_mode = ExecutionMode.NextTick, .pending_intent = null, .pending_decision_time = null, .execution_model = ExecutionModel.initDefault() };
        const result = try engine.run(allocator);
        const cost_pct =
            if (result.total_gross_value > 0)
                (result.total_fees / result.total_gross_value) * 100
            else
                null;
        std.debug.print(
            "{s:14} | {d:14.2} | {d:14.2} | {d:14.2} | {d:14.2} | ",
            .{
                result.strategy_name,
                result.gross_pnl,
                result.net_pnl,
                result.total_fees,
                result.total_gross_value,
            },
        );
        if (cost_pct) |pct| {
            std.debug.print("{d:7.2}%\n", .{pct});
        } else {
            std.debug.print("{s:8}\n", .{"N/A"});
        }
    }
}
