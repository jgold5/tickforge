const Side = @import("trade.zig").Trade.Side;

pub const ExecutionModel = struct {
    commission_per_trade: f64,
    slippage_bps: f64,

    pub fn initDefault() ExecutionModel {
        return ExecutionModel{ .commission_per_trade = 1, .slippage_bps = 1 };
    }

    pub fn compute(self: *const ExecutionModel, side: Side, price: f64, quantity: f64) ExecutionResult {
        const slippage = price * (self.slippage_bps / 10_000);
        _ = quantity;
        const exec_price = switch (side) {
            .Buy => price + slippage,
            .Sell => price - slippage,
        };
        return ExecutionResult{ .exec_price = exec_price, .fee = self.commission_per_trade };
    }
};

pub const ExecutionResult = struct {
    exec_price: f64,
    fee: f64,
};
