| Replacement for the Comad picture decompressor (Miss World '96 style, 0x39a28).
| Original keeps a 32 KB LZ window in work RAM (0xc08000) which the jtgals core does not have.
| Here the bg bitmap itself is the window: a back reference to output word s is read back from
| the bitmap at origin + (s / width) * 512 + (s % width) * 2.  Output is written raw; when the
| "darken" mode bit is set the whole picture is darkened in a final pass (same formula as 0x39d7c).
| Stream format (verified offline): plain nibble stream, MSB nibble first
|   0xxx xxxx xxxx xxxx : literal, pixel = token << 1
|   10rr rrrr rrrr rrrr + cccc : copy c+1 words from window index r (c == 0 -> end of picture)
|   11cc               : repeat last pixel c+1 times
| in: d1 = table base, d7 = picture index, d5 = bitmap offset (from 0x520000).  FLAGVAR bit1 = darken
        .text
decomp:
        movem.l %d0-%d7/%a0-%a6,-(%sp)
        bclr    #0,FLAGVAR
        lea     0x520000,%a1
        adda.l  %d5,%a1
        movea.l %a1,%a5                 | picture origin
        movea.l %d1,%a0
        lsl.w   #2,%d7
        andi.l  #0xff,%d7
        adda.l  %d7,%a0
        move.l  (%a0),%d0
        add.l   %d1,%d0
        addq.l  #8,%d0
        movea.l %d0,%a0                 | stream
        move.l  -4(%a0),%d1
        swap    %d1                     | d1.w = width
        andi.l  #0xffff,%d1
        move.l  #256,%d0
        sub.l   %d1,%d0
        add.l   %d0,%d0
        movea.l %d0,%a3                 | row skip in bytes
        moveq   #0,%d4                  | nibbles left in d3
        moveq   #0,%d6                  | output position
        moveq   #0,%d7                  | dest column
        moveq   #0,%d2                  | last pixel
token:  bsr     getnib
        cmpi.w  #8,%d0
        bcc   notlit
        bsr     get3                    | d0 = 15-bit literal
        add.w   %d0,%d0
        move.w  %d0,%d2
        bsr   put
        bra   token
notlit: cmpi.w  #12,%d0
        bcc   rep
        andi.w  #3,%d0
        bsr     get3                    | d0 = 14-bit window index
        move.l  %d6,%d5
        sub.w   %d0,%d5
        andi.l  #0x3fff,%d5             | distance
        bne   1f
        move.l  #0x4000,%d5
1:      move.l  %d6,%d0
        sub.l   %d5,%d0                 | source position s
        divu.w  %d1,%d0                 | low: row, high: column
        moveq   #0,%d5
        move.w  %d0,%d5
        lsl.l   #8,%d5
        add.l   %d5,%d5                 | row * 512
        swap    %d0
        moveq   #0,%d7
        move.w  %d0,%d7                 | (temporarily) source column
        movea.l %d7,%a6
        add.l   %d7,%d7
        add.l   %d7,%d5
        lea     0(%a5,%d5.l),%a2        | source address
        bsr     getnib
        tst.w   %d0
        beq   done
        move.w  %d0,%d5                 | count - 1
        move.l  %d6,%d0                 | recover dest column = pos % width
        divu.w  %d1,%d0
        swap    %d0
        moveq   #0,%d7
        move.w  %d0,%d7
cpy:    move.w  (%a2)+,%d2
        bsr   put
        addq.w  #1,%a6
        cmpa.w  %d1,%a6
        bne   2f
        suba.l  %a6,%a6
        adda.l  %a3,%a2
2:      dbra    %d5,cpy
        bra   token
rep:    andi.w  #3,%d0
        move.w  %d0,%d5
3:      bsr   put
        dbra    %d5,3b
        bra   token

put:    move.w  %d2,(%a1)+
        addq.l  #1,%d6
        addq.w  #1,%d7
        cmp.w   %d1,%d7
        bne   4f
        moveq   #0,%d7
        adda.l  %a3,%a1
4:      rts

getnib: tst.w   %d4
        bne   5f
        move.w  (%a0)+,%d3
        moveq   #4,%d4
5:      rol.w   #4,%d3
        move.w  %d3,%d0
        andi.w  #15,%d0
        subq.w  #1,%d4
        rts

get3:   move.w  %d0,-(%sp)              | prefix nibble already in d0
        moveq   #2,%d5
6:      bsr   getnib
        move.w  (%sp),%d7
        lsl.w   #4,%d7
        or.w    %d0,%d7
        move.w  %d7,(%sp)
        dbra    %d5,6b
        move.w  (%sp)+,%d0
        move.l  %d6,%d7                 | restore dest column (d7 was used as scratch)
        divu.w  %d1,%d7
        swap    %d7
        andi.l  #0xffff,%d7
        rts

done:   btst    #1,FLAGVAR
        beq   9f
        move.l  %d6,%d0                 | darken pass over the whole picture
        divu.w  %d1,%d0
        subq.w  #1,%d0                  | rows - 1
        movea.l %a5,%a1
7:      move.w  %d1,%d5
        subq.w  #1,%d5
8:      move.w  (%a1),%d2
        andi.w  #0xf7bc,%d2
        lsr.w   #1,%d2
        move.w  %d2,(%a1)+
        dbra    %d5,8b
        adda.l  %a3,%a1
        dbra    %d0,7b
9:      clr.b   FLAGVAR
        movem.l (%sp)+,%d0-%d7/%a0-%a6
        rts

| boot RAM clear for the relocated work RAM (replaces the 64 KB clear of 0xc00000; no stack yet)
bootclr:
        lea     0x51c000,%a1
        move.w  #0x0fff,%d0
10:     clr.l   (%a1)+
        dbra    %d0,10b
        lea     0x702000,%a1
        move.w  #0x0bff,%d0
11:     clr.l   (%a1)+
        dbra    %d0,11b
        jmp     BOOTRET

| sound-bank/flip register write (0x900000, high byte): the core rotates the picture 180 degrees for
| Gals Panic (a vertical game); horizontal games need the flip bit inverted to come out the right way up
flipw:  move.w  %d0,-(%sp)
        eori.b  #0x40,%d0
        move.b  %d0,0x900000
        move.w  (%sp)+,%d0
        tst.b   %d0
        rts
