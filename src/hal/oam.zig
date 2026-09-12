const std = @import("std");
const specs = @import("specs.zig");

/// OAM hardware definition
/// A single OAM entry is 64 bits (8 bytes):
/// attr0 (16-bit), attr1 (16-bit), attr2 (16-bit), affine (16-bit).
pub const ObjAttr = packed struct {
    attr0: u16,
    attr1: u16,
    attr2: u16,
    fill: u16, // padding / affine index
};

/// OAM Object Shapes (attr0 bits 14-15)
pub const Shape = struct {
    pub const SQUARE: u16 = 0;
    pub const HORIZONTAL: u16 = 1;
    pub const VERTICAL: u16 = 2;
    pub const FORBIDDEN: u16 = 3;
};

/// OAM Object Sizes (attr1 bits 14-15)
pub const Size = struct {
    pub const SIZE_0: u16 = 0; // Square: 8x8, Horizontal: 16x8, Vertical: 8x16
    pub const SIZE_1: u16 = 1; // Square: 16x16, Horizontal: 32x8, Vertical: 8x32
    pub const SIZE_2: u16 = 2; // Square: 32x32, Horizontal: 32x16, Vertical: 16x32
    pub const SIZE_3: u16 = 3; // Square: 64x64, Horizontal: 64x32, Vertical: 32x64
};

/// GBA hardware-supported sprite sizes mapped directly to OAM Shape (attr0) and Size (attr1).
pub const SpriteSize = enum(u4) {
    size_8x8,
    size_16x16,
    size_32x32,
    size_64x64,
    size_16x8,
    size_32x8,
    size_32x16,
    size_64x32,
    size_8x16,
    size_8x32,
    size_16x32,
    size_32x64,

    /// Number of 8x8 4-bpp hardware tile slots (32-byte units) occupied by this sprite size.
    pub inline fn tileCount(self: SpriteSize) u16 {
        return switch (self) {
            .size_8x8 => 1,
            .size_16x8, .size_8x16 => 2,
            .size_16x16, .size_32x8, .size_8x32 => 4,
            .size_32x16, .size_16x32 => 8,
            .size_32x32 => 16,
            .size_64x32, .size_32x64 => 32,
            .size_64x64 => 64,
        };
    }

    /// Returns the OAM Shape (attr0 bits 14-15) corresponding to this sprite size.
    pub inline fn toShape(self: SpriteSize) u16 {
        return switch (self) {
            .size_8x8, .size_16x16, .size_32x32, .size_64x64 => Shape.SQUARE,
            .size_16x8, .size_32x8, .size_32x16, .size_64x32 => Shape.HORIZONTAL,
            .size_8x16, .size_8x32, .size_16x32, .size_32x64 => Shape.VERTICAL,
        };
    }

    /// Returns the OAM Size (attr1 bits 14-15) corresponding to this sprite size.
    pub inline fn toSize(self: SpriteSize) u16 {
        return switch (self) {
            .size_8x8, .size_16x8, .size_8x16 => Size.SIZE_0,
            .size_16x16, .size_32x8, .size_8x32 => Size.SIZE_1,
            .size_32x32, .size_32x16, .size_16x32 => Size.SIZE_2,
            .size_64x64, .size_64x32, .size_32x64 => Size.SIZE_3,
        };
    }

    /// Converts width and height (in pixels) to SpriteSize if valid, otherwise returns error.InvalidSpriteSize.
    pub fn fromDimensions(width: u16, height: u16) error{InvalidSpriteSize}!SpriteSize {
        return switch (width) {
            8 => switch (height) {
                8 => .size_8x8,
                16 => .size_8x16,
                32 => .size_8x32,
                else => error.InvalidSpriteSize,
            },
            16 => switch (height) {
                8 => .size_16x8,
                16 => .size_16x16,
                32 => .size_16x32,
                else => error.InvalidSpriteSize,
            },
            32 => switch (height) {
                8 => .size_32x8,
                16 => .size_32x16,
                32 => .size_32x32,
                64 => .size_32x64,
                else => error.InvalidSpriteSize,
            },
            64 => switch (height) {
                32 => .size_64x32,
                64 => .size_64x64,
                else => error.InvalidSpriteSize,
            },
            else => error.InvalidSpriteSize,
        };
    }
};

test "OAM001: SpriteSize toShape and toSize mapping" {
    // Square sizes
    try std.testing.expectEqual(Shape.SQUARE, SpriteSize.size_8x8.toShape());
    try std.testing.expectEqual(Size.SIZE_0, SpriteSize.size_8x8.toSize());
    try std.testing.expectEqual(Shape.SQUARE, SpriteSize.size_16x16.toShape());
    try std.testing.expectEqual(Size.SIZE_1, SpriteSize.size_16x16.toSize());
    try std.testing.expectEqual(Shape.SQUARE, SpriteSize.size_32x32.toShape());
    try std.testing.expectEqual(Size.SIZE_2, SpriteSize.size_32x32.toSize());
    try std.testing.expectEqual(Shape.SQUARE, SpriteSize.size_64x64.toShape());
    try std.testing.expectEqual(Size.SIZE_3, SpriteSize.size_64x64.toSize());

    // Horizontal sizes
    try std.testing.expectEqual(Shape.HORIZONTAL, SpriteSize.size_16x8.toShape());
    try std.testing.expectEqual(Size.SIZE_0, SpriteSize.size_16x8.toSize());
    try std.testing.expectEqual(Shape.HORIZONTAL, SpriteSize.size_32x8.toShape());
    try std.testing.expectEqual(Size.SIZE_1, SpriteSize.size_32x8.toSize());
    try std.testing.expectEqual(Shape.HORIZONTAL, SpriteSize.size_32x16.toShape());
    try std.testing.expectEqual(Size.SIZE_2, SpriteSize.size_32x16.toSize());
    try std.testing.expectEqual(Shape.HORIZONTAL, SpriteSize.size_64x32.toShape());
    try std.testing.expectEqual(Size.SIZE_3, SpriteSize.size_64x32.toSize());

    // Vertical sizes
    try std.testing.expectEqual(Shape.VERTICAL, SpriteSize.size_8x16.toShape());
    try std.testing.expectEqual(Size.SIZE_0, SpriteSize.size_8x16.toSize());
    try std.testing.expectEqual(Shape.VERTICAL, SpriteSize.size_8x32.toShape());
    try std.testing.expectEqual(Size.SIZE_1, SpriteSize.size_8x32.toSize());
    try std.testing.expectEqual(Shape.VERTICAL, SpriteSize.size_16x32.toShape());
    try std.testing.expectEqual(Size.SIZE_2, SpriteSize.size_16x32.toSize());
    try std.testing.expectEqual(Shape.VERTICAL, SpriteSize.size_32x64.toShape());
    try std.testing.expectEqual(Size.SIZE_3, SpriteSize.size_32x64.toSize());
}
