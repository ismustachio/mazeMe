const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const mazeMe_test = b.addTest("mazeMe.zig");
    mazeMe_test.setBuildMode(mode);

    const test_step = b.step("check_semantics", "Verifies that all declarations are kinda sane.");
    test_step.dependOn(&mazeMe_test.step);
}
