const std = @import("std");

// zig fmt: off
pub const Register = enum(u8) {
    // 0-7, 16-bit registers. id is int value - 8.
    ax, cx, dx, bx, sp, bp, si, di,
    
    // 8-15, 8-bit registers. id is int value - 16.
    al, cl, dl, bl, ah, ch, dh, bh,

    /// Returns the bit-width of the register.
    pub fn size(self: @This()) u7 {
        return switch (@enumToInt(self)) {
            0...7 => 16,
            8...15 => 8,
            else => unreachable,
        };
    }

    /// Returns the register's id. This is used in practically every opcode the
    /// x86 has. It is embedded in some instructions, such as the `B8 +rd` move
    /// instruction, and is used in the R/M byte.
    pub fn id(self: @This()) u3 {
        return @truncate(u3, @enumToInt(self));
    }

    /// Returns the index into `callee_preserved_regs`.
    pub fn allocIndex(self: Register) ?u4 {
        return switch (self) {
            .ax, .al => 0,
            .cx, .cl => 1,
            .dx, .dl => 2,
            .si  => 3,
            .di => 4,
            else => null,
        };
    }

    /// Convert from any register to its 8 bit alias.
    pub fn to8(self: Register) Register {
        return @intToEnum(Register, @as(u8, self.id()) + 8);
    }

    pub fn dwarfLocOp(reg: Register) u8 {
        _ = reg;
        unreachable;
    }
};

// zig fmt: on

/// Type of an effective address
///
/// The underlying values are encoded as follows:
///  * bits 0-2 => R/M
///  * bits 3-4 => mod
///
/// Helped by: https://sandpile.org/x86/opc_rm16.htm
pub const EffectiveAddrType = enum(u5) {

    /// [bx + si]
    eff_bx_si = 0b00000,
    /// [bx + di]
    eff_bx_di = 0b00001,
    /// [bp + si] (defaults to SS)
    eff_bp_si = 0b00010,
    /// [bp + di] (defaults to SS)
    eff_bp_di = 0b00011,
    /// [si]
    eff_si = 0b00100,
    /// [di]
    eff_di = 0b00101,
    /// [imm16]
    eff_imm16 = 0b00110,
    /// [bx]
    eff_bx = 0b00111,

    /// [bx + si + imm8]
    eff_bx_si_imm8 = 0b01000,
    /// [bx + di + imm8]
    eff_bx_di_imm8 = 0b01001,
    /// [bp + si + imm8] (defaults to SS)
    eff_bp_si_imm8 = 0b01010,
    /// [bp + di + imm8] (defaults to SS)
    eff_bp_di_imm8 = 0b01011,
    /// [si + imm8]
    eff_si_imm8 = 0b01100,
    /// [di + imm8]
    eff_di_imm8 = 0b01101,
    /// [bp + imm8] (defaults to SS)
    eff_bp_imm8 = 0b01110,
    /// [bx + imm8]
    eff_bx_imm8 = 0b01111,

    /// [bx + si + imm16]
    eff_bx_si_imm16 = 0b10000,
    /// [bx + di + imm16]
    eff_bx_di_imm16 = 0b10001,
    /// [bp + si + imm16] (defaults to SS)
    eff_bp_si_imm16 = 0b10010,
    /// [bp + di + imm16] (defaults to SS)
    eff_bp_di_imm16 = 0b10011,
    /// [si + imm16]
    eff_si_imm16 = 0b10100,
    /// [di + imm16]
    eff_di_imm16 = 0b10101,
    /// [bp + imm16] (defaults to SS)
    eff_bp_imm16 = 0b10110,
    /// [bx + imm16]
    eff_bx_imm16 = 0b10111,

    /// Either al, or ax
    reg_0 = 0b11000,
    /// Either cl, or cx
    reg_1 = 0b11001,
    /// Either dl, or dx
    reg_2 = 0b11010,
    /// Either bl, or bx
    reg_3 = 0b11011,
    /// Either ah, or sp
    reg_4 = 0b11100,
    /// Either ch, or bp
    reg_5 = 0b11101,
    /// Either dh, or si
    reg_6 = 0b11110,
    /// Either bh, or di
    reg_7 = 0b11111,

    pub fn fromRegister(reg: Register) EffectiveAddrType {
        return switch (reg) {
            .al, .ax => .reg_0,
            .cl, .cx => .reg_1,
            .dl, .dx => .reg_2,
            .bl, .bx => .reg_3,
            .ah, .sp => .reg_4,
            .ch, .bp => .reg_5,
            .dh, .si => .reg_6,
            .bh, .di => .reg_7,
        };
    }

    pub fn getMod(self: EffectiveAddrType) u2 {
        return @truncate(u2, @enumToInt(self) >> 3);
    }

    pub fn getRM(self: EffectiveAddrType) u3 {
        return @truncate(u3, @enumToInt(self));
    }
    
    /// Returns size of an immediate that's meant to follow the Mod/RM byte
    pub fn immSize(self: EffectiveAddrType) usize {
        return switch (self.getMod()) {
            0b00 => if (self == .eff_imm16) 1 else 0,
            0b01 => 1,
            0b10 => 2,
            0b11 => 0,
        };
    }
};

/// Format of a Mod/RM byte:
///  * bits 0-2 => rm
///  * bits 3-5 => reg
///  * bits 6-7 => mod
pub fn createModRmByte(effective: EffectiveAddrType, other: Register) u8 {
    var result: u8 = 0;
    result |= @intCast(u8, effective.getRM()) << 0;
    result |= @intCast(u8, other.id()) << 3;
    result |= @intCast(u8, effective.getMod()) << 6;
    return result;
}

test "create 16-bit mod/rm" {
    std.testing.expectEqual(0x9a, createModRmByte(.eff_bp_si_imm16, .bx));
}

/// The primitive x86_16 assembler helper
pub const Encoder = struct {
    code: *std.ArrayList(u8),

    pub fn init(code: *std.ArrayList(u8)) Encoder {
        return Encoder{
            .code = code,
        };
    }

    pub fn imm8(self: *Encoder, imm: u8) !void {
        try self.code.append(imm);
    }

    pub fn imm16(self: *Encoder, imm: u16) !void {
        try self.code.append(@truncate(u8, imm >> 0));
        try self.code.append(@truncate(u8, imm >> 8));
    }

    pub fn modRm(self: *Encoder, effective: EffectiveAddrType, other: Register) !void {
        try self.imm8(createModRmByte(effective, other));
    }

    pub fn retn(self: *Encoder) !void {
        try self.imm8(0xc3);
    }

    /// Generates `mov dest, src`
    /// Asserts that dest and src are of an equal size
    pub fn moveRegToReg(self: *Encoder, dest: Register, src: Register) !void {
        if (dest.size() != src.size())
            @panic("x86_16 codegen bug: Encoder.moveRegToReg: dest and src are of different sizes");

        try self.moveRegToEff(EffectiveAddrType.fromRegister(dest), src);
    }

    pub fn moveRegToEff(self: *Encoder, dest: EffectiveAddrType, src: Register) !void {
        switch (src.size()) {
            8 => {
                // mov Eb, Gb
                try self.imm8(0x88);
                try self.modRm(dest, src);
            },
            16 => {
                // mov Ew, Gw
                try self.imm8(0x89);
                try self.modRm(dest, src);
            },
            else => unreachable,
        }
    }

    pub fn moveEffToReg(self: *Encoder, dest: Register, src: EffectiveAddrType) !void {
        switch (dest.size()) {
            8 => {
                // mov Gb, Eb
                try self.imm8(0x8a);
                try self.modRm(src, dest);
            },
            16 => {
                // mov Gw, Ew
                try self.imm8(0x8b);
                try self.modRm(src, dest);
            },
            else => unreachable,
        }
    }

    /// Generates `mov dest, val`
    /// Asserts that val can fit in the target register
    pub fn moveImmToReg(self: *Encoder, dest: Register, val: u16) !void {
        switch (dest.size()) {
            8 => {
                if (val > 0xFF)
                    @panic("x86_16 codegen bug: Encoder.moveImmToReg: val is too large for destination register");

                // mov Gb, imm8
                try self.imm8(@as(u8, 0xB0) + dest.id());
                try self.imm8(@truncate(u8, val));
            },
            16 => {
                // mov Gb, imm8
                try self.imm8(@as(u8, 0xB8) + dest.id());
                try self.imm16(val);
            },
            else => unreachable,
        }
    }

    pub fn addRegToReg(self: *Encoder, dest: Register, src: Register) !void {
        switch (dest.size()) {
            8 => {
                // add Eb, Gb
                try self.imm8(0x00);
                try self.modRm(EffectiveAddrType.fromRegister(dest), src);
            },
            16 => {
                // mov Ew, Gw
                try self.imm8(0x01);
                try self.modRm(EffectiveAddrType.fromRegister(dest), src);
            },
            else => unreachable,
        }
    }

    /// Generates `add reg, imm`
    /// Assertsthat val can fit in the target register
    pub fn addImmToReg(self: *Encoder, reg: Register, imm: u16) !void {
        if (reg.size() == 8 and imm > 0xFF)
            @panic("x86_16 codegen bug: Encoder.moveImmToReg: val is too large for destination register");

        switch (reg) {
            .al => {
                // add al, imm8
                try self.imm8(0x04);
                try self.imm8(@truncate(u8, imm));
            },
            .ax => {
                // add ax, imm8
                try self.imm8(0x05);
                try self.imm16(imm);
            },
            else => switch (reg.size()) {
                8 => {
                    // grp1 Eb, imm8 (reg=0, `add` opcode)
                    try self.imm8(0x80);
                    try self.modRm(EffectiveAddrType.fromRegister(reg), @intToEnum(Register, 0));
                    try self.imm8(@truncate(u8, imm));
                },
                16 => {
                    // grp1 Ew, imm16 (reg=0, `add` opcode)
                    try self.imm8(0x81);
                    try self.modRm(EffectiveAddrType.fromRegister(reg), @intToEnum(Register, 0));
                    try self.imm16(imm);
                },
                else => unreachable,
            },
        }
    }

    pub fn push(self: *Encoder, reg: Register) !void {
        try self.imm8(@as(u8, 0x50) + reg.id());
    }

    pub fn pop(self: *Encoder, reg: Register) !void {
        try self.imm8(@as(u8, 0x58) + reg.id());
    }
};

pub const callee_preserved_regs = [_]Register{ .ax, .cx, .dx, .si, .di };
