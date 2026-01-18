pub const Intent = union(enum) {
    Hold,
    Buy: f64,
    Sell: f64,
};
