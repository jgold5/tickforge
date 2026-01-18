const std = @import("std");
const Market = @import("market.zig").Market;
const Portfolio = @import("portfolio.zig").Portfolio;
const BacktestResult = @import("../result.zig").BacktestResult;
const Strategy = @import("../strategy/strategy.zig").Strategy;
const DumbStrategy = @import("../strategy/dumb.zig").DumbStrategy;
const Intent = @import("../strategy/intent.zig").Intent;
const BuyEveryTick = @import("../strategy/buy_every_tick.zig").BuyEveryTick;

pub const Engine = struct {
    market: Market,
    portfolio: Portfolio,
    time: usize,
    strategy: BuyEveryTick,

    pub fn run(self: *Engine) BacktestResult {
        var rejected_buys: usize = 0;
        var rejected_sells: usize = 0;
        while (self.time < self.market.len()) {
            const price = self.market.price_at(self.time);
            const intent = self.strategy.decide(price, &self.portfolio, self.time);
            //intent execution
            self.execute(intent, price, &rejected_buys, &rejected_sells);
            self.time += 1;
        }
        const curr_price = self.market.price_at(self.time - 1);
        return BacktestResult{ .final_value = self.portfolio.value(curr_price), .rejected_buys = rejected_buys, .rejected_sells = rejected_sells };
    }

    fn execute(self: *Engine, intent: Intent, price: f64, rejected_buys: *usize, rejected_sells: *usize) void {
        std.debug.print("intent: {any} @ price: {d}\n", .{ intent, price });
        switch (intent) {
            .Hold => {},
            .Buy => |qty| {
                if (self.portfolio.cash >= (price * qty)) {
                    self.portfolio.cash -= (price * qty);
                    self.portfolio.position += qty;
                } else {
                    rejected_buys.* += 1;
                }
                std.debug.assert(self.portfolio.cash >= 0);
            },
            .Sell => |qty| {
                if (self.portfolio.position >= qty) {
                    self.portfolio.cash += (price * qty);
                    self.portfolio.position -= qty;
                } else {
                    rejected_sells.* += 1;
                }
                std.debug.assert(self.portfolio.position >= 0);
            },
        }
    }
};
