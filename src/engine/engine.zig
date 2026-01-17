const std = @import("std");
const Market = @import("market.zig").Market;
const Portfolio = @import("portfolio.zig").Portfolio;
const BacktestResult = @import("../result.zig").BacktestResult;
const Strategy = @import("../strategy/strategy.zig").Strategy;
const DumbStrategy = @import("../strategy/dumb.zig").DumbStrategy;

pub const Engine = struct {
    market: Market,
    portfolio: Portfolio,
    time: usize,
    strategy: DumbStrategy,

    pub fn run(self: *Engine) BacktestResult {
        var rejected_buys: usize = 0;
        var rejected_sells: usize = 0;
        while (self.time < self.market.len()) {
            const price = self.market.price_at(self.time);
            const intent = self.strategy.decide(price, &self.portfolio, self.time);
            switch (intent) {
                .Hold => {},
                .Buy => {
                    if (self.portfolio.cash >= price) {
                        self.portfolio.cash -= price;
                        self.portfolio.position += 1;
                    } else {
                        rejected_buys += 1;
                    }
                    std.debug.assert(self.portfolio.cash >= 0);
                },
                .Sell => {
                    if (self.portfolio.position >= 1) {
                        self.portfolio.cash += price;
                        self.portfolio.position -= 1;
                    } else {
                        rejected_sells += 1;
                    }
                    std.debug.assert(self.portfolio.position >= 0);
                },
            }
            self.time += 1;
        }
        const curr_price = self.market.price_at(self.time - 1);
        return BacktestResult{ .final_value = self.portfolio.value(curr_price), .rejected_buys = rejected_buys, .rejected_sells = rejected_sells };
    }
};
