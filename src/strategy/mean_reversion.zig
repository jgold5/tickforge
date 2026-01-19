const Intent = @import("intent.zig").Intent;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;
const Strategy = @import("../strategy/strategy.zig").Strategy;

pub const MeanReversion = struct {
    window: usize,
    threshold_pct: f64,

    pub fn decide(self: *MeanReversion, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
        _ = self;
        _ = current_price;
        _ = portfolio_snap;
        _ = current_time;
        return Intent{.Hold};
    }
};

pub fn meanReversionDecideAdapter(ctx: *anyopaque, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
    const mean: *MeanReversion = @ptrCast(@alignCast(ctx));
    return mean.decide(current_price, portfolio_snap, current_time);
}

pub fn toStrategy(self: *MeanReversion) Strategy {
    return Strategy{ .ctx = self, .decideFn = meanReversionDecideAdapter };
}
