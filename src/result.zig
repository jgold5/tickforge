const Trade = @import("engine/trade.zig").Trade;

pub const BacktestResult = struct {
    final_cash: f64,
    final_position: f64,
    executed_buys: usize,
    executed_sells: usize,
    rejected_buys: usize,
    rejected_sells: usize,
    trades: []Trade,

    pub fn finalEquity(self: *const BacktestResult, final_price: f64) f64 {
        return self.final_cash + (self.final_position * final_price);
    }

    pub fn pnl(self: *const BacktestResult, starting_cash: f64, final_price: f64) f64 {
        return self.finalEquity(final_price) - starting_cash;
    }
};
