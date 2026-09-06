const std = @import("std");
const hal = @import("zamgba-hal");
const physics = @import("physics/physics.zig");
const AABB = physics.AABB;
const Fixed24_8 = physics.Fixed24_8;
const CollisionMap = physics.CollisionMap;
const CollisionMask = physics.CollisionMask;
const Collision = physics.Collision;

const gfx2d = @import("gfx2d/gfx2d.zig");
const StaticTile = gfx2d.StaticTile;
const AnimatedTiles = gfx2d.AnimatedTiles;
const SpriteSheet = gfx2d.SpriteSheet;
const AnimationMode = gfx2d.AnimationMode;
const AnimationTag = gfx2d.AnimationTag;
const TileError = gfx2d.TileError;

pub const SpriteError = error{
    InvalidDimensions,
    Unimplemented,
};

const ShapeSize = struct {
    shape: u16,
    size: u16,
};

/// Validates width and height against GBA hardware OBJ dimensions and returns Shape and Size bits.
fn getShapeAndSize(width: u16, height: u16) SpriteError!ShapeSize {
    if (width == 8 and height == 8) return .{ .shape = hal.oam.Shape.SQUARE, .size = hal.oam.Size.SIZE_0 };
    if (width == 16 and height == 16) return .{ .shape = hal.oam.Shape.SQUARE, .size = hal.oam.Size.SIZE_1 };
    if (width == 32 and height == 32) return .{ .shape = hal.oam.Shape.SQUARE, .size = hal.oam.Size.SIZE_2 };
    if (width == 64 and height == 64) return .{ .shape = hal.oam.Shape.SQUARE, .size = hal.oam.Size.SIZE_3 };

    if (width == 16 and height == 8) return .{ .shape = hal.oam.Shape.HORIZONTAL, .size = hal.oam.Size.SIZE_0 };
    if (width == 32 and height == 8) return .{ .shape = hal.oam.Shape.HORIZONTAL, .size = hal.oam.Size.SIZE_1 };
    if (width == 32 and height == 16) return .{ .shape = hal.oam.Shape.HORIZONTAL, .size = hal.oam.Size.SIZE_2 };
    if (width == 64 and height == 32) return .{ .shape = hal.oam.Shape.HORIZONTAL, .size = hal.oam.Size.SIZE_3 };

    if (width == 8 and height == 16) return .{ .shape = hal.oam.Shape.VERTICAL, .size = hal.oam.Size.SIZE_0 };
    if (width == 8 and height == 32) return .{ .shape = hal.oam.Shape.VERTICAL, .size = hal.oam.Size.SIZE_1 };
    if (width == 16 and height == 32) return .{ .shape = hal.oam.Shape.VERTICAL, .size = hal.oam.Size.SIZE_2 };
    if (width == 32 and height == 64) return .{ .shape = hal.oam.Shape.VERTICAL, .size = hal.oam.Size.SIZE_3 };

    return SpriteError.InvalidDimensions;
}

/// Result of collision check during movement.
pub const CollisionResult = struct {
    collided_x: bool = false,
    collided_y: bool = false,

    pub fn hasCollided(self: CollisionResult) bool {
        return self.collided_x or self.collided_y;
    }
};

/// High-level orthogonal Sprite: encapsulates AABB, velocity, collision layers, flips, and visibility.
pub const Sprite = struct {
    aabb: AABB,
    velocity_x: Fixed24_8 = Fixed24_8.zero,
    velocity_y: Fixed24_8 = Fixed24_8.zero,

    /// 16-bit collision layer (self classification)
    layer: CollisionMask = Collision.NONE,

    /// 16-bit collision mask (layers this sprite interacts with)
    mask: CollisionMask = Collision.ALL,

    /// Horizontal flip (face left / right)
    h_flip: bool = false,

    /// Vertical flip
    v_flip: bool = false,

    visible: bool = true,

    /// Initialize a Sprite with Fixed24_8 sub-pixel coordinates and validates GBA hardware sprite dimensions.
    pub fn init(x: Fixed24_8, y: Fixed24_8, width: u16, height: u16) SpriteError!Sprite {
        _ = try getShapeAndSize(width, height);
        return .{
            .aabb = AABB.init(x, y, width, height),
        };
    }

    /// Check if this sprite can interact with another sprite based on 16-bit layer and mask filtering.
    pub inline fn canCollideWith(self: *const Sprite, other: *const Sprite) bool {
        return Collision.canInteract(self.layer, self.mask, other.layer, other.mask);
    }

    /// Internal helper to advance and collide a single axis (X or Y).
    fn moveAxis(self: *Sprite, collision_map: CollisionMap, axis: enum { x, y }) bool {
        const vel = switch (axis) {
            .x => self.velocity_x,
            .y => self.velocity_y,
        };
        if (vel.raw == 0) return false;

        const test_box = switch (axis) {
            .x => AABB.init(self.aabb.x.add(vel), self.aabb.y, self.aabb.width, self.aabb.height),
            .y => AABB.init(self.aabb.x, self.aabb.y.add(vel), self.aabb.width, self.aabb.height),
        };

        if (collision_map.isColliding(test_box)) {
            switch (axis) {
                .x => self.velocity_x = Fixed24_8.zero,
                .y => self.velocity_y = Fixed24_8.zero,
            }
            return true;
        } else {
            switch (axis) {
                .x => self.aabb.x = test_box.x,
                .y => self.aabb.y = test_box.y,
            }
            return false;
        }
    }

    /// Move the sprite by its current velocity, checking and resolving collisions
    /// independently on X and Y axes against the CollisionMap.
    pub fn moveAndCollide(self: *Sprite, collision_map: CollisionMap) CollisionResult {
        return .{
            .collided_x = self.moveAxis(collision_map, .x),
            .collided_y = self.moveAxis(collision_map, .y),
        };
    }
};

/// Compiles an engine-level sprite and provided static tile into a hardware OAM attribute.
/// Internal OAM attribute builder.
///
/// Design Decision:
/// `Sprite` is a pure spatial/physics entity (position, velocity, AABB, flips, collision masks)
/// and deliberately does NOT hold graphical tile metadata (tile_index, palette_bank, bpp).
/// Conversely, `StaticTile` and `AnimatedTiles` only hold tile descriptors without spatial context.
///
/// GBA hardware OAM requires BOTH spatial bits (Attr0/Attr1) and graphical tile bits (Attr2).
/// Therefore, `compileOamAttr` is kept module-private to enforce that only complete composite
/// entities (`StaticSprite`, `AnimatedSprite`) expose public `toOamAttr()` methods to `engine.drawSprite()`.
fn compileOamAttr(spr: *const Sprite, tile_attr: StaticTile) hal.oam.ObjAttr {
    if (!spr.visible) {
        return .{ .attr0 = 160, .attr1 = 0, .attr2 = 0, .fill = 0 };
    }

    const shape_size = getShapeAndSize(spr.aabb.width, spr.aabb.height) catch ShapeSize{
        .shape = hal.oam.Shape.SQUARE,
        .size = hal.oam.Size.SIZE_0,
    };

    const y_val: i32 = @intCast(spr.aabb.y.toInt());
    const x_val: i32 = @intCast(spr.aabb.x.toInt());

    const y_hw: u16 = @as(u16, @bitCast(@as(i16, @truncate(y_val)))) & 0x00FF;
    const x_hw: u16 = @as(u16, @bitCast(@as(i16, @truncate(x_val)))) & 0x01FF;

    const bpp_bit: u16 = if (tile_attr.bpp == .bpp8) (1 << 13) else 0;
    const h_flip_bit: u16 = if (spr.h_flip) (1 << 12) else 0;
    const v_flip_bit: u16 = if (spr.v_flip) (1 << 13) else 0;

    const attr0: u16 = y_hw | (shape_size.shape << 14) | bpp_bit;
    const attr1: u16 = x_hw | (shape_size.size << 14) | h_flip_bit | v_flip_bit;
    const attr2: u16 = (tile_attr.tile_index & 0x03FF) | (@as(u16, tile_attr.palette_bank & 0x0F) << 12);

    return .{
        .attr0 = attr0,
        .attr1 = attr1,
        .attr2 = attr2,
        .fill = 0,
    };
}

/// Composite structure: Combines a Sprite with a StaticTile.
pub const StaticSprite = struct {
    sprite: Sprite,
    tile: StaticTile = .{},

    pub fn init(x: Fixed24_8, y: Fixed24_8, width: u16, height: u16, tile_attr: StaticTile) SpriteError!StaticSprite {
        return .{
            .sprite = try Sprite.init(x, y, width, height),
            .tile = tile_attr,
        };
    }

    pub fn toOamAttr(self: *const StaticSprite) hal.oam.ObjAttr {
        return compileOamAttr(&self.sprite, self.tile);
    }

    /// Fills GBA OBJ VRAM and updates OBJ PALRAM with solid color tile graphics.
    pub fn fillSolidColor(self: *const StaticSprite, color: gfx2d.Color) gfx2d.TileError!void {
        return self.tile.fillSolidColor(self.sprite.aabb.width, self.sprite.aabb.height, color);
    }
};

/// Composite structure: Combines a spatial Sprite with AnimatedTiles.
pub const AnimatedSprite = struct {
    sprite: Sprite,
    tiles: AnimatedTiles,

    /// Creates and initializes an animated sprite from a converted SpriteSheet and position.
    pub fn init(sheet: *const SpriteSheet, mode: AnimationMode, x: Fixed24_8, y: Fixed24_8) (TileError || SpriteError)!AnimatedSprite {
        const tiles = try AnimatedTiles.init(sheet, mode);
        const spr = try Sprite.init(x, y, sheet.width, sheet.height);
        return .{
            .sprite = spr,
            .tiles = tiles,
        };
    }

    /// Releases any allocated VRAM slot back to the VramAllocator.
    pub fn deinit(self: *AnimatedSprite) void {
        self.tiles.deinit();
    }

    /// Selects an animation tag by name (e.g. "fly", "run", "idle").
    pub fn setAnimation(self: *AnimatedSprite, tag_name: []const u8) TileError!void {
        return self.tiles.setAnimation(tag_name);
    }

    /// Selects an animation tag by index without runtime string lookup.
    pub fn setAnimationByIndex(self: *AnimatedSprite, tag_index: usize) TileError!void {
        return self.tiles.setAnimationByIndex(tag_index);
    }

    /// Directly sets the current frame index.
    pub fn setFrame(self: *AnimatedSprite, frame_index: usize) TileError!void {
        return self.tiles.setFrame(frame_index);
    }

    /// Advances the animation frame timer by 1 tick (~16.6ms at 60Hz).
    pub fn update(self: *AnimatedSprite) void {
        self.tiles.update();
    }

    /// Compiles into a GBA hardware OAM attribute.
    pub fn toOamAttr(self: *const AnimatedSprite) hal.oam.ObjAttr {
        return compileOamAttr(&self.sprite, self.tiles.getTile());
    }

    /// Accesses the underlying Sprite component.
    pub fn getSprite(self: *AnimatedSprite) *Sprite {
        return &self.sprite;
    }
};

test "SPR001: init validates dimensions" {
    const spr = try Sprite.init(Fixed24_8.fromInt(10), Fixed24_8.fromInt(20), 8, 8);
    try std.testing.expectEqual(@as(u16, 8), spr.aabb.width);
    try std.testing.expectEqual(@as(u16, 8), spr.aabb.height);

    try std.testing.expectError(SpriteError.InvalidDimensions, Sprite.init(Fixed24_8.fromInt(10), Fixed24_8.fromInt(20), 12, 12));
}

test "SPR002: getShapeAndSize valid dimensions" {
    // Square
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.SQUARE, .size = hal.oam.Size.SIZE_0 }, try getShapeAndSize(8, 8));
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.SQUARE, .size = hal.oam.Size.SIZE_1 }, try getShapeAndSize(16, 16));
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.SQUARE, .size = hal.oam.Size.SIZE_2 }, try getShapeAndSize(32, 32));
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.SQUARE, .size = hal.oam.Size.SIZE_3 }, try getShapeAndSize(64, 64));

    // Horizontal
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.HORIZONTAL, .size = hal.oam.Size.SIZE_0 }, try getShapeAndSize(16, 8));
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.HORIZONTAL, .size = hal.oam.Size.SIZE_1 }, try getShapeAndSize(32, 8));
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.HORIZONTAL, .size = hal.oam.Size.SIZE_2 }, try getShapeAndSize(32, 16));
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.HORIZONTAL, .size = hal.oam.Size.SIZE_3 }, try getShapeAndSize(64, 32));

    // Vertical
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.VERTICAL, .size = hal.oam.Size.SIZE_0 }, try getShapeAndSize(8, 16));
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.VERTICAL, .size = hal.oam.Size.SIZE_1 }, try getShapeAndSize(8, 32));
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.VERTICAL, .size = hal.oam.Size.SIZE_2 }, try getShapeAndSize(16, 32));
    try std.testing.expectEqual(ShapeSize{ .shape = hal.oam.Shape.VERTICAL, .size = hal.oam.Size.SIZE_3 }, try getShapeAndSize(32, 64));
}

test "SPR003: getShapeAndSize invalid dimensions" {
    try std.testing.expectError(SpriteError.InvalidDimensions, getShapeAndSize(10, 10));
    try std.testing.expectError(SpriteError.InvalidDimensions, getShapeAndSize(8, 80));
    try std.testing.expectError(SpriteError.InvalidDimensions, getShapeAndSize(128, 128));
}

test "SPR004: toOamAttr encoding with StaticTile" {
    var spr = try Sprite.init(Fixed24_8.fromInt(10), Fixed24_8.fromInt(20), 16, 32); // Vertical (shape 2, size 2)
    const tile_attr = StaticTile{ .tile_index = 4, .palette_bank = 2, .bpp = .bpp4 };

    const attr = compileOamAttr(&spr, tile_attr);
    // attr0: Y=20 (0x14), shape=2 -> (2 << 14) | 20 = 0x8014
    try std.testing.expectEqual(@as(u16, 0x8014), attr.attr0);
    // attr1: X=10 (0x0A), size=2 -> (2 << 14) | 10 = 0x800A
    try std.testing.expectEqual(@as(u16, 0x800A), attr.attr1);
    // attr2: tile_index=4, palette_bank=2 -> (2 << 12) | 4 = 0x2004
    try std.testing.expectEqual(@as(u16, 0x2004), attr.attr2);
}

fn mockWallAtTile3_0(tx: u16, ty: u16) bool {
    return tx == 3 and ty == 0;
}

test "SPR007: Sprite moveAndCollide stops against map obstacles" {
    const map = CollisionMap.init(.size_256x256, mockWallAtTile3_0, .solid);

    // Sprite at x=8, y=0, size 8x8 (tile 1, 0)
    var spr = try Sprite.init(Fixed24_8.fromInt(8), Fixed24_8.fromInt(0), 8, 8);
    spr.velocity_x = Fixed24_8.fromInt(8); // Move right by 8 pixels per step

    // Step 1: Moves from x=8 to x=16 (tile 2) -> Clear
    var res = spr.moveAndCollide(map);
    try std.testing.expect(!res.hasCollided());
    try std.testing.expectEqual(@as(i32, 16), spr.aabb.x.toInt());

    // Step 2: Next step would move from x=16 to x=24 (tile 3, which is solid) -> Collision!
    res = spr.moveAndCollide(map);
    try std.testing.expect(res.collided_x);
    try std.testing.expect(!res.collided_y);
    try std.testing.expect(res.hasCollided());
    try std.testing.expectEqual(@as(i32, 16), spr.aabb.x.toInt());
    try std.testing.expectEqual(Fixed24_8.zero.raw, spr.velocity_x.raw);

    // Step 3: Test negative velocity (moving left)
    spr.velocity_x = Fixed24_8.fromInt(-8);
    res = spr.moveAndCollide(map);
    try std.testing.expect(!res.hasCollided());
    try std.testing.expectEqual(@as(i32, 8), spr.aabb.x.toInt());
}

test "SPR008: Sprite collision via AABB" {
    const spr1 = try Sprite.init(Fixed24_8.fromInt(10), Fixed24_8.fromInt(10), 16, 16);
    const spr2 = try Sprite.init(Fixed24_8.fromInt(20), Fixed24_8.fromInt(20), 16, 16);
    const spr3 = try Sprite.init(Fixed24_8.fromInt(50), Fixed24_8.fromInt(50), 16, 16);

    try std.testing.expect(spr1.aabb.isColliding(spr2.aabb));
    try std.testing.expect(spr1.aabb.collidesWith(spr2.aabb));
    try std.testing.expect(!spr1.aabb.isColliding(spr3.aabb));
}

test "SPR009: Sprite layer and mask filtering" {
    var player = try Sprite.init(Fixed24_8.fromInt(0), Fixed24_8.fromInt(0), 16, 16);
    player.layer = Collision.layer(0); // Layer 0: Player
    player.mask = Collision.layer(1); // Mask: Only Enemy (Layer 1)

    var enemy = try Sprite.init(Fixed24_8.fromInt(0), Fixed24_8.fromInt(0), 16, 16);
    enemy.layer = Collision.layer(1); // Layer 1: Enemy
    enemy.mask = Collision.layer(0); // Mask: Only Player (Layer 0)

    var item = try Sprite.init(Fixed24_8.fromInt(0), Fixed24_8.fromInt(0), 8, 8);
    item.layer = Collision.layer(2); // Layer 2: Item
    item.mask = Collision.layer(3); // Mask: Layer 3

    // Player and Enemy can collide
    try std.testing.expect(player.canCollideWith(&enemy));
    try std.testing.expect(enemy.canCollideWith(&player));

    // Player and Item cannot collide (masks do not match)
    try std.testing.expect(!player.canCollideWith(&item));
    try std.testing.expect(!item.canCollideWith(&player));
}

test "SPR010: toOamAttr horizontal and vertical flip encoding" {
    var spr = try Sprite.init(Fixed24_8.fromInt(10), Fixed24_8.fromInt(20), 16, 16);
    spr.h_flip = true;
    spr.v_flip = true;
    const tile_attr = StaticTile{ .tile_index = 0, .palette_bank = 0, .bpp = .bpp4 };

    const attr = compileOamAttr(&spr, tile_attr);
    const expected_attr1: u16 = 10 | (1 << 14) | (1 << 12) | (1 << 13);
    try std.testing.expectEqual(expected_attr1, attr.attr1);
}

test "SPR011: toOamAttr 8-bpp color mode encoding" {
    const spr = try Sprite.init(Fixed24_8.fromInt(10), Fixed24_8.fromInt(20), 32, 32);
    const tile_attr = StaticTile{ .tile_index = 0, .palette_bank = 0, .bpp = .bpp8 };

    const attr = compileOamAttr(&spr, tile_attr);
    const expected_attr0: u16 = 20 | (1 << 13);
    try std.testing.expectEqual(expected_attr0, attr.attr0);
}

test "SPR013: StaticSprite composition and toOamAttr output" {
    const static_spr = try StaticSprite.init(Fixed24_8.fromInt(15), Fixed24_8.fromInt(25), 32, 16, .{
        .tile_index = 12,
        .palette_bank = 4,
        .bpp = .bpp4,
    });

    const attr = static_spr.toOamAttr();
    // 32x16 Horizontal: shape=1, size=2 -> attr0 has (1 << 14) | 25, attr1 has (2 << 14) | 15
    try std.testing.expectEqual(@as(u16, (1 << 14) | 25), attr.attr0);
    try std.testing.expectEqual(@as(u16, (2 << 14) | 15), attr.attr1);
    try std.testing.expectEqual(@as(u16, (4 << 12) | 12), attr.attr2);
}

test "SPR014: StaticSprite composition and toOamAttr with custom palette bank" {
    const solid_spr = try StaticSprite.init(Fixed24_8.fromInt(5), Fixed24_8.fromInt(10), 8, 8, .{
        .tile_index = 1,
        .palette_bank = 2,
    });

    try std.testing.expectEqual(@as(u16, 1), solid_spr.tile.tile_index);
    try std.testing.expectEqual(@as(u4, 2), solid_spr.tile.palette_bank);

    const attr = solid_spr.toOamAttr();
    try std.testing.expectEqual(@as(u16, 10), attr.attr0);
    try std.testing.expectEqual(@as(u16, 5), attr.attr1);
    try std.testing.expectEqual(@as(u16, (2 << 12) | 1), attr.attr2);
}

test "ANI007: AnimatedSprite composition and toOamAttr output" {
    const dummy_sheet = SpriteSheet{
        .bpp = .bpp4,
        .width = 16,
        .height = 16,
        .tile_count_per_frame = 4,
        .frame_count = 2,
        .tiles = &[_]u8{0} ** 256,
        .durations_ms = &[_]u16{ 100, 100 },
        .tags = &[_]AnimationTag{
            .{ .name = "idle", .from_frame = 0, .to_frame = 1, .direction = .forward },
        },
    };

    var anim_spr = try AnimatedSprite.init(&dummy_sheet, .static, Fixed24_8.fromInt(20), Fixed24_8.fromInt(30));
    defer anim_spr.deinit();

    try anim_spr.setAnimation("idle");
    try std.testing.expectError(TileError.TagNotFound, anim_spr.setAnimation("non_existent"));

    try anim_spr.setAnimationByIndex(0);
    try std.testing.expectError(TileError.TagNotFound, anim_spr.setAnimationByIndex(5));

    try anim_spr.setFrame(1);
    try std.testing.expectError(TileError.InvalidFrameIndex, anim_spr.setFrame(10));

    const spr = anim_spr.getSprite();
    spr.h_flip = true;

    const attr = anim_spr.toOamAttr();
    try std.testing.expectEqual(@as(u16, 30), attr.attr0 & 0x00FF);
    try std.testing.expectEqual(@as(u16, 20 | (1 << 14) | (1 << 12)), attr.attr1);
}

fn mockAllPassable(_: u16, _: u16) bool {
    return false;
}

test "SPR015: moveAndCollide boundary handling in all 4 directions across solid and empty maps" {
    const map_solid = CollisionMap.init(.size_256x256, mockAllPassable, .solid);
    const map_empty = CollisionMap.init(.size_256x256, mockAllPassable, .empty);

    // 1. Move Left across boundary x=0 (x: 4 -> -4, span [-4, 4))
    {
        var spr_solid = try Sprite.init(Fixed24_8.fromInt(4), Fixed24_8.fromInt(64), 8, 8);
        spr_solid.velocity_x = Fixed24_8.fromInt(-8);
        const res_solid = spr_solid.moveAndCollide(map_solid);
        try std.testing.expect(res_solid.collided_x);
        try std.testing.expectEqual(@as(i32, 4), spr_solid.aabb.x.toInt());
        try std.testing.expectEqual(Fixed24_8.zero.raw, spr_solid.velocity_x.raw);

        var spr_empty = try Sprite.init(Fixed24_8.fromInt(4), Fixed24_8.fromInt(64), 8, 8);
        spr_empty.velocity_x = Fixed24_8.fromInt(-8);
        const res_empty = spr_empty.moveAndCollide(map_empty);
        try std.testing.expect(!res_empty.collided_x);
        try std.testing.expectEqual(@as(i32, -4), spr_empty.aabb.x.toInt());
    }

    // 2. Move Right across boundary x=256 (x: 248 -> 256, span [256, 264))
    {
        var spr_solid = try Sprite.init(Fixed24_8.fromInt(248), Fixed24_8.fromInt(64), 8, 8);
        spr_solid.velocity_x = Fixed24_8.fromInt(8);
        const res_solid = spr_solid.moveAndCollide(map_solid);
        try std.testing.expect(res_solid.collided_x);
        try std.testing.expectEqual(@as(i32, 248), spr_solid.aabb.x.toInt());
        try std.testing.expectEqual(Fixed24_8.zero.raw, spr_solid.velocity_x.raw);

        var spr_empty = try Sprite.init(Fixed24_8.fromInt(248), Fixed24_8.fromInt(64), 8, 8);
        spr_empty.velocity_x = Fixed24_8.fromInt(8);
        const res_empty = spr_empty.moveAndCollide(map_empty);
        try std.testing.expect(!res_empty.collided_x);
        try std.testing.expectEqual(@as(i32, 256), spr_empty.aabb.x.toInt());
    }

    // 3. Move Top across boundary y=0 (y: 4 -> -4, span [-4, 4))
    {
        var spr_solid = try Sprite.init(Fixed24_8.fromInt(64), Fixed24_8.fromInt(4), 8, 8);
        spr_solid.velocity_y = Fixed24_8.fromInt(-8);
        const res_solid = spr_solid.moveAndCollide(map_solid);
        try std.testing.expect(res_solid.collided_y);
        try std.testing.expectEqual(@as(i32, 4), spr_solid.aabb.y.toInt());
        try std.testing.expectEqual(Fixed24_8.zero.raw, spr_solid.velocity_y.raw);

        var spr_empty = try Sprite.init(Fixed24_8.fromInt(64), Fixed24_8.fromInt(4), 8, 8);
        spr_empty.velocity_y = Fixed24_8.fromInt(-8);
        const res_empty = spr_empty.moveAndCollide(map_empty);
        try std.testing.expect(!res_empty.collided_y);
        try std.testing.expectEqual(@as(i32, -4), spr_empty.aabb.y.toInt());
    }

    // 4. Move Bottom across boundary y=256 (y: 248 -> 256, span [256, 264))
    {
        var spr_solid = try Sprite.init(Fixed24_8.fromInt(64), Fixed24_8.fromInt(248), 8, 8);
        spr_solid.velocity_y = Fixed24_8.fromInt(8);
        const res_solid = spr_solid.moveAndCollide(map_solid);
        try std.testing.expect(res_solid.collided_y);
        try std.testing.expectEqual(@as(i32, 248), spr_solid.aabb.y.toInt());
        try std.testing.expectEqual(Fixed24_8.zero.raw, spr_solid.velocity_y.raw);

        var spr_empty = try Sprite.init(Fixed24_8.fromInt(64), Fixed24_8.fromInt(248), 8, 8);
        spr_empty.velocity_y = Fixed24_8.fromInt(8);
        const res_empty = spr_empty.moveAndCollide(map_empty);
        try std.testing.expect(!res_empty.collided_y);
        try std.testing.expectEqual(@as(i32, 256), spr_empty.aabb.y.toInt());
    }
}
