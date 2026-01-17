pub const Portfolio = struct {
    cash: f64,
    position: f64,

    pub fn value(self: *const Portfolio, price: f64) f64 {
        return self.cash + self.position * price;
    }

    pub fn init(starting_cash: f64) Portfolio {
        return Portfolio{
            .cash = starting_cash,
            .position = 0,
        };
    }
};
