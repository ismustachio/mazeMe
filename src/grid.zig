const std = @import("std");
const expect = std.testing.expect;
const RndGen = std.rand.DefaultPrng;
const Stdout = std.io.getStdOut();
const Allocator = std.mem.Allocator;

const DistancesError = error{
    NoSolution,
};

//TODO: impl denit, distances, at least one opening always

const Cell = struct {
    const Self = @This();
    x: usize,
    y: usize,
    north: ?*Cell = null,
    south: ?*Cell = null,
    west: ?*Cell = null,
    east: ?*Cell = null,
    links: std.AutoHashMap(Cell, bool),
    allocator: Allocator,

    pub fn init(x: usize, y: usize, allocator: Allocator) Cell {
        return Self{
            .x = x,
            .y = y,
            .allocator = allocator,
            .links = std.AutoHashMap(Cell, bool).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn link(self: *Self, cell: *Cell, bidi: bool) !void {
        try self.links.put(cell.*, true);
        if (bidi) {
            try cell.links.put(self.*, true);
        }
    }

    pub fn unlink(self: *Self, cell: *Cell, bidi: bool) !void {
        try self.links.remove(cell.*);
        if (bidi) {
            try cell.links.remove(self.*);
        }
    }

    pub fn isLinked(self: Self, cell: Cell) ?bool {
        return self.links.get(cell);
    }

    pub fn isEquals(self: Self, xy: Cell) bool {
        return self.x == xy.x and self.y == xy.y;
    }

    pub fn neighbors(self: Self) []Cell {
        var neigh = std.ArrayList(Cell).init(self.allocator);
        if (self.north) |north| {
            neigh.append(north.*);
        }
        if (self.south) |south| {
            neigh.append(south.*);
        }
        if (self.west) |west| {
            neigh.append(west.*);
        }
        if (self.east) |east| {
            neigh.append(east.*);
        }
        return neigh.toOwnedSlice();
    }

    pub fn distances(self: Self) !Distances {
        var dists = try Distances.init(self, self.allocator);
        var frontier = std.ArrayList(Cell).init(self.allocator);
        var new_frontier = std.ArrayList(Cell).init(self.allocator);
        try frontier.append(self);
        var currentCell: ?Cell = frontier.popOrNull();
        while (currentCell) |cell| : (currentCell = frontier.popOrNull()) {
            new_frontier.clearAndFree();
            var it = cell.links.iterator();
            while (it.next()) |kv| {
                if (dists.get(kv.key_ptr.*) == null) {
                    // its safe here
                    try dists.set(kv.key_ptr.*, dists.get(cell).? + 1);
                    try new_frontier.append(kv.key_ptr.*);
                }
            }
            try frontier.appendSlice(new_frontier.toOwnedSlice());
        }
        return dists;
    }
};

pub const BinaryTree = struct {
    pub fn on(grid: *Grid) !void {
        var rnd = RndGen.init(0).random();
        var neighborCount: usize = 0;
        var neighbors: [2]?*Cell = undefined;
        for (grid.cells) |*cells| {
            for (cells.*) |*cell| {
                neighbors = undefined;
                if (cell.*) |c| {
                    if (c.north) |north| {
                        neighbors[neighborCount] = north;
                        neighborCount += 1;
                    }
                    if (c.east) |east| {
                        neighbors[neighborCount] = east;
                        neighborCount += 1;
                    }
                    if (neighborCount > 0) {
                        const idx = rnd.uintLessThanBiased(usize, neighborCount);
                        const neighbor = neighbors[idx];
                        if (neighbor) |n| {
                            try c.link(n, true);
                        }
                    }
                }
                neighborCount = 0;
            }
        }
    }
};

const Sidewinder = struct {
    pub fn on(grid: *Grid, allocator: Allocator) !void {
        var rnd = RndGen.init(0).random();
        var run = std.ArrayList([]const u8).init(allocator);
        var at_eastern_boundary: bool = false;
        var at_northern_boundary: bool = false;
        var should_close_out: bool = false;
        for (grid.cells) |*cells| {
            run.clearAndFree();
            for (cells.*) |*cell| {
                if (cell) |c| {
                    run.append(c);
                    at_eastern_boundary = c.east == null;
                    at_northern_boundary = c.north == null;
                    should_close_out = at_eastern_boundary or (!at_northern_boundary and rnd.uintLessThanBiased(usize, 2) == 0);

                    if (should_close_out) {
                        var member = run.sample();
                        if (member.north != null) {
                            member.link(member.north, true);
                        }
                        run.clearAndFree();
                    } else {
                        c.link(c.east, true);
                    }
                }
            }
        }
    }
};

// records the distance of each cell from root
const Distances = struct {
    const Self = @This();
    root: Cell,
    allocator: Allocator,
    cells: std.AutoHashMap(Cell, usize),

    pub fn init(root: Cell, allocator: Allocator) !Self {
        var self = Distances{ .root = root, .allocator = allocator, .cells = std.AutoHashMap(Cell, usize).init(allocator) };
        try self.cells.put(root, 0);
        return self;
    }

    pub fn get(self: Self, cell: Cell) ?usize {
        return self.cells.get(cell);
    }

    pub fn set(self: *Self, cell: Cell, distance: usize) !void {
        try self.cells.put(cell, distance);
    }

    pub fn path_to_goal(self: Self, goal: Cell) error{NoSolution}!Distances {
        var current = goal;

        var breadcrumbs = Distances.init(self.root);
        if (self.cells.get(current)) |distance| {
            try breadcrumbs.set(current, distance);
        } else {
            return error.NoSolution;
        }

        while (!current.isEqual(self.root)) {
            var iterator = current.links.iterator();
            while (iterator.next()) |neighbor| {
                if (self.cells.get(neighbor.key_ptr.*).? < self.cells.get(current).?) {
                    breadcrumbs.set(neighbor.key_ptr.*, self.cells.get(neighbor.key_ptr.*).?);
                    current = neighbor.key_ptr.*;
                }
            }
        }
        return breadcrumbs;
    }
};

pub const Grid = struct {
    const Self = @This();
    cells: [][]?*Cell = undefined,
    allocator: Allocator,
    rows: usize,
    cols: usize,
    distances: ?Distances = undefined,

    pub fn size(self: Self) usize {
        return self.rows * self.cols;
    }

    fn always_one(self: *Self) void {
        var rnd = RndGen.init(0).random();
        var num_nolinks: usize = 0;
        var is_good_link: bool = false;
        for (self.cells) |cells| {
            // check this row
            for (cells) |cell| {
                if (cell.north == null and cell.east == null and cell.west == null and cell.south == null) {
                    num_nolinks += 1;
                }
            }
            if (num_nolinks == cells.len) {
                while (!is_good_link) {
                    var idx = rnd.uintLessThanBiased(usize, cells.len);
                    var pos = rnd.uintLessThanBiased(usize, 4);
                    // make sure to not to link outside the border
                    var cell = cells[idx];
                    switch (pos) {
                        0 => {
                            if (cell.y - 1 >= 0) {
                                cell.link(cell.north, true);
                                is_good_link = true;
                            }
                        },
                        1 => {
                            if (cell.y + 1 < self.rows) {
                                cell.link(cell.south, true);
                                is_good_link = true;
                            }
                        },
                        2 => {
                            if (cell.x + 1 < self.cols) {
                                cell.link(cell.east, true);
                                is_good_link = true;
                            }
                        },
                        3 => {
                            if (cell.x - 1 >= 0) {
                                cell.link(cell.west, true);
                                is_good_link = true;
                            }
                        },
                        else => {},
                    }
                }
            }
            is_good_link = false;
        }
    }

    pub fn pretty_print(self: Self) !void {
        var buffer = std.ArrayList([]const u8).init(self.allocator);
        var top = std.ArrayList([]const u8).init(self.allocator);
        var bottom = std.ArrayList([]const u8).init(self.allocator);
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
                if (cell) |c| {
                    east_boundary = "|";
                    if (c.east) |east| {
                        if (c.isLinked(east.*)) |linked| {
                            if (linked) {
                                east_boundary = " ";
                            }
                        }
                    }

                    south_boundary = "---";
                    if (c.south) |south| {
                        if (c.isLinked(south.*)) |linked| {
                            if (linked) {
                                south_boundary = "   ";
                            }
                        }
                    }
                    try top.append(try self.cell_body(c.*));
                }
                try top.append(east_boundary);
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

    pub fn init(rows: usize, cols: usize, allocator: Allocator) !Self {
        var self = Grid{ .rows = rows, .cols = cols, .allocator = allocator };
        self.cells = try allocator.alloc([]?*Cell, rows);
        for (self.cells) |*row, j| {
            row.* = try allocator.alloc(?*Cell, cols);
            for (row.*) |*r, i| {
                r.* = try allocator.create(Cell);
                r.*.?.* = Cell.init(i, j, allocator);
            }
        }

        for (self.cells) |*row| {
            for (row.*) |*r| {
                var y = r.*.?.y;
                var x = r.*.?.x;
                if (y > 0 and y - 1 >= 0) {
                    r.*.?.north = self.cells[y - 1][x];
                }
                if (y + 1 < self.rows) {
                    r.*.?.south = self.cells[y + 1][x];
                }
                if (x > 0 and x - 1 >= 0) {
                    r.*.?.west = self.cells[y][x - 1];
                }
                if (x + 1 < self.cols) {
                    r.*.?.east = self.cells[y][x + 1];
                }
            }
        }
        return self;
    }

    pub fn cell_body(self: Self, cell: Cell) ![]const u8 {
        var out = std.io.getStdOut().writer();
        var buf: []u8 = undefined;
        if (self.distances) |distances| {
            try out.print("body\n", .{});
            if (distances.get(cell)) |c| {
                return try std.fmt.bufPrint(buf, "{}", .{c});
            }
        }
        return "   ";
    }

    pub fn random_cell(self: Self) Cell() {
        var rnd = RndGen.init(0);
        var rows = rnd.random().int(usize) % self.rows;
        var cols = rnd.random().int(usize) % self.cols;
        return self.cells[rows][cols];
    }

    pub fn set_distances(self: *Self, dists: Distances) void {
        self.distances = dists;
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

test "pretty_print" {

    //var start = grid.cells[0][0];
    ////var distances = try start.?.distances();
    //grid.set_distances(distances);
    //try grid.pretty_print();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = arena.allocator();
    var grid = try Grid.init(8, 8, a);
    try BinaryTree.on(&grid);
    try grid.pretty_print();
}

test "pretty_print distances" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = arena.allocator();
    var grid = try Grid.init(8, 8, a);
    try BinaryTree.on(&grid);
    var start = grid.cells[0][0];
    var distances = try start.?.distances();
    grid.set_distances(distances);
    try grid.pretty_print();
}
