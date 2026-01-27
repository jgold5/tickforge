const Trade = @import("engine/trade.zig").Trade;

pub const BacktestResult = struct {
    final_cash: f64,
    final_position: f64,
    executed_buys: usize,
    executed_sells: usize,
    rejected_buys: usize,
    rejected_sells: usize,
    initial_equity: f64,
    final_equity: f64,
    trade_count: usize,
    max_drawdown: f64,
    trades: []Trade,
    strategy_name: []const u8,
    equity_curve: []f64,
    total_fees: f64 = 0,
    total_gross_value: f64 = 0,
    gross_pnl: f64 = 0,
    net_pnl: f64 = 0,
    start_time: usize,
    end_time: usize,
};
