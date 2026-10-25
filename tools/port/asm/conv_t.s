| VU-002 -> Pandora sprite list converter for Fantasia on jtgals
| Called in place of "jmp $100" at 0x99c (vblank IRQ sprite copy)
        .ifndef SHADOW
        .equ SHADOW, 0x53c400
        .equ FLAGS,  0x53c100
        .equ MARK,   0x53c300
        .endif
        .equ PAND,   0x700000
        .text
conv:
        jsr     COPYFN                | original: copy RAM list -> sprite RAM (now shadow)
        movem.l %d0-%d7/%a0-%a3,-(%sp)
        cmpi.w  #0x5a5a,MARK
        beq.s   init_done
        lea     PAND,%a0
        move.w  #0x0fff,%d0
clr1:   clr.w   (%a0)+
        dbra    %d0,clr1
        lea     FLAGS,%a0
        move.w  #511,%d0
clr2:   clr.b   (%a0)+
        dbra    %d0,clr2
        move.w  #0x5a5a,MARK
init_done:
        lea     SHADOW,%a0
        lea     PAND,%a1
        lea     FLAGS,%a2
        move.l  OFS1,%d6
        add.l   OFS2,%d6
        move.w  %d6,%d5               | y offset (1/64 px)
        swap    %d6                   | x offset (1/64 px)
        move.w  #511,%d7
loop:   move.w  2(%a0),%d1            | tile code
        bne.s   active
        tst.b   (%a2)
        beq.s   next
        clr.b   (%a2)
        clr.b   13(%a1)
        clr.b   15(%a1)
        bra.s   next
active: st      (%a2)
        move.w  (%a0),%d0             | attr
        move.w  4(%a0),%d2            | x
        add.w   %d6,%d2
        asr.w   #6,%d2
        move.w  6(%a0),%d3            | y
        add.w   %d5,%d3
        asr.w   #6,%d3
        add.w   #YOFF,%d3
        move.w  %d0,%d4
        lsl.w   #2,%d4
        andi.w  #0xf0,%d4             | palette (low 4 bits of colour) << 4
        btst    #8,%d2
        beq.s   1f
        bset    #0,%d4
1:      btst    #8,%d3
        beq.s   2f
        bset    #1,%d4
2:      move.b  %d4,7(%a1)            | byte 3
        move.b  %d2,9(%a1)            | byte 4: x
        move.b  %d3,11(%a1)           | byte 5: y
        move.b  %d1,13(%a1)           | byte 6: code low
        lsr.w   #8,%d1
        andi.b  #0x3f,%d1
        btst    #1,%d0
        beq.s   3f
        bset    #7,%d1                | flip x
3:      btst    #0,%d0
        beq.s   4f
        bset    #6,%d1                | flip y
4:      move.b  %d1,15(%a1)           | byte 7
next:   addq.l  #8,%a0
        lea     16(%a1),%a1
        addq.l  #1,%a2
        dbra    %d7,loop
        .if IRQ4FN
        movem.l %d0-%d7/%a0-%a6,-(%sp)
        jsr     IRQ4FN                | Comad boards raise IRQ4 every frame; Gals Panic never does
        movem.l (%sp)+,%d0-%d7/%a0-%a6
        .endif
        movem.l (%sp)+,%d0-%d7/%a0-%a3
        rts
