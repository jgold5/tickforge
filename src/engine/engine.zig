const std = @import("std");
const Market = @import("market.zig").Market;
const Portfolio = @import("portfolio.zig").Portfolio;
const BacktestResult = @import("../result.zig").BacktestResult;
const Strategy = @import("../strategy/strategy.zig").Strategy;
const DumbStrategy = @import("../strategy/dumb.zig").DumbStrategy;
const Intent = @import("../strategy/intent.zig").Intent;
const BuyEveryTick = @import("../strategy/buy_every_tick.zig").BuyEveryTick;
const Trade = @import("trade.zig").Trade;
const ExecutionModel = @import("execution.zig");
const Metrics = @import("metrics.zig");

const enable_decision_logging = false;
const enable_execution_logging = false;

pub const Engine = struct {
    market: Market,
    portfolio: Portfolio,
    time: usize,
    strategy: Strategy,
    execution_mode: ExecutionMode,
    pending_intent: ?Intent,
    pending_decision_time: ?usize,
    execution_model: ExecutionModel.ExecutionModel,

    pub fn run(self: *Engine, allocator: std.mem.Allocator) !BacktestResult {
        var rejected_buys: usize = 0;
        var rejected_sells: usize = 0;
        var executed_buys: usize = 0;
        var executed_sells: usize = 0;
        const initial_equity = self.portfolio.cash + self.portfolio.position * self.market.priceAt(self.time);
        var trades = std.ArrayList(Trade).init(allocator);
        var peak_equity = initial_equity;
        var max_drawdown: f64 = 0;
        const equity_curve: []f64 = try allocator.alloc(f64, self.market.len());
        while (self.time < self.market.len()) {
            const price = self.market.priceAt(self.time);
            if (self.execution_mode == ExecutionMode.NextTick) {
                if (self.pending_intent) |pi| {
                    try self.execute(pi, price, &executed_buys, &executed_sells, &rejected_buys, &rejected_sells, &trades, self.time);
                    if (enable_execution_logging) {
                        logExecution(self.pending_intent.?, self.strategy.name, self.time, self.pending_decision_time.?, price);
                    }
                }
                self.pending_intent = null;
                self.pending_decision_time = null;
            }
            const intent = self.strategy.decide(price, &self.portfolio, self.time);
            if (enable_decision_logging) {
                logDecision(intent, self.strategy.name, self.time, price);
            }
            //intent execution
            if (self.execution_mode == ExecutionMode.NextTick) {
                self.pending_intent = intent;
                self.pending_decision_time = self.time;
            } else {
                try self.execute(intent, price, &executed_buys, &executed_sells, &rejected_buys, &rejected_sells, &trades, self.time);
                if (enable_execution_logging) {
                    logExecution(intent, self.strategy.name, self.time, self.time, price);
                }
            }
            const equity = self.portfolio.cash + self.portfolio.position * price;
            equity_curve[self.time] = equity;
            if (equity > peak_equity) {
                peak_equity = equity;
            } else {
                const drawdown = (equity - peak_equity) / peak_equity;
                if (drawdown < max_drawdown) {
                    max_drawdown = drawdown;
                }
            }
            self.time += 1;
        }
        const tradesAsSlice = try trades.toOwnedSlice();
        const last_price = self.market.priceAt(self.time - 1);
        const final_equity = self.portfolio.cash + self.portfolio.position * last_price;
        return BacktestResult{ .final_cash = self.portfolio.cash, .final_position = self.portfolio.position, .executed_buys = executed_buys, .executed_sells = executed_sells, .rejected_buys = rejected_buys, .rejected_sells = rejected_sells, .trades = tradesAsSlice, .initial_equity = initial_equity, .final_equity = final_equity, .trade_count = executed_buys + executed_sells, .max_drawdown = max_drawdown, .strategy_name = self.strategy.name, .equity_curve = equity_curve, .total_fees = Metrics.calcTotalFees(tradesAsSlice), .total_gross_value = Metrics.calcTotalGrossValue(tradesAsSlice), .net_pnl = Metrics.calcNetPnL(initial_equity, self.portfolio.cash, self.portfolio.position, last_price), .gross_pnl = Metrics.calcGrossPnL(initial_equity, tradesAsSlice, &self.market) };
    }

    fn execute(
        self: *Engine,
        intent: Intent,
        price: f64,
        executed_buys: *usize,
        executed_sells: *usize,
        rejected_buys: *usize,
        rejected_sells: *usize,
        trade_list: *std.ArrayList(Trade),
        time: usize,
    ) !void {
        switch (intent) {
            .Hold => {},
            .Buy => |qty| {
                const execution_result = self.execution_model.compute(.Buy, price, qty);
                const total_cost = execution_result.exec_price * qty + execution_result.fee;
                if (total_cost > self.portfolio.cash) {
                    rejected_buys.* += 1;
                    return;
                }
                self.portfolio.cash -= total_cost;
                self.portfolio.position += qty;
                executed_buys.* += 1;
                try trade_list.append(Trade{ .price = execution_result.exec_price, .time = time, .quantity = qty, .side = .Buy, .fee = execution_result.fee, .gross_value = execution_result.exec_price * qty });
                std.debug.assert(self.portfolio.cash >= 0);
            },
            .Sell => |qty| {
                const execution_result = self.execution_model.compute(.Sell, price, qty);
                if (self.portfolio.position < qty) {
                    rejected_sells.* += 1;
                    return;
                }
                self.portfolio.cash += execution_result.exec_price * qty;
                self.portfolio.cash -= execution_result.fee;
                self.portfolio.position -= qty;
                executed_sells.* += 1;
                try trade_list.append(Trade{ .price = execution_result.exec_price, .time = time, .quantity = qty, .side = .Sell, .fee = execution_result.fee, .gross_value = execution_result.exec_price * qty });
                std.debug.assert(self.portfolio.position >= 0);
            },
        }
    }
};

pub const ExecutionMode = enum { SameTick, NextTick };

fn logDecision(intent: Intent, name: []const u8, time: usize, price: f64) void {
    switch (intent) {
        .Buy => {
            std.debug.print("[{s}] decided BUY @ t={} (price={d:.2})\n", .{ name, time, price });
        },
        .Sell => {
            std.debug.print("[{s}] decided SELL @ t={} (price={d:.2})\n", .{ name, time, price });
        },
        else => {},
    }
}

fn logExecution(intent: Intent, name: []const u8, time: usize, decision_time: usize, price: f64) void {
    switch (intent) {
        .Buy => {
            std.debug.print("[{s}] executed BUY @ t={} (price={d:.2}, decided @ t={})\n", .{ name, time, price, decision_time });
        },
        .Sell => {
            std.debug.print("[{s}] executed SELL @ t={} (price={d:.2}, decided @ t={})\n", .{ name, time, price, decision_time });
        },
        else => {},
    }
}
