// K054539 check: Verilog vs a copy of MAME's sound_stream_update
#include "Vjtxexex_k539.h"
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <cstdint>
#include <cstring>
static uint8_t rom[1<<20];
struct Ref {
    uint8_t regs[0x230]; uint8_t ram[0x8000]; int reverb_pos=0;
    struct { int pos,pfrac,val,pval; } chs[8];
    double voltab[256], pantab[0xf];
    uint8_t latch[8][3];
    Ref(){ memset(regs,0,sizeof regs); memset(ram,0,sizeof ram); memset(chs,0,sizeof chs);
        for(int i=0;i<256;i++) voltab[i]=pow(10.0,(-36.0*i/0x40)/20.0)/4.0;
        for(int i=0;i<0xf;i++) pantab[i]=sqrt((double)i)/sqrt((double)0xe); }
    bool regupdate(){ return !(regs[0x22f]&0x80); }
    void keyon(int c){ if(regupdate()) regs[0x22c]|=1<<c; }
    void keyoff(int c){ if(regupdate()) regs[0x22c]&=~(1<<c); }
    int rb(int a){ return rom[a&0xfffff]; }
    void write(int o,uint8_t d){
        bool latchm=(regs[0x22f]&1);
        if(latchm && o<0x100){ int offs=(o&0x1f)-0xc, ch=o>>5; if(offs>=0&&offs<=2){ latch[ch][offs]=d; return; } }
        else switch(o){
            case 0x214: for(int ch=0;ch<8;ch++) if(d&(1<<ch)){ if(latchm) for(int i=0;i<3;i++) regs[(ch<<5)+0xc+i]=latch[ch][i]; keyon(ch);} break;
            case 0x215: for(int ch=0;ch<8;ch++) if(d&(1<<ch)) keyoff(ch); break;
        }
        regs[o]=d;
    }
    void sample(int &L,int &R){
        static const int16_t dpcm[16]={0,0x100,0x200,0x400,0x800,0x1000,0x2000,0x4000,0,-0x4000,-0x2000,-0x1000,-0x800,-0x400,-0x200,-0x100};
        int16_t *rbase=(int16_t*)ram;
        double lval,rval; lval=rval=rbase[reverb_pos]; rbase[reverb_pos]=0;
        for(int ch=0;ch<8;ch++) if(regs[0x22c]&(1<<ch)){
            uint8_t *base1=regs+0x20*ch,*base2=regs+0x200+2*ch; auto *chan=chs+ch;
            int delta=base1[0]|(base1[1]<<8)|(base1[2]<<16); int vol=base1[3]; int bval=vol+base1[4]; if(bval>255) bval=255;
            int pan=base1[5]; if(pan>=0x81&&pan<=0x8f) pan-=0x81; else if(pan>=0x11&&pan<=0x1f) pan-=0x11; else pan=7;
            double lvol=voltab[vol]*pantab[pan], rvol=voltab[vol]*pantab[0xe - pan], rbvol=voltab[bval]/2;
            int rdelta=(base1[6]|(base1[7]<<8))>>3; rdelta=(rdelta+reverb_pos)&0x3fff;
            int cur_pos=base1[0xc]|(base1[0xd]<<8)|(base1[0xe]<<16);
            int fdelta,pdelta; if(base2[0]&0x20){delta=-delta;fdelta=0x10000;pdelta=-1;} else {fdelta=-0x10000;pdelta=1;}
            int cur_pfrac,cur_val,cur_pval;
            if(cur_pos!=chan->pos){chan->pos=cur_pos;cur_pfrac=cur_val=cur_pval=0;} else {cur_pfrac=chan->pfrac;cur_val=chan->val;cur_pval=chan->pval;}
            int lp=base1[8]|(base1[9]<<8)|(base1[10]<<16);
            switch(base2[0]&0xc){
            case 0: cur_pfrac+=delta; while(cur_pfrac&~0xffff){cur_pfrac+=fdelta;cur_pos+=pdelta;cur_pval=cur_val;cur_val=(int16_t)(rb(cur_pos)<<8);
                if(cur_val==(int16_t)0x8000&&(base2[1]&1)){cur_pos=lp;cur_val=(int16_t)(rb(cur_pos)<<8);} if(cur_val==(int16_t)0x8000){keyoff(ch);cur_val=0;break;}} break;
            case 4: pdelta<<=1; cur_pfrac+=delta; while(cur_pfrac&~0xffff){cur_pfrac+=fdelta;cur_pos+=pdelta;cur_pval=cur_val;cur_val=(int16_t)(rb(cur_pos)|rb(cur_pos+1)<<8);
                if(cur_val==(int16_t)0x8000&&(base2[1]&1)){cur_pos=lp;cur_val=(int16_t)(rb(cur_pos)|rb(cur_pos+1)<<8);} if(cur_val==(int16_t)0x8000){keyoff(ch);cur_val=0;break;}} break;
            case 8: cur_pos<<=1; cur_pfrac<<=1; if(cur_pfrac&0x10000){cur_pfrac&=0xffff;cur_pos|=1;}
                cur_pfrac+=delta; while(cur_pfrac&~0xffff){cur_pfrac+=fdelta;cur_pos+=pdelta;cur_pval=cur_val;cur_val=rb(cur_pos>>1);
                if(cur_val==0x88&&(base2[1]&1)){cur_pos=lp<<1;cur_val=rb(cur_pos>>1);} if(cur_val==0x88){keyoff(ch);cur_val=0;break;}
                if(cur_pos&1) cur_val>>=4; else cur_val&=15; cur_val=cur_pval+dpcm[cur_val]; if(cur_val<-32768) cur_val=-32768; else if(cur_val>32767) cur_val=32767;}
                cur_pfrac>>=1; if(cur_pos&1) cur_pfrac|=0x8000; cur_pos>>=1; break;
            }
            lval+=cur_val*lvol; rval+=cur_val*rvol; rbase[(rdelta+reverb_pos)&0x1fff]+=int16_t(cur_val*rbvol);
            chan->pos=cur_pos;chan->pfrac=cur_pfrac;chan->pval=cur_pval;chan->val=cur_val;
            if(regupdate()){base1[0xc]=cur_pos&0xff;base1[0xd]=cur_pos>>8&0xff;base1[0xe]=cur_pos>>16&0xff;}
        }
        reverb_pos=(reverb_pos+1)&0x1fff;
        auto cl=[](double v){ int x=(int)v; return x>32767?32767:x<-32768?-32768:x; };
        L=cl(lval); R=cl(rval);
    }
};
Vjtxexex_k539 *top; Ref ref; long tk=0;
void tick(){ top->clk=0; top->eval();
    top->rom_ok = top->rom_cs; top->rom_data = rom[top->rom_addr&0xfffff];
    top->clk=1; top->eval(); tk++; }
void wr(int a,int d){ top->cs=1; top->wr=1; top->addr=a; top->din=d; tick(); top->cs=0; top->wr=0; ref.write(a,d); tick(); }
int main(int argc,char**argv){
    srand(argc>1?atoi(argv[1]):1);
    for(int i=0;i<(1<<20);i++){ rom[i]=rand(); if(rom[i]==0x80||rom[i]==0x88) rom[i]=0x40; }
    // end markers
    for(int k=0;k<20000;k++){ int a=rand()&0xfffff; rom[a]=(rand()&1)?0x80:0x88; rom[a^1]=0; }
    top=new Vjtxexex_k539; top->rst=1; for(int i=0;i<4;i++) tick(); top->rst=0;
    wr(0x22f, 0x01);
    int maxd=0; long sumd=0, amp=0; int kmis=0, koffs=0; int lastk=0; int ns=6000;
    for(int s=0;s<ns;s++){
        if(s%500==0){ // reprogram some channels
            for(int ch=0;ch<8;ch++) if(rand()%2){
                int b=ch*0x20; int d=rand()%0x30000;
                wr(b+0,d&0xff); wr(b+1,d>>8&0xff); wr(b+2,d>>16);
                wr(b+3,rand()%80); wr(b+4,rand()%0x60); wr(b+5,0x11+rand()%15);
                int rd=rand()&0xffff; wr(b+6,rd&0xff); wr(b+7,rd>>8);
                int lp=rand()&0xfffff; wr(b+8,lp&0xff); wr(b+9,lp>>8&0xff); wr(b+10,lp>>16);
                int p=rand()&0xfffff; wr(b+0xc,p&0xff); wr(b+0xd,p>>8&0xff); wr(b+0xe,p>>16);
                int m=(rand()%3)*4 | ((rand()%4==0)?0x20:0); wr(0x200+2*ch,m); wr(0x201+2*ch,rand()&1);
                wr(0x214,1<<ch);
            }
        }
        top->sample=1; tick(); top->sample=0;
        for(int i=0;i<1000;i++) tick();
        int L,R; ref.sample(L,R); amp+=abs(L);
        top->addr=0x22c; tick(); tick(); if(top->dout!=ref.regs[0x22c]) kmis++;
        koffs += __builtin_popcount(lastk & ~ref.regs[0x22c]); lastk=ref.regs[0x22c];
        int dl=abs(L-(int16_t)top->left), dr=abs(R-(int16_t)top->right);
        if(dl>maxd) maxd=dl; if(dr>maxd) maxd=dr; sumd+=dl+dr;
        if((dl>40||dr>40) && s<5000) { printf("sample %d: ref %d %d  rtl %d %d keyon %02x/%02x\n",s,L,R,(int16_t)top->left,(int16_t)top->right, ref.regs[0x22c], 0); }
    }
    printf("keyoffs %d keyon mismatches %d  avg|L| %ld  max diff %d  mean %.2f\n", koffs, kmis, amp/ns, maxd, sumd/(2.0*ns));
}
