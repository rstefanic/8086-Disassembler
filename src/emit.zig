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

        // Write out the label if this instruction has one
        if (byte.label_ref) |label_ref| {
            try stdout.print("label_{d}:\n", .{label_ref});
        }

        const instruction = Instructions.Instruction.make(byte.data);
        const count = switch (instruction) {
            .mov => |mov| try parseMov(mov, node, stdout),
            .add => |add| try parseAdd(add, node, stdout),
            .je => try parseJe(node, stdout),
            .jl => try parseJl(node, stdout),
            .jle => try parseJle(node, stdout),
            .jb => try parseJb(node, stdout),
            .jbe => try parseJbe(node, stdout),
            .jp => try parseJp(node, stdout),
            .jo => try parseJo(node, stdout),
            .js => try parseJs(node, stdout),
            .jnz => try parseJnz(node, stdout),
            .jnl => try parseJnl(node, stdout),
            .jnle => try parseJnle(node, stdout),
            .jnb => try parseJnb(node, stdout),
            .jnbe => try parseJnbe(node, stdout),
            .jnp => try parseJnp(node, stdout),
            .jno => try parseJno(node, stdout),
            .jns => try parseJns(node, stdout),
            .loop => try parseLoop(node, stdout),
            .loopz => try parseLoopz(node, stdout),
            .loopnz => try parseLoopnz(node, stdout),
            .jcxz => try parseJcxz(node, stdout),
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

fn parseAdd(add: Instructions.Add, node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    var count: usize = 0;
    var current = node;

    switch (add) {
        .RegMemWithRegToEither => |a| {
            const w_flag = a.w;
            const d_flag = a.d;

            var mod_reg_rm: Binary.ModeRegRm = undefined;
            if (current.next) |next| {
                const mod_reg_rm_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                mod_reg_rm = @bitCast(mod_reg_rm_byte.data);
                current = next;
                count += 1;
            } else {
                return error.ExpectedModRegRm;
            }

            try stdout.print("add ", .{});
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
        .ImmToRegMem => |a| {
            const w_flag = a.w;
            const s_flag = a.w;

            var mod_reg_rm: Binary.ModeRegRm = undefined;
            if (current.next) |next| {
                const mod_reg_rm_byte: *Disassemble.Byte = @fieldParentPtr("node", next);
                mod_reg_rm = @bitCast(mod_reg_rm_byte.data);
                current = next;
                count += 1;
            } else {
                return error.ExpectedModRegRm;
            }

            try stdout.print("add ", .{});
            switch (mod_reg_rm.mode) {
                Binary.Mode.Register => {
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

                        if (s_flag or !w_flag) {
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
                    try stdout.print("], {s} {d}\n", .{ size_keyword, immediate });
                },
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

                        if (s_flag or !w_flag) {
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

                        if (s_flag or !w_flag) {
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
            }
        },
        .ImmToAcc => |a| {
            const w_flag = a.w;

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

            const register = if (w_flag) Register.AX else Register.AL;
            try stdout.print("add {s}, [{d}]\n", .{ register.emit(), immediate });
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

fn findLabelRef(node: *DoublyLinkedList.Node, displacement: i8) usize {
    var current: ?*DoublyLinkedList.Node = node;

    // Account for the displacement starting from the next instruction.
    var n = displacement + 1;
    while (current) |curr_node| {
        std.debug.assert(current != null);

        if (n > 0) {
            current = curr_node.next;
            n -= 1;
        } else if (n < 0) {
            current = curr_node.prev;
            n += 1;
        } else {
            break;
        }
    }

    const byte: *Disassemble.Byte = @fieldParentPtr("node", current.?);
    std.debug.assert(byte.label_ref != null);
    return byte.label_ref.?;
}

inline fn emitShortJump(stdout: *std.Io.Writer, current: *DoublyLinkedList.Node, mneominc: []const u8, displacement: i8) !void {
    const label_ref = findLabelRef(current, displacement);
    try stdout.print("{s} label_{d}\t; {d}\n", .{ mneominc, label_ref, displacement });
}

fn parseByteFromNode(node: *DoublyLinkedList.Node, expected_type: Disassemble.ByteType) *Disassemble.Byte {
    const byte: *Disassemble.Byte = @fieldParentPtr("node", node);
    if (byte.type != expected_type) {
        std.debug.print("Expected \"{any}\"; Got \"{any}\"\n", .{ expected_type, byte.type });
        @panic("Unexpected Byte type");
    }
    return byte;
}

fn parseJumpDisplacement(node: *DoublyLinkedList.Node) !i8 {
    const disp_lo_byte: *Disassemble.Byte = parseByteFromNode(node, .DispLo);
    const displacement: i8 = @bitCast(disp_lo_byte.data);
    return displacement;
}

fn parseJe(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "je", displacement);
    }

    return 1;
}

fn parseJl(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jl", displacement);
    }

    return 1;
}

fn parseJle(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jle", displacement);
    }

    return 1;
}

fn parseJb(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jb", displacement);
    }

    return 1;
}

fn parseJbe(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jbe", displacement);
    }

    return 1;
}

fn parseJp(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jp", displacement);
    }

    return 1;
}

fn parseJo(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jo", displacement);
    }

    return 1;
}

fn parseJs(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "js", displacement);
    }

    return 1;
}

fn parseJnz(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jnz", displacement);
    }

    return 1;
}

fn parseJnl(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jnl", displacement);
    }

    return 1;
}

fn parseJnle(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jnle", displacement);
    }

    return 1;
}

fn parseJnb(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jnb", displacement);
    }

    return 1;
}

fn parseJnbe(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jnbe", displacement);
    }

    return 1;
}

fn parseJnp(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jnp", displacement);
    }

    return 1;
}

fn parseJno(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jno", displacement);
    }

    return 1;
}

fn parseJns(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jns", displacement);
    }

    return 1;
}

fn parseLoop(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "loop", displacement);
    }

    return 1;
}

fn parseLoopz(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "loopz", displacement);
    }

    return 1;
}

fn parseLoopnz(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "loopnz", displacement);
    }

    return 1;
}

fn parseJcxz(node: *DoublyLinkedList.Node, stdout: *std.Io.Writer) !usize {
    if (node.next) |next| {
        const displacement = try parseJumpDisplacement(next);
        try emitShortJump(stdout, next, "jcxz", displacement);
    }

    return 1;
}
