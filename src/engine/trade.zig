pub const Trade = struct {
    time: usize,
    side: Side,
    price: f64,
    quantity: f64,

    pub const Side = enum { Buy, Sell };
};
