/*
 * MPEG-4 video frame extraction
 * Copyright (c) 2003 Fabrice Bellard
 * Copyright (c) 2003 Michael Niedermayer
 *
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#define UNCHECKED_BITSTREAM_READER 1

#include "decode.h"
#include "parser.h"
#include "mpegvideo.h"
#include "mpeg4videodec.h"
#include "mpeg4videodefs.h"

struct Mp4vParseContext {
    ParseContext pc;
    Mpeg4DecContext dec_ctx;
    int first_picture;
};

/**
 * Find the end of the current frame in the bitstream.
 * @return the position of the first byte of the next frame, or -1
 */
static int mpeg4_find_frame_end(ParseContext *pc, const uint8_t *buf, int buf_size)
{
    int vop_found, i;
    uint32_t state;

    vop_found = pc->frame_start_found;
    state     = pc->state;

    i = 0;
    if (!vop_found) {
        for (i = 0; i < buf_size; i++) {
            state = (state << 8) | buf[i];
            if (state == VOP_STARTCODE) {
                i++;
                vop_found = 1;
                break;
            }
        }
    }

    if (vop_found) {
        /* EOF considered as end of frame */
        if (buf_size == 0)
            return 0;
        for (; i < buf_size; i++) {
            state = (state << 8) | buf[i];
            if ((state & 0xFFFFFF00) == 0x100) {
                if (state == SLICE_STARTCODE || state == EXT_STARTCODE)
                    continue;
                pc->frame_start_found = 0;
                pc->state             = -1;
                return i - 3;
            }
        }
    }
    pc->frame_start_found = vop_found;
    pc->state             = state;
    return END_NOT_FOUND;
}

/* XXX: make it use less memory */
static int mpeg4_decode_header(AVCodecParserContext *s1, AVCodecContext *avctx,
                               const uint8_t *buf, int buf_size)
{
    struct Mp4vParseContext *pc = s1->priv_data;
    Mpeg4DecContext *dec_ctx = &pc->dec_ctx;
    MPVContext *const s = &dec_ctx->h.c;
    GetBitContext gb1, *gb = &gb1;
    int ret;

    s->avctx               = avctx;

    if (avctx->extradata_size && pc->first_picture) {
        init_get_bits(gb, avctx->extradata, avctx->extradata_size * 8);
        ret = ff_mpeg4_parse_picture_header(dec_ctx, gb, 1, 1);
        if (ret < 0)
            av_log(avctx, AV_LOG_WARNING, "Failed to parse extradata\n");
    }

    init_get_bits(gb, buf, 8 * buf_size);
    ret = ff_mpeg4_parse_picture_header(dec_ctx, gb, 0, 1);
    avctx->has_b_frames = !s->low_delay;
    if (s->width && (!avctx->width || !avctx->height ||
                     !avctx->coded_width || !avctx->coded_height)) {
        ret = ff_set_dimensions(avctx, s->width, s->height);
        if (ret < 0)
            return ret;
    }
    if((s1->flags & PARSER_FLAG_USE_CODEC_TS) && s->avctx->framerate.num>0 && ret>=0){
        av_assert1(s1->pts == AV_NOPTS_VALUE);
        av_assert1(s1->dts == AV_NOPTS_VALUE);

        s1->pts = av_rescale_q(s->time, (AVRational){1, s->avctx->framerate.num}, (AVRational){1, 1200000});
    }

    s1->pict_type     = s->pict_type;
    pc->first_picture = 0;
    return ret;
}

static av_cold int mpeg4video_parse_init(AVCodecParserContext *s)
{
    struct Mp4vParseContext *pc = s->priv_data;

    pc->first_picture           = 1;
    pc->dec_ctx.quant_precision       = 5;
    pc->dec_ctx.h.c.slice_context_count = 1;
    pc->dec_ctx.showed_packed_warning = 1;
    return 0;
}

static int mpeg4video_parse(AVCodecParserContext *s,
                            AVCodecContext *avctx,
                            const uint8_t **poutbuf, int *poutbuf_size,
                            const uint8_t *buf, int buf_size)
{
    ParseContext *pc = s->priv_data;
    int next;

    if (s->flags & PARSER_FLAG_COMPLETE_FRAMES) {
        next = buf_size;
    } else {
        next = mpeg4_find_frame_end(pc, buf, buf_size);

        if (ff_combine_frame(pc, next, &buf, &buf_size) < 0) {
            *poutbuf      = NULL;
            *poutbuf_size = 0;
            return buf_size;
        }
    }
    mpeg4_decode_header(s, avctx, buf, buf_size);

    *poutbuf      = buf;
    *poutbuf_size = buf_size;
    return next;
}

const AVCodecParser ff_mpeg4video_parser = {
    .codec_ids      = { AV_CODEC_ID_MPEG4 },
    .priv_data_size = sizeof(struct Mp4vParseContext),
    .parser_init    = mpeg4video_parse_init,
    .parser_parse   = mpeg4video_parse,
    .parser_close   = ff_parse_close,
};
