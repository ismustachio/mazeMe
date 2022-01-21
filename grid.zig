const std = @import("std");
const expect = std.testing.expect;
const RndGen = std.rand.DefaultPrng;
const Stdout = std.io.getStdOut();

const CellErrors = error{
    Invalid,
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

const Cell = struct {
    const Self = @This();
    x: usize,
    y: usize,
    north: ?*Cell = undefined,
    south: ?*Cell = undefined,
    west: ?*Cell = undefined,
    east: ?*Cell = undefined,
    links: std.AutoHashMap(Cell, bool),
    allocator: std.mem.Allocator,

    pub fn init(x: usize, y: usize, allocator: std.mem.Allocator) type {
        return Self{
            .x = x,
            .y = y,
            .allocator = allocator,
            .links = std.AutoHashMap(Cell, bool).init(allocator),
        };
    }

    pub fn link(self: *Self, cell: *Cell, bidi: bool) !void {
        try self.links.put(cell.*, true);
        if (bidi) {
            try cell.links.put(self.*, true);
        }
    }

    pub fn unlink(self: *Self, cell: *Cell, bidi: bool) !void {
        try self.links.remove(cell);
        if (bidi) {
            try cell.links.remove(self);
        }
    }

    pub fn keys(self: Self) []Cell() {
        return self.links.keys;
    }

    pub fn isLinked(self: Self, cell: Cell) ?bool {
        return self.links.get(cell);
    }

    pub fn isEquals(self: Self, xy: Cell) bool {
        return self.x == xy.x and self.y == xy.y;
    }

    pub fn neighbors(self: Self) []Cell() {
        var neigh = std.ArrayList(Cell).init(self.allocator);
        if (self.north != null) |north| {
            neigh.append(north);
        }
        if (self.south != null) |south| {
            neigh.append(south);
        }
        if (self.west != null) |west| {
            neigh.append(west);
        }
        if (self.east != null) |east| {
            neigh.append(east);
        }
        return neigh.toOwnedSlice();
    }
};

const BinaryTree = struct {
    pub fn on(grid: *Grid()) !void {
        var rnd = RndGen.init(0);
        var neighborCount: usize = 0;
        var neighbors: [2]?*Cell = undefined;
        for (grid.cells) |cells| {
            for (cells) |cell| {
                neighbors = undefined;
                if (cell.?.north != null) {
                    neighbors[neighborCount] = cell.?.north;
                    neighborCount += 1;
                }
                if (cell.?.east != null) {
                    neighbors[neighborCount] = cell.?.east;
                    neighborCount += 1;
                }
                if (neighborCount > 0) {
                    const idx = (rnd.random().int(usize) % neighborCount);
                    const n = neighbors[idx];
                    if (n != null) {
                        try cell.?.link(n.?, true);
                    }
                }
                neighborCount = 0;
            }
        }
    }
};

fn Grid() type {
    return struct {
        const Self = @This();
        cells: [][]?*Cell = undefined,
        allocator: std.mem.Allocator,
        rows: usize,
        cols: usize,

        pub fn size(self: Self) usize {
            return self.rows * self.cols;
        }

        pub fn pretty_print(self: Self, allocator: std.mem.Allocator) !void {
            var buffer = std.ArrayList([]const u8).init(allocator);
            var top = std.ArrayList([]const u8).init(allocator);
            var bottom = std.ArrayList([]const u8).init(allocator);
            var i: usize = 0;
            var j: usize = 0;
            var east_boundary: []const u8 = " ";
            var south_boundary: []const u8 = "   ";
            var out = std.io.getStdOut().writer();
            try buffer.append("+");
            while (i < self.cols) : (i += 1) {
                try buffer.append("---+");
            }
            try buffer.append("\n");
            i = 0;
            for (self.cells) |cells| {
                try top.append("|");
                try bottom.append("+");
                for (cells) |cell| {
                    if (cell.?.isLinked(cell.?.east.?.*).?) {
                        east_boundary = " ";
                    } else {
                        east_boundary = "|";
                    }
                    try top.append("   ");
                    try top.append(east_boundary);
                    if (cell.?.isLinked(cell.?.south.?.*).?) {
                        south_boundary = "   ";
                    } else {
                        south_boundary = "---";
                    }
                    try bottom.append(south_boundary);
                    try bottom.append("+");
                }
                for (top.items) |t| {
                    try buffer.append(t);
                }
                try buffer.append("\n");
                for (bottom.items) |b| {
                    try buffer.append(b);
                }
                try buffer.append("\n");
                top.clearAndFree();
                bottom.clearAndFree();
                j = 0;
            }

            try out.print("\n", .{});
            for (buffer.items) |buf| {
                try out.print("{s}", .{buf});
            }
        }

        pub fn init(rows: usize, cols: usize, allocator: std.mem.Allocator) !Self {
            var self = Grid(){ .rows = rows, .cols = cols, .allocator = allocator };
            self.cells = try allocator.alloc([]?*Cell, rows);
            for (self.cells) |*row| {
                row.* = try allocator.alloc(?*Cell, cols);
                for (row.*) |r| {
                    r.?.*.x = 0;
                    r.?.*.y = 0;
                    r.?.*.allocator = allocator;
                    r.?.*.links = std.AutoHashMap(Cell, bool).init(allocator);
                }
            }
            self.configure_grid();
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.cells);
        }

        fn configure_grid(self: *Self) void {
            for (self.cells) |*row| {
                for (row.*) |cell| {
                    var y = cell.?.y;
                    var x = cell.?.x;
                    if (y - 1 > 0) {
                        cell.?.north = self.cells[y - 1][x];
                    }
                    if (y + 1 > 0) {
                        cell.?.south = self.cells[y + 1][x];
                    }
                    if (x - 1 > 0) {
                        cell.?.west = self.cells[y][x - 1];
                    }
                    if (x + 1 > 0) {
                        cell.?.east = self.cells[y][x + 1];
                    }
                }
            }
        }

        pub fn random_cell(self: Self) Cell() {
            var rnd = RndGen.init(0);
            var rows = rnd.random().int(usize) % self.rows;
            var cols = rnd.random().int(usize) % self.cols;
            return self.cells[rows][cols];
        }

        //fn random(rows: usize, cols: usize, spareness: f32, allocator: std.mem.Allocator) !Self {
        //   var grid = try Grid().init(rows, cols, allocator);
        //  var rnd = RndGen.init(0);
        // for (grid.cells) |cells| {
        //    for (cells) |*cell| {
        //       if (rnd.random().float(f32) < spareness) {
        //          cell.state = .open;
        //     }
        //  }
        // }
        // return grid;
        // }

        //fn dfs(self: Self, start: Cell, goal: Cell, allocator: std.mem.Allocator) !?[]const Cell {
        //    var frontier = std.ArrayList(Cell).init(allocator);
        //    try frontier.append(start);
        //    var explored = std.ArrayList(Cell).init(allocator);
        //    var currentCell: ?Cell = frontier.popOrNull();
        //    var route = std.ArrayList(Cell).init(allocator);
        //    while (currentCell) |cell| : (currentCell = frontier.popOrNull()) {
        //        if (cell.isEquals(goal)) {
        //            try route.insert(0, cell);
        //            return route.toOwnedSlice();
        //        }
        //        for (try self.successor(cell.x, cell.y, allocator)) |child| {
        //            var memberFound: bool = blabel: {
        //                for (explored.items) |member| {
        //                    if (member.x == child.x and member.y == child.y) {
        //                        break :blabel true;
        //                    }
        //                }
        //                break :blabel false;
        //            };

        //            if (!memberFound) {
        //                try explored.append(child);
        //                try route.insert(0, cell);
        //                try frontier.append(child);
        //            }
        //        }
        //    }
        //    return null;
        //}

        //fn bfs(self: Self, start: Cell, goal: Cell, allocator: std.mem.Allocator) !?[]const Cell {
        //    var frontier = std.ArrayList(Cell).init(allocator);
        //    try frontier.append(start);
        //    var explored = std.ArrayList(Cell).init(allocator);
        //    var currentCell: ?Cell = frontier.popOrNull();
        //    var route = std.ArrayList(Cell).init(allocator);
        //    while (currentCell) |cell| : (currentCell = frontier.popOrNull()) {
        //        if (cell.isEquals(goal)) {
        //            try route.insert(0, cell);
        //            return route.toOwnedSlice();
        //        }
        //        for (try self.successor(cell.x, cell.y, allocator)) |child| {
        //            var memberFound: bool = blabel: {
        //                for (explored.items) |member| {
        //                    if (member.isEquals(child)) {
        //                        break :blabel true;
        //                    }
        //                }
        //                break :blabel false;
        //            };

        //            if (!memberFound) {
        //                try explored.append(child);
        //                try route.insert(0, cell);
        //                try frontier.insert(0, child);
        //            }
        //        }
        //    }
        //    return null;
        //}

        //fn successor(self: Self, x: usize, y: usize, allocator: std.mem.Allocator) ![]Cell {
        //    var cells = std.ArrayList(Cell).init(allocator);
        //    if (y + 1 < self.rows and self.cells[y + 1][x].state != .blocked) {
        //        try cells.append(self.cells[y + 1][x]);
        //    }

        //    if (y > 0 and self.cells[y - 1][x].state != .blocked) {
        //        try cells.append(self.cells[y - 1][x]);
        //    }
        //    if (x + 1 < self.cols and self.cells[y][x + 1].state != .blocked) {
        //        try cells.append(self.cells[y][x + 1]);
        //    }
        //    if (x > 0 and self.cells[y][x - 1].state != .blocked) {
        //        try cells.append(self.cells[y][x - 1]);
        //    }
        //    return cells.items;
        //}

        //pub fn markPath(self: *Self, cells: []const Cell) void {
        //    var start = cells[cells.len - 1];
        //    var goal = cells[0];
        //    self.cells[goal.y][goal.x].state = .goal;
        //    for (cells[1 .. cells.len - 1]) |cell| {
        //        self.cells[cell.y][cell.x].state = .path;
        //    }
        //    self.cells[start.y][start.x].state = .start;
        //}

        //pub fn reset(self: *Self) void {
        //    for (self.cells) |cells| {
        //        for (cells) |*cell| {
        //            cell.state = .open;
        //        }
        //    }
        //}
    };
}

test "grid pretty print" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = arena.allocator();
    var grid = try Grid().init(8, 8, a);
    defer grid.deinit();
    try BinaryTree.on(&grid);
    try grid.pretty_print(a);
}
