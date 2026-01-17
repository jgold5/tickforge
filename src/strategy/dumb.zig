const Intent = @import("intent.zig").Intent;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;

pub const DumbStrategy = struct {
    pub fn decide(self: DumbStrategy, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
        _ = self;
        _ = current_price;
        _ = portfolio_snap;
        if (current_time == 0) {
            return Intent.Buy;
        }
        if (current_time == 1) {
            return Intent.Sell;
        }
        return Intent.Hold;
    }
};
