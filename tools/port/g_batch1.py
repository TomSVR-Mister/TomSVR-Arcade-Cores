from games_fantasia import *
T = [0xe01a,0xe03a,0xe05a,0xe11a,0xe13a,0xe17a,0xe1ba,0xe1fa,0xe23a,0xe27a,0xe2ba,0xe3ba]
OKI = ['fantasia/2.music1', 'fantasia/1.music2']
build('fantasia', 'fantasia', 'Fantasia (940429 PCB, set 1)', ('fantasia/16.pro2', 'fantasia/13.pro1'),
      'fantasia/17.scr3', OKI, 'refs_fantasia.json', data_patch=T, timers=())
build('fantasiab', 'fantasiab', 'Fantasia (940429 PCB, set 2)', ('fantasia/fantasiab/fantasia_16', 'fantasia/fantasiab/fantasia_13'),
      'fantasia/17.scr3', OKI, 'refs_fantasiab.json', data_patch=T, timers=(), zips=('fantasiab.zip', 'fantasia.zip'))
build('fantasiaa', 'fantasiaa', 'Fantasia (940307 PCB)', ('fantasia/fantasiaa/prog2_16.ue17', 'fantasia/fantasiaa/prog1_13.ud17'),
      'fantasia/17.scr3', ['fantasia/fantasiaa/music1_1.ub6', 'fantasia/1.music2'], 'refs_fantasiaa.json', data_patch=T, timers=(),
      zips=('fantasiaa.zip', 'fantasia.zip'))
