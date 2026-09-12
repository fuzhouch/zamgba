const std = @import("std");
const hal = @import("zamgba-hal");
const specs = hal.specs;

pub const SpriteSize = hal.oam.SpriteSize;

pub const VramError = error{
    OutOfVram,
    BlockNotAllocated,
};

const TOTAL_TILES: u16 = specs.Tile.TOTAL_OBJ_TILES;
const MAX_ORDER: usize = 10; // 2^10 = 1024
const ORDER_COUNT: usize = MAX_ORDER + 1;
const NULL_INDEX: i16 = -1;

/// Hardware allocation descriptor returned by VramAllocator.
pub const VramAllocation = struct {
    tile_index: u16, // Hardware base tile index (0..1023)
    tile_count: u16, // Number of 32-byte slot units allocated
    byte_offset: u32, // Offset in bytes from OBJ VRAM base (0x06010000)

    pub fn toVramPointer(self: VramAllocation, base_vram: [*]volatile u16) [*]volatile u16 {
        return base_vram + (@as(usize, self.tile_index) * specs.Tile.WORDS_4BPP);
    }
};

const BlockNode = struct {
    order: u4 = 0,
    is_free: bool = false,
    next: i16 = NULL_INDEX,
    prev: i16 = NULL_INDEX,
};

var nodes: [TOTAL_TILES]BlockNode = undefined;
var free_lists: [ORDER_COUNT]i16 = undefined;
var free_tile_count: u16 = TOTAL_TILES;
var is_initialized: bool = false;

fn pushFree(order: usize, idx: i16) void {
    const old_head = free_lists[order];
    nodes[@as(usize, @intCast(idx))].next = old_head;
    nodes[@as(usize, @intCast(idx))].prev = NULL_INDEX;
    nodes[@as(usize, @intCast(idx))].is_free = true;
    nodes[@as(usize, @intCast(idx))].order = @as(u4, @intCast(order));

    if (old_head != NULL_INDEX) {
        nodes[@as(usize, @intCast(old_head))].prev = idx;
    }
    free_lists[order] = idx;
}

fn removeFree(order: usize, idx: i16) void {
    const u_idx = @as(usize, @intCast(idx));
    const p = nodes[u_idx].prev;
    const n = nodes[u_idx].next;

    if (p != NULL_INDEX) {
        nodes[@as(usize, @intCast(p))].next = n;
    } else {
        free_lists[order] = n;
    }

    if (n != NULL_INDEX) {
        nodes[@as(usize, @intCast(n))].prev = p;
    }

    nodes[u_idx].next = NULL_INDEX;
    nodes[u_idx].prev = NULL_INDEX;
    nodes[u_idx].is_free = false;
}

fn popFree(order: usize) ?i16 {
    const head = free_lists[order];
    if (head == NULL_INDEX) return null;
    removeFree(order, head);
    return head;
}

/// Clears all allocations and resets VRAM state to 1024 contiguous free tiles.
pub fn reset() void {
    for (&nodes) |*n| {
        n.* = .{
            .order = 0,
            .is_free = false,
            .next = NULL_INDEX,
            .prev = NULL_INDEX,
        };
    }
    for (&free_lists) |*head| {
        head.* = NULL_INDEX;
    }

    pushFree(MAX_ORDER, 0);
    free_tile_count = TOTAL_TILES;
    is_initialized = true;
}

/// Allocates a contiguous VRAM block suitable for a sprite with given SpriteSize and bit depth.
pub fn alloc(size: SpriteSize, bpp: hal.specs.BppMode) VramError!VramAllocation {
    const units = size.tileCount() << @intFromEnum(bpp);
    return allocUnits(units);
}

/// Computes the smallest power-of-2 buddy tree order (0..10) capable of holding `units`.
/// Example: 1 unit -> Order 0 (2^0 = 1), 32 units -> Order 5 (2^5 = 32), 33 units -> Order 6 (2^6 = 64).
fn unitsToOrder(units: u16) usize {
    if (units <= 1) return 0;
    const leading_zeros = @as(usize, @clz(units - 1));
    return 16 - leading_zeros;
}

/// Allocates a block with exact power-of-2 unit count.
pub fn allocUnits(units: u16) VramError!VramAllocation {
    std.debug.assert(is_initialized);
    if (units == 0 or units > TOTAL_TILES) {
        return error.OutOfVram;
    }

    // Determine target buddy order (ceil to power of 2)
    const target_order = unitsToOrder(units);
    if (target_order > MAX_ORDER) {
        return error.OutOfVram;
    }

    // Find smallest available order >= target_order
    var order: usize = target_order;
    while (order <= MAX_ORDER and free_lists[order] == NULL_INDEX) : (order += 1) {}

    if (order > MAX_ORDER) {
        return error.OutOfVram;
    }

    // Pop the block and split buddies downwards if needed
    const blk_idx = popFree(order).?;
    while (order > target_order) {
        order -= 1;
        const buddy_idx = blk_idx + @as(i16, @intCast(@as(u16, 1) << @as(u4, @intCast(order))));
        pushFree(order, buddy_idx);
    }

    nodes[@as(usize, @intCast(blk_idx))].order = @as(u4, @intCast(target_order));
    nodes[@as(usize, @intCast(blk_idx))].is_free = false;

    const allocated_units = @as(u16, 1) << @as(u4, @intCast(target_order));
    free_tile_count -= allocated_units;

    return VramAllocation{
        .tile_index = @as(u16, @intCast(blk_idx)),
        .tile_count = allocated_units,
        .byte_offset = @as(u32, @intCast(blk_idx)) * @as(u32, @intCast(specs.Tile.BYTES_4BPP)),
    };
}

/// Frees an allocated VRAM block and coalesces adjacent buddies.
pub fn free(alloc_info: VramAllocation) VramError!void {
    std.debug.assert(is_initialized);

    const blk_idx = alloc_info.tile_index;
    if (blk_idx >= TOTAL_TILES or nodes[blk_idx].is_free) {
        return error.BlockNotAllocated;
    }

    var current_idx: i16 = @as(i16, @intCast(blk_idx));
    var current_order: usize = nodes[blk_idx].order;
    const allocated_units = @as(u16, 1) << @as(u4, @intCast(current_order));
    free_tile_count += allocated_units;

    // Coalesce buddies upwards
    while (current_order < MAX_ORDER) {
        const buddy_idx = current_idx ^ @as(i16, @intCast(@as(u16, 1) << @as(u4, @intCast(current_order))));
        if (buddy_idx < 0 or buddy_idx >= @as(i16, @intCast(TOTAL_TILES))) break;

        const u_buddy = @as(usize, @intCast(buddy_idx));
        if (nodes[u_buddy].is_free and nodes[u_buddy].order == current_order) {
            removeFree(current_order, buddy_idx);
            current_idx = @min(current_idx, buddy_idx);
            current_order += 1;
        } else {
            break;
        }
    }

    pushFree(current_order, current_idx);
}

/// Returns the total number of free 32-byte 4-bpp tile units currently available.
pub fn getFreeTileCount() u16 {
    std.debug.assert(is_initialized);
    return free_tile_count;
}

test "VRM001: SpriteSize tileCount and fromDimensions" {
    // 4-bpp / 8-bpp tile unit calculations
    try std.testing.expectEqual(@as(u16, 1), SpriteSize.size_8x8.tileCount() << @intFromEnum(hal.specs.BppMode.bpp4));
    try std.testing.expectEqual(@as(u16, 4), SpriteSize.size_16x16.tileCount() << @intFromEnum(hal.specs.BppMode.bpp4));
    try std.testing.expectEqual(@as(u16, 16), SpriteSize.size_32x32.tileCount() << @intFromEnum(hal.specs.BppMode.bpp4));
    try std.testing.expectEqual(@as(u16, 64), SpriteSize.size_64x64.tileCount() << @intFromEnum(hal.specs.BppMode.bpp4));

    try std.testing.expectEqual(@as(u16, 2), SpriteSize.size_8x8.tileCount() << @intFromEnum(hal.specs.BppMode.bpp8));
    try std.testing.expectEqual(@as(u16, 8), SpriteSize.size_16x16.tileCount() << @intFromEnum(hal.specs.BppMode.bpp8));
    try std.testing.expectEqual(@as(u16, 32), SpriteSize.size_32x32.tileCount() << @intFromEnum(hal.specs.BppMode.bpp8));
    try std.testing.expectEqual(@as(u16, 128), SpriteSize.size_64x64.tileCount() << @intFromEnum(hal.specs.BppMode.bpp8));

    // fromDimensions tests
    try std.testing.expectEqual(SpriteSize.size_8x8, try SpriteSize.fromDimensions(8, 8));
    try std.testing.expectEqual(SpriteSize.size_16x16, try SpriteSize.fromDimensions(16, 16));
    try std.testing.expectEqual(SpriteSize.size_64x32, try SpriteSize.fromDimensions(64, 32));
    try std.testing.expectError(error.InvalidSpriteSize, SpriteSize.fromDimensions(7, 8));
    try std.testing.expectError(error.InvalidSpriteSize, SpriteSize.fromDimensions(0, 16));
}

test "VRM002: alloc single 8x8 4bpp sprite (1 unit)" {
    reset();
    const a1 = try alloc(.size_8x8, .bpp4);
    try std.testing.expectEqual(@as(u16, 0), a1.tile_index);
    try std.testing.expectEqual(@as(u16, 1), a1.tile_count);
    try std.testing.expectEqual(@as(u32, 0), a1.byte_offset);

    // Validate block splitting when allocating 1 single block
    try std.testing.expectEqual(@as(i16, NULL_INDEX), free_lists[10]);
    try std.testing.expectEqual(@as(i16, hal.specs.Tile.TOTAL_OBJ_TILES / 2), free_lists[9]);
    try std.testing.expectEqual(@as(i16, hal.specs.Tile.TOTAL_OBJ_TILES / 4), free_lists[8]);
    try std.testing.expectEqual(@as(i16, hal.specs.Tile.TOTAL_OBJ_TILES / 8), free_lists[7]);
    try std.testing.expectEqual(@as(i16, hal.specs.Tile.TOTAL_OBJ_TILES / 16), free_lists[6]);
    try std.testing.expectEqual(@as(i16, hal.specs.Tile.TOTAL_OBJ_TILES / 32), free_lists[5]);
    try std.testing.expectEqual(@as(i16, hal.specs.Tile.TOTAL_OBJ_TILES / 64), free_lists[4]);
    try std.testing.expectEqual(@as(i16, hal.specs.Tile.TOTAL_OBJ_TILES / 128), free_lists[3]);
    try std.testing.expectEqual(@as(i16, hal.specs.Tile.TOTAL_OBJ_TILES / 256), free_lists[2]);
    try std.testing.expectEqual(@as(i16, hal.specs.Tile.TOTAL_OBJ_TILES / 512), free_lists[1]);
    try std.testing.expectEqual(@as(i16, hal.specs.Tile.TOTAL_OBJ_TILES / 1024), free_lists[0]);
    // Meanwhile, nodes contains allocated buffer
    try std.testing.expectEqual(false, nodes[0].is_free);
    try std.testing.expectEqual(0, nodes[0].order);
    try std.testing.expectEqual(NULL_INDEX, nodes[0].prev);
    try std.testing.expectEqual(NULL_INDEX, nodes[0].next);

    const allocated_idx = [_]usize{ 1, 2, 4, 8, 16, 32, 64, 128, 256, 512 };
    const allocated_order = [_]u4{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    for (allocated_idx, allocated_order) |i, o| {
        try std.testing.expectEqual(true, nodes[i].is_free);
        try std.testing.expectEqual(o, nodes[i].order);
        try std.testing.expectEqual(NULL_INDEX, nodes[i].prev);
        try std.testing.expectEqual(NULL_INDEX, nodes[i].next);
    }

    // Now free the allocated block. The status should be reverted.
    try free(a1);
    try std.testing.expectEqual(@as(i16, 0), free_lists[10]);
    for (0..9) |i| {
        try std.testing.expectEqual(@as(i16, NULL_INDEX), free_lists[i]);
    }
    try std.testing.expectEqual(true, nodes[0].is_free);
    try std.testing.expectEqual(10, nodes[0].order);
    try std.testing.expectEqual(NULL_INDEX, nodes[0].prev);
    try std.testing.expectEqual(NULL_INDEX, nodes[0].next);
}

test "VRM003: alloc 32x32 8bpp sprite (32 units)" {
    reset();
    const a1 = try alloc(.size_32x32, .bpp8);
    try std.testing.expectEqual(@as(u16, 0), a1.tile_index);
    try std.testing.expectEqual(@as(u16, 32), a1.tile_count);
    try std.testing.expectEqual(@as(u32, 0), a1.byte_offset);
}

test "VRM004: buddy splitting and merging on free" {
    reset();
    const a1 = try alloc(.size_16x16, .bpp4); // 4 units (index 0..3)
    const a2 = try alloc(.size_16x16, .bpp4); // 4 units (index 4..7)

    try std.testing.expectEqual(@as(u16, 0), a1.tile_index);
    try std.testing.expectEqual(@as(u16, 4), a2.tile_index);

    try free(a1);
    try free(a2);

    try std.testing.expectEqual(TOTAL_TILES, getFreeTileCount());
}

test "VRM005: OutOfVram error when memory exhausted" {
    reset();
    // 64x64 8-bpp sprite takes 128 units. 8 such sprites consume 8 * 128 = 1024 units (100% VRAM).
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        _ = try alloc(.size_64x64, .bpp8);
    }

    // 9th allocation must fail
    try std.testing.expectError(error.OutOfVram, alloc(.size_8x8, .bpp4));
}

test "VRM006: free invalid block or double-free returns BlockNotAllocated" {
    reset();
    const a1 = try alloc(.size_16x16, .bpp4);
    try free(a1);

    // Double-free must fail
    try std.testing.expectError(error.BlockNotAllocated, free(a1));

    // Invalid tile index must fail
    const invalid_alloc = VramAllocation{
        .tile_index = 2000,
        .tile_count = 4,
        .byte_offset = 2000 * @as(u32, @intCast(specs.Tile.BYTES_4BPP)),
    };
    try std.testing.expectError(error.BlockNotAllocated, free(invalid_alloc));
}

test "VRM007: allocUnits edge cases and toVramPointer" {
    reset();
    try std.testing.expectError(error.OutOfVram, allocUnits(0));
    try std.testing.expectError(error.OutOfVram, allocUnits(2048));

    const a = try allocUnits(16);
    // Base OBJ VRAM address
    const mock_vram = specs.MemorySections.OBJ_VRAM;
    const ptr = a.toVramPointer(mock_vram);
    try std.testing.expectEqual(@intFromPtr(specs.MemorySections.OBJ_VRAM), @intFromPtr(ptr));
}

test "VRM008: unitsToOrder computes exact power-of-2 order" {
    try std.testing.expectEqual(@as(usize, 0), unitsToOrder(0));
    try std.testing.expectEqual(@as(usize, 0), unitsToOrder(1));
    try std.testing.expectEqual(@as(usize, 1), unitsToOrder(2));
    try std.testing.expectEqual(@as(usize, 2), unitsToOrder(3)); // Ceil: 3 -> 4 (Order 2)
    try std.testing.expectEqual(@as(usize, 2), unitsToOrder(4));
    try std.testing.expectEqual(@as(usize, 3), unitsToOrder(8));
    try std.testing.expectEqual(@as(usize, 4), unitsToOrder(16));
    try std.testing.expectEqual(@as(usize, 5), unitsToOrder(32));
    try std.testing.expectEqual(@as(usize, 6), unitsToOrder(64));
    try std.testing.expectEqual(@as(usize, 7), unitsToOrder(128));
    try std.testing.expectEqual(@as(usize, 10), unitsToOrder(1024));
}
