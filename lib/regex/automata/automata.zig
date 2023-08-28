const std = @import("std");
pub const nfa = @import("nfa.zig");

test "test automata creation" {
    // Mem allocator
    var buf: [1048576]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buf);
    var allocator = alloc.allocator();

    var start: usize = 0;
    var end: usize = 0;

    // Automata 1
    var b = nfa.Automata(u32).new(&allocator);
    defer b.deinit();
    start = b.addEmptyState(true, false) catch |err| {
        return err;
    };
    end = b.addEmptyState(false, true) catch |err| {
        return err;
    };
    b.addTransition(start, end, 12) catch |err| {
        return err;
    };

    // Automata 2
    var c = nfa.Automata(u32).new(&allocator);
    defer c.deinit();
    start = c.addEmptyState(true, false) catch |err| {
        return err;
    };
    end = c.addEmptyState(false, true) catch |err| {
        return err;
    };
    c.addTransition(start, end, 135) catch |err| {
        return err;
    };

    // Test alternate
    var d = nfa.NFAAlternate(u32, &b, &c, &allocator) catch |err| {
        return err;
    };

    var finishes = d.getStartStates() catch |err| {
        return err;
    };

    for (finishes.items) |state| {
        std.debug.print("{}: {}\n", .{ state, d.states.items[state] });
    }
    finishes.deinit();

    // Test concat
    d = nfa.NFAConcat(u32, &b, &c, &allocator) catch |err| {
        return err;
    };

    finishes = d.getStartStates() catch |err| {
        return err;
    };

    for (finishes.items) |state| {
        std.debug.print("{}: {}\n", .{ state, d.states.items[state] });
    }
    finishes.deinit();

    var lst = b.getAlphabet() catch |err| {
        return err;
    };
    defer lst.deinit();
    for (lst.items) |it| {
        std.debug.print("{}\n", .{it orelse 0});
    }

    std.debug.print("Has finish: {}\n", .{c.hasFinish()});

    var j = nfa.NFAKleenee(u32, &d, &allocator) catch |err| {
        return err;
    };
    std.debug.print("{}\n", .{j});

    // Test Epsilon closure
    var a = b.addEmptyState(false, false) catch |err| {
        return err;
    };
    var x = b.addEmptyState(false, false) catch |err| {
        return err;
    };
    b.addTransition(start, end, 12) catch |err| {
        return err;
    };

    b.addTransition(start, a, null) catch |err| {
        return err;
    };
    b.addTransition(a, x, null) catch |err| {
        return err;
    };
    b.addTransition(x, a, null) catch |err| {
        return err;
    };
    b.addTransition(end, x, null) catch |err| {
        return err;
    };

    var closure = b.epsilonClosure(start) catch |err| {
        return err;
    };
    std.debug.print("Start: ", .{});
    for (closure.items) |item| {
        std.debug.print("{}, ", .{item});
    }
    std.debug.print("\n", .{});

    closure = b.epsilonClosure(end) catch |err| {
        return err;
    };
    std.debug.print("End: ", .{});
    for (closure.items) |item| {
        std.debug.print("{}, ", .{item});
    }
    std.debug.print("\n", .{});
}

test "DFA conversion" {
    // Mem allocator
    var buf: [4194304]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buf);
    var allocator = alloc.allocator();

    var r = nfa.Automata(u32).new(&allocator);
    _ = r.addEmptyState(true, false) catch |err| {
        return err;
    };
    _ = r.addEmptyState(true, false) catch |err| {
        return err;
    };
    _ = r.addEmptyState(false, true) catch |err| {
        return err;
    };

    r.addTransition(0, 0, 1) catch |err| {
        return err;
    };
    r.addTransition(0, 0, 2) catch |err| {
        return err;
    };
    r.addTransition(0, 1, 1) catch |err| {
        return err;
    };
    r.addTransition(1, 2, 2) catch |err| {
        return err;
    };

    var g = r.toDFA() catch |err| {
        return err;
    };
    std.debug.print("\n", .{});
    for (0.., g.states.items) |item, state| {
        std.debug.print("Item #{} transitions (start = {}, finish = {}):\n", .{ item, state.start, state.finish });
        for (state.transitions.items) |trans| {
            std.debug.print(" - From: {} to {}, symbol = {}\n", .{ item, trans.dest, trans.symbol orelse 121 });
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("Items - {}\n", .{g.states.items.len});
}
