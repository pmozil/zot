# Zot - a basic DFA regex implementation in zig

## It's speed is comparable to POSIX C regex!

This project uses a nondeterministic FA to create the regex, and then 
converts it into a deterministic one.

Here's an example of how to use the regex structure:

```zig

const std = @import("std");
const regex = @import("regex");

pub fn main() !void {
    var buf: [131072]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buf);
    var allocator = alloc.allocator();

    var x: [24]u8 = "0x(0|1|2|3|4|5|6|7|8|8)+".*;
    var y: [6]u8 = "0x1223".*;
    var w: [4]u8 = "1223".*;

    var re = regex.Regex.new(allocator);
    std.debug.print("\n{s}\n", .{try re.infixToPostfix(&x)});
    try re.compile(&x);

    std.debug.print("Match {s}: {}\n", .{ y, re.match(&y) });
    std.debug.print("Match {s}: {}\n", .{ w, re.match(&w) });

    std.debug.print("Total states: {}\n", .{re.autom.?.states.items.len});
    for (0.., re.autom.?.states.items) |item, state| {
        std.debug.print(
            "Item #{} transitions (start = {}, finish = {}):\n",
            .{ item, state.start, state.finish },
        );
        for (state.transitions.items) |trans| {
            std.debug.print(
                " - From: {} to {}, symbol = {s}\n",
                .{ item, trans.dest, [1]u8{trans.symbol orelse 121} },
            );
        }
        std.debug.print("\n", .{});
    }
}
```

And here's wat the program will output:

```
0x.01|2|3|4|5|6|7|8|8|+.
Match 0x1223: true
Match 1223: false
Total states: 4
Item #0 transitions (start = true, finish = false):
 - From: 0 to 1, symbol = 0

Item #1 transitions (start = false, finish = false):
 - From: 1 to 2, symbol = x

Item #2 transitions (start = false, finish = false):
 - From: 2 to 3, symbol = 0
 - From: 2 to 3, symbol = 7
 - From: 2 to 3, symbol = 6
 - From: 2 to 3, symbol = 5
 - From: 2 to 3, symbol = 4
 - From: 2 to 3, symbol = 3
 - From: 2 to 3, symbol = 2
 - From: 2 to 3, symbol = 1
 - From: 2 to 3, symbol = 8

Item #3 transitions (start = false, finish = true):
 - From: 3 to 3, symbol = 0
 - From: 3 to 3, symbol = 7
 - From: 3 to 3, symbol = 6
 - From: 3 to 3, symbol = 5
 - From: 3 to 3, symbol = 4
 - From: 3 to 3, symbol = 3
 - From: 3 to 3, symbol = 2
 - From: 3 to 3, symbol = 1
 - From: 3 to 3, symbol = 8
```

It even works with most unicode strings (though this was accidental)

```zig
const std = @import("std");
const regex = @import("regex");

pub fn main() !void {
    var buf: [131072]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buf);
    var allocator = alloc.allocator();

    var x = "ä(bc|d)+".*;
    var y = "äbcbcd".*;
    var w: [4]u8 = "1223".*;

    var re = regex.Regex.new(allocator);
    std.debug.print("\n{s}\n", .{try re.infixToPostfix(&x)});
    try re.compile(&x);

    std.debug.print("Match {s}: {}\n", .{ y, re.match(&y) });
    std.debug.print("Match {s}: {}\n", .{ w, re.match(&w) });
}
```

```
ä.bc.d|+.
Match äbcbcd: true
Match 1223: false
```
