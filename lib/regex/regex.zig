const std = @import("std");
const ArrayList = std.ArrayList;
const automata = @import("automata");
const nfa = automata.nfa;
const Automata = nfa.Automata(u8);

pub const Regex = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    autom: ?Automata,

    pub fn new(alloc: std.mem.Allocator) Self {
        return .{
            .alloc = alloc,
            .autom = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.autom.?.deinit();
    }

    fn toEscape(chr: u8) u8 {
        return switch (chr) {
            else => chr,
            't' => '\t',
            'n' => '\n',
        };
    }

    fn isOperator(chr: u8) bool {
        return chr == '+' or chr == '*' or chr == '.' or chr == '|';
    }

    fn getPrecedence(chr: u8) u8 {
        return switch (chr) {
            '|' => 1,
            '.' => 2,
            '*', '+' => 3,
            else => 0,
        };
    }

    pub fn preprocess(self: *Self, src: []u8) ![]u8 {
        var result = ArrayList(u8).init(self.alloc);
        defer result.deinit();

        for (0.., src) |i, curChar| {
            if (i + 1 < src.len) {
                var nextChar: u8 = src[i + 1];
                try result.append(curChar);
                if (curChar != '(' and
                    nextChar != ')' and
                    !Self.isOperator(nextChar) and
                    curChar != '|')
                {
                    try result.append('.');
                }
            }
        }
        try result.append(src[src.len - 1]);
        return try result.toOwnedSlice();
    }

    pub fn infixToPostfix(self: *Self, regex: []u8) ![]u8 {
        var stack = ArrayList(u8).init(self.alloc);
        defer stack.deinit();
        var result = ArrayList(u8).init(self.alloc);
        defer result.deinit();
        var res = try self.preprocess(regex);
        defer self.alloc.free(res);

        for (res) |char| {
            switch (char) {
                else => {
                    try result.append(char);
                },
                '(' => {
                    try stack.append(char);
                },
                ')' => {
                    while (stack.items.len > 0 and stack.getLast() != '(') {
                        var operator = stack.pop();
                        try result.append(operator);
                    }
                    if (stack.getLastOrNull() == ')') {
                        _ = stack.pop();
                    }
                },
                '+',
                '*',
                '.',
                '|',
                => {
                    const precedence = Self.getPrecedence(char);
                    while (stack.items.len > 0 and
                        stack.getLastOrNull() != '(' and
                        precedence <= Self.getPrecedence(stack.getLast()))
                    {
                        try result.append(stack.pop());
                    }
                    try stack.append(char);
                },
            }
        }

        while (stack.items.len > 0) {
            var operator = stack.pop();
            if (operator == '(') {
                continue;
            }
            try result.append(operator);
        }

        return try result.toOwnedSlice();
    }

    pub fn compile(self: *Self, src: []u8) !void {
        if (self.autom != null) {
            self.autom.?.deinit();
        }

        var res = try self.infixToPostfix(src);
        defer self.alloc.free(res);

        var stack = ArrayList(Automata).init(self.alloc);
        defer stack.deinit();

        var isEscape: bool = false;

        outer: for (res) |sym| {
            if (isEscape) {
                try stack.append(
                    try Automata.newBasic(self.alloc, Self.toEscape(sym)),
                );
                isEscape = false;
                continue :outer;
            }

            isEscape = sym == '\\';

            switch (sym) {
                // Do nothing with the escape symbol
                // Should '\' actually be appended,
                // It would be done with "\\", and
                // thus pushed in the isEscape if clause
                '\\' => {},

                '.' => {
                    var singleSymbolAutomata = stack.pop();
                    defer singleSymbolAutomata.deinit();
                    var concatAutomata = stack.pop();
                    defer concatAutomata.deinit();

                    var newAutomata = try nfa.NFAConcat(
                        u8,
                        &concatAutomata,
                        &singleSymbolAutomata,
                        self.alloc,
                    );
                    try stack.append(newAutomata);
                },

                '|' => {
                    var singleSymbolAutomata = stack.pop();
                    defer singleSymbolAutomata.deinit();
                    var concatAutomata = stack.pop();
                    defer concatAutomata.deinit();

                    var newAutomata = try nfa.NFAAlternate(
                        u8,
                        &concatAutomata,
                        &singleSymbolAutomata,
                        self.alloc,
                    );
                    try stack.append(newAutomata);
                },

                '*' => {
                    var prev = stack.pop();
                    defer prev.deinit();
                    var newAutomata = try nfa.NFAKleenee(u8, &prev, self.alloc);
                    try stack.append(newAutomata);
                },

                '+' => {
                    var prev = stack.pop();
                    defer prev.deinit();
                    var newAutomata = try nfa.NFAPlus(u8, &prev, self.alloc);
                    try stack.append(newAutomata);
                },

                else => {
                    try stack.append(
                        try Automata.newBasic(self.alloc, sym),
                    );
                },
            }
        }

        if (stack.items.len != 1) {
            while (stack.items.len > 0) {
                var autom = stack.pop();
                autom.deinit();
            }
            return error.BadSyntax;
        }

        var preDFA = stack.pop();
        defer preDFA.deinit();
        self.autom = try preDFA.toDFA();
    }

    pub fn match(self: *Self, str: []u8) bool {
        if (self.autom == null) {
            return false;
        }

        var curState: ?*const nfa.AutomataState(u8) = null;
        for (self.autom.?.states.items) |state| {
            if (state.start) {
                curState = &state;
                break;
            }
        }
        if (curState == null) {
            return false;
        }

        for (str) |char| {
            var foundTransition = false;
            for (curState.?.transitions.items) |trans| {
                if (trans.symbol == char) {
                    curState = &self.autom.?.states.items[trans.dest];
                    foundTransition = true;
                    break;
                }
            }
            if (!foundTransition) {
                return false;
            }
        }
        return true;
    }
};

test "Convert to postfix" {
    var buf: [128]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buf);
    var allocator = alloc.allocator();

    var x = "(adc|b)*".*;

    var re = Regex.new(allocator);
    std.debug.print("\n{s}\n", .{try re.infixToPostfix(&x)});
    try re.compile(&x);
}
