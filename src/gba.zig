// This file contains code used by linker scripts when building GBA
// executable.

const root = @import("root");

// Memory section for hardware read/write
// REF: https://www.coranac.com/tonc/text/hardware.htm#sec-memory
pub const MemorySections = struct {
    // System ROM: 16KiB,  32bit bus, read-only, executable
    // EWRAM     : 256KiB, 16bit bus, multi-boot code.
    // IWRAM     : 32KiB,  32bit bus, for ARM code 
    // IO RAM    : 1KiB,   16bit bus, graphics, sound, buttons
    // PAL RAM   : 1KiB,   16bit bus, 2 palette, 256 colors, 15-bit
    // VRAM      : 96KiB,  16bit bus, Video
    // OAM       : 1KiB,   32bit bus, sprite control
    // PAK ROM   : 32MiB (variable), 16bit bus, Normal executable code
    // Cart ROM  : 16KiB (variable), 8bit bus, save data
    pub const SYSROM    = @as([*]u32,          @ptrFromInt(0x00000000));
    pub const EWRAM     = @as([*]u16,          @ptrFromInt(0x02000000));
    pub const IWRAM     = @as([*]u32,          @ptrFromInt(0x03000000));
    pub const IORAM     = @as([*]volatile u16, @ptrFromInt(0x04000000));
    pub const PALRAM    = @as([*]volatile u16, @ptrFromInt(0x05000000));
    pub const VRAM      = @as([*]volatile u16, @ptrFromInt(0x06000000));
    pub const OAM       = @as([*]volatile u32, @ptrFromInt(0x07000000));
    pub const PAKROM    = @as([*]u32,          @ptrFromInt(0x08000000));
    pub const CARTROM   = @as([*]volatile u32, @ptrFromInt(0x0E000000));

    pub const SYSROM_SIZE_BYTES  = 16 * 1024;
    pub const EWROM_SIZE_BYTES   = 256 * 1024;
    pub const IWROM_SIZE_BYTES   = 32 * 1024;
    pub const IORAM_SIZE_BYTES   = 1024;
    pub const PALRAM_SIZE_BYTES  = 1024;
    pub const VRAM_SIZE_BYTES    = 96 * 1024;
    pub const OARAM_SIZE_BYTES   = 1024;
    pub const PAKROM_SIZE_BYTES  = 32 * 1024 * 1024;
    pub const CARTROM_SIZE_BYTES = 64 * 1024;
};


pub const SCREEN_WIDTH_PIXELS = 240;
pub const SCREEN_HEIGHT_PIXELS = 160;

export fn _start() linksection(".text._start") void {
    asm volatile (
        \\.arm
        \\.cpu arm7tdmi
        \\b 1f
        \\.space 0xE0
        \\1:
        \\b 1b
    );
}
