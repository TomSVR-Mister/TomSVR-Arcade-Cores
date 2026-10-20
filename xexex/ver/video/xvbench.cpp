// xvbench dumpdir out.raw [frames]
#include "Vxvbench.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <string>
#include <cstdint>
using namespace std;
static Vxvbench *t;
static vector<uint8_t> tiles, lvcrom, objrom;
static uint64_t ticks = 0;
static int cen6 = 0;
struct Rom { int lat = 0; uint32_t last = ~0u; };
static Rom rt, rl, ro;

static vector<uint8_t> rd(const string &f) {
    vector<uint8_t> v; FILE *fp = fopen(f.c_str(), "rb");
    if (!fp) { fprintf(stderr, "cannot open %s\n", f.c_str()); exit(1); }
    fseek(fp, 0, SEEK_END); v.resize(ftell(fp)); fseek(fp, 0, SEEK_SET);
    if (fread(v.data(), 1, v.size(), fp) != v.size()) exit(1); fclose(fp); return v;
}
static uint32_t w32(const vector<uint8_t> &m, uint32_t a) {
    a &= m.size() - 1;
    return m[a] | m[a + 1] << 8 | m[a + 2] << 16 | (uint32_t)m[a + 3] << 24;
}
static void rom(Rom &r, bool cs, uint32_t addr, const vector<uint8_t> &m, uint32_t &data, uint8_t &ok) {
    if (!cs) { ok = 0; r.last = ~0u; return; }
    if (addr != r.last) { r.last = addr; r.lat = 7; ok = 0; }
    if (r.lat > 0) { r.lat--; ok = 0; return; }
    data = w32(m, addr * 4); ok = 1;
}
static void tick() {
    t->pxl_cen  = cen6 == 0;
    t->pxl2_cen = cen6 == 0 || cen6 == 3;
    t->clk = 0; t->eval();
    rom(rt, t->tile_cs, t->tile_addr, tiles, t->tile_data, t->tile_ok);
    rom(rl, t->lvc_cs, t->lvc_addr, lvcrom, t->lvc_data, t->lvc_ok);
    rom(ro, t->obj_cs, t->obj_addr, objrom, t->obj_data, t->obj_ok);
    t->clk = 1; t->eval();
    cen6 = (cen6 + 1) % 6; ticks++;
}
static void wr(int cs, uint32_t a, uint16_t d, int dsn = 0) {
    t->cs = 1 << cs; t->cpu_addr = a; t->cpu_dout = d; t->cpu_dsn = dsn; t->cpu_we = 1;
    tick();
    t->cs = 0; t->cpu_we = 0; tick();
}
static vector<uint16_t> r16(const string &f) {
    auto b = rd(f); vector<uint16_t> v(b.size() / 2);
    for (size_t i = 0; i < v.size(); i++) v[i] = b[2 * i] | b[2 * i + 1] << 8;
    return v;
}
int main(int argc, char **argv) {
    string d = argv[1]; int frames = argc > 3 ? atoi(argv[3]) : 3;
    string roms = getenv("XROMS") ? getenv("XROMS") : ".";
    tiles = rd(roms + "/tiles.bin"); lvcrom = rd(roms + "/lvc.bin"); objrom = rd(roms + "/obj.bin");
    t = new Vxvbench;
    t->gfx_en = getenv("GFXEN") ? strtol(getenv("GFXEN"), 0, 16) : 0xff;
    t->rst = 1; for (int k = 0; k < 20; k++) tick(); t->rst = 0; tick();
    // misc
    FILE *fm = fopen((d + "/misc.txt").c_str(), "r"); char key[32]; unsigned val; unsigned k246[8] = {0}; unsigned ctl2 = 0, k250page = 0;
    while (fscanf(fm, "%31s %x", key, &val) == 2) {
        string k = key;
        if (k == "control2") ctl2 = val;
        else if (k == "k250page") k250page = val;
        else if (k.rfind("k246_", 0) == 0) k246[k[5] - '0'] = val;
    }
    fclose(fm);
    t->alpha_off = (ctl2 >> 9) & 1;
    auto k157 = r16(d + "/k157.bin");
    for (int i = 0; i < 32; i++) wr(0, i, k157[i]);
    auto vram = r16(d + "/vram.bin");
    for (int p = 0; p < 8; p++) {
        int row = p >> 1, col = p & 1, mp = row * 4 + col;
        wr(0, 25, row << 3 | col);
        for (int i = 0; i < 4096; i++) wr(1, i, vram[mp * 4096 + i]);
    }
    wr(0, 25, k157[25]);
    auto pal = r16(d + "/pal.bin");
    for (int i = 0; i < 4096; i++) wr(6, i, pal[i]);
    auto k251 = rd(d + "/k251.bin");
    for (int i = 0; i < 16; i++) wr(7, i, k251[i]);
    auto k338 = r16(d + "/k338.bin");
    for (int i = 0; i < 16; i++) wr(8, i, k338[i]);
    // LVC: the shown buffer is m_buffer[page]; load it twice through the CPU RAM and the DMA
    auto k250 = r16(d + "/k250ram.bin"); auto k250r = rd(d + "/k250reg.bin");
    for (int i = 0; i < 0x800; i++) wr(2, i, k250[0x2000 + k250page * 0x800 + i]);
    for (int i = 0; i < 8; i++) if (i != 4) wr(3, i, k250r[i]);
    for (int n = 0; n < 2; n++) { wr(3, 4, k250r[4] | 2); wr(3, 4, k250r[4] & ~2); for (int k = 0; k < 3000; k++) tick(); }
    for (int i = 0; i < 0x1000; i++) wr(2, i, k250[i]);
    // sprites
    // MAME's snapshot shows the objects copied by the DMA at the previous vertical blank: XSPR names that spriteram
    auto spr = r16(getenv("XSPR") ? getenv("XSPR") : d + "/spr.bin");
    for (int i = 0; i < 16384; i++) wr(4, i, spr[i]);
    for (int i = 0; i < 4; i++) {
        unsigned v = k246[2 * i] << 8 | k246[2 * i + 1];
        if (i == 2) v |= 0x10;   // keep the object DMA on
        wr(5, i, v);
    }
    // run and capture the last frame
    FILE *fo = fopen(argv[2], "wb");
    int fcnt = 0; uint8_t lvbl_l = t->LVBL, lhbl_l = t->LHBL; int x = 0, y = 0;
    vector<uint8_t> img(512 * 300 * 3, 0);
    long ocs = 0, obsy = 0;
    while (fcnt <= frames) {
        tick();
        if (t->obj_cs && t->obj_ok) ocs++;
        if (t->dma_bsy) obsy++;
        if (cen6 == 1) {   // just after a pxl_cen edge
            if (t->LVBL && !lvbl_l) { fcnt++; y = 0; }
            if (t->LHBL && !lhbl_l) { x = 0; if (t->LVBL) y++; }
            lvbl_l = t->LVBL; lhbl_l = t->LHBL;
            if (fcnt == frames && y < 300 && x < 512) {
                uint8_t *p = &img[(y * 512 + x) * 3]; p[0] = t->red; p[1] = t->green; p[2] = t->blue;
            }
            x++;
        }
    }
    fwrite(img.data(), 1, img.size(), fo); fclose(fo);
    fprintf(stderr, "obj rom reads %ld, dma busy clocks %ld\n", ocs, obsy);
    fprintf(stderr, "done, %llu ticks\n", (unsigned long long)ticks);
    return 0;
}
