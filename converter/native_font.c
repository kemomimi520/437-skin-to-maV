/* Small ABI around unmodified FreeType 2.5.0. No game binary is loaded. */
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_MODULE_H
#include <stdlib.h>
#include <string.h>

typedef struct { FT_Library library; FT_Face face; } BridgeFont;
#define API __declspec(dllexport)

API void *msb_font_open(const unsigned char *data, int length, int size) {
    BridgeFont *f=(BridgeFont*)calloc(1,sizeof(BridgeFont));
    FT_UInt hinting_engine=1; /* Adobe CFF, used by the original player. */
    if (!f) return NULL;
    if (FT_Init_FreeType(&f->library) ||
        FT_Property_Set(f->library,"cff","hinting-engine",&hinting_engine) ||
        FT_New_Memory_Face(f->library,data,length,0,&f->face) ||
        FT_Select_Charmap(f->face,FT_ENCODING_UNICODE) ||
        FT_Set_Char_Size(f->face,size*64,size*64,0,0)) {
        if(f->face) FT_Done_Face(f->face);
        if(f->library) FT_Done_FreeType(f->library);
        free(f);return NULL;
    }
    return f;
}

API void msb_font_close(void *handle) {
    BridgeFont *f=(BridgeFont*)handle;
    if(f) { FT_Done_Face(f->face);FT_Done_FreeType(f->library);free(f); }
}

API int msb_font_glyph(void *handle, unsigned int code, int *metrics,
                       unsigned char *pixels, int capacity) {
    BridgeFont *f=(BridgeFont*)handle;
    FT_GlyphSlot slot;
    int width,height,row;
    if (!FT_Get_Char_Index(f->face,code)) return -1;
    /* Native 0x702da8 explicitly uses 0x8004: RENDER | NO_AUTOHINT. */
    if (FT_Load_Char(f->face,code,0x8004)) return -2;
    slot=f->face->glyph;width=slot->bitmap.width;height=slot->bitmap.rows;
    metrics[0]=width;metrics[1]=height;
    metrics[2]=slot->metrics.horiBearingX>>6;
    metrics[3]=slot->metrics.horiBearingY>>6;
    metrics[4]=slot->metrics.horiAdvance>>6;
    metrics[5]=f->face->size->metrics.height>>6;
    metrics[6]=f->face->size->metrics.ascender>>6;
    metrics[7]=f->face->size->metrics.descender>>6;
    metrics[8]=slot->bitmap_left;metrics[9]=slot->bitmap_top;
    if (pixels && capacity>=width*height) {
        for(row=0;row<height;row++)
            memcpy(pixels+row*width,slot->bitmap.buffer+row*slot->bitmap.pitch,width);
    }
    return width*height;
}
