const gba = @import("gba");

// The gameHeader is required at the beginning of GBA rom
// with correct game name, game code, maker code and version.
// It can't be initialized within main(), because GBA BIOS relies on
// the header to locate main().
//
// In devkitARM, this step not done in build time, but done by
// gbafix. This approach is learnt from ZigGBA. It allows we build
// everything in code, intead of requiring an additional gbafix.
//
// Note that the ``export`` keyword and `linksection(".gba.header")``
// attribute are both required. The linker
// script name, ``.gba.header``, is a convention used in zamgba to
// locate header at linking time.
//
export var gameHeader linksection(".gba.header") = gba.setupROMHeader(
    "FIRST",
    "AFSE",
    "00",
    0,
);

// Make sure the main() function is tagged with `export' keyword.
// It makes the function visible in symbol table of ELF file.
// It's required to allow the assembly code in zamgba library locate
// the address of main() function as entry point.
export fn main() noreturn {
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

    // The loop is required to match the ``noreturn`` return value.
    // Zamgba does not handle program exit gracefully because GBA
    // does not provide concept of graceful exit due to a lack of
    // operating system. Make sure the while (true) {} always exist.
    while (true) {}
}
