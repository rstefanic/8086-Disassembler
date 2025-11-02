const MovSubtype = enum {
    RegMemToFromReg,
    ImmToRegMem,
    ImmToReg,
    MemToAcc,
    AccToMem,

    // TODO: Implement remaining MOV instructions
    // RegMemToSegReg,
    // SegRegToRegMem,
};

pub const Mov = union(MovSubtype) {
    RegMemToFromReg: struct { d: bool, w: bool },
    ImmToRegMem: struct { w: bool },
    ImmToReg: struct { w: bool, reg: u3 },
    MemToAcc: struct { w: bool },
    AccToMem: struct { w: bool },

    // TODO: Implement remaining MOV instructions
    // RegMemToSegReg: struct {},
    // SegRegToRegMem: struct {},
};

const InstructionType = enum {
    mov,
};

pub const Instruction = union(InstructionType) {
    mov: Mov,

    pub fn make(byte: u8) Instruction {
        return switch (byte & 0b11111111) {
            0b10001000...0b10001011 => regMemToFromReg: {
                const w = (byte & 0b00000001) > 0;
                const d = (byte & 0b00000010) > 0;
                break :regMemToFromReg Instruction{ .mov = Mov{ .RegMemToFromReg = .{ .d = d, .w = w } } };
            },
            0b11000110 => Instruction{ .mov = Mov{ .ImmToRegMem = .{ .w = false } } },
            0b11000111 => Instruction{ .mov = Mov{ .ImmToRegMem = .{ .w = true } } },
            0b10110000...0b10111111 => immToRegister: {
                const w = (byte & 0b00001000) > 0;
                const reg: u3 = @truncate(byte & 0b00000111);
                break :immToRegister Instruction{ .mov = Mov{ .ImmToReg = .{ .w = w, .reg = reg } } };
            },
            0b10100000 => Instruction{ .mov = Mov{ .MemToAcc = .{ .w = false } } },
            0b10100001 => Instruction{ .mov = Mov{ .MemToAcc = .{ .w = true } } },
            0b10100010 => Instruction{ .mov = Mov{ .AccToMem = .{ .w = false } } },
            0b10100011 => Instruction{ .mov = Mov{ .AccToMem = .{ .w = true } } },

            // TODO: Implement remaining MOV instructions
            // 0b10001110 => Instruction{ .mov = Mov{ .RegMemToSegReg = .{} } },
            // 0b10001100 => Instruction{ .mov = Mov{ .SegRegToRegMem = .{} } },

            else => @panic("Unimplemented instruction"),
        };
    }
};
