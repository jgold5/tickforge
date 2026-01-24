pub const Trade = struct {
    time: usize,
    side: Side,
    price: f64,
    quantity: f64,
    fee: f64 = 0,
    gross_value: f64 = 0,
};

pub const Side = enum { Buy, Sell };
