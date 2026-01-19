const std = @import("std");
const Intent = @import("intent.zig").Intent;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;
const Strategy = @import("../strategy/strategy.zig").Strategy;

pub const MeanReversion = struct {
    window: usize,
    threshold_pct: f64,
    prices: []f64,
    count: usize,
    head: usize,

    pub fn init(allocator: std.mem.Allocator, window: usize, threshold_pct: f64) !MeanReversion {
        const prices = try allocator.alloc(f64, window);
        return MeanReversion{ .window = window, .threshold_pct = threshold_pct, .prices = prices, .count = 0, .head = 0 };
    }

    pub fn decide(self: *MeanReversion, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
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
            return Intent{ .Buy = 1 };
        } else if (current_price > avg * (1.0 + self.threshold_pct)) {
            return Intent{ .Sell = 1 };
        }
        _ = portfolio_snap;
        _ = current_time;
        return Intent.Hold;
    }
};

pub fn meanReversionDecideAdapter(ctx: *anyopaque, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
    const mean: *MeanReversion = @ptrCast(@alignCast(ctx));
    return mean.decide(current_price, portfolio_snap, current_time);
}

pub fn toStrategy(self: *MeanReversion) Strategy {
    return Strategy{ .ctx = self, .decideFn = meanReversionDecideAdapter };
}
