| Small (40x48) portrait drawn by scaling the large (48x56) one, so the small set needs no ROM space.
| replaces the start of the 40x48 routine: d0 = face number, a0 = bitmap address.  TAB56 = 48x56 pointer table.
        .text
face40: lsl.w   #2,%d0
        lea     TAB56,%a1
        movea.l (%a1,%d0.w),%a1
        movem.l %d2-%d4/%a2-%a4,-(%sp)
        lea     vmap(%pc),%a3
        lea     umap(%pc),%a4
        moveq   #0,%d1                  | r
1:      moveq   #0,%d2
        move.b  (%a3,%d1.w),%d2         | source row
        mulu.w  #96,%d2                 | 48 words per row
        lea     (%a1,%d2.l),%a2
        moveq   #0,%d3                  | c
2:      moveq   #0,%d4
        move.b  (%a4,%d3.w),%d4
        add.w   %d4,%d4
        move.w  (%a2,%d4.w),%d4
        move.w  %d3,%d2
        add.w   %d2,%d2
        move.w  %d4,(%a0,%d2.w)
        addq.w  #1,%d3
        cmpi.w  #40,%d3
        bne.s   2b
        lea     512(%a0),%a0
        addq.w  #1,%d1
        cmpi.w  #48,%d1
        bne.s   1b
        movem.l (%sp)+,%d2-%d4/%a2-%a4
        rts
| u: 40 columns from 48 (c*48/40), v: 48 rows from 56 (r*56/48)
umap:   .byte 0,1,2,3,4,6,7,8,9,10,12,13,14,15,16,18,19,20,21,22,24,25,26,27,28,30,31,32,33,34,36,37,38,39,40,42,43,44,45,46
vmap:   .byte 0,1,2,3,4,5,7,8,9,10,11,12,14,15,16,17,18,19,21,22,23,24,25,26,28,29,30,31,32,33,35,36,37,38,39,40,42,43,44,45,46,47,49,50,51,52,53,54
        .even
