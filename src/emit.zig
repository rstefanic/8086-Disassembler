const std = @import("std");
const DoublyLinkedList = std.DoublyLinkedList;

const Binary = @import("binary.zig");
const Disassemble = @import("disassemble.zig");
const Instructions = @import("instruction.zig");
const Register = @import("register.zig").Register;

pub fn emit(self: *const Disassemble, stdout: *std.Io.Writer) !void {
    var current = self.code.first;
    while (current) |node| {
        const byte: *Disassemble.Byte = @fieldParentPtr("node", node);
        if (byte.type != .Instruction) {
            std.debug.print("Expected Instruction, found : {any}\n", .{byte.type});
            return error.InstructionExpected;
        }
        current = node.next;

        const instruction = Instructions.Instruction.make(byte.data);
        const count = switch (instruction) {
            .mov => |mov| try parseMov(mov, node, stdout),
            else => @panic("Not yet implemented"),
        };

        for (0..count) |_| {
            if (current) |c| {
                current = c.next;
            }
        }
    }
}

fn parseMov(mov: Instructions.Mov, node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    var count: usize = 0;
    var current = node;
    switch (mov) {
        .RegMemToFromReg => |m| {
            const d_flag = m.d;
            const w_flag = m.w;

            var mod_reg_rm: Binary.ModeRegRm = undefined;
            if (current.next) |next| {
                const mod_reg_rm_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                mod_reg_rm = @bitCast(mod_reg_rm_byte.data);
                current = next;
                count += 1;
            } else {
                return error.ExpectedModRegRm;
            }

            try stdout.print("mov ", .{});
            switch (mod_reg_rm.mode) {
                Binary.Mode.Register => {
                    const operand_one = Register.make(mod_reg_rm.reg, w_flag);
                    const operand_two = Register.make(mod_reg_rm.rm, w_flag);
                    try stdout.print("{s}, {s}\n", .{ operand_two.emit(), operand_one.emit() });
                },
                Binary.Mode.MemoryNoDisplacement => {
                    const register = Register.make(mod_reg_rm.reg, w_flag).emit();

                    // Handle the special case when there IS a displacement
                    // when the MODE is set to "No Displacement".
                    if (mod_reg_rm.rm == 0b110) {
                        var data_lo: u8 = undefined;
                        var data_hi: u16 = undefined;

                        if (current.next) |next| {
                            const lo_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                            data_lo = lo_byte.data;
                            count += 1;
                            current = next;
                        } else {
                            return error.ExpectedDataLo;
                        }

                        if (current.next) |next| {
                            const hi_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                            data_hi = hi_byte.data;
                            count += 1;
                            current = next;
                        } else {
                            return error.ExpectedDataHi;
                        }

                        const addr = (data_hi << 8) | data_lo;
                        try stdout.print("{s}, [{d}]\n", .{ register, addr });
                    } else {
                        if (d_flag) {
                            try stdout.print("{s}, [", .{register});
                            try writeEffectiveAddress(stdout, mod_reg_rm.rm);
                            try stdout.print("]\n", .{});
                        } else {
                            try stdout.print("[", .{});
                            try writeEffectiveAddress(stdout, mod_reg_rm.rm);
                            try stdout.print("], {s}\n", .{register});
                        }
                    }
                },
                Binary.Mode.Memory8BitDisplacement => {
                    // 8 bit displacement allows for the displacement to be
                    // signed. It does this by performing sign extension
                    // on the byte and using that as the displacement value.
                    var data_lo: u8 = undefined;

                    if (current.next) |next| {
                        const lo_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                        data_lo = lo_byte.data;
                        count += 1;
                        current = next;
                    } else {
                        return error.ExpectedDataLo;
                    }

                    const msb_set = (0b1000_0000 & data_lo) == 0b1000_0000;
                    const data_hi: u16 =
                        if (msb_set)
                            0b1111_1111_0000_0000
                        else
                            0b0000_0000_0000_0000;
                    const displacement: i16 = @bitCast(data_hi | data_lo);
                    const op: u8 = if (displacement >= 0) '+' else '-';
                    const register = Register.make(mod_reg_rm.reg, w_flag).emit();

                    if (d_flag) {
                        try stdout.print("{s}, [", .{register});
                        try writeEffectiveAddress(stdout, mod_reg_rm.rm);
                        try stdout.print(" {c} {d}]\n", .{ op, @abs(displacement) });
                    } else {
                        try stdout.print("[", .{});
                        try writeEffectiveAddress(stdout, mod_reg_rm.rm);
                        try stdout.print(" {c} {d}], {s}\n", .{ op, @abs(displacement), register });
                    }
                },
                Binary.Mode.Memory16BitDisplacement => {
                    var data_lo: u8 = undefined;
                    var data_hi: u16 = undefined;

                    if (current.next) |next| {
                        const lo_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                        data_lo = lo_byte.data;
                        count += 1;
                        current = next;
                    } else {
                        return error.ExpectedDataLo;
                    }

                    if (current.next) |next| {
                        const hi_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                        data_hi = hi_byte.data;
                        count += 1;
                        current = next;
                    } else {
                        return error.ExpectedDataHi;
                    }

                    const displacement: i16 = @bitCast((data_hi << 8) | data_lo);
                    const op: u8 = if (displacement >= 0) '+' else '-';
                    const register = Register.make(mod_reg_rm.reg, w_flag).emit();

                    if (d_flag) {
                        try stdout.print("{s}, [", .{register});
                        try writeEffectiveAddress(stdout, mod_reg_rm.rm);
                        try stdout.print(" {c} {d}]\n", .{ op, @abs(displacement) });
                    } else {
                        try stdout.print("[", .{});
                        try writeEffectiveAddress(stdout, mod_reg_rm.rm);
                        try stdout.print(" {c} {d}], {s}\n", .{ op, @abs(displacement), register });
                    }
                },
            }
        },
        .ImmToRegMem => |m| {
            const w_flag = m.w;

            var mod_reg_rm: Binary.ModeRegRm = undefined;
            if (current.next) |next| {
                const mod_reg_rm_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                mod_reg_rm = @bitCast(mod_reg_rm_byte.data);
                current = next;
                count += 1;
            } else {
                return error.ExpectedModRegRm;
            }

            try stdout.print("mov ", .{});
            switch (mod_reg_rm.mode) {
                Binary.Mode.MemoryNoDisplacement => {
                    if (w_flag) {
                        var disp_lo: u8 = undefined;
                        var disp_hi: u16 = undefined;

                        if (current.next) |next| {
                            const disp_lo_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                            disp_lo = disp_lo_byte.data;
                            count += 1;
                            current = next;
                        } else {
                            return error.ExpectedDispLo;
                        }

                        if (current.next) |next| {
                            const disp_hi_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                            disp_hi = disp_hi_byte.data;
                            count += 1;
                            current = next;
                        } else {
                            return error.ExpectedDispHi;
                        }
                        const displacement = (disp_hi << 8) | disp_lo;

                        try stdout.print("[", .{});
                        try writeEffectiveAddress(stdout, mod_reg_rm.rm);
                        try stdout.print("], word {d}\n", .{displacement});
                    } else {
                        var disp: u8 = undefined;

                        if (current.next) |next| {
                            const disp_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                            disp = disp_byte.data;
                            count += 1;
                            current = next;
                        } else {
                            return error.ExpectedDispLo;
                        }

                        try stdout.print("[", .{});
                        try writeEffectiveAddress(stdout, mod_reg_rm.rm);
                        try stdout.print("], byte {d}\n", .{disp});
                    }
                },
                Binary.Mode.Memory8BitDisplacement => {
                    // 8 bit displacement allows for the displacement to be
                    // signed. It does this by performing sign extension
                    // on the byte and using that as the displacement value.
                    var disp_lo: u8 = undefined;
                    if (current.next) |next| {
                        const disp_lo_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                        disp_lo = disp_lo_byte.data;
                        count += 1;
                        current = next;
                    } else {
                        return error.ExpectedDispLo;
                    }

                    const msb_set = (0b1000_0000 & disp_lo) == 0b1000_0000;
                    const disp_hi: u16 =
                        if (msb_set)
                            0b1111_1111_0000_0000
                        else
                            0b0000_0000_0000_0000;
                    const displacement: i16 = @bitCast(disp_hi | disp_lo);
                    const op: u8 = if (displacement >= 0) '+' else '-';

                    // Read immediate value
                    const immediate = immediate: {
                        var data_lo: u8 = undefined;

                        if (current.next) |next| {
                            const lo_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                            data_lo = lo_byte.data;
                            count += 1;
                            current = next;
                        } else {
                            return error.ExpectedDataLo;
                        }

                        if (!w_flag) {
                            break :immediate data_lo;
                        }

                        var data_hi: u16 = undefined;
                        if (current.next) |next| {
                            const hi_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                            data_hi = hi_byte.data;
                            count += 1;
                            current = next;
                        } else {
                            return error.ExpectedDataHi;
                        }
                        break :immediate (data_hi << 8) | data_lo;
                    };
                    const size_keyword: *const [4:0]u8 = if (w_flag) "word" else "byte";

                    try stdout.print("[", .{});
                    try writeEffectiveAddress(stdout, mod_reg_rm.rm);
                    try stdout.print(" {c} {d}], {s} {d}\n", .{ op, @abs(displacement), size_keyword, immediate });
                },
                Binary.Mode.Memory16BitDisplacement => {
                    // Read two bytes for the displacement value
                    var disp_lo: u8 = undefined;
                    var disp_hi: u16 = undefined;

                    if (current.next) |next| {
                        const disp_lo_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                        disp_lo = disp_lo_byte.data;
                        count += 1;
                        current = next;
                    } else {
                        return error.ExpectedDispLo;
                    }

                    if (current.next) |next| {
                        const disp_hi_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                        disp_hi = disp_hi_byte.data;
                        count += 1;
                        current = next;
                    } else {
                        return error.ExpectedDispHi;
                    }
                    const displacement = (disp_hi << 8) | disp_lo;
                    const op: u8 = if (displacement >= 0) '+' else '-';

                    // Read immediate value
                    const immediate = immediate: {
                        var data_lo: u8 = undefined;

                        if (current.next) |next| {
                            const lo_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                            data_lo = lo_byte.data;
                            count += 1;
                            current = next;
                        } else {
                            return error.ExpectedDataLo;
                        }

                        if (!w_flag) {
                            break :immediate data_lo;
                        }

                        var data_hi: u16 = undefined;
                        if (current.next) |next| {
                            const hi_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                            data_hi = hi_byte.data;
                            count += 1;
                            current = next;
                        } else {
                            return error.ExpectedDataHi;
                        }
                        break :immediate (data_hi << 8) | data_lo;
                    };
                    const size_keyword: *const [4:0]u8 = if (w_flag) "word" else "byte";

                    try stdout.print("[", .{});
                    try writeEffectiveAddress(stdout, mod_reg_rm.rm);
                    try stdout.print(" {c} {d}], {s} {d}\n", .{ op, @abs(displacement), size_keyword, immediate });
                },
                else => {
                    std.debug.print("Invalid mode for  \"Immediate to register/memory\" instruction. mode: {any}\n", .{mod_reg_rm.mode});
                    return error.InvalidInstruction;
                },
            }
        },
        .ImmToReg => |m| {
            const w_flag = m.w;
            const register_encoding = m.reg;
            const reg = Register.make(register_encoding, w_flag);

            if (w_flag) {
                var data_lo: u8 = undefined;
                var data_hi: u16 = undefined;

                if (current.next) |next| {
                    const lo_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                    data_lo = lo_byte.data;
                    count += 1;
                    current = next;
                } else {
                    return error.ExpectedDataLo;
                }

                if (current.next) |next| {
                    const hi_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                    data_hi = hi_byte.data;
                    count += 1;
                    current = next;
                } else {
                    return error.ExpectedDataHi;
                }
                const immediate: u16 = (data_hi << 8) | data_lo;
                try stdout.print("mov {s}, {d}\n", .{ reg.emit(), immediate });
            } else {
                var data: u8 = undefined;

                if (current.next) |next| {
                    const byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                    data = byte.data;
                    count += 1;
                    current = next;
                } else {
                    return error.ExpectedDataLo;
                }
                try stdout.print("mov {s}, {d}\n", .{ reg.emit(), data });
            }
        },
        .AccToMem => |m| {
            const w_flag = m.w;

            var data_lo: u8 = undefined;
            var data_hi: u16 = undefined;

            if (current.next) |next| {
                const lo_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                data_lo = lo_byte.data;
                count += 1;
                current = next;
            } else {
                return error.ExpectedDataLo;
            }

            if (current.next) |next| {
                const hi_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                data_hi = hi_byte.data;
                count += 1;
                current = next;
            } else {
                return error.ExpectedDataHi;
            }
            const addr = (data_hi << 8) | data_lo;

            // If we're only moving 8 bits, move into AL
            const register = if (w_flag) Register.AX else Register.AL;
            try stdout.print("mov [{d}], {s}\n", .{ addr, register.emit() });
        },
        .MemToAcc => |m| {
            const w_flag = m.w;
            var data_lo: u8 = undefined;
            var data_hi: u16 = undefined;

            if (current.next) |next| {
                const lo_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                data_lo = lo_byte.data;
                count += 1;
                current = next;
            } else {
                return error.ExpectedDataLo;
            }

            if (current.next) |next| {
                const hi_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                data_hi = hi_byte.data;
                count += 1;
                current = next;
            } else {
                return error.ExpectedDataHi;
            }
            const addr = (data_hi << 8) | data_lo;

            // If we're only moving 8 bits, move into AL
            const register = if (w_flag) Register.AX else Register.AL;
            try stdout.print("mov {s}, [{d}]\n", .{ register.emit(), addr });
        },
    }

    return count;
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
