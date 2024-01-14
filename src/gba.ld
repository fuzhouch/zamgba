/*
 * The linker script is originated from ZigGBA project but modified
 * during study.
 *
 * REF: https://github.com/wendigojaeger/ZigGBA
 */

/*
 * Memory layout is based on tonc and other documetations. I mainly
 * learn from lokathor.
 * 
 * 1. https://www.coranac.com/tonc/text/hardware.htm#sec-memory
 * 2. https://lokathor.github.io/gba-from-scratch/ex1.html
 * 3. https://mcyoung.xyz/2021/06/01/linker-script/
 * 4. https://github.com/devkitPro/devkitarm-crtls/blob/master/gba_cart.ld
 */
MEMORY {
    system  : ORIGIN = 0x00000000, LENGTH = 16K
    ewram   : ORIGIN = 0x02000000, LENGTH = 256K
    iwram   : ORIGIN = 0x03000000, LENGTH = 32K
    ioram   : ORIGIN = 0x04000000, LENGTH = 1K
    palram  : ORIGIN = 0x05000000, LENGTH = 1K
    vram    : ORIGIN = 0x06000000, LENGTH = 1K
    oam     : ORIGIN = 0x07000000, LENGTH = 1K
    pakrom  : ORIGIN = 0x08000000, LENGTH = 32M
    cartram : ORIGIN = 0x0E000000, LENGTH = 64K
}

/* Copied from devkitpro/gba_cart.ld */
ENTRY(__text_start)

OUTPUT_FORMAT("elf32-littlearm", "elf32-bigarm", "elf32-littlearm")
OUTPUT_ARCH(arm)

__text_start  = ORIGIN(pakrom);
__eheap_end   = ORIGIN(ewram) + LENGTH(ewram);
__iwram_start = ORIGIN(iwram);
__iwram_top   = ORIGIN(iwram) + LENGTH(iwram);
__sp_irq      = __iwram_top - 0x060;
__sp_usr      = __sp_irq - 0x0a0;
__irq_flags   = 0x03007ff8;

SECTIONS
{
    . = __text_start;
    .text :
    {
        *(.text.start)
        *(.text .text.*)
    } >pakrom
}

/* TODO: Need a .start section. */
