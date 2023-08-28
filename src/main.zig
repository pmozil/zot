const std = @import("std");
const regex = @import("regex");

pub fn main() !void {
    var buf: [131072]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buf);
    var allocator = alloc.allocator();
    // var allocator = std.heap.page_allocator;

    var x: [24]u8 = "0x(0|1|2|3|4|5|6|7|8|8)+".*;
    var y = "0x1223333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777".*;
    // var w: [4]u8 = "1223".*;

    var re = regex.Regex.new(allocator);
    // std.debug.print("\n{s}\n", .{try re.infixToPostfix(&x)});
    try re.compile(&x);

    std.debug.print("Match {s}: {}\n", .{ y, re.match(&y) });
    // std.debug.print("Match {s}: {}\n", .{ w, re.match(&w) });

    // std.debug.print("Total states: {}\n", .{re.autom.?.states.items.len});
    // for (0.., re.autom.?.states.items) |item, state| {
    //     std.debug.print(
    //         "Item #{} transitions (start = {}, finish = {}):\n",
    //         .{ item, state.start, state.finish },
    //     );
    //     for (state.transitions.items) |trans| {
    //         std.debug.print(
    //             " - From: {} to {}, symbol = {s}\n",
    //             .{ item, trans.dest, [1]u8{trans.symbol orelse 121} },
    //         );
    //     }
    //     std.debug.print("\n", .{});
    // }
    re.deinit();
}
