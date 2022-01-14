const std = @import("std");
const expect = std.testing.expect;
const RndGen = std.rand.DefaultPrng;
const Stdout = std.io.getStdOut();

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
    x: usize,
    y: usize,
    state: State,
    pub fn isEquals(self: @This(), xy: Cell) bool {
        return self.x == xy.x and self.y == xy.y;
    }
};

fn Grid() type {
    return struct {
        const Self = @This();
        cells: [][]Cell = undefined,
        rows: usize,
        cols: usize,

        pub fn size(self: Self) usize {
            return self.rows * self.cols;
        }

        pub fn rawPrint(self: Self) !void {
            var out = std.io.getStdOut().writer();
            try out.print("\n", .{});
            for (self.cells) |cells| {
                for (cells) |*cell| {
                    try out.print("{s}", .{cell.state.toCharacter()});
                }
                try out.print("\n", .{});
            }
        }

        pub fn init(rows: usize, cols: usize, allocator: std.mem.Allocator) !Self {
            var self = Grid(){ .rows = rows, .cols = cols };
            self.cells = try allocator.alloc([]Cell, rows);
            for (self.cells) |*row, j| {
                row.* = try allocator.alloc(Cell, rows);
                for (row.*) |*r, i| {
                    r.x = i;
                    r.y = j;
                    r.state = .open;
                }
            }
            return self;
        }

        fn random(rows: usize, cols: usize, spareness: f32) Self {
            var grid = Grid.init(rows, cols);
            var rnd = RndGen.init(0);
            for (grid.cells) |cells| {
                for (cells) |*cell| {
                    if (rnd.random().float(f32) < spareness) {
                        cell.state = .blocked;
                    }
                }
            }
            return grid;
        }

        fn binaryTree(rows: usize, cols: usize) Self {
            var grid = Grid().init(rows, cols);
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
                        neighbors[neighborCount] = grid.cells[i][j + 1];
                        neighborCount += 1;
                    }

                    if (neighborCount == 2) {
                        const idx = (rnd.random().int(usize) % neighborCount) ^ 1;
                        const n = neighbors[idx];
                        grid.cells[n.xy.y][n.xy.x] = .blocked;
                        neighborCount = 0;
                    }
                }
                j = 0;
            }
            return grid;
        }

        fn dfs(self: Self, start: Cell, goal: Cell, allocator: std.mem.Allocator) ![]const Cell {
            var frontier = std.ArrayList(Cell).init(allocator);
            try frontier.append(start);
            var explored = std.ArrayList(Cell).init(allocator);
            var currentCell: ?Cell = frontier.popOrNull();
            var memberFound = false;
            var route = std.ArrayList(Cell).init(allocator);
            while (currentCell) |cell| : (currentCell = frontier.popOrNull()) {
                if (cell.isEquals(goal)) {
                    try route.insert(0, cell);
                    return route.toOwnedSlice();
                }
                for (try self.successor(cell.x, cell.y, allocator)) |child| {
                    for (explored.items) |member| {
                        if (member.x == child.x and member.y == child.y) {
                            memberFound = true;
                            break;
                        }
                    }

                    if (!memberFound) {
                        try explored.append(child);
                        try route.insert(0, cell);
                        try frontier.append(child);
                    }
                }
                memberFound = false;
            }
            return undefined;
        }

        fn bfs(self: Self, start: Cell, goal: Cell, allocator: std.mem.Allocator) ![]const Cell {
            var frontier = std.ArrayList(Cell).init(allocator);
            try frontier.append(start);
            var explored = std.ArrayList(Cell).init(allocator);
            var currentCell: ?Cell = frontier.popOrNull();
            var memberFound = false;
            var route = std.ArrayList(Cell).init(allocator);
            while (currentCell) |cell| : (currentCell = frontier.popOrNull()) {
                if (cell.isEquals(goal)) {
                    try route.insert(0, cell);
                    return route.toOwnedSlice();
                }
                for (try self.successor(cell.x, cell.y, allocator)) |child| {
                    for (explored.items) |member| {
                        if (member.x == child.x and member.y == child.y) {
                            memberFound = true;
                            break;
                        }
                    }

                    if (!memberFound) {
                        try explored.append(child);
                        try route.insert(0, cell);
                        try frontier.insert(0, child);
                    }
                }
                memberFound = false;
            }
            return undefined;
        }

        fn successor(self: Self, x: usize, y: usize, allocator: std.mem.Allocator) ![]Cell {
            var cells = std.ArrayList(Cell).init(allocator);
            if (y + 1 < self.cells.len and self.cells[y + 1][x].state != .blocked) {
                try cells.append(self.cells[y + 1][x]);
            }

            if (y > 0 and self.cells[y - 1][x].state != .blocked) {
                try cells.append(self.cells[y - 1][x]);
            }
            if (x + 1 < self.cells[0].len and self.cells[y][x + 1].state != .blocked) {
                try cells.append(self.cells[y][x + 1]);
            }
            if (x > 0 and self.cells[y][x - 1].state != .blocked) {
                try cells.append(self.cells[y][x - 1]);
            }
            return cells.items;
        }

        pub fn markPath(self: *Self, cells: []const Cell) void {
            var start = cells[cells.len - 1];
            var goal = cells[0];
            self.cells[goal.y][goal.x].state = .goal;
            for (cells[1 .. cells.len - 1]) |cell| {
                self.cells[cell.y][cell.x].state = .path;
            }
            self.cells[start.y][start.x].state = .start;
        }

        pub fn reset(self: *Self) void {
            for (self.cells) |cells| {
                for (cells) |*cell| {
                    cell.state = .open;
                }
            }
        }
    };
}

test "grid default" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = arena.allocator();
    const grid = try Grid().init(4, 4, a);
    try expect(grid.rows == 4 and grid.cols == 4);
}

test "grid successor" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = arena.allocator();
    //    var out = std.io.getStdOut().writer();

    // A Grid thats open errwhere
    // Start at (0,0), successor should be 2, (0,1) and (1,0)
    const grid = try Grid().init(4, 4, a);
    var succs = try grid.successor(0, 0, a);

    try expect(succs.len == 2);
    try expect(succs[0].x == 0 and succs[0].y == 1);
    try expect(succs[1].x == 1 and succs[1].y == 0);

    // Start at (1,1), successors should be 4,
    // (1,2), (1,0), (2,1), and (0,1)
    succs = try grid.successor(1, 1, a);
    try expect(succs.len == 4);
    try expect(succs[0].x == 1 and succs[0].y == 2);
    try expect(succs[1].x == 1 and succs[1].y == 0);
    try expect(succs[2].x == 2 and succs[2].y == 1);
    try expect(succs[3].x == 0 and succs[3].y == 1);
}

test "grid markPath" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = arena.allocator();
    var xys = [_]Cell{ Cell{ .x = 2, .y = 2, .state = .goal }, Cell{ .x = 2, .y = 1, .state = .path }, Cell{ .x = 1, .y = 1, .state = .path }, Cell{ .x = 1, .y = 0, .state = .path }, Cell{ .x = 1, .y = 0, .state = .path }, Cell{ .x = 0, .y = 0, .state = .start } };
    var grid = try Grid().init(4, 4, a);
    grid.markPath(&xys);

    try expect(@enumToInt(grid.cells[0][0].state) == @enumToInt(State.start));
    try expect(@enumToInt(grid.cells[0][1].state) == @enumToInt(State.path));
    try expect(@enumToInt(grid.cells[1][1].state) == @enumToInt(State.path));
    try expect(@enumToInt(grid.cells[1][2].state) == @enumToInt(State.path));
    try expect(@enumToInt(grid.cells[2][2].state) == @enumToInt(State.goal));
}

test "grid reset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = arena.allocator();
    var xys = [_]Cell{ Cell{ .x = 2, .y = 2, .state = .goal }, Cell{ .x = 2, .y = 1, .state = .path }, Cell{ .x = 1, .y = 1, .state = .path }, Cell{ .x = 1, .y = 0, .state = .path }, Cell{ .x = 1, .y = 0, .state = .path }, Cell{ .x = 0, .y = 0, .state = .start } };
    var grid = try Grid().init(4, 4, a);
    grid.markPath(&xys);

    grid.reset();
    try expect(@enumToInt(grid.cells[0][0].state) == @enumToInt(State.open));
    try expect(@enumToInt(grid.cells[2][2].state) == @enumToInt(State.open));
}

test "grid dfs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = arena.allocator();
    const start = Cell{ .x = 0, .y = 0, .state = .start };
    const goal = Cell{ .x = 1, .y = 1, .state = .goal };
    var grid = try Grid().init(4, 4, a);
    const solution = try grid.dfs(start, goal, a);
    grid.markPath(solution);
    try grid.rawPrint();
}

test "grid bfs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = arena.allocator();
    const start = Cell{ .x = 0, .y = 0, .state = .start };
    const goal = Cell{ .x = 1, .y = 1, .state = .goal };
    var grid = try Grid().init(4, 4, a);
    const solution = try grid.bfs(start, goal, a);
    grid.markPath(solution);
    try grid.rawPrint();
}
