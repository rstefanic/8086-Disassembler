pub const Register = enum {
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
