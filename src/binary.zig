const Binary = @This();

const std = @import("std");

const Instructions = @import("instruction.zig");
const Register = @import("register.zig").Register;

data: []u8,
position: usize = 0,

pub const Mode = enum(u2) {
    MemoryNoDisplacement = 0b00,
    Memory8BitDisplacement = 0b01,
    Memory16BitDisplacement = 0b10,
    Register = 0b11,
};

pub const ModeRegRm = packed struct {
    rm: u3,
    reg: u3,
    mode: Mode,
};

const DisassembleError = error{EOF};

pub fn eof(self: *Binary) bool {
    return self.position >= self.data.len;
}

pub fn peek(self: *Binary) DisassembleError!u8 {
    const next_pos = self.position + 1;
    if (next_pos >= self.data.len) {
        return DisassembleError.EOF;
    }

    return self.data[next_pos];
}

pub fn next(self: *Binary) DisassembleError!u8 {
    if (self.eof()) {
        return DisassembleError.EOF;
    }

    const byte = self.data[self.position];
    self.position += 1;
    return byte;
}
