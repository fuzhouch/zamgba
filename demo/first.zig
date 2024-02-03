const gba = @import("gba");

// A .header is required to be put at the beginning of GBA rom
// with correct game name, game code, maker code and version.
// In devkitARM, this step not done in build time, but done by
// gbafix. We learn from ZigGBA to build it manually.
//
// I'm looking for a way to completely remove this statement, leaving
// only main() in SDK users' code.
//
export var gameHeader linksection(".header") = gba.setupROMHeader(
    "FIRST",
    "AFSE",
    "00",
    0,
);

fn main() noreturn {
    // The example https://www.coranac.com/tonc/text/first.htm

    // *(unsigned int*)0x04000000 = 0x0403;
    // ((unsigned short*)0x06000000)[120+80*240] = 0x001F;
    // ((unsigned short*)0x06000000)[136+80*240] = 0x03E0;
    // ((unsigned short*)0x06000000)[120+96*240] = 0x7C00;

    const display = @as(*volatile u16, @ptrFromInt(0x04000000));
    display.* = 0x0403;
    const videoRAM = @as([*]u16, @ptrFromInt(0x06000000));
    videoRAM[120 + 80 * 240] = 0x001F;
    videoRAM[136 + 80 * 240] = 0x03E0;
    videoRAM[120 + 96 * 240] = 0x7C00;

    while (true) {}
}
