const Market = @import("market.zig").Market;
const Trade = @import("trade.zig").Trade;

pub fn calcTotalFees(trades: []const Trade) f64 {
    var tot: f64 = 0;
    for (trades) |t| {
        tot += t.fee;
    }
    return tot;
}

pub fn calcTotalGrossValue(trades: []const Trade) f64 {
    var tot: f64 = 0;
    for (trades) |t| {
        tot += t.gross_value;
    }
    return tot;
}

pub fn calcGrossPnL(initial_equity: f64, trades: []const Trade, market: *const Market) f64 {
    var gross_cash = initial_equity;
    var gross_position: f64 = 0;
    if (trades.len == 0) return 0;
    for (trades) |trade| {
        const market_price = market.priceAt(trade.time);
        switch (trade.side) {
            .Buy => {
                gross_cash -= market_price * trade.quantity;
                gross_position += trade.quantity;
            },
            .Sell => {
                gross_cash += market_price * trade.quantity;
                gross_position -= trade.quantity;
            },
        }
    }
    const final_price = market.priceAt(trades[(trades.len - 1)].time);
    const gross_equity = gross_cash + gross_position * final_price;
    return gross_equity - initial_equity;
}
