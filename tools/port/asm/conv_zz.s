| Zip & Zap on jtcomad.  Installed as the IRQ3 (vblank) handler.
| 1. runs the original IRQ3 handler (palette upload)
| 2. converts (and compacts) the VU-002 sprite list (bootleg layout, kept in a shadow buffer) to the Pandora list at 0x700000.
|    Bootleg rules (MAME kaneko16_sprite_device::bootleg_draw_sprites): code = w1 & 0x1fff, colour = (w0 >> 2) & 15,
|    flipx = w0 bit 1, flipy = w0 bit 0, (w0 & 0x6000) == 0x6000 -> position relative to the previous sprite,
|    positions are w2 >> 6, w3 >> 6, kept as signed 10-bit values.
| 3. runs the IRQ4 handler (task tick + inputs), which the Gals Panic hardware never raises.
| symbols: ORIG3, ORIG4, SHADOW, FLAGS, MARK, XOFF, YOFF
        .equ PAND,   0x700000
        .text
irq3:   pea     1f(%pc)
        move.w  %sr,-(%sp)
        jmp     ORIG3                   | original handler ends with rte -> 1f
1:      movem.l %d0-%d7/%a0-%a3,-(%sp)
        lea     SHADOW,%a0
        lea     PAND,%a1
        moveq   #0,%d6                  | running x
        moveq   #0,%d5                  | running y
        move.w  #511,%d7
loop:   move.w  (%a0),%d0               | attr
        move.w  4(%a0),%d2
        lsr.w   #6,%d2
        move.w  6(%a0),%d3
        lsr.w   #6,%d3
        move.w  %d0,%d4
        andi.w  #0x6000,%d4
        cmpi.w  #0x6000,%d4
        bne.s   absol
        add.w   %d2,%d6
        add.w   %d3,%d5
        bra.s   norm
absol:  move.w  %d2,%d6
        move.w  %d3,%d5
norm:   lsl.w   #6,%d6                  | sign-extend 10 bits
        asr.w   #6,%d6
        lsl.w   #6,%d5
        asr.w   #6,%d5
        move.w  2(%a0),%d1              | tile code
        andi.w  #0x1fff,%d1
        beq.s   next                    | empty: not copied (the list is compacted)
        move.w  %d6,%d2
        add.w   #XOFF,%d2
        move.w  %d5,%d3
        add.w   #YOFF,%d3
        move.w  %d0,%d4
        lsl.w   #2,%d4
        andi.w  #0xf0,%d4               | colour << 4
        btst    #8,%d2
        beq.s   2f
        bset    #0,%d4
2:      btst    #8,%d3
        beq.s   3f
        bset    #1,%d4
3:      move.b  %d4,7(%a1)
        move.b  %d2,9(%a1)
        move.b  %d3,11(%a1)
        move.b  %d1,13(%a1)
        lsr.w   #8,%d1
        andi.b  #0x3f,%d1
        btst    #1,%d0
        beq.s   4f
        bset    #7,%d1                  | flip x
4:      btst    #0,%d0
        beq.s   5f
        bset    #6,%d1                  | flip y
5:      move.b  %d1,15(%a1)
        lea     16(%a1),%a1
next:   addq.l  #8,%a0
        dbra    %d7,loop
        cmpa.l  #PAND+0x2000,%a1
        bcc.s   7f
        move.b  #0x08,7(%a1)            | end of list (jtcomad sprite engine)
        clr.b   13(%a1)
        clr.b   15(%a1)
7:
        movem.l (%sp)+,%d0-%d7/%a0-%a3
        pea     6f(%pc)
        move.w  %sr,-(%sp)
        jmp     ORIG4                   | task tick, ends with rte -> 6f
6:      rte
