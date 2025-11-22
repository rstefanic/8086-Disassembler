const Disassemble = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const DoublyLinkedList = std.DoublyLinkedList;

const Binary = @import("binary.zig");
const Instructions = @import("instruction.zig");

pub const ByteType = enum {
    Instruction,
    ModRegRm,
    DispLo,
    DispHi,
    DataLo,
    DataHi,
    AddrLo,
    AddrHi,
};

pub const Byte = struct {
    data: u8,
    label_ref: ?usize,
    type: ByteType,
    node: DoublyLinkedList.Node,
};

allocator: Allocator,
code: std.DoublyLinkedList,

pub fn init(allocator: Allocator, binary: *Binary) !Disassemble {
    var code: std.DoublyLinkedList = .{};

    while (!binary.eof()) {
        const byte = try binary.next();
        const instruction = Instructions.Instruction.make(byte);
        const instruction_byte = try tagByte(allocator, byte, .Instruction);
        code.append(&instruction_byte.node);

        switch (instruction) {
            .mov => |mov| try handleMovInstruction(allocator, mov, binary, &code),
            .add => |add| try handleAddInstruction(allocator, add, binary, &code),
            .je, .jl, .jle, .jb, .jbe, .jp, .jo, .js, .jnz, .jnl, .jnle, .jnb, .jnbe, .jnp, .jno, .jns, .loop, .loopz, .loopnz, .jcxz => 
                try handleJmpInstruction(allocator, binary, &code),
        }
    }

    // Once we've finished tagging all the bytes, we want to do a pass through
    // to tag instructions that are referenced by other instructions with labels.
    var current = code.first;
    var label_count: usize = 1;
    while (current) |node| {
        const byte: *Byte = @fieldParentPtr("node", node);

        // We only need to inspect instructions
        if (byte.type == .Instruction) {
            const instruction = Instructions.Instruction.make(byte.data);
            switch (instruction) {
                .je, .jl, .jle, .jb, .jbe, .jp, .jo, .js, .jnz, .jnl, .jnle, .jnb, .jnbe, .jnp, .jno, .jns, .loop, .loopz, .loopnz, .jcxz => {
                    // Read the displacement byte.
                    const next = node.next;
                    std.debug.assert(next != null);
                    const disp_byte: *Byte = @fieldParentPtr("node", next.?);
                    std.debug.assert(disp_byte.type == .DispLo);

                    var displacement: i8 = @bitCast(disp_byte.data);

                    // The displacement occurs from the start of the *next*
                    // instruction and not the current instruction. This is
                    // because the CPU has already decoded the instruction and
                    // it's ready to decode the next instruction, so the
                    // displacement is calculated from the next instruction.
                    displacement += 1;

                    // Find where we're jumping to.
                    const to = relativeNode(next.?, displacement);
                    std.debug.assert(to != null);

                    // Ensure it's an instruction.
                    const jump_byte: *Byte = @fieldParentPtr("node", to.?);
                    std.debug.assert(jump_byte.type == .Instruction);

                    // Make sure the instruction has a label number so it can be referenced.
                    if (jump_byte.*.label_ref == null) {
                        jump_byte.*.label_ref = label_count;
                        label_count += 1;
                    }
                },
                else => {},
            }
        }

        current = node.next;
    }

    return Disassemble{ .allocator = allocator, .code = code };
}

pub fn deinit(self: *const Disassemble) void {
    var node: ?*DoublyLinkedList.Node = self.code.first;
    while (node) |n| {
        const byte: *Byte = @fieldParentPtr("node", n);
        node = n.next;
        self.allocator.destroy(byte);
    }
}

fn handleMovInstruction(allocator: Allocator, mov: Instructions.Mov, binary: *Binary, code: *DoublyLinkedList) !void {
    switch (mov) {
        .RegMemToFromReg => |_| {
            try tagBytesModRegRmWithDisp(allocator, binary, code);
        },
        .ImmToRegMem => |*m| {
            const w_flag = m.*.w;
            try tagBytesImmToRegMem(allocator, binary, code, w_flag, null);
        },
        .ImmToReg => |*m| {
            try tagBytesData(allocator, binary, code, m.*.w, null);
        },
        .AccToMem => |*m| {
            try tagBytesData(allocator, binary, code, m.*.w, null);
        },
        .MemToAcc => |*m| {
            try tagBytesData(allocator, binary, code, m.*.w, null);
        },
    }
}

fn handleAddInstruction(allocator: Allocator, add: Instructions.Add, binary: *Binary, code: *DoublyLinkedList) !void {
    switch (add) {
        .RegMemWithRegToEither => {
            try tagBytesModRegRmWithDisp(allocator, binary, code);
        },
        .ImmToRegMem => |*a| {
            const w_flag = a.*.w;
            const s_flag = a.*.s;
            try tagBytesImmToRegMem(allocator, binary, code, w_flag, s_flag);
        },
        .ImmToAcc => |*a| {
            try tagBytesData(allocator, binary, code, a.*.w, null);
        },
    }
}

fn handleJmpInstruction(allocator: Allocator, binary: *Binary, code: *DoublyLinkedList) !void {
    const displacement = try binary.next();
    const diplacement_byte = try tagByte(allocator, displacement, .DispLo);
    code.append(&diplacement_byte.node);
}

fn tagByte(allocator: Allocator, data: u8, tag: ByteType) !*Byte {
    const byte = try allocator.create(Byte);
    byte.* = .{
        .data = data,
        .label_ref = null,
        .type = tag,
        .node = .{},
    };
    return byte;
}

fn relativeNode(node: *DoublyLinkedList.Node, count: i8) ?*DoublyLinkedList.Node {
    var current: ?*DoublyLinkedList.Node = node;
    var remaining = count;
    while (true) {
        std.debug.assert(current != null);

        if (remaining > 0) {
            current = current.?.next;
            remaining -= 1;
        } else if (remaining < 0) {
            current = current.?.prev;
            remaining += 1;
        } else {
            break;
        }
    }

    return current;
}

fn tagBytesImmToRegMem(allocator: Allocator, binary: *Binary, code: *DoublyLinkedList, w_flag: bool, s_flag: ?bool) !void {
    const mod_reg_rm_val: u8 = try binary.next();
    const mod_reg_rm: Binary.ModeRegRm = @bitCast(mod_reg_rm_val);
    const mod_reg_rm_byte = try tagByte(allocator, mod_reg_rm_val, .ModRegRm);
    code.append(&mod_reg_rm_byte.node);

    switch (mod_reg_rm.mode) {
        Binary.Mode.MemoryNoDisplacement => {
            const data_lo_val = try binary.next();
            const data_lo = try tagByte(allocator, data_lo_val, .DataLo);
            code.append(&data_lo.node);

            if (s_flag) |s| {
                if (s == true) {
                    return;
                }
            }

            if (w_flag) {
                const data_hi_val = try binary.next();
                const data_hi = try tagByte(allocator, data_hi_val, .DataHi);
                code.append(&data_hi.node);
            }
        },
        Binary.Mode.Memory8BitDisplacement => {
            const disp_lo_val = try binary.next();
            const disp_lo = try tagByte(allocator, disp_lo_val, .DispLo);
            code.append(&disp_lo.node);

            const data_lo_val = try binary.next();
            const data_lo = try tagByte(allocator, data_lo_val, .DataLo);
            code.append(&data_lo.node);

            if (s_flag) |s| {
                if (s == true) {
                    return;
                }
            }

            if (w_flag) {
                const data_hi_val = try binary.next();
                const data_hi = try tagByte(allocator, data_hi_val, .DataHi);
                code.append(&data_hi.node);
            }
        },
        Binary.Mode.Memory16BitDisplacement => {
            const disp_lo_val = try binary.next();
            const disp_lo = try tagByte(allocator, disp_lo_val, .DispLo);
            code.append(&disp_lo.node);

            const disp_hi_val = try binary.next();
            const disp_hi = try tagByte(allocator, disp_hi_val, .DispHi);
            code.append(&disp_hi.node);

            // TODO: Try replacing the following lines with `tagBytesData`
            const data_lo_val = try binary.next();
            const data_lo = try tagByte(allocator, data_lo_val, .DataLo);
            code.append(&data_lo.node);

            if (s_flag) |s| {
                if (s == true) {
                    return;
                }
            }

            if (w_flag) {
                const data_hi_val = try binary.next();
                const data_hi = try tagByte(allocator, data_hi_val, .DispHi);
                code.append(&data_hi.node);
            }
        },
        Binary.Mode.Register => {
            try tagBytesData(allocator, binary, code, w_flag, s_flag);
        },
    }
}

fn tagBytesModRegRmWithDisp(allocator: Allocator, binary: *Binary, code: *DoublyLinkedList) !void {
    // Check out how much we'll need to read
    const mod_reg_rm_val: u8 = try binary.next();
    const mod_reg_rm: Binary.ModeRegRm = @bitCast(mod_reg_rm_val);
    const mod_reg_rm_byte = try tagByte(allocator, mod_reg_rm_val, .ModRegRm);
    code.append(&mod_reg_rm_byte.node);

    switch (mod_reg_rm.mode) {
        Binary.Mode.MemoryNoDisplacement => {
            // Handle the special case when there IS a displacement
            // when the MODE is set to "No Displacement".
            if (mod_reg_rm.rm == 0b110) {
                const byte_lo_val = try binary.next();
                const byte_lo = try tagByte(allocator, byte_lo_val, .DispLo);
                code.append(&byte_lo.node);

                const byte_hi_val = try binary.next();
                const byte_hi = try tagByte(allocator, byte_hi_val, .DispHi);
                code.append(&byte_hi.node);
            }
        },
        Binary.Mode.Memory8BitDisplacement => {
            const byte_lo_val = try binary.next();
            const byte_lo = try tagByte(allocator, byte_lo_val, .DispLo);
            code.append(&byte_lo.node);
        },
        Binary.Mode.Memory16BitDisplacement => {
            const byte_lo_val = try binary.next();
            const byte_lo = try tagByte(allocator, byte_lo_val, .DispLo);
            code.append(&byte_lo.node);

            const byte_hi_val = try binary.next();
            const byte_hi = try tagByte(allocator, byte_hi_val, .DispHi);
            code.append(&byte_hi.node);
        },
        Binary.Mode.Register => {
            // Nothing more to do
        },
    }
}

fn tagBytesData(allocator: Allocator, binary: *Binary, code: *DoublyLinkedList, w_flag: bool, s_flag: ?bool) !void {
    const data_lo_val = try binary.next();
    const data_lo = try tagByte(allocator, data_lo_val, .DataLo);
    code.append(&data_lo.node);

    if (s_flag) |s| {
        if (s) {
            return;
        }
    }

    if (w_flag) {
        const data_hi_val = try binary.next();
        const data_hi = try tagByte(allocator, data_hi_val, .DataHi);
        code.append(&data_hi.node);
    }
}
