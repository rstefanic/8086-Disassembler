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
    je,
    jl,
    jle,
    jb,
    jbe,
    jp,
    jo,
    js,
    jnz,
    jnl,
    jnle,
    jnb,
    jnbe,
    jnp,
    jno,
    jns,
    loop,
    loopz,
    loopnz,
    jcxz,
};

pub const Instruction = union(InstructionType) {
    mov: Mov,
    je,
    jl,
    jle,
    jb,
    jbe,
    jp,
    jo,
    js,
    jnz,
    jnl,
    jnle,
    jnb,
    jnbe,
    jnp,
    jno,
    jns,
    loop,
    loopz,
    loopnz,
    jcxz,

    pub fn make(byte: u8) Instruction {
        return switch (byte & 0b11111111) {
            // MOV
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

            // JMP
            0b01110100 => Instruction.je,
            0b01111100 => Instruction.jl,
            0b01111110 => Instruction.jle,
            0b01110010 => Instruction.jb,
            0b01110110 => Instruction.jbe,
            0b01111010 => Instruction.jp,
            0b01110000 => Instruction.jo,
            0b01111000 => Instruction.js,
            0b01110101 => Instruction.jnz,
            0b01111101 => Instruction.jnl,
            0b01111111 => Instruction.jnle,
            0b01110011 => Instruction.jnb,
            0b01110111 => Instruction.jnbe,
            0b01111011 => Instruction.jnp,
            0b01110001 => Instruction.jno,
            0b01111001 => Instruction.jns,
            0b11100010 => Instruction.loop,
            0b11100001 => Instruction.loopz,
            0b11100000 => Instruction.loopnz,
            0b11100011 => Instruction.jcxz,

            else => @panic("Unimplemented instruction"),
        };
    }
};
