const Binary = @This();

const std = @import("std");

const Instructions = @import("instruction.zig");
const Register = @import("register.zig").Register;

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

const DisassembleError = error{ EOF, NotYetImplemented, InvalidInstruction };

pub fn disassemble(self: *Binary, stdout: *std.Io.Writer) !void {
    try stdout.print("bits 16\n", .{});

    while (!self.eof()) {
        const byte = try self.next();
        const instruction = Instructions.Instruction.make(byte);

        switch (instruction) {
            .mov => |*mov| try self.emitMov(mov.*, stdout),
            .je => try self.emitJe(stdout),
            .jl => try self.emitJl(stdout),
            .jle => try self.emitJle(stdout),
            .jb => try self.emitJb(stdout),
            .jbe => try self.emitJbe(stdout),
            .jp => try self.emitJp(stdout),
            .jo => try self.emitJo(stdout),
            .js => try self.emitJs(stdout),
            .jnz => try self.emitJnz(stdout),
            .jnl => try self.emitJnl(stdout),
            .jnle => try self.emitJnle(stdout),
            .jnb => try self.emitJnb(stdout),
            .jnbe => try self.emitJnbe(stdout),
            .jnp => try self.emitJnp(stdout),
            .jno => try self.emitJno(stdout),
            .jns => try self.emitJns(stdout),
            .loop => try self.emitLoop(stdout),
            .loopz => try self.emitLoopz(stdout),
            .loopnz => try self.emitLoopnz(stdout),
            .jcxz => try self.emitJcxz(stdout),
        }
    }
}

fn eof(self: *Binary) bool {
    return self.position >= self.data.len;
}

fn peek(self: *Binary) DisassembleError!u8 {
    const next_pos = self.position + 1;
    if (next_pos >= self.data.len) {
        return DisassembleError.EOF;
    }

    return self.data[next_pos];
}

fn next(self: *Binary) DisassembleError!u8 {
    if (self.eof()) {
        return DisassembleError.EOF;
    }

    const byte = self.data[self.position];
    self.position += 1;
    return byte;
}

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

fn emitMov(self: *Binary, mov: Instructions.Mov, stdout: *std.Io.Writer) !void {
    switch (mov) {
        .RegMemToFromReg => |*m| {
            const d_flag = m.*.d;
            const w_flag = m.*.w;
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
                    // Handle the special case when there IS a displacement
                    // when the MODE is set to "No Displacement".
                    if (mode_reg_rm.rm == 0b110) {
                        const byte_lo = try self.next();
                        const byte_hi: u16 = try self.next();
                        const addr = (byte_hi << 8) | byte_lo;
                        try stdout.print("{s}, [{d}]\n", .{ register, addr });
                    } else {
                        if (d_flag) {
                            try stdout.print("{s}, [", .{register});
                            try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                            try stdout.print("]\n", .{});
                        } else {
                            try stdout.print("[", .{});
                            try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                            try stdout.print("], {s}\n", .{register});
                        }
                    }
                },
                Mode.Memory8BitDisplacement => {
                    // 8 bit displacement allows for the displacement to be
                    // signed. It does this by performing sign extension
                    // on the byte and using that as the displacement value.
                    const byte_lo = try self.next();
                    const msb_set = (0b1000_0000 & byte_lo) == 0b1000_0000;
                    const byte_hi: u16 =
                        if (msb_set)
                            0b1111_1111_0000_0000
                        else
                            0b0000_0000_0000_0000;
                    const displacement: i16 = @bitCast(byte_hi | byte_lo);
                    const op: u8 = if (displacement >= 0) '+' else '-';
                    const register = Register.make(mode_reg_rm.reg, w_flag).emit();

                    if (d_flag) {
                        try stdout.print("{s}, [", .{register});
                        try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                        try stdout.print(" {c} {d}]\n", .{ op, @abs(displacement) });
                    } else {
                        try stdout.print("[", .{});
                        try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                        try stdout.print(" {c} {d}], {s}\n", .{ op, @abs(displacement), register });
                    }
                },
                Mode.Memory16BitDisplacement => {
                    const byte_lo = try self.next();
                    const byte_hi: u16 = try self.next();
                    const displacement: i16 = @bitCast((byte_hi << 8) | byte_lo);
                    const op: u8 = if (displacement >= 0) '+' else '-';
                    const register = Register.make(mode_reg_rm.reg, w_flag).emit();

                    if (d_flag) {
                        try stdout.print("{s}, [", .{register});
                        try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                        try stdout.print(" {c} {d}]\n", .{ op, @abs(displacement) });
                    } else {
                        try stdout.print("[", .{});
                        try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                        try stdout.print(" {c} {d}], {s}\n", .{ op, @abs(displacement), register });
                    }
                },
            }
        },
        .ImmToRegMem => |*m| {
            const w_flag = m.w;
            const mode_reg_rm_byte = try self.next();
            const mode_reg_rm: ModeRegRm = @bitCast(mode_reg_rm_byte);

            try stdout.print("mov ", .{});
            switch (mode_reg_rm.mode) {
                Mode.MemoryNoDisplacement => {
                    if (w_flag) {
                        const byte_lo = try self.next();
                        const byte_hi: u16 = try self.next();
                        const immediate = (byte_hi << 8) | byte_lo;
                        try stdout.print("[", .{});
                        try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                        try stdout.print("], word {d}\n", .{immediate});
                    } else {
                        const immediate = try self.next();
                        try stdout.print("[", .{});
                        try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                        try stdout.print("], byte {d}\n", .{immediate});
                    }
                },
                Mode.Memory8BitDisplacement => {
                    // 8 bit displacement allows for the displacement to be
                    // signed. It does this by performing sign extension
                    // on the byte and using that as the displacement value.
                    const byte_lo = try self.next();
                    const msb_set = (0b1000_0000 & byte_lo) == 0b1000_0000;
                    const byte_hi: u16 =
                        if (msb_set)
                            0b1111_1111_0000_0000
                        else
                            0b0000_0000_0000_0000;
                    const displacement: i16 = @bitCast(byte_hi | byte_lo);
                    const op: u8 = if (displacement >= 0) '+' else '-';

                    // Read immediate value
                    const immediate = immediate: {
                        const data_lo = try self.next();
                        if (!w_flag) {
                            break :immediate data_lo;
                        }

                        const data_hi: u16 = try self.next();
                        break :immediate (data_hi << 8) | data_lo;
                    };
                    const size_keyword: *const [4:0]u8 = if (w_flag) "word" else "byte";

                    try stdout.print("[", .{});
                    try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                    try stdout.print(" {c} {d}], {s} {d}\n", .{ op, @abs(displacement), size_keyword, immediate });
                },
                Mode.Memory16BitDisplacement => {
                    // Read two bytes for the displacement value
                    const byte_lo = try self.next();
                    const byte_hi: u16 = try self.next();
                    const displacement: i16 = @bitCast((byte_hi << 8) | byte_lo);
                    const op: u8 = if (displacement >= 0) '+' else '-';

                    // Read immediate value
                    const immediate = immediate: {
                        const data_lo = try self.next();
                        if (!w_flag) {
                            break :immediate data_lo;
                        }

                        const data_hi: u16 = try self.next();
                        break :immediate (data_hi << 8) | data_lo;
                    };
                    const size_keyword: *const [4:0]u8 = if (w_flag) "word" else "byte";

                    try stdout.print("[", .{});
                    try writeEffectiveAddress(stdout, mode_reg_rm.rm);
                    try stdout.print(" {c} {d}], {s} {d}\n", .{ op, @abs(displacement), size_keyword, immediate });
                },
                else => {
                    std.debug.print("Invalid mode for  \"Immediate to register/memory\" instruction. mode: {any}\n", .{mode_reg_rm.mode});
                    return DisassembleError.InvalidInstruction;
                },
            }
        },
        .ImmToReg => |*m| {
            const w_flag = m.*.w;
            const register_encoding = m.*.reg;
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
        },
        .AccToMem => |*m| {
            const w_flag = m.*.w;
            const byte_lo = try self.next();
            const byte_hi: u16 = try self.next();
            const addr = (byte_hi << 8) | byte_lo;

            // If we're only moving 8 bits, move into AL
            const register = if (w_flag) Register.AX else Register.AL;
            try stdout.print("mov [{d}], {s}\n", .{ addr, register.emit() });
        },
        .MemToAcc => |*m| {
            const w_flag = m.*.w;
            const byte_lo = try self.next();
            const byte_hi: u16 = try self.next();
            const addr = (byte_hi << 8) | byte_lo;

            // If we're only moving 8 bits, move into AL
            const register = if (w_flag) Register.AX else Register.AL;
            try stdout.print("mov {s}, [{d}]\n", .{ register.emit(), addr });
        },
    }
}

fn emitJe(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("je {d}\n", .{displacement});
}

fn emitJl(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jl {d}\n", .{displacement});
}

fn emitJle(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jle {d}\n", .{displacement});
}

fn emitJb(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jb {d}\n", .{displacement});
}

fn emitJbe(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jbe {d}\n", .{displacement});
}

fn emitJp(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jp {d}\n", .{displacement});
}

fn emitJo(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jo {d}\n", .{displacement});
}

fn emitJs(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("js {d}\n", .{displacement});
}

fn emitJnz(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jnz {d}\n", .{displacement});
}

fn emitJnl(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jnl {d}\n", .{displacement});
}

fn emitJnle(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jnle {d}\n", .{displacement});
}

fn emitJnb(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jnb {d}\n", .{displacement});
}

fn emitJnbe(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jnbe {d}\n", .{displacement});
}

fn emitJnp(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jnp {d}\n", .{displacement});
}

fn emitJno(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jno {d}\n", .{displacement});
}

fn emitJns(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jns {d}\n", .{displacement});
}

fn emitLoop(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("loop {d}\n", .{displacement});
}

fn emitLoopz(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("loopz {d}\n", .{displacement});
}

fn emitLoopnz(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("loopnz {d}\n", .{displacement});
}

fn emitJcxz(self: *Binary, stdout: *std.Io.Writer) !void {
    const displacement = try self.next();
    try stdout.print("jcxz {d}\n", .{displacement});
}
