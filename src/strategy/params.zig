const MomentumParams = @import("momentum.zig");

pub const StrategyParams = union(enum) {
    Momentum: MomentumParams,
};
