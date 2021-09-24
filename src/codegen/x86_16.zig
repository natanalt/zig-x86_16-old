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

    /// Convert from any register to its 32 bit alias.
    pub fn to32(self: Register) Register {
        _ = self;
        @compileError("x86_16: Register.to32() is never going to exist");
    }

    /// Convert from any register to its 16 bit alias.
    pub fn to16(self: Register) Register {
        return @intToEnum(Register, @as(u8, self.id()) + 8);
    }

    /// Convert from any register to its 8 bit alias.
    pub fn to8(self: Register) Register {
        return @intToEnum(Register, @as(u8, self.id()) + 16);
    }

    pub fn dwarfLocOp(reg: Register) u8 {
        _ = reg;
        unreachable;
    }
};

// zig fmt: on

pub const callee_preserved_regs = [_]Register{ .ax, .cx, .dx, .si, .di };