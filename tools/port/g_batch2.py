from games_fantasia import *
T = [0xe250,0xe270,0xe290,0xe350,0xe370,0xe3b0,0xe3f0,0xe430,0xe470,0xe4b0,0xe4f0,0xe5f0]
NF = 'newfant/'
ITEMS = [(0x4c41dc, 0x2ac00), (0x4a81dc, 0x1c000), (0x4829c0, 0x12c0e), (0x4955ce, 0x12c0e)]
FACESB = (0x4c41dc, 0x2ac00)
def data(f): return [(0x100000, 'il', (NF + f[0], NF + f[1])), (0x200000, 'il', (NF + f[2], NF + f[3])),
                     (0x300000, 'il', (NF + f[4], NF + f[5])), (0x400000, 'il', (NF + f[6], NF + f[7]))]
DNF = data(['iscr2.10', 'iscr1.05', 'iscr4.09', 'iscr3.04', 'iscr6.08', 'iscr5.03', 'iscr8.11', 'iscr7.06'])
D95 = data(['fantsy95/i-scr2.10', 'fantsy95/i-scr1.5', 'fantsy95/i-scr4.9', 'fantsy95/i-scr3.4',
            'fantsy95/i-scr6.8', 'fantsy95/i-scr5.3', 'fantsy95/i-scr8.11', 'fantsy95/i-scr7.6'])
DHN = D95[:3] + [(0x400000, 'il', (NF + 'hotnight/11_i-scr8_4m_11.ue20b', NF + 'hotnight/6_i-scr7_4m_6.ue20a'))]
kw = dict(data_patch=T, items=ITEMS, faces=FACESB, year='1995', dips=DIPS_NEWFANT)
build('newfant', 'newfant', 'New Fantasia (1995 copyright)', (NF + 'prog2.12', NF + 'prog1.07'), NF + 'nf95obj1.13',
      [NF + 'musc1.01', NF + 'musc2.02'], 'refs2_newfant.json', zips=('newfant.zip',), data=DNF, **kw)
build('newfanta', 'newfanta', 'New Fantasia (1994 copyright)', (NF + 'prog2.12', NF + 'prog1.07'), NF + 'fantsy95/obj1.13',
      [NF + 'musc1.01', NF + 'musc2.02'], 'refs2_newfant.json', zips=('newfanta.zip', 'newfant.zip'), data=DNF,
      **dict(kw, year='1994'))
build('hotnight', 'hotnight', 'Hot Night', (NF + 'hotnight/12_prog2_4m_12.ue17', NF + 'hotnight/7_prog1_4m_7.ud17'),
      NF + 'fantsy95/obj1.13', [NF + 'fantsy95/music1.1', NF + 'fantsy95/music2.2'], 'refs2_hotnight.json', data=DHN,
      zips=('hotnight.zip', 'newfant.zip'), manufacturer='Bulldog Amusements Inc.', **dict(kw, year='1994'))
build('fantsy95', 'fantsy95', "Fantasy '95", (NF + 'fantsy95/prog2.12', NF + 'fantsy95/prog1.7'),
      NF + 'fantsy95/obj1.13', [NF + 'fantsy95/music1.1', NF + 'fantsy95/music2.2'], 'refs2_fantsy95.json', data=D95,
      zips=('fantsy95.zip', 'newfant.zip'), manufacturer='Hi-max Technology Inc.', **kw)
