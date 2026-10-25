from games_fantasia import *
build('fantasian', 'fantasian', 'Fantasia (940803 PCB)',
      ('fantasian/prog2_12.ue17', 'fantasian/prog1_7.ud17'), 'fantasian/obj1_13.u5',
      ['fantasia/2.music1', 'fantasia/1.music2'], 'refs_fantasian.json',
      data_patch=[0xe044,0xe064,0xe084,0xe144,0xe164,0xe1a4,0xe1e4,0xe224,0xe264,0xe2a4,0xe2e4,0xe3e4],
      zips=('fantasian.zip', 'fantasia.zip'))
