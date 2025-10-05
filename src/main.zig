const std = @import("std");

const Error = error{FileNotFound};

const Register = enum {
    AL,
    CL,
    DL,
    BL,
    AH,
    CH,
    DH,
    BH,
    AX,
    CX,
    DX,
    BX,
    SP,
    BP,
    SI,
    DI,

    pub fn make(reg: u3, w: bool) Register {
        if (w) {
            return switch (reg) {
                0b000 => Register.AX,
                0b001 => Register.CX,
                0b010 => Register.DX,
                0b011 => Register.BX,
                0b100 => Register.SP,
                0b101 => Register.BP,
                0b110 => Register.SI,
                0b111 => Register.DI,
            };
        } else {
            return switch (reg) {
                0b000 => Register.AL,
                0b001 => Register.CL,
                0b010 => Register.DL,
                0b011 => Register.BL,
                0b100 => Register.AH,
                0b101 => Register.CH,
                0b110 => Register.DH,
                0b111 => Register.BH,
            };
        }
    }

    pub fn emit(self: Register) *const [2:0]u8 {
        return switch (self) {
            .AL => "al",
            .CL => "cl",
            .DL => "dl",
            .BL => "bl",
            .AH => "ah",
            .CH => "ch",
            .DH => "dh",
            .BH => "bh",
            .AX => "ax",
            .CX => "cx",
            .DX => "dx",
            .BX => "bx",
            .SP => "sp",
            .BP => "bp",
            .SI => "si",
            .DI => "di",
        };
    }
};

fn writeEffectiveAddress(stdout: *std.Io.Writer, rm: u3) !void {
    switch (rm) {
        0b000 => try stdout.print("bx + si", .{}),
        0b001 => try stdout.print("bx + di", .{}),
        0b010 => try stdout.print("bp + si", .{}),
        0b011 => try stdout.print("bp + di", .{}),
        0b100 => try stdout.print("si", .{}),
        0b101 => try stdout.print("di", .{}),
        0b110 => try stdout.print("bp", .{}),
        0b111 => try stdout.print("bx", .{}),
    }
}

const Code = struct {
    data: []u8,
    position: usize = 0,

    const Mode = enum(u2) {
        MemoryNoDisplacement = 0b00,
        Memory8BitDisplacement = 0b01,
        Memory16BitDisplacement = 0b10,
        Register = 0b11,
    };

    const ModeRegRm = packed struct {
        rm: u3,
        reg: u3,
        mode: Mode,
    };

    const CodeError = error{ EOF, NotYetImplemented };

    pub fn disassemble(self: *Code, stdout: *std.Io.Writer) !void {
        try stdout.print("bits 16\n", .{});

        while (!self.eof()) {
            const byte = try self.next();

            if ((byte & 0b10110000) == 0b10110000) {
                // Immediate to register
                const w_flag = (byte & 0b00001000) > 0;
                const register_encoding: u3 = @truncate(byte & 0b00000111);
                const reg = Register.make(register_encoding, w_flag);
                if (w_flag) {
                    const data_lo = try self.next();
                    const data_hi: u16 = try self.next();
                    const immediate: u16 = (data_hi << 8) | data_lo;
                    try stdout.print("mov {s}, {d}\n", .{ reg.emit(), immediate });
                } else {
                    const data = try self.next();
                    try stdout.print("mov {s}, {d}\n", .{ reg.emit(), data });
                }
            } else if ((byte & 0b10100010) == 0b10100010) {
                // Accumulator to memory
                const w_flag = (byte & 0b00000001) > 0;
                const byte_lo = try self.next();
                const byte_hi: u16 = try self.next();
                const addr = (byte_hi << 8) | byte_lo;

                // If we're only moving 8 bits, move into AL
                const register = if(w_flag) Register.AX else Register.AL;
                try stdout.print("mov [{d}], {s}\n", .{addr, register.emit()});
            } else if ((byte & 0b10100000) == 0b10100000) {
                // Memory to accumulator
                const w_flag = (byte & 0b00000001) > 0;
                const byte_lo = try self.next();
                const byte_hi: u16 = try self.next();
                const addr = (byte_hi << 8) | byte_lo;

                // If we're only moving 8 bits, move into AL
                const register = if(w_flag) Register.AX else Register.AL;
                try stdout.print("mov {s}, [{d}]\n", .{register.emit(), addr});
            } else if ((byte & 0b10001000) == 0b10001000) {
                // Register/memory to/from register
                const d_flag = (byte & 0b00000010) > 0;
                const w_flag = (byte & 0b00000001) > 0;
                const mode_reg_rm_byte = try self.next();
                const mode_reg_rm: ModeRegRm = @bitCast(mode_reg_rm_byte);

                try stdout.print("mov ", .{});
                switch (mode_reg_rm.mode) {
                    Mode.Register => {
                        const operand_one = Register.make(mode_reg_rm.reg, w_flag);
                        const operand_two = Register.make(mode_reg_rm.rm, w_flag);
                        try stdout.print("{s}, {s}\n", .{ operand_two.emit(), operand_one.emit() });
                    },
                    Mode.MemoryNoDisplacement => {
                        const register = Register.make(mode_reg_rm.reg, w_flag).emit();
                        if (d_flag) {
                            try stdout.print("{s}, [", .{register});
                            try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                            try stdout.print("]\n", .{});
                        } else {
                            try stdout.print("[", .{});
                            try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                            try stdout.print("], {s}\n", .{register});
                        }
                    },
                    Mode.Memory8BitDisplacement => {
                        const displacement = try self.next();
                        const register = Register.make(mode_reg_rm.reg, w_flag).emit();
                        if (d_flag) {
                            try stdout.print("{s}, [", .{register});
                            try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                            try stdout.print(" + {d}]\n", .{displacement});
                        } else {
                            try stdout.print("[", .{});
                            try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                            try stdout.print(" + {d}], {s}\n", .{ displacement, register });
                        }
                    },
                    Mode.Memory16BitDisplacement => {
                        const byte_lo = try self.next();
                        const byte_hi: u16 = try self.next();
                        const displacement = (byte_hi << 8) | byte_lo;
                        const register = Register.make(mode_reg_rm.reg, w_flag).emit();
                        if (d_flag) {
                            try stdout.print("{s}, [", .{register});
                            try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                            try stdout.print(" + {d}]\n", .{displacement});
                        } else {
                            try stdout.print("[", .{});
                            try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                            try stdout.print(" + {d}], {s}\n", .{ displacement, register });
                        }
                    },
                }
            } else {
                return CodeError.NotYetImplemented;
            }
        }
    }

    fn eof(self: *Code) bool {
        return self.position >= self.data.len;
    }

    fn peek(self: *Code) CodeError!u8 {
        const next_pos = self.position + 1;
        if (next_pos >= self.data.len) {
            return CodeError.EOF;
        }

        return self.data[next_pos];
    }

    fn next(self: *Code) CodeError!u8 {
        if (self.eof()) {
            return CodeError.EOF;
        }

        const byte = self.data[self.position];
        self.position += 1;
        return byte;
    }
};

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
        try stdout.print("Input file required", .{});
        try stdout.flush();
        return Error.FileNotFound;
    }

    const filename = args[1];
    const content = try std.fs.cwd().readFileAlloc(allocator, filename, std.math.maxInt(usize));
    defer allocator.free(content);

    var code = Code{ .data = content };
    try code.disassemble(stdout);
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
        var code = Code{ .data = expected_bin };
        var buf: [1024]u8 = undefined;
        var writer = std.io.Writer.fixed(&buf);
        try code.disassemble(&writer);
        try test_file.writeAll(&buf);

        // Recompile the test file using nasm.
        const test_result_filename = "test";
        const nasm2_cmd = [_][]const u8{ "nasm", "-o", test_result_filename, test_filename };
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
