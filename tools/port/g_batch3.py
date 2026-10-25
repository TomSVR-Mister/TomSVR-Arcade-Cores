from games_c0 import *
M = 'missw96/'
build('missw96', 'missw96', "Miss World '96 (Nude) (C-3000A PCB, set 1)", (M + 'mw96_10.bin', M + 'mw96_06.bin'),
      [(M + 'mw96_09.bin', M + 'mw96_05.bin'), (M + 'mw96_08.bin', M + 'mw96_04.bin'), (M + 'mw96_07.bin', M + 'mw96_03.bin')],
      M + 'mw96_11.bin', [M + 'mw96_01.bin', M + 'mw96_02.bin'], 'refs2_missw96.json', zips=('missw96.zip',))
SM = 'smissw/'
build('smissw', 'smissw', 'Super Miss World', (SM + '10_prog2.ue17', SM + '6_prog1.ud17'),
      [(SM + '9_im1-b.ue16b', SM + '5_im1-a.ue16a'), (SM + '8_im2-b.ue15b', SM + '4_im2-a.ue15a'), (SM + '7_im3-b.ue14b', SM + '3_im3-a.ue14a')],
      SM + '15_obj11.u5', [SM + '1_music1.ub6', SM + '2_music2.uc6'], 'refs2_smissw.json', zips=('smissw.zip',))
