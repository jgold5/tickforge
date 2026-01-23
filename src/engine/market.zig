pub const Market = struct {
    ctx: *anyopaque,
    lenFn: *const fn (*anyopaque) usize,
    priceAtFn: *const fn (*anyopaque, usize) f64,
    prices: []const f64,

    pub fn len(self: *const Market) usize {
        return self.lenFn(self.ctx);
    }

    pub fn priceAt(self: *const Market, t: usize) f64 {
        return self.priceAtFn(self.ctx, t);
    }
};
