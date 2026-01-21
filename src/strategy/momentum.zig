const std = @import("std");
const Intent = @import("intent.zig").Intent;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;
const Strategy = @import("../strategy/strategy.zig").Strategy;

pub const Momentum = struct {
    window: usize,
    threshold_pct: f64,
    prices: []f64,
    count: usize,
    head: usize,

    pub fn init(allocator: std.mem.Allocator, window: usize, threshold_pct: f64) !Momentum {
        const prices = try allocator.alloc(f64, window);
        return Momentum{ .window = window, .threshold_pct = threshold_pct, .prices = prices, .count = 0, .head = 0 };
    }

    pub fn decide(self: *Momentum, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
        self.prices[self.head] = current_price;
        self.head = (self.head + 1) % self.window;
        if (self.count < self.window) {
            self.count += 1;
        }
        if (self.count < self.window) {
            return Intent.Hold;
        }
        var sum: f64 = 0;
        for (self.prices) |p| sum += p;
        const len_as_float: f64 = @floatFromInt(self.prices.len);
        const avg = sum / len_as_float;
        if (current_price < avg * (1.0 - self.threshold_pct)) {
            return Intent{ .Sell = 1 };
        } else if (current_price > avg * (1.0 + self.threshold_pct)) {
            return Intent{ .Buy = 1 };
        }
        _ = current_time;
        _ = portfolio_snap;
        return Intent.Hold;
    }
};

pub fn momentumDecideAdapter(ctx: *anyopaque, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
    const momentum: *Momentum = @ptrCast(@alignCast(ctx));
    return momentum.decide(current_price, portfolio_snap, current_time);
}

pub fn toStrategy(self: *Momentum) Strategy {
    return Strategy{ .ctx = self, .decideFn = momentumDecideAdapter, .name = "Momentum" };
}
