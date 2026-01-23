pub const Market = @import("../engine/market.zig").Market;
pub const SyntheticMarket = struct {
    prices: []const f64,

    pub fn len(self: *const SyntheticMarket) usize {
        return self.prices.len;
    }

    pub fn priceAt(self: *const SyntheticMarket, t: usize) f64 {
        return self.prices[t];
    }
};

pub fn syntheticLenAdapter(ctx: *anyopaque) usize {
    const synthetic_market: *SyntheticMarket = @ptrCast(@alignCast(ctx));
    return synthetic_market.len();
}

pub fn syntheticPriceAdapter(ctx: *anyopaque, t: usize) f64 {
    const synthetic_market: *SyntheticMarket = @ptrCast(@alignCast(ctx));
    return synthetic_market.priceAt(t);
}

pub fn toMarket(self: *SyntheticMarket) Market {
    return Market{ .ctx = self, .lenFn = syntheticLenAdapter, .priceAtFn = syntheticPriceAdapter, .prices = self.prices };
}
