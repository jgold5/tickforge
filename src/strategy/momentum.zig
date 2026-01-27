const std = @import("std");
const Intent = @import("intent.zig").Intent;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;
const Strategy = @import("../strategy/strategy.zig").Strategy;

pub const Momentum = struct {
    prices: []f64,
    count: usize,
    head: usize,
    params: MomentumParams,

    pub fn init(allocator: std.mem.Allocator, params: MomentumParams) !Momentum {
        const prices = try allocator.alloc(f64, params.lookback);
        return Momentum{ .prices = prices, .count = 0, .head = 0, .params = params };
    }

    pub fn decide(self: *Momentum, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
        self.prices[self.head] = current_price;
        self.head = (self.head + 1) % self.params.lookback;
        if (self.count < self.params.lookback) {
            self.count += 1;
        }
        if (self.count < self.params.lookback) {
            return Intent.Hold;
        }
        var sum: f64 = 0;
        for (self.prices) |p| sum += p;
        const len_as_float: f64 = @floatFromInt(self.prices.len);
        const avg = sum / len_as_float;
        if (current_price < avg * (1.0 - self.params.threshold)) {
            return Intent{ .Sell = 1 };
        } else if (current_price > avg * (1.0 + self.params.threshold)) {
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
    return Strategy{ .ctx = self, .decideFn = momentumDecideAdapter, .name = "Momentum", .resetFn = null };
}

pub const MomentumParams = struct {
    lookback: usize,
    threshold: f64,
};
