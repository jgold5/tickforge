const Intent = @import("intent.zig").Intent;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;

pub const BuyEveryTick = struct {
    pub fn decide(self: BuyEveryTick, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
        _ = self;
        _ = current_price;
        _ = portfolio_snap;
        _ = current_time;
        return Intent{ .Buy = 1.0 };
    }
};
