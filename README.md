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
