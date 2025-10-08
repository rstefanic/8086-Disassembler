const std = @import("std");

const Binary = @import("binary.zig");

const Error = error{FileNotFound};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (args.len < 2) {
        try stdout.print("Input file required\n", .{});
        try stdout.flush();
        return Error.FileNotFound;
    }

    const filename = args[1];
    const content = try std.fs.cwd().readFileAlloc(allocator, filename, std.math.maxInt(usize));
    defer allocator.free(content);

    var bin = Binary{ .data = content };
    try bin.disassemble(stdout);
    try stdout.flush();
}

test "Match disassembled version with compiled version" {
    var test_directory = try std.fs.cwd().openDir("tests", .{ .iterate = true });
    defer test_directory.close();

    try test_directory.setAsCwd();
    var files_iterator = test_directory.iterate();

    // Compile each file of valid 8086 using nasm, disassemble the compiled
    // code, and then re-compile the disassembled code. The final result
    // should be the same byte-for-byte which will be checked using cmp.
    while (try files_iterator.next()) |file| {
        // By default, nasm will just strip the `.asm` suffix for the final bin.
        const expected_bin_filename = expected_bin_filename: {
            var split = std.mem.splitScalar(u8, file.name, '.');
            break :expected_bin_filename split.next().?;
        };

        // Compile the test file to get the expected binary output.
        const nasm_cmd = [_][]const u8{ "nasm", file.name };
        var nasm = std.process.Child.init(&nasm_cmd, std.testing.allocator);
        try nasm.spawn();
        const nasm_results = try nasm.wait();
        try std.testing.expect(nasm_results.Exited == 0);
        defer test_directory.deleteFile(expected_bin_filename) catch @panic("Could not delete expected binary file");

        // Read the binary output from the input file.
        const expected_bin = try std.fs.cwd().readFileAlloc(std.testing.allocator, expected_bin_filename, std.math.maxInt(usize));
        defer std.testing.allocator.free(expected_bin);

        // Create a test file where we disassemble the binary for testing.
        const test_filename = "test.asm";
        const test_file = try test_directory.createFile(test_filename, .{});
        defer test_directory.deleteFile(test_filename) catch @panic("Could not delete test file");

        // Call disassemble and write the results to the test file.
        var bin = Binary{ .data = expected_bin };
        var buf: [1024]u8 = undefined;
        var writer = std.io.Writer.fixed(&buf);
        try bin.disassemble(&writer);
        try test_file.writeAll(&buf);

        // Recompile the test file using nasm.
        const test_result_filename = "test";
        const nasm2_cmd = [_][]const u8{ "nasm", "-w-orphan-labels", "-o", test_result_filename, test_filename };
        var nasm2 = std.process.Child.init(&nasm2_cmd, std.testing.allocator);
        try nasm2.spawn();
        const nasm2_results = try nasm2.wait();
        try std.testing.expect(nasm2_results.Exited == 0);
        defer test_directory.deleteFile(test_result_filename) catch @panic("Could not delete test results");

        // The results of recompiling the disassembled output should be byte-for-byte identical.
        const cmp_cmd = [_][]const u8{ "cmp", expected_bin_filename, test_result_filename };
        var cmp = std.process.Child.init(&cmp_cmd, std.testing.allocator);
        try cmp.spawn();
        const cmp_results = try cmp.wait();
        try std.testing.expect(cmp_results.Exited == 0);
    }
}
