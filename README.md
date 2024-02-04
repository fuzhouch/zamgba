# Introduction

[Zamgba](https://github.com/fuzhouch/zamgba) is a project to learn
how to program for [Game Boy Advance](https://en.wikipedia.org/wiki/Game_Boy_Advance).
My goal is to use Game Boy Advance as a target platform to
develop my own video gamed as hobby.

The motivation was brought when I learn [TIC-80](https://tic80.com), a
popular open source fantasy console. I love the idea behind
(which was indeed brought by
[PICO-8](https://www.lexaloffle.com/pico-8.php)), that a fantasy console
should include all tools needed for development. However, it brings a
limitation, that it is not easy to make use of modern
graphics or music composing tools into development workflow, such as
[Asprite](https://www.aseprite.org)
or [Famistudio](https://www.famistudio.org/).
Besides, I would like to program targeting a true hardware with
low-level concepts (e.g. IRQs.). A high-level
scripting language used by fantasy console does not allow me do this.

[Game Boy Advance](https://en.wikipedia.org/wiki/Game_Boy_Advance) has
been a popular gaming hardware since I was a kid.
Though it has reached end-of-life for a long time, there are many
games available. People play them on real hardwares (GBA, GBA SP,
Nintendo DS or 3DS), hardware simulator
([Analogue Pocket](https://www.analogue.co) or emulators
(either via desktop or many retro handheld devices). Unlike
fantasy consoles,
[Game Boy Advance](https://en.wikipedia.org/wiki/Game_Boy_Advance)
is based on real ARM processor. The knowledge of hardware programming
is still useful nowadays.

Overall, [Game Boy Advance](https://en.wikipedia.org/wiki/Game_Boy_Advance)
appears to be a better target platform than fantasy console for me to
create 2D based, retro style game for fun.

## The programming languages

I use [Zig programming language](https://ziglang.org) to construct my
project. Zig is a low-level language just like C, but it comes with many
language constructs to prevent memory bugs. Meanwhile, Zig comes with a
perfect compiler toolchain, which keeps cross-compiling in mind from
the first day.


## How can I (as a reader) use the project

Nothing for now. This is a self-learning session to study the classic
[tonc](https://www.coranac.com/tonc/text/toc.htm) documentation.
The content of this repository is indeed a set of example code following
the tutorial. It is neither a game, nor a new emulator,
or an existing rom hack. 

If you are interested in how to learn hardware oriented programming, no
matter with Zig or other programming languages, you may (eventually) find
something useful here. :)

Though it sounds completely useless for now, it may change in the future.
If I happen to figure out a clear direction, I will update this
documentation and make it official.

## ...But I'm a hacker!

Well, if you are also interested programming GBA in Zig, follow the
steps below:

1. Install Zig in master branch. The codebase is compiled with
   version ``0.12.0-dev.2547+eb4024036`` (2024-02-04). Some package
   managers like [scoop](https://scoop.sh) or
   [AUR](https://aur.archlinux.org) allows installing dev version
   of Zig toolchain. If you prefer building it from source (LLVM+Zig),
   refer to [here](https://github.com/ziglang/zig/wiki/Building-Zig-From-Source).
2. Clone [Zamgba](https://github.com/fuzhouch/zamgba) source code.
3. Build with command, ``zig build``. You will be able to get
   demo roms from ``zig-out/bin/first.gba``. There's another binary,
   ``zig-out/bin/first``, which is the ELF format of GBA executable
   code. Unfortunately the binary is not executable (haven't figured
   out the reason), but it contains symbols and linker section info,
   which is useful for debugging.
4. Run the ROM. I use [mgba](https://mgba.io) command line under Linux.
   With a command ``mgba ./zig-out/bin/first.gba`` to run. You will be
   able to see three pixels (red, green and blue) on screen.
5. For debugging, use ``mgba -d ./zig-out/bin/first.gba``. It's a
   powerful assembly debugging tool to solve a lot of problems.

### How can I add my own code?

1. Clone zamgba project.
2. Add your code, let's say, ``helloworld.zig``, under ``demo/``.
3. Open ``build.zig``. Edit a line in ``build()`` to add your executable.
4. Run ``zig build`` command line from top level of ``zamgba`` project.

The build script looks like below:

```
...
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const gba_thumb_target = buildGBAThumbTarget(b);

    // Core library
    const lib = addStaticLib(b, gba_thumb_target, optimize);
    b.installArtifact(lib);
    b.default_step.dependOn(&lib.step);

    // Demos
    addExe(b, gba_thumb_target, optimize, "first", "demo/first.zig", lib);

    // fuzhouch: Add your ROM here
    addExe(b, gba_thumb_target, optimize, "first", "demo/helloworld.zig", lib);

    ...
}
```

When writing ``helloworld.zig``, there are three rules required, in order
to compile a working GBA ROM:

1. A global header variable must be defined, with ``export`` keyword
   and ``linksection(".gba.header")`` tagged. It must be initialized
   with gba.setupROMHeader() function. Every 
2. The ``main()`` function must be tagged with ``export`` keyword.
3. The ``main()`` must not return. Zamgba does not handle program exit
   since GBA does not define graceful shutdown due to a lack of
   operating system.

Please check comments in ``demo/first.zig`` for technical reasons.

### Can I reference your library as a dependency?

Possible but not tested yet. The current structure is a bit irregular
comparing with typical Zig project because my ``build.zig`` sets a
cross compilation toolchain. When referencing ``zamgba`` as a dependency,
the ``build.zig`` script must be updated as well. I haven't found a good
approach yet.
