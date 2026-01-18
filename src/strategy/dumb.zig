const Intent = @import("intent.zig").Intent;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;
const Strategy = @import("../strategy/strategy.zig").Strategy;

pub const DumbStrategy = struct {
    pub fn decide(self: DumbStrategy, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
        _ = self;
        _ = current_price;
        _ = portfolio_snap;
        if (current_time == 0) {
            return Intent{ .Buy = 1 };
        }
        if (current_time == 1) {
            return Intent{ .Sell = 1 };
        }
        return Intent.Hold;
    }
};

pub fn dumbDecideAdapter(ctx: *anyopaque, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
    const dumb: *DumbStrategy = @ptrCast(@alignCast(ctx));
    return dumb.decide(current_price, portfolio_snap, current_time);
}

pub fn toStrategy(dumb: *DumbStrategy) Strategy {
    return Strategy{ .ctx = dumb, .decideFn = dumbDecideAdapter };
}
