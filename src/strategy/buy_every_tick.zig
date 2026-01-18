const Intent = @import("intent.zig").Intent;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;
const Strategy = @import("../strategy/strategy.zig").Strategy;

pub const BuyEveryTick = struct {
    pub fn decide(self: BuyEveryTick, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
        _ = self;
        _ = current_price;
        _ = portfolio_snap;
        _ = current_time;
        return Intent{ .Buy = 1.0 };
    }
};

pub fn buyEveryTickDecideAdapter(ctx: *anyopaque, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
    const dumb: *BuyEveryTick = @ptrCast(@alignCast(ctx));
    return dumb.decide(current_price, portfolio_snap, current_time);
}

pub fn toStrategy(buyEveryTick: *BuyEveryTick) Strategy {
    return Strategy{ .ctx = buyEveryTick, .decideFn = buyEveryTickDecideAdapter };
}
