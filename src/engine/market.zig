pub const Market = struct {
    prices: []f64,

    pub fn len(self: *const Market) usize {
        return self.prices.len;
    }

    pub fn price_at(self: *const Market, t: usize) f64 {
        return self.prices[t];
    }
};
