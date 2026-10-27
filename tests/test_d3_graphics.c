#include "../third_party/nxnative/dm/host/dm_d3_graphics.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc,char **argv) {
    assert(!strcmp(dm_d3_graphics_image(NULL,"main","unknown"),"main"));
    assert(!strcmp(dm_d3_graphics_image("normal","main","unknown"),"main"));
    assert(!strcmp(dm_d3_graphics_image("wide","main",DM_D3_MAIN_BUILD_ID),"mainwide"));
    assert(!strcmp(dm_d3_graphics_image("wide","sdk","unknown"),"sdk"));
    assert(!dm_d3_graphics_image("wide","main","2607a74f5df7754cc0357b5df7e49694"));
    assert(!dm_d3_graphics_image("wide","main",NULL));
    assert(!dm_d3_graphics_image("stretch","main",DM_D3_MAIN_BUILD_ID));
    assert(!dm_d3_graphics_image("wide",NULL,DM_D3_MAIN_BUILD_ID));
    assert(!dm_d3_wide_text_valid(NULL,0));
    if(argc>1) {
        FILE *f=fopen(argv[1],"rb");assert(f);assert(!fseek(f,0,SEEK_END));long n=ftell(f);assert(n>0);rewind(f);
        uint8_t *text=malloc((size_t)n);assert(text);assert(fread(text,1,(size_t)n,f)==(size_t)n);fclose(f);
        assert(dm_d3_wide_text_valid(text,(size_t)n));
        const size_t offsets[]={0xe7858,0xe785c,0xe7860,0xe7864,0xe7868,0xe786c,0xebb48,0x29b480,0x29b484,0x29b7e8,0x29b914};
        for(unsigned i=0;i<sizeof offsets/sizeof offsets[0];i++) {
            text[offsets[i]]^=1;assert(!dm_d3_wide_text_valid(text,(size_t)n));text[offsets[i]]^=1;
        }
        assert(!dm_d3_wide_text_valid(text,0x29b91f));
        // The previous 1568x720 profile must not pass the raised guard.
        const uint32_t old[][2]={{0xe7858,0xd280c408},{0xe785c,0xd280c409},
            {0xe7868,0x528c16ca},{0xe786c,0x72a8016a}};
        for(unsigned i=0;i<sizeof old/sizeof old[0];i++)memcpy(text+old[i][0],&old[i][1],4);
        assert(!dm_d3_wide_text_valid(text,(size_t)n));free(text);
    }
    puts("PASS: exact-build signed wide selection, unchanged normal/SDK identity, geometry/text guards and mutations");
}
