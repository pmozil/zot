const std = @import("std");
const ArrayList = std.ArrayList;

pub fn AutomataTransition(comptime T: type) type {
    return struct {
        // If symbol is null, then the transition is ε
        symbol: ?T,
        dest: usize,
    };
}

pub fn AutomataState(comptime T: type) type {
    return struct {
        const Self = @This();

        start: bool = false,
        finish: bool = false,
        transitions: ArrayList(AutomataTransition(T)),

        fn deinit(self: *Self) void {
            self.transitions.deinit();
        }
    };
}

pub fn Automata(comptime T: type) type {
    return struct {
        const Self = @This();

        states: ArrayList(AutomataState(T)),
        numStates: usize = 0,
        alloc: std.mem.Allocator,

        pub fn new(alloc: std.mem.Allocator) Self {
            return Self{
                .alloc = alloc,
                .states = ArrayList(AutomataState(T)).init(alloc),
            };
        }

        pub fn newEpsilon(alloc: std.mem.Allocator) !Self {
            var newAutomata = Self{
                .alloc = alloc,
                .states = ArrayList(AutomataState(T)).init(alloc),
            };

            const start = try newAutomata.addEmptyState(true, false);
            const end = try newAutomata.addEmptyState(false, true);
            _ = try newAutomata.addTransition(start, end, null);

            return newAutomata;
        }

        pub fn newBasic(alloc: std.mem.Allocator, symbol: T) !Self {
            var newAutomata = Self{
                .alloc = alloc,
                .states = ArrayList(AutomataState(T)).init(alloc),
            };

            const start = try newAutomata.addEmptyState(true, false);
            const end = try newAutomata.addEmptyState(false, true);
            _ = try newAutomata.addTransition(start, end, symbol);

            return newAutomata;
        }

        pub fn addEmptyState(
            self: *Self,
            isStart: bool,
            isFinish: bool,
        ) !usize {
            try self.states.append(
                AutomataState(T){
                    .start = isStart,
                    .finish = isFinish,
                    .transitions = ArrayList(AutomataTransition(T)).init(self.alloc),
                },
            );
            return self.states.items.len - 1;
        }

        pub fn addTransition(
            self: *Self,
            from: usize,
            to: usize,
            symbol: ?T,
        ) !AutomataTransition(T) {
            for (self.states.items[from].transitions.items) |trans| {
                if (trans.symbol == symbol and trans.dest == to) {
                    return trans;
                }
            }

            try self.states.items[from].transitions.append(
                .{
                    .symbol = symbol,
                    .dest = to,
                },
            );
            return self.states.items[from].transitions.items[
                self.states.items[from].transitions.items.len - 1
            ];
        }

        pub fn getAlphabet(self: *Self) !ArrayList(?T) {
            var alphabet = ArrayList(?T).init(self.alloc);

            for (self.states.items) |state| {
                for (state.transitions.items) |transition| {
                    var insert = true;

                    for (alphabet.items) |symbol| {
                        if (symbol == transition.symbol) {
                            insert = false;
                            break;
                        }
                    }

                    if (insert) {
                        try alphabet.append(transition.symbol);
                    }
                }
            }

            return alphabet;
        }

        pub fn getStartStates(self: *Self) !ArrayList(usize) {
            var startStates = ArrayList(usize).init(self.alloc);

            for (0.., self.states.items) |i, state| {
                if (state.start) {
                    try startStates.append(i);
                }
            }

            return startStates;
        }

        pub fn getFinishStates(self: *Self) !ArrayList(usize) {
            var finishStates = ArrayList(usize).init(self.alloc);

            for (0.., self.states.items) |i, state| {
                if (state.finish) {
                    try finishStates.append(i);
                }
            }

            return finishStates;
        }

        pub fn concatenateInPlace(self: *Self, other: *Self) !void {
            defer other.deinit();

            const prevLen: usize = self.states.items.len;
            var prevFinishes: ArrayList(usize) = try self.getFinishStates();
            defer prevFinishes.deinit();

            try self.concatNfa(other);

            for (other.states.items) |state| {
                var i = try self.addEmptyState(false, state.finish);
                if (state.start) {
                    for (prevFinishes.items) |idx| {
                        self.addTransition(idx, i, null);
                    }
                }
            }

            for (prevFinishes.items) |idx| {
                self.states.items[idx].finish = false;
            }

            for (0.., other.states.items) |i, state| {
                for (state.transitions.items) |transition| {
                    _ = try self.addTransition(
                        prevLen + i,
                        prevLen + transition.dest,
                        transition.symbol,
                    );
                }
            }
        }

        pub fn concatNfa(self: *Self, other: *Self) !void {
            const prevLen: usize = self.states.items.len;

            for (other.states.items) |state| {
                _ = try self.addEmptyState(state.start, state.finish);
            }

            for (0.., other.states.items) |i, state| {
                for (state.transitions.items) |transition| {
                    _ = try self.addTransition(
                        prevLen + i,
                        prevLen + transition.dest,
                        transition.symbol,
                    );
                }
            }
        }

        pub fn deinit(self: *Self) void {
            while (self.states.items.len > 0) {
                var state = self.states.pop();
                state.deinit();
            }

            self.states.deinit();
        }

        pub fn epsilonClosure(self: *Self, state: usize) !ArrayList(usize) {
            var reachable = ArrayList(usize).init(self.alloc);
            var reachableStack = ArrayList(usize).init(self.alloc);
            defer reachableStack.deinit();
            try reachable.append(state);
            try reachableStack.append(state);

            while (reachableStack.items.len > 0) {
                var itemIdx: usize = reachableStack.pop();
                var curState = self.states.items[itemIdx];

                for (curState.transitions.items) |trans| {
                    if (trans.symbol != null) {
                        continue;
                    }

                    var add = false;
                    for (reachable.items) |item| {
                        if (item == trans.dest) {
                            add = true;
                        }
                    }
                    for (reachableStack.items) |item| {
                        if (item == trans.dest) {
                            add = true;
                        }
                    }

                    if (add) {
                        continue;
                    }

                    try reachable.append(trans.dest);
                    try reachableStack.append(trans.dest);
                }
            }

            return reachable;
        }

        pub fn nodeIsStart(self: *Self, idx: usize) bool {
            if (self.states.items.len <= idx) {
                return false;
            }
            return self.states.items[idx].start;
        }

        pub fn nodeIsEnd(self: *Self, idx: usize) bool {
            if (self.states.items.len <= idx) {
                return false;
            }
            return self.states.items[idx].finish;
        }

        pub fn hasFinish(self: *Self) bool {
            for (self.states.items) |state| {
                if (state.finish) {
                    return true;
                }
            }

            return false;
        }

        fn arrayToBitSet(self: *Self, a1: []usize) !std.DynamicBitSet {
            var max: usize = 0;
            for (a1) |elem| {
                if (elem > max) {
                    max = elem;
                }
            }
            var bitset = try std.DynamicBitSet.initEmpty(self.alloc, max + 1);

            for (a1) |elem| {
                bitset.set(elem);
            }

            return bitset;
        }

        const Trans = struct {
            from: usize,
            sym: T,
        };

        const StateStackElement = struct {
            elem: std.DynamicBitSet,
            from: ?std.ArrayList(Trans) = null,
        };

        pub fn toDFA(self: *Self) !Self {
            var dfa = Self.new(self.alloc);
            var states = ArrayList(std.DynamicBitSet).init(self.alloc);
            defer states.deinit();
            var statesStack = ArrayList(StateStackElement).init(self.alloc);
            defer statesStack.deinit();
            var alphabet = try self.getAlphabet();
            defer alphabet.deinit();

            var starts = try self.getStartStates();
            var clos = try self.epsilonClosure(starts.items[0]);

            try statesStack.append(.{ .elem = try self.arrayToBitSet(clos.items) });

            starts.deinit();
            clos.deinit();

            var isStart = true;

            var startIdx: usize = 0;
            while (statesStack.items.len > 0) {
                var stackClosure = statesStack.pop();
                var nodeEnd = false;

                var iter = stackClosure.elem.iterator(.{});
                while (iter.next()) |item| {
                    if (self.nodeIsEnd(item)) {
                        nodeEnd = true;
                    }
                }

                try states.append(stackClosure.elem);

                startIdx = try dfa.addEmptyState(isStart, nodeEnd);
                isStart = false;

                if (stackClosure.from != null) {
                    for (stackClosure.from.?.items) |trans| {
                        _ = try dfa.addTransition(trans.from, startIdx, trans.sym);
                    }
                    stackClosure.from.?.deinit();
                }

                for (alphabet.items) |letter| {
                    if (letter == null) {
                        continue;
                    }

                    var newClosure = ArrayList(usize).init(self.alloc);
                    defer newClosure.deinit();

                    iter = stackClosure.elem.iterator(.{});
                    while (iter.next()) |state| {
                        for (self.states.items[state].transitions.items) |trans| {
                            if (trans.symbol != letter) {
                                continue;
                            }

                            var closure = try self.epsilonClosure(trans.dest);
                            defer closure.deinit();

                            try newClosure.appendSlice(closure.items);
                        }
                    }

                    var append = newClosure.items.len > 0;
                    var newBitSet = try self.arrayToBitSet(newClosure.items);

                    for (0.., states.items) |i, stateArr| {
                        if (newBitSet.eql(stateArr)) {
                            append = false;
                            _ = try dfa.addTransition(startIdx, i, letter);
                        }
                    }

                    for (0.., statesStack.items) |i, stateArr| {
                        if (newBitSet.eql(stateArr.elem)) {
                            append = false;
                            if (stateArr.from == null) {
                                statesStack.items[i].from = ArrayList(Trans).init(self.alloc);
                                try statesStack.items[i].from.?.append(.{
                                    .from = startIdx,
                                    .sym = letter.?,
                                });
                            } else {
                                try statesStack.items[i].from.?.append(.{
                                    .from = startIdx,
                                    .sym = letter.?,
                                });
                            }
                        }
                    }

                    if (append) {
                        var arr = ArrayList(Trans).init(self.alloc);
                        try arr.append(.{ .from = startIdx, .sym = letter.? });

                        try statesStack.append(.{
                            .elem = newBitSet,
                            .from = arr,
                        });
                    }
                }
            }

            while (states.items.len > 0) {
                var state = states.pop();
                state.deinit();
            }

            var optimisedStates = try dfa.makeOptimisedStates();
            dfa.states = optimisedStates;

            return dfa;
        }

        fn transitionsAreEqual(
            t1: *ArrayList(AutomataTransition(T)),
            t2: *ArrayList(AutomataTransition(T)),
        ) !bool {
            var t2Copy = try t2.clone();
            defer t2Copy.deinit();
            for (t1.items) |trans| {
                var i: usize = 0;

                while (i < t2Copy.items.len) {
                    const other = t2Copy.items[i];
                    if (other.dest == trans.dest and
                        other.symbol == trans.symbol and
                        t2Copy.items.len > 0)
                    {
                        _ = t2Copy.orderedRemove(i);
                        break;
                    }
                    i += 1;
                }
            }
            return t2Copy.items.len == 0;
        }

        fn makeOptimisedStates(self: *Self) !ArrayList(AutomataState(T)) {
            const pair = struct {
                removed: usize,
                prev: usize,
            };

            var removedStates = ArrayList(pair).init(self.alloc);
            defer removedStates.deinit();

            var statesCopy = try self.states.clone();
            defer statesCopy.deinit();

            var idx: usize = 0;
            var newStates = ArrayList(AutomataState(T)).init(self.alloc);

            while (statesCopy.items.len > 0) {
                var state = statesCopy.orderedRemove(0);
                var foundIdentical = false;

                // Check is there already exists a state with the transitions of
                // state. If so, don't append to the states.
                for (0..newStates.items.len) |i| {
                    foundIdentical = foundIdentical or try Self.transitionsAreEqual(
                        &newStates.items[i].transitions,
                        &state.transitions,
                    );
                    foundIdentical = foundIdentical and (state.start == newStates.items[i].start) and
                        (state.finish == newStates.items[i].finish);

                    // There already exists a state wth such transitions,
                    // so we have to check that is has the start/finish properties
                    // of both the states
                    if (foundIdentical) {
                        try removedStates.append(
                            .{
                                .removed = idx,
                                .prev = i,
                            },
                        );
                        state.deinit();
                        break;
                    }
                }

                if (!foundIdentical) {
                    try newStates.append(state);
                }

                idx += 1;
            }

            for (0..newStates.items.len) |i| {
                for (0.., newStates.items[i].transitions.items) |transIdx, trans| {
                    var sub: usize = 0;
                    for (removedStates.items) |rmState| {
                        if (trans.dest == rmState.removed) {
                            newStates.items[i].transitions.items[transIdx].dest = rmState.prev;
                            break;
                        }

                        if (trans.dest > rmState.removed) {
                            sub += 1;
                        }
                    }
                    newStates.items[i].transitions.items[transIdx].dest -= sub;
                }
            }

            return newStates;
        }
    };
}

pub fn addState(states: *ArrayList(usize), stateNum: usize) !void {
    var add: bool = true;
    for (states.items) |state| {
        if (state == stateNum) {
            add = false;
            break;
        }
    }

    if (add) {
        try states.append(stateNum);
    }
}

pub fn NFAConcat(
    comptime T: type,
    a1: *Automata(T),
    a2: *Automata(T),
    alloc: std.mem.Allocator,
) !Automata(T) {
    var new = Automata(T).new(alloc);

    try new.concatNfa(a1);
    try new.concatNfa(a2);

    var finishes: ArrayList(usize) = try a1.getFinishStates();
    var starts: ArrayList(usize) = try a2.getStartStates();
    defer starts.deinit();
    defer finishes.deinit();

    for (finishes.items) |fin| {
        new.states.items[fin].finish = false;
        for (starts.items) |start| {
            new.states.items[fin].start = false;
            _ = try new.addTransition(fin, a1.states.items.len + start, null);
        }
    }

    return new;
}
pub fn NFAPlus(
    comptime T: type,
    a1: *Automata(T),
    alloc: std.mem.Allocator,
) !Automata(T) {
    var new = Automata(T).new(alloc);
    defer new.deinit();
    var base_start = try new.addEmptyState(true, false);
    var base_finish = try new.addEmptyState(false, true);

    var dfa = try a1.toDFA();
    defer dfa.deinit();

    try new.concatNfa(&dfa);

    var starts: ArrayList(usize) = try new.getStartStates();
    defer starts.deinit();

    var finishes: ArrayList(usize) = try new.getFinishStates();
    defer finishes.deinit();

    for (finishes.items) |fin| {
        if (fin == base_finish) {
            continue;
        }

        new.states.items[fin].finish = false;
        _ = try new.addTransition(fin, base_finish, null);
        for (starts.items) |start| {
            if (start == base_start) {
                continue;
            }
            _ = try new.addTransition(fin, start, null);
        }
    }

    for (starts.items) |start| {
        if (start == base_start) {
            continue;
        }

        new.states.items[start].start = false;
        _ = try new.addTransition(base_start, start, null);
    }

    return new.toDFA();
}

pub fn NFAKleenee(
    comptime T: type,
    a1: *Automata(T),
    alloc: std.mem.Allocator,
) !Automata(T) {
    var new = Automata(T).new(alloc);
    defer new.deinit();
    var base_start = try new.addEmptyState(true, false);
    var base_finish = try new.addEmptyState(false, true);

    _ = try new.addTransition(base_start, base_finish, null);
    var dfa = try a1.toDFA();
    defer dfa.deinit();

    try new.concatNfa(&dfa);

    var starts: ArrayList(usize) = try new.getStartStates();
    defer starts.deinit();

    var finishes: ArrayList(usize) = try new.getFinishStates();
    defer finishes.deinit();

    for (finishes.items) |fin| {
        if (fin == base_finish) {
            continue;
        }

        new.states.items[fin].finish = false;
        _ = try new.addTransition(fin, base_finish, null);
        for (starts.items) |start| {
            if (start == base_start) {
                continue;
            }
            _ = try new.addTransition(fin, start, null);
        }
    }

    for (starts.items) |start| {
        if (start == base_start) {
            continue;
        }

        new.states.items[start].start = false;
        _ = try new.addTransition(base_start, start, null);
    }

    return new.toDFA();
}

pub fn NFAAlternate(
    comptime T: type,
    a1: *Automata(T),
    a2: *Automata(T),
    alloc: std.mem.Allocator,
) !Automata(T) {
    var new = Automata(T).new(alloc);

    var base_start = try new.addEmptyState(true, false);
    var base_finish = try new.addEmptyState(false, true);

    var dfa1 = try a1.toDFA();
    defer dfa1.deinit();
    var dfa2 = try a2.toDFA();
    defer dfa2.deinit();

    try new.concatNfa(&dfa1);
    try new.concatNfa(&dfa2);

    var starts: ArrayList(usize) = try new.getStartStates();
    defer starts.deinit();

    var finishes: ArrayList(usize) = try new.getFinishStates();
    defer finishes.deinit();

    for (starts.items) |start| {
        if (start == base_start) {
            continue;
        }
        _ = try new.addTransition(base_start, start, null);
        new.states.items[start].start = false;
    }

    for (finishes.items) |fin| {
        if (fin == base_finish) {
            continue;
        }

        _ = try new.addTransition(fin, base_finish, null);
        new.states.items[fin].finish = false;
    }

    return new;
}
