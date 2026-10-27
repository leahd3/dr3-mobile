#include "../third_party/nxnative/dm/host/dm_d3_graphics.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

// Offsets guarded by both word tables; each one must be load-bearing.
static const size_t guarded[]={0xe7858,0xe785c,0xe7860,0xe7864,0xe7868,0xe786c,
    0xe7870,0xe7874,0xebb48,0x29b480,0x29b484,0x29b7e8,0x29b854,0x29b914,
    0x29b918,0x29b91c};

static uint8_t *load(const char *path,size_t *n) {
    FILE *f=fopen(path,"rb");assert(f);assert(!fseek(f,0,SEEK_END));long size=ftell(f);assert(size>0);rewind(f);
    uint8_t *text=malloc((size_t)size);assert(text);assert(fread(text,1,(size_t)size,f)==(size_t)size);fclose(f);
    *n=(size_t)size;return text;
}

static void check_image(const char *path,const char *mode,const char *other) {
    size_t n;uint8_t *text=load(path,&n);
    assert(dm_d3_graphics_text_valid(mode,text,n));
    // The other patched size's words must be rejected, not merely tolerated.
    assert(!dm_d3_graphics_text_valid(other,text,n));
    for(unsigned i=0;i<sizeof guarded/sizeof guarded[0];i++) {
        text[guarded[i]]^=1;assert(!dm_d3_graphics_text_valid(mode,text,n));text[guarded[i]]^=1;
    }
    assert(!dm_d3_graphics_text_valid(mode,text,0x29b91f));
    assert(!dm_d3_graphics_text_valid(mode,NULL,n));
    free(text);
}

int main(int argc,char **argv) {
    assert(!strcmp(dm_d3_graphics_image(NULL,"main","unknown"),"main"));
    assert(!strcmp(dm_d3_graphics_image("normal","main","unknown"),"main"));
    assert(!strcmp(dm_d3_graphics_image("wide","main",DM_D3_MAIN_BUILD_ID),"mainwide"));
    assert(!strcmp(dm_d3_graphics_image("wider","main",DM_D3_MAIN_BUILD_ID),"mainwide"));
    assert(!strcmp(dm_d3_graphics_image("wide","sdk","unknown"),"sdk"));
    assert(!dm_d3_graphics_image("wide","main","2607a74f5df7754cc0357b5df7e49694"));
    assert(!dm_d3_graphics_image("wide","main",NULL));
    assert(!dm_d3_graphics_image("stretch","main",DM_D3_MAIN_BUILD_ID));
    assert(!dm_d3_graphics_image("wide",NULL,DM_D3_MAIN_BUILD_ID));

    assert(dm_d3_graphics_mode_width(NULL)==0);
    assert(dm_d3_graphics_mode_width("normal")==0);
    assert(dm_d3_graphics_mode_width("wide")==1568);
    assert(dm_d3_graphics_mode_width("wider")==1920);
    assert(dm_d3_graphics_mode_width("stretch")==-1);
    // iOS still exposes one patched option named "wide"; it carries the 1920x720 words.
    assert(!strcmp(dm_d3_graphics_ios_mode("wide"),"wider"));
    assert(dm_d3_graphics_ios_mode(NULL)==NULL);
    assert(dm_d3_graphics_text_valid("normal",NULL,0));
    assert(!dm_d3_graphics_text_valid("stretch",NULL,0));

    assert(argc==3);
    check_image(argv[1],"wide","wider");
    check_image(argv[2],"wider","wide");

    // A 1568x720 image that was partly raised to the 1920x720 width is neither mode.
    size_t n;uint8_t *text=load(argv[2],&n);
    const uint32_t wide_width[]={0xd280c408,0xd280c409};
    for(unsigned i=0;i<2;i++)memcpy(text+0xe7858+4*i,&wide_width[i],4);
    assert(!dm_d3_graphics_text_valid("wide",text,n));
    assert(!dm_d3_graphics_text_valid("wider",text,n));
    free(text);
    puts("PASS: exact-build signed selection, normal/SDK identity, per-mode 1568/1920 word tables and mismatch rejection");
}
