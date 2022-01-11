const std = @import("std");
const expect = std.testing.expect;
const RndGen = std.rand.DefaultPrng;
const Stdout = std.io.getStdOut();

const XY = packed struct {
    x: usize,
    y: usize,

    pub fn isEquals(self: @This(), xy: XY) bool {
        return self.x == xy.x and self.y == xy.y;
    }

    //pub fn euclidian(self: @This(), xy: XY) usize {

    // }

    // pub fn manhattan(self: @This(), xy: XY) usize {

    //}

};

const State = enum(u8) {
    open,
    blocked,
    path,
    start,
    goal,

    pub fn toCharacter(self: State) []const u8 {
        const char = switch (self) {
            .open => "O",
            .blocked => "B",
            .path => "P",
            .start => "S",
            .goal => "G",
        };
        return char;
    }
};

const Cell = packed struct {
    xy: XY,
    state: State,
};

const Node = packed struct {
    current: ?*Cell,
    parent: ?*Node,
    cost: usize,
    heuristic: usize,

    pub fn hashValue(self: @This()) usize {
        return self.cost + self.heuristic;
    }
};

fn Stack(comptime T: type) type {
    return packed struct {
        const Self = @This();
        container: std.ArrayList(T),

        fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .container = std.ArrayList(T).init(allocator),
            };
        }

        pub fn isEmpty(self: Self) bool {
            return self.container.items.len == 0;
        }

        pub fn push(self: Self, value: T) !void {
            try self.container.append(value);
        }

        pub fn pop(self: Self) !T {
            return try self.container.pop();
        }
    };
}

fn Queue(comptime T: type) type {
    return packed struct {
        const Self = @This();
        container: std.ArrayList(T),

        fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .container = std.ArrayList(T).init(allocator),
            };
        }

        pub fn isEmpty(self: Self) bool {
            return self.container.items.len == 0;
        }

        pub fn push(self: Self, value: T) void {
            self.container.append(value);
        }

        pub fn pop(self: Self) T {
            return self.container.orderedRemove(0);
        }
    };
}

fn Grid(comptime rows: usize, comptime cols: usize) type {
    return packed struct {
        const Self = @This();
        cells: [rows][cols]Cell,
        rows: usize = rows,
        cols: usize = cols,

        pub fn size(self: Self) usize {
            _ = self;
            return rows * cols;
        }

        pub fn rawPrint(self: Self) !void {
            var out = std.io.getStdOut().writer();
            var i: usize = 0;
            var j: usize = 0;
            try out.print("\n", .{});
            while (i < rows) : (i += 1) {
                while (j < cols) : (j += 1) {
                    try out.print("{s}", .{self.cells[i][j].state.toCharacter()});
                }
                j = 0;
                try out.print("\n", .{});
            }
        }

        pub fn default() Self {
            var cells = init: {
                var initial_value: [rows][cols]Cell = undefined;
                for (initial_value) |*pts, i| {
                    for (pts) |*pt, j| {
                        pt.* = Cell{
                            .xy = XY{
                                .x = j,
                                .y = i,
                            },
                            .state = .open,
                        };
                    }
                }
                break :init initial_value;
            };
            return Self{ .cells = cells };
        }

        fn spareness(spare: f32) Self {
            var grid = default();
            var i: usize = 0;
            var j: usize = 0;
            var rnd = RndGen.init(0);
            while (i < rows) : (i += 1) {
                while (j < cols) : (j += 1) {
                    if (rnd.random().float(f32) < spare) {
                        grid.cells[i][j].state = .blocked;
                    }
                }
                j = 0;
            }
            return grid;
        }

        fn binaryTree() Self {
            var grid = default();
            var i: usize = 0;
            var j: usize = 0;
            var rnd = RndGen.init(0);
            var neighborCount = 0;
            var neighbors: [2]Cell = undefined;
            while (i < rows) : (i += 1) {
                while (j < cols) : (j += 1) {
                    neighbors = undefined;
                    if (i - 1 > 0) {
                        neighbors[neighborCount] = grid.cells[i - 1][j];
                        neighborCount += 1;
                    }
                    if (j + 1 < cols) {
                        neighbors[neighborCount] = grid.cells[i - 1][j];
                        neighborCount += 1;
                    }
                    if (neighborCount > 0) {
                        const idx = rnd.random().int(usize) % neighborCount;
                        const n = neighbors[idx];
                        grid.cells[n.xy.y][n.xy.x] = .blocked;
                        neighborCount = 0;
                    }
                }
                j = 0;
            }
            return grid;
        }

        fn dfs(self: Self, comptime start: Cell, comptime goal: Cell, allocator: std.mem.Allocator) !?Node {
            var frontier = Stack(Node).init(allocator);
            frontier.push(Node{ .current = start });
            var explored = std.ArrayList(Node).init(allocator);
            var currentNode: Node = undefined;
            var nodeLink: Node = undefined;
            var memberFound = false;

            while (frontier.isEmpty() == false) : (currentNode = frontier.pop()) {
                if (self.isGoal(currentNode, goal)) {
                    nodeLink = currentNode;
                    break;
                }
                for (self.successor(currentNode)) |child| {
                    for (explored) |member| {
                        if (member.isEquals(child)) {
                            memberFound = true;
                            break;
                        }
                    }

                    if (!memberFound) {
                        try explored.append(child);
                        try frontier.push(Node{ .current = child, .parent = currentNode });
                    } else {
                        memberFound = false;
                    }
                }
            }
            return nodeLink;
        }

        fn pathToGoal(self: Self, node: *Node, allocator: std.mem.Allocator) ![]const XY {
            _ = self;
            var xys = std.ArrayList(XY).init(allocator);
            var currentNode: ?*Node = node;
            while (currentNode != null) : (currentNode = currentNode.?.parent) {
                try xys.insert(0, currentNode.?.current.?.xy);
            }
            return xys.toOwnedSlice();
        }

        fn successor(self: Self, cell: Cell, allocator: std.mem.Allocator) ![]const Cell {
            var cells = std.ArrayList(Cell).init(allocator);
            if (cell.xy.y + 1 < rows and self.cells[cell.xy.y + 1][cell.xy.x].state != .blocked) {
                try cells.append(self.cells[cell.xy.y + 1][cell.xy.x]);
            }
            if (cell.xy.y > 0 and self.cells[cell.xy.y - 1][cell.xy.x].state != .blocked) {
                try cells.append(self.cells[cell.xy.y - 1][cell.xy.x]);
            }
            if (cell.xy.x + 1 < cols and self.cells[cell.xy.y][cell.xy.x + 1].state != .blocked) {
                try cells.append(self.cells[cell.xy.y][cell.xy.x + 1]);
            }
            if (cell.xy.x > 0 and self.cells[cell.xy.y][cell.xy.x - 1].state != .blocked) {
                try cells.append(self.cells[cell.xy.y][cell.xy.x - 1]);
            }
            return cells.toOwnedSlice();
        }

        pub fn markPath(self: *Self, xys: []XY, start: Cell, goal: Cell) void {
            for (xys) |xy| {
                self.cells[xy.y][xy.x].state = .path;
            }
            self.cells[start.xy.y][start.xy.x].state = .start;
            self.cells[goal.xy.y][goal.xy.x].state = .goal;
        }

        pub fn reset(self: *Self) void {
            for (self.cells) |*cells| {
                for (cells) |*cell| {
                    cell.state = .open;
                }
            }
        }
    };
}

test "grid default" {
    const grid = Grid(4, 4).default();
    try expect(grid.rows == 4 and grid.cols == 4);
}

test "grid successor" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = arena.allocator();
    //    var out = std.io.getStdOut().writer();

    // A Grid thats open errwhere
    // Start at (0,0), successor should be 2, (0,1) and (1,0)
    const grid = Grid(4, 4).default();
    var succs = try grid.successor(grid.cells[0][0], a);

    try expect(succs.len == 2);
    try expect(succs[0].xy.x == 0 and succs[0].xy.y == 1);
    try expect(succs[1].xy.x == 1 and succs[1].xy.y == 0);

    // Start at (1,1), successors should be 4,
    // (1,2), (1,0), (2,1), and (0,1)
    succs = try grid.successor(grid.cells[1][1], a);
    try expect(succs.len == 4);
    try expect(succs[0].xy.x == 1 and succs[0].xy.y == 2);
    try expect(succs[1].xy.x == 1 and succs[1].xy.y == 0);
    try expect(succs[2].xy.x == 2 and succs[2].xy.y == 1);
    try expect(succs[3].xy.x == 0 and succs[3].xy.y == 1);
}

test "grid pathToGoal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = arena.allocator();
    var cell1 = Cell{ .xy = XY{ .x = 2, .y = 1 }, .state = .open };
    var cell2 = Cell{ .xy = XY{ .x = 1, .y = 1 }, .state = .open };
    var cell3 = Cell{ .xy = XY{ .x = 1, .y = 0 }, .state = .open };
    var cell4 = Cell{ .xy = XY{ .x = 0, .y = 0 }, .state = .open };

    var node: Node = Node{
        .cost = 0,
        .heuristic = 0,
        .current = &cell1,
        .parent = &Node{
            .cost = 0,
            .heuristic = 0,
            .current = &cell2,
            .parent = &Node{
                .cost = 0,
                .heuristic = 0,
                .current = &cell3,
                .parent = &Node{
                    .cost = 0,
                    .heuristic = 0,
                    .current = &cell4,
                    .parent = null,
                },
            },
        },
    };

    const grid = Grid(4, 4).default();
    var xys = try grid.pathToGoal(&node, a);
    try expect(xys.len == 4);
    try expect(xys[0].x == 0 and xys[0].y == 0);
    try expect(xys[1].x == 1 and xys[1].y == 0);
    try expect(xys[2].x == 1 and xys[2].y == 1);
    try expect(xys[3].x == 2 and xys[3].y == 1);
}

test "grid markPath" {
    var xys = [_]XY{ XY{ .x = 2, .y = 2 }, XY{ .x = 2, .y = 1 }, XY{ .x = 1, .y = 1 }, XY{ .x = 1, .y = 0 }, XY{ .x = 0, .y = 0 } };
    var start = Cell{ .xy = XY{ .x = 0, .y = 0 }, .state = .start };
    var goal = Cell{ .xy = XY{ .x = 2, .y = 2 }, .state = .goal };
    var grid = Grid(4, 4).default();
    grid.markPath(
        &xys,
        start,
        goal,
    );

    try expect(@enumToInt(grid.cells[0][0].state) == @enumToInt(State.start));
    try expect(@enumToInt(grid.cells[0][1].state) == @enumToInt(State.path));
    try expect(@enumToInt(grid.cells[1][1].state) == @enumToInt(State.path));
    try expect(@enumToInt(grid.cells[1][2].state) == @enumToInt(State.path));
    try expect(@enumToInt(grid.cells[2][2].state) == @enumToInt(State.goal));
}

test "grid reset" {
    var start = Cell{ .xy = XY{ .x = 0, .y = 0 }, .state = .start };
    var goal = Cell{ .xy = XY{ .x = 2, .y = 2 }, .state = .goal };
    var xys = [_]XY{ XY{ .x = 2, .y = 2 }, XY{ .x = 2, .y = 1 } };
    var grid = Grid(4, 4).default();
    grid.markPath(
        &xys,
        start,
        goal,
    );

    grid.reset();
    try expect(@enumToInt(grid.cells[0][0].state) == @enumToInt(State.open));
    try expect(@enumToInt(grid.cells[2][2].state) == @enumToInt(State.open));
}

test "grid dfs" {}
