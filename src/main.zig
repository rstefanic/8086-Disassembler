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

    pub fn make(reg: u3, w: u1) Register {
        if (w == 0) {
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
        } else {
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

const Code = struct {
    data: []u8,
    position: usize = 0,

    const Mode = enum(u2) {
        MemoryModeNoDisplacement = 0b00,
        MemoryMode8BitDisplacement = 0b01,
        MemoryMode16BitDisplacement = 0b10,
        RegisterMode = 0b11,
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

            if (byte & 0b10001000 == 0b10001000) {
                const w_flag: u1 = if ((byte & 0b00000001) > 0) 0b1 else 0b0;
                const mode_reg_rm_byte = try self.next();
                const mode_reg_rm: ModeRegRm = @bitCast(mode_reg_rm_byte);
                if (mode_reg_rm.mode == Mode.RegisterMode) {
                    const operand_one = Register.make(mode_reg_rm.reg, w_flag);
                    const operand_two = Register.make(mode_reg_rm.rm, w_flag);
                    try stdout.print("mov {s}, {s}\n", .{ operand_two.emit(), operand_one.emit() });
                } else {
                    return CodeError.NotYetImplemented;
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
