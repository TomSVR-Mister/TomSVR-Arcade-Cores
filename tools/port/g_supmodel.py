import sys
from port import COMAD
assert COMAD
M = 'supmodel/'; M2 = 'supmodl2/'
which = sys.argv[1:] or ['supmodel', 'supmodl2']
if 'supmodel' in which:
    import games_fantasia as F
    data = [(0x100000, 'il', (M + 'i-scr2.10', M + 'i-scr1.5')), (0x200000, 'il', (M + 'i-scr4.9', M + 'i-scr3.4')),
            (0x300000, 'il', (M + 'i-scr6.8', M + 'i-scr5.3')), (0x400000, 'il', (M + 'i-scr8.11', M + 'i-scr7.6'))]
    print(F.build('supmodel', 'supmodel', 'Super Model', (M + 'prog2.12', M + 'prog1.7'), M + 'obj1.13',
                  [M + 'music1.1', M + 'music2.2'], 'refs_supmodel.json', data=data, items=[], faces=(0, 0),
                  timers=(0x800006, 0x800008), zips=('supmodel.zip',),
                  data_patch=[0xe246,0xe266,0xe286,0xe346,0xe366,0xe3a6,0xe3e6,0xe426,0xe466,0xe4a6,0xe4e6,0xe5e6], year='1994', dips=F.DIPS_NEWFANT))
if 'supmodl2' in which:
    from games_lzfull import build
    banks = [(0, 'il', (M2 + '12_prog2.ue17', M2 + '7_prog1.ud17')), (0x100000, 'il', (M2 + '11_i-scr2.ue16b', M2 + '6_i-scr1.ue16a')),
             (0x200000, 'il', (M2 + '10_i-scr4.ue15b', M2 + '5_i-scr3.ue15a')), (0x300000, 'il', (M2 + '9_i-scr6.ue14b', M2 + '4_i-scr5.ue14a')),
             (0x400000, 'il', (M2 + '8_i-scr8.ue20b', M2 + '3_i-scr7.ue20a'))]
    print(build('supmodl2', 'supmodl2', 'Super Model II', banks, [M2 + '13_obj1.u5', M2 + '14_obj2.u4'],
                [M2 + '1_music1.ub6', M2 + '2_music2.uc6'], 'refs_supmodl2.json', ('supmodl2.zip',),
                timers=(0x800006, 0x800008, 0x80000a), year='1997'))
