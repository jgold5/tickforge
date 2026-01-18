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

    pub fn run(self: *Engine, allocator: std.mem.Allocator) !BacktestResult {
        var rejected_buys: usize = 0;
        var rejected_sells: usize = 0;
        var executed_buys: usize = 0;
        var executed_sells: usize = 0;
        var trades = std.ArrayList(Trade).init(allocator);
        while (self.time < self.market.len()) {
            const price = self.market.price_at(self.time);
            const intent = self.strategy.decide(price, &self.portfolio, self.time);
            //intent execution
            try self.execute(intent, price, &executed_buys, &executed_sells, &rejected_buys, &rejected_sells, &trades, self.time);
            self.time += 1;
        }
        //const curr_price = self.market.price_at(self.time - 1);
        return BacktestResult{ .final_cash = self.portfolio.cash, .final_position = self.portfolio.position, .executed_buys = executed_buys, .executed_sells = executed_sells, .rejected_buys = rejected_buys, .rejected_sells = rejected_sells, .trades = try trades.toOwnedSlice() };
    }

    fn execute(self: *Engine, intent: Intent, price: f64, executed_buys: *usize, executed_sells: *usize, rejected_buys: *usize, rejected_sells: *usize, trade_list: *std.ArrayList(Trade), time: usize) !void {
        std.debug.print("intent: {any} @ price: {d}\n", .{ intent, price });
        switch (intent) {
            .Hold => {},
            .Buy => |qty| {
                if (self.portfolio.cash >= (price * qty)) {
                    self.portfolio.cash -= (price * qty);
                    self.portfolio.position += qty;
                    executed_buys.* += 1;
                    try trade_list.append(Trade{ .price = price, .time = time, .quantity = qty, .side = Trade.Side.Buy });
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
                } else {
                    rejected_sells.* += 1;
                }
                std.debug.assert(self.portfolio.position >= 0);
            },
        }
    }
};
