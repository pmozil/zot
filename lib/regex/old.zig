const std = @import("std");
const ArrayList = std.ArrayList;

const Actions = enum(usize) {
    Stop,
    Jump,
    Match,
    Branch,
    Lparen = 128,
    Rparen,
    Altern,
    Concat,
    Kleenee,
};

const Instruction = struct {
    const Self = @This();

    operand: usize,
    address: usize,

    pub fn new(op: usize, addr: usize) Self {
        return Self{
            .operand = op,
            .address = addr,
        };
    }
};

const Regex = struct {
    const Self = @This();

    alloc: *std.mem.Allocator,
    instructions: ArrayList(Instruction),

    pub fn init(alloc: *std.mem.Allocator) Self {
        return Self{
            .alloc = alloc,
            .instructions = ArrayList(Instruction).init(alloc.*),
        };
    }

    pub fn deinit(self: *Self) void {
        self.instructions.deinit();
    }

    fn prepare(self: *Self, src: []u8) !ArrayList(usize) {
        var escape: []usize = try self.alloc.alloc(usize, 128);
        var dest: ArrayList(usize) = ArrayList(usize).init(self.alloc.*);
        var concat: bool = false;
        var parens: usize = 0;

        escape['n'] = '\n';
        escape['r'] = '\r';
        escape['t'] = '\t';
        escape['\\'] = 0;
        for ("\"()*\\|") |char| {
            escape[char] = char;
        }

        for (0.., src) |i, char| {
            switch (char) {
                '(' => {
                    try dest.append(@intFromEnum(Actions.Lparen));
                    concat = false;
                    parens += 1;
                },
                ')' => {
                    try dest.append(@intFromEnum(Actions.Rparen));
                    if (parens == 0) {
                        return error.MismatchedParentheses;
                    }
                    parens -= 1;
                },
                '*' => {
                    try dest.append(@intFromEnum(Actions.Kleenee));
                },
                '|' => {
                    try dest.append(@intFromEnum(Actions.Altern));
                    concat = false;
                },
                '\\' => {
                    if (i + 1 >= src.len) {
                        return error.Unparsable;
                    }
                    try dest.append(escape[src[i + 1]]);
                },
                else => {
                    if (concat) {
                        try dest.append(@intFromEnum(Actions.Concat));
                    }
                    try dest.append(char);
                },
            }
            concat = true;
        }
        try dest.append(@intFromEnum(Actions.Rparen));

        return dest;
    }

    fn toReversePolish(self: *Self, src: []u8) ![]usize {
        var dest = try self.prepare(src);
        defer dest.deinit();
        var result = try dest.toOwnedSlice();

        var stack: ArrayList(usize) = ArrayList(usize).init(self.alloc.*);
        defer stack.deinit();

        var j: usize = 0;
        var i: usize = 0;

        try stack.append(@intFromEnum(Actions.Lparen));

        while (i < result.len) {
            var sym = result[i];
            i += 1;

            switch (sym) {
                @intFromEnum(Actions.Lparen) => {
                    try stack.append(sym);
                },

                @intFromEnum(Actions.Rparen) => {
                    while (sym <= stack.items[stack.items.len - 1]) {
                        result[j] = stack.pop();
                        j += 1;
                    }
                    _ = stack.pop();
                },

                @intFromEnum(Actions.Altern),
                @intFromEnum(Actions.Concat),
                @intFromEnum(Actions.Kleenee),
                => {
                    while (sym <= stack.items[stack.items.len - 1]) {
                        result[j] = stack.pop();
                        j += 1;
                    }
                    try stack.append(sym);
                },

                else => {
                    result[j] = sym;
                    j += 1;
                },
            }
        }

        return result[0..(j + 1)];
    }

    pub fn compile(self: *Self, src: []u8) !void {
        var stack: ArrayList(usize) = ArrayList(usize).init(self.alloc.*);
        defer stack.deinit();

        var res = try self.toReversePolish(src);
        defer self.alloc.free(res);
        var code: []Instruction = try self.alloc.alloc(Instruction, 5 * res.len / 2);
        defer self.alloc.free(code);
        var pc: usize = 0;

        for (res) |sym| {
            switch (sym) {
                else => {
                    try stack.append(pc);
                    code[pc] = Instruction.new(
                        @intFromEnum(Actions.Jump),
                        pc + 2,
                    );
                    pc += 1;
                    code[pc] = Instruction.new(
                        @intFromEnum(Actions.Match),
                        sym,
                    );
                    pc += 1;
                },

                @intFromEnum(Actions.Concat) => {
                    _ = stack.pop();
                },

                @intFromEnum(Actions.Kleenee) => {
                    code[pc] = Instruction.new(@intFromEnum(Actions.Branch), '*');
                    pc += 1;
                    code[pc] = code[stack.items[stack.items.len - 1]];
                    pc += 1;
                    code[stack.items[stack.items.len - 1]] = Instruction.new(
                        @intFromEnum(Actions.Jump),
                        pc - 2,
                    );
                },

                @intFromEnum(Actions.Altern) => {
                    code[pc] = Instruction.new(
                        @intFromEnum(Actions.Jump),
                        pc + 5,
                    );
                    pc += 1;
                    code[pc] = Instruction.new(
                        @intFromEnum(Actions.Branch),
                        '|',
                    );
                    pc += 1;
                    code[pc] = code[stack.items[stack.items.len - 1]];
                    pc += 1;
                    code[pc] = code[stack.items[stack.items.len - 2]];
                    pc += 1;

                    code[stack.items[stack.items.len - 2]] = Instruction.new(
                        @intFromEnum(Actions.Jump),
                        pc - 3,
                    );
                    code[stack.items[stack.items.len - 1]] = Instruction.new(
                        @intFromEnum(Actions.Jump),
                        pc,
                    );
                },
            }
        }
        code[pc] = Instruction.new(@intFromEnum(Actions.Stop), pc);
        pc += 1;

        try self.instructions.appendSlice(code[0..pc]);
    }

    pub fn match(self: *Self, src: []u8) !bool {
        var c: usize = src[0];
        var i: usize = 1;
        var pc: usize = 0;
        var shift: usize = 0;

        var nlist: ArrayList(usize) = ArrayList(usize).init(self.alloc.*);
        defer nlist.deinit();

        var clist: ArrayList(usize) = ArrayList(usize).init(self.alloc.*);
        defer clist.deinit();

        while (i <= src.len) {
            std.debug.print("c = {}\n", .{c});
            switch (self.instructions.items[pc].operand) {
                @intFromEnum(Actions.Stop) => {},

                @intFromEnum(Actions.Jump) => {
                    pc = self.instructions.items[pc].address;
                    continue;
                },

                @intFromEnum(Actions.Match) => {
                    if (c == self.instructions.items[pc].address) {
                        try nlist.append(self.instructions.items[pc + 1].address);
                    }
                },

                @intFromEnum(Actions.Branch) => {
                    try clist.append(self.instructions.items[pc + 1].address);
                    pc = self.instructions.items[pc + 2].address;
                    continue;
                },

                else => {},
            }

            if (shift == clist.items.len) {
                if (nlist.items.len == 0) {
                    return false;
                }

                shift = 0;
                clist.clearAndFree();

                while (nlist.items.len > 0) {
                    try clist.append(nlist.pop());
                }

                if (src.len > i) {
                    c = src[i];
                }

                i += 1;
            }

            pc = clist.items[shift];
            shift += 1;
        }

        i = shift;
        while (i < clist.items.len) : (i += 1) {
            if (self.instructions.items[clist.items[i]].operand == @intFromEnum(Actions.Stop)) {
                return true;
            }
        }

        return self.instructions.items[pc].operand == @intFromEnum(Actions.Stop);
    }
};

test "Regex construction" {
    var alloc = std.heap.page_allocator;
    var re = Regex.init(&alloc);
    defer re.deinit();
    std.debug.print("\n", .{});

    var x = [_]u8{ 'a', 'b', 'c' };
    try re.compile(&x);
    std.debug.print("\nMatch {s}: {}\n", .{ x, try re.match(&x) });
    var y = [_]u8{ 'a', 'b', 'c', 'd' };
    std.debug.print("\nMatch {s}: {}\n", .{ y, try re.match(&y) });
    var u = [_]u8{ 'a', 'b', 'c', 'a', 'b', 'c' };
    std.debug.print("\nMatch {s}: {}\n", .{ u, try re.match(&u) });

    var re1 = Regex.init(&alloc);
    defer re1.deinit();
    var t = "(a|b)*a".*;
    try re1.compile(&t);
    var h = "abababaa".*;
    std.debug.print("\nMatch {s}: {}\n", .{ h, try re.match(&h) });
}
