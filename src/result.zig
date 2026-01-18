pub const BacktestResult = struct {
    final_cash: f64,
    final_position: f64,
    executed_buys: usize,
    executed_sells: usize,
    rejected_buys: usize,
    rejected_sells: usize,
};
