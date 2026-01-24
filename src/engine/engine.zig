const std = @import("std");
const Market = @import("market.zig").Market;
const Portfolio = @import("portfolio.zig").Portfolio;
const BacktestResult = @import("../result.zig").BacktestResult;
const Strategy = @import("../strategy/strategy.zig").Strategy;
const DumbStrategy = @import("../strategy/dumb.zig").DumbStrategy;
const Intent = @import("../strategy/intent.zig").Intent;
const BuyEveryTick = @import("../strategy/buy_every_tick.zig").BuyEveryTick;
const Trade = @import("trade.zig").Trade;

pub const Engine = struct {
    market: Market,
    portfolio: Portfolio,
    time: usize,
    strategy: Strategy,
    execution_mode: ExecutionMode,
    pending_intent: ?Intent,

    pub fn run(self: *Engine, allocator: std.mem.Allocator) !BacktestResult {
        var rejected_buys: usize = 0;
        var rejected_sells: usize = 0;
        var executed_buys: usize = 0;
        var executed_sells: usize = 0;
        const initial_equity = self.portfolio.cash;
        var trades = std.ArrayList(Trade).init(allocator);
        var peak_equity = initial_equity;
        var max_drawdown: f64 = 0;
        const equity_curve: []f64 = try allocator.alloc(f64, self.market.len());
        while (self.time < self.market.len()) {
            const price = self.market.priceAt(self.time);
            if (self.execution_mode == ExecutionMode.NextTick) {
                if (self.pending_intent) |pi| {
                    try self.execute(pi, price, &executed_buys, &executed_sells, &rejected_buys, &rejected_sells, &trades, self.time);
                }
                self.pending_intent = null;
            }
            const intent = self.strategy.decide(price, &self.portfolio, self.time);
            //intent execution
            if (self.execution_mode == ExecutionMode.NextTick) {
                self.pending_intent = intent;
            } else {
                try self.execute(intent, price, &executed_buys, &executed_sells, &rejected_buys, &rejected_sells, &trades, self.time);
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
        const last_price = self.market.priceAt(self.time - 1);
        return BacktestResult{ .final_cash = self.portfolio.cash, .final_position = self.portfolio.position, .executed_buys = executed_buys, .executed_sells = executed_sells, .rejected_buys = rejected_buys, .rejected_sells = rejected_sells, .trades = try trades.toOwnedSlice(), .initial_equity = initial_equity, .final_equity = self.portfolio.cash + self.portfolio.position * last_price, .trade_count = executed_buys + executed_sells, .max_drawdown = max_drawdown, .strategy_name = self.strategy.name, .equity_curve = equity_curve };
    }

    fn execute(self: *Engine, intent: Intent, price: f64, executed_buys: *usize, executed_sells: *usize, rejected_buys: *usize, rejected_sells: *usize, trade_list: *std.ArrayList(Trade), time: usize) !void {
        const enable_trade_logging = true;
        switch (intent) {
            .Hold => {},
            .Buy => |qty| {
                if (self.portfolio.cash >= (price * qty)) {
                    self.portfolio.cash -= (price * qty);
                    self.portfolio.position += qty;
                    executed_buys.* += 1;
                    try trade_list.append(Trade{ .price = price, .time = time, .quantity = qty, .side = Trade.Side.Buy });
                    if (enable_trade_logging) std.debug.print("[{s}] t={d} BUY {d} @ {d:.2}\n", .{ self.strategy.name, self.time, qty, price });
                } else {
                    rejected_buys.* += 1;
                }
                std.debug.assert(self.portfolio.cash >= 0);
            },
            .Sell => |qty| {
                if (self.portfolio.position >= qty) {
                    self.portfolio.cash += (price * qty);
                    self.portfolio.position -= qty;
                    executed_sells.* += 1;
                    try trade_list.append(Trade{ .price = price, .time = time, .quantity = qty, .side = Trade.Side.Sell });
                    if (enable_trade_logging) std.debug.print("[{s}] t={d} SELL {d} @ {d:.2}\n", .{ self.strategy.name, self.time, qty, price });
                } else {
                    rejected_sells.* += 1;
                }
                std.debug.assert(self.portfolio.position >= 0);
            },
        }
    }
};

pub const ExecutionMode = enum { SameTick, NextTick };
