// This file contains code used by linker scripts when building GBA
// executable.

// I didn't copy logic from ZigGBA because I found the definition
// varies with other projects like https://github.com/ryankurte/rust-gba.git.
// Unfortunatley none of them can be built from latest Rust / Zig since
// 2024-01. I decide to understand the full progress to make a code
// boot from scratch. So I really understand how it works.
//
// The code below is based on GBATek 3.0 backup below:
// https://fabiensanglard.net/another_world_polygons_GBA/gbatech.html
// https://github.com/gbadev-org/gbadoc
// http://r32.github.io/other/2023-03-22-gba-dev.html
const header = @import("header.zig");

// Memory section for hardware read/write
// REF: https://www.coranac.com/tonc/text/hardware.htm#sec-memory
pub const MemorySections = struct {
    // System ROM: 00000000-00003FFF 16KiB,  32bit bus, read-only, executable
    //   Not used: 00004000-01FFFFFF
    // EWRAM     : 02000000-0203FFFF 256KiB, 16bit bus, multi-boot code.
    //   Not used: 02004000-02FFFFFF
    // IWRAM     : 03000000-03007FFF 32KiB,  32bit bus, for ARM code
    //   Not used: 03008000-03FFFFFF
    // IO RAM    : 04000000-040003FE 1KiB,   16bit bus, graphics, sound, buttons
    //   Not used: 04000400-04FFFFFF
    // PAL RAM   : 05000000-050003FF 1KiB,   16bit bus, 2 palette, 256 colors, 15-bit
    //   Not used: 05000400-05FFFFFF
    // VRAM      : 06000000-06017FFF 96KiB,  16bit bus, Video
    //   Not used: 06018000-06FFFFFF
    // OAM       : 07000000-070003FF 1KiB,   32bit bus, sprite control
    //   Not used: 07000400-07FFFFFF
    // PAK ROM   : 08000000-09FFFFFF 32MiB (variable), 16bit bus, Normal executable code
    // PAK ROM   : 0A000000-0BFFFFFF 32MiB (variable), 16bit bus, Normal executable code
    // PAK ROM   : 0C000000-0DFFFFFF 32MiB (variable), 16bit bus, Normal executable code
    // Cart SRAM : 0E000000-0E00FFFF 16KiB-64KiB (variable), 8bit bus, save data
    //   Not used: 0E010000-0FFFFFFF
    //   Not used: 10000000-FFFFFFFF
    pub const SYSROM = @as([*]u32, @ptrFromInt(0x00000000));
    pub const EWRAM = @as([*]u16, @ptrFromInt(0x02000000));
    pub const IWRAM = @as([*]u32, @ptrFromInt(0x03000000));
    pub const IORAM = @as([*]volatile u16, @ptrFromInt(0x04000000));
    pub const PALRAM = @as([*]volatile u16, @ptrFromInt(0x05000000));
    pub const VRAM = @as([*]volatile u16, @ptrFromInt(0x06000000));
    pub const OAM = @as([*]volatile u32, @ptrFromInt(0x07000000));
    pub const PAKROM = @as([*]u32, @ptrFromInt(0x08000000));
    pub const CARTROM = @as([*]volatile u32, @ptrFromInt(0x0E000000));

    pub const SYSROM_SIZE_BYTES = 16 * 1024;
    pub const EWROM_SIZE_BYTES = 256 * 1024;
    pub const IWROM_SIZE_BYTES = 32 * 1024;
    pub const IORAM_SIZE_BYTES = 1024;
    pub const PALRAM_SIZE_BYTES = 1024;
    pub const VRAM_SIZE_BYTES = 96 * 1024;
    pub const OARAM_SIZE_BYTES = 1024;
    pub const PAKROM_SIZE_BYTES = 32 * 1024 * 1024;
    pub const CARTROM_SIZE_BYTES = 64 * 1024;
};

pub const SCREEN_WIDTH_PIXELS = 240;
pub const SCREEN_HEIGHT_PIXELS = 160;

// ==================================================================
// Below are boot code
// ==================================================================

// The variables below are defined in gba.ld.
extern var _sbss: u32;
extern var _ebss: u32;
extern var _sdata: u32;
extern var _edata: u32;
extern var _sidata: u32;
extern var __sp_irq: u32;
extern var __sp_usr: u32;

pub fn setupROMHeader(
    comptime gameTitle: []const u8,
    comptime gameCode: []const u8,
    comptime makerCode: []const u8,
    comptime softwareVersion: u8,
) header.Header {
    var h = header.headerTemplate;
    comptime {
        const isUpper = @import("std").ascii.isUpper;
        const isDigit = @import("std").ascii.isDigit;
        for (gameTitle, 0..) |eachCh, i| {
            const isValidChar = isUpper(eachCh) or isDigit(eachCh);
            if (isValidChar and i < 12) {
                h.gameTitle[i] = eachCh;
            } else {
                if (i >= 12) {
                    @compileError("Game name is too long: expect <= 12 characters.");
                } else if (!isValidChar) {
                    @compileError("Game name must be all Uppercase+digit.");
                }
            }
        }

        for (gameCode, 0..) |eachCh, i| {
            const isValidChar = isUpper(eachCh);
            if (isValidChar and i < 4) {
                h.gameCode[i] = eachCh;
            } else {
                if (i >= 4) {
                    @compileError("Game code is too long: expect <= 4 characters.");
                } else if (!isValidChar) {
                    @compileError("Game code must be all Uppercase.");
                }
            }
        }

        for (makerCode, 0..) |eachCh, i| {
            const isValidChar = isDigit(eachCh);
            if (isValidChar and i < 2) {
                h.makerCode[i] = eachCh;
            } else {
                if (i >= 2) {
                    @compileError("Maker code is too long: expect <= 2 characters.");
                } else if (!isValidChar) {
                    @compileError("Game code must be all digits.");
                }
            }
        }

        h.softwareVersion = softwareVersion;
        // Compute checksum
        // TODO: The code below is copied from ZigGBA but don't
        // quite understand its semantics. Need to check again with GBATEK.
        var complementCheck: u8 = 0;
        var index: usize = 0xA0;
        // TODO: Unlike ZigGBA, we add multiboot to header, so header
        // size is adjusted from 192 to 228. Supposed
        // the cast should be 192 bytes. Is it still correct?
        const computeCheckData = @as([228]u8, @bitCast(h));
        while (index < 0xA0 + (0xBD - 0xA0)) : (index += 1) {
            complementCheck +%= computeCheckData[index];
        }

        const tempCheck = -(0x19 + @as(i32, @intCast(complementCheck)));
        h.complementCheck = @as(u8, @intCast(tempCheck & 0xFF));
    }
    return h;
}

fn zeroBss() void {
    // Clear memory of .bss section
    // (between _sbss and _ebss), filling them to all 0.
}

fn copyDataToEWRAM() void {
    // Copy .data section to EWRAM
}

fn callUserMain() void {
    // The logic below just simply call main() function from client.
    // Note that compiler can automatically detect the content of
    // main() is compiled ARM or Thumb instruction set. No need to do +1
    // manually.
    //
    // If you prefer a link script name, for example,
    //
    //    export fn main() linksection(".gba.main") {}
    //
    // then we have do manually call 'adds r0, r0, #1' before calling
    // 'bx r0', in order to tell bx that we are calling a thumb
    // function.
    asm volatile (
        \\.thumb
        \\.cpu arm7tdmi
        \\ldr r0, =main
        \\bx r0
    );
}

export fn _boot() linksection(".gba.boot") void {
    // After jumping from, _start(), we have reached _boot() function.
    // ZigGBA provides a way like:
    //
    //     const root = @import("root");
    //     'if (@hasDecl(root, "main") { root.main(); }'
    //
    // However, we can't go to main() because @hasDecl() is triggered
    // at *compile time*, resolving root as gba.zig. Thus it always
    // falls into a loop. To prove it happens at compile time, just put
    // root.main() out of @hasDecl() block, it fails compliation
    // immediately.
    //
    // NOTE: ZigGBA applies the same approach. Unfortunately the built
    // code does not work anymore. Anyway it also goes to an
    // 'lsl r0, r0, #0' loop. I believe it has the same problem.
    //
    // To solve the problem, I decide to use assembly code to call main
    // function. See callUserMain() for details.
    zeroBss();
    copyDataToEWRAM();
    callUserMain();
    while (true) {}
}

export fn _start() linksection(".gba.start") void {
    // Line 1: Set register base to ioram
    // Line 2-4: Turn on IRQ mode (see gbadoc->hardware-interrupts)
    // Line 5: Set IRQ Stack: 0x03000000 - 0x60 = 0x03007FA0
    // Line 6-7: Switch to System Mode
    // Line 8: Set user stack: (__sp_irq - 0xa0 = 0x03007F00)
    // Line 9-10: Jump to _boot() function for initiaization.
    asm volatile (
        \\.arm
        \\.cpu arm7tdmi
        \\mov r0, #0x04000000
        \\str r0, [r0, #0x208]
        \\mov r0, #0x12
        \\msr cpsr, r0
        \\ldr sp, =__sp_irq
        \\mov r0, #0x1f
        \\msr cpsr, r0
        \\ldr sp, =__sp_usr
        \\ldr r3, =_boot
        \\bx r3
    );

    //    \\add r0, pc, #1
    //    \\bx r0
    // _boot(); // ZigGBA's approach, which does not work.

    // The logic here is different with ZigGBA. ZigGBA combines startup
    // code in _start(). Thus just do 'bx pc + 1'. However it does not
    // work in our case, as the next thumb is interpreted as 'bx lr',
    // then it goes back to 'b 0x080000C0'. A loop back to header.
    // This is wrong.
    //
    // ZigGBA just directly does 'bx pc +1', putting _boot() at end of
    // assembly code in _start(). However in my case it always
    // fall into an exception calling swige #46464, then move back to
    // 0x08000000, loop again.
    //
    // I still don't understand the root cause. Thus, I modified it
    // to make it a workaround: just directly jump to _start(). This
    // is somehow a good choice, as we can go to Zig world as early
    // as possible.
}
