| Monster picture DIP (DSW1 copy in RAM): bit 7 = 0 -> Off (threshold 0: the meter never stops at the monster),
| bit 7 = 1 and bit 2 = 0 -> Slow (boss drains 1 notch instead of 3), both 1 -> Normal (original)
        .text
moninit:
        btst    #7,DSW
        beq.s   1f
        move.w  #6,THR
        rts
1:      clr.w   THR
        rts
mondrain:
        btst    #2,DSW
        beq.s   1f
        move.w  #-3,34(%a6)
        rts
1:      move.w  #-1,34(%a6)
        rts
