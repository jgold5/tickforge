const Intent = @import("intent.zig").Intent;
const Portfolio = @import("../engine/portfolio.zig").Portfolio;

pub const Strategy = struct {
    ctx: *anyopaque,
    decideFn: *const fn (*anyopaque, f64, *const Portfolio, usize) Intent,
    name: []const u8,

    pub fn decide(self: Strategy, current_price: f64, portfolio_snap: *const Portfolio, current_time: usize) Intent {
        return self.decideFn(self.ctx, current_price, portfolio_snap, current_time);
    }
};
