/*
 * bridge_pcb.c — standalone KiCad .kicad_pcb S-expression parser
 * Pure C11, no external dependencies.
 * Parses footprints, segments (tracks), vias, zones, pads.
 * Renders per-layer SVG for the PCB viewer.
 */

#include "kicad_bridge.h"
#include "kicad_bridge_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

/* ------------------------------------------------------------------ */
/* Shared S-expression helpers (mirror of bridge_sch.c)                */
/* ------------------------------------------------------------------ */

static const char* pcb_find_sexp_block(const char* content, size_t len,
                                       size_t start_offset,
                                       const char* prefix,
                                       const char** end_out)
{
    size_t prefix_len = strlen(prefix);
    if (start_offset >= len) return NULL;

    const char* p = content + start_offset;
    const char* end = content + len;

    while (p < end) {
        const char* found = (const char*)memmem(p, (size_t)(end - p),
                                                 prefix, prefix_len);
        if (!found) return NULL;

        int depth = 0;
        const char* q = found;
        while (q < end) {
            if (*q == '(')      depth++;
            else if (*q == ')') {
                depth--;
                if (depth == 0) {
                    if (end_out) *end_out = q + 1;
                    return found;
                }
            }
            q++;
        }
        p = found + prefix_len;
    }
    return NULL;
}

static int pcb_extract_quoted(const char* block, size_t block_len,
                              const char* key, char* buf, size_t buf_size)
{
    size_t key_len = strlen(key);
    const char* end = block + block_len;
    const char* p = block;

    while (p < end) {
        const char* found = (const char*)memmem(p, (size_t)(end - p),
                                                 key, key_len);
        if (!found) return 0;
        const char* after = found + key_len;
        while (after < end && isspace((unsigned char)*after)) after++;
        if (after >= end || *after != '"') { p = found + key_len; continue; }
        after++;
        size_t i = 0;
        while (after < end && *after != '"' && i < buf_size - 1)
            buf[i++] = *after++;
        buf[i] = '\0';
        return 1;
    }
    return 0;
}

static int pcb_extract_at(const char* block, size_t block_len,
                          double* x_out, double* y_out, double* angle_out)
{
    const char needle[] = "(at ";
    size_t nlen = sizeof(needle) - 1;
    const char* end = block + block_len;
    const char* p = (const char*)memmem(block, block_len, needle, nlen);
    if (!p) return 0;
    p += nlen;
    if (p >= end) return 0;

    char* ep = NULL;
    double x = strtod(p, &ep);
    if (ep == p) return 0;
    p = ep;
    while (p < end && isspace((unsigned char)*p)) p++;
    double y = strtod(p, &ep);
    if (ep == p) return 0;
    p = ep;
    while (p < end && isspace((unsigned char)*p)) p++;
    double angle = 0.0;
    if (p < end && (*p == '-' || isdigit((unsigned char)*p))) {
        angle = strtod(p, &ep);
        if (ep == p) angle = 0.0;
    }
    *x_out = x;
    *y_out = y;
    if (angle_out) *angle_out = angle;
    return 1;
}

/*
 * pcb_extract_token — read the next whitespace/paren-delimited token
 * from p into buf (up to buf_size-1 chars). Returns pointer after token.
 */
static const char* pcb_extract_token(const char* p, const char* end,
                                     char* buf, size_t buf_size)
{
    while (p < end && (isspace((unsigned char)*p) || *p == '(' || *p == ')'))
        p++;
    size_t i = 0;
    while (p < end && !isspace((unsigned char)*p) && *p != '(' && *p != ')'
           && i < buf_size - 1)
        buf[i++] = *p++;
    buf[i] = '\0';
    return p;
}

/* ------------------------------------------------------------------ */
/* Layer id <-> name mapping                                           */
/* ------------------------------------------------------------------ */

/* KiCad standard layer ids */
static const struct { int id; const char* name; const char* color; } kicad_std_layers[] = {
    {  0, "F.Cu",      "#ff5555" },
    { 31, "B.Cu",      "#5599ff" },
    { 32, "B.Adhes",   "#8b2be2" },
    { 33, "F.Adhes",   "#c2c200" },
    { 34, "B.Paste",   "#3399ff" },
    { 35, "F.Paste",   "#cc99cc" },
    { 36, "B.SilkS",   "#aaaaaa" },
    { 37, "F.SilkS",   "#ffff00" },
    { 38, "B.Mask",    "#cc0000" },
    { 39, "F.Mask",    "#ff0000" },
    { 44, "Edge.Cuts", "#ffff00" },
    { 45, "Margin",    "#ff00ff" },
    { 46, "B.CrtYd",   "#ff00ff" },
    { 47, "F.CrtYd",   "#ff00ff" },
    { 48, "B.Fab",     "#888888" },
    { 49, "F.Fab",     "#888888" },
    { -1, NULL, NULL }
};

static int layer_name_to_id(const char* name)
{
    for (int i = 0; kicad_std_layers[i].name; i++) {
        if (strcmp(kicad_std_layers[i].name, name) == 0)
            return kicad_std_layers[i].id;
    }
    /* Inner copper layers Cu1..Cu30 */
    if (strncmp(name, "In", 2) == 0) {
        int n = atoi(name + 2);
        if (n >= 1 && n <= 30) return n;
    }
    return -1;
}

static const char* layer_id_to_color(int id)
{
    for (int i = 0; kicad_std_layers[i].name; i++) {
        if (kicad_std_layers[i].id == id)
            return kicad_std_layers[i].color;
    }
    /* Inner copper */
    if (id >= 1 && id <= 30) return "#44aa44";
    return "#888888";
}

/* ------------------------------------------------------------------ */
/* Parsing passes                                                       */
/* ------------------------------------------------------------------ */

static void parse_pcb_layers(KicadPcb* pcb)
{
    /* (layers
         (0 "F.Cu" signal)
         (31 "B.Cu" signal)
         ...
       ) */
    const char* content = pcb->raw_content;
    size_t len = pcb->raw_len;
    const char prefix[] = "(layers";
    const char* block_end = NULL;
    const char* block = pcb_find_sexp_block(content, len, 0, prefix, &block_end);
    if (!block) {
        /* No explicit layers block — insert standard copper + silkscreen */
        for (int i = 0; kicad_std_layers[i].name && pcb->layer_count < PCB_MAX_LAYERS; i++) {
            PcbLayer* l = &pcb->layers[pcb->layer_count++];
            l->id = kicad_std_layers[i].id;
            strncpy(l->name, kicad_std_layers[i].name, PCB_MAX_PROP_LEN - 1);
            strncpy(l->color, kicad_std_layers[i].color, 15);
            l->visible = 1;
        }
        return;
    }

    size_t block_len = (size_t)(block_end - block);
    /* Each layer entry: (id "name" type) */
    const char* p = block + strlen("(layers");
    const char* bend = block + block_len;
    while (p < bend && pcb->layer_count < PCB_MAX_LAYERS) {
        /* Find next '(' */
        while (p < bend && *p != '(') p++;
        if (p >= bend) break;
        p++; /* skip '(' */
        /* Read id */
        char id_str[16] = {0};
        p = pcb_extract_token(p, bend, id_str, sizeof(id_str));
        if (id_str[0] == '\0' || strcmp(id_str, "layers") == 0) break;
        int layer_id = atoi(id_str);
        /* Read name */
        while (p < bend && isspace((unsigned char)*p)) p++;
        char name[PCB_MAX_PROP_LEN] = {0};
        if (p < bend && *p == '"') {
            p++;
            size_t i = 0;
            while (p < bend && *p != '"' && i < PCB_MAX_PROP_LEN - 1)
                name[i++] = *p++;
            name[i] = '\0';
            if (p < bend) p++; /* skip closing " */
        }
        if (name[0] == '\0') {
            /* skip to closing ')' */
            while (p < bend && *p != ')') p++;
            if (p < bend) p++;
            continue;
        }
        PcbLayer* l = &pcb->layers[pcb->layer_count++];
        l->id = layer_id;
        strncpy(l->name, name, PCB_MAX_PROP_LEN - 1);
        /* Look up standard color */
        const char* col = layer_id_to_color(layer_id);
        strncpy(l->color, col, 15);
        l->visible = 1;
        /* skip to closing ')' of this entry */
        while (p < bend && *p != ')') p++;
        if (p < bend) p++;
    }

    /* Ensure standard layers are present even if not in file */
    if (pcb->layer_count == 0) {
        for (int i = 0; kicad_std_layers[i].name && pcb->layer_count < PCB_MAX_LAYERS; i++) {
            PcbLayer* l = &pcb->layers[pcb->layer_count++];
            l->id = kicad_std_layers[i].id;
            strncpy(l->name, kicad_std_layers[i].name, PCB_MAX_PROP_LEN - 1);
            strncpy(l->color, kicad_std_layers[i].color, 15);
            l->visible = 1;
        }
    }
}

static int layer_name_in_pcb(const KicadPcb* pcb, const char* name)
{
    /* First check parsed layers */
    for (int i = 0; i < pcb->layer_count; i++) {
        if (strcmp(pcb->layers[i].name, name) == 0)
            return pcb->layers[i].id;
    }
    return layer_name_to_id(name);
}

static void parse_pads_in_footprint(PcbFootprint* fp,
                                    const char* block, size_t block_len)
{
    const char prefix[] = "(pad ";
    size_t offset = 0;
    while (fp->pad_count < PCB_MAX_PADS) {
        const char* pad_end = NULL;
        const char* pad = pcb_find_sexp_block(block, block_len, offset, prefix, &pad_end);
        if (!pad) break;
        size_t pad_len = (size_t)(pad_end - pad);

        PcbPad* p = &fp->pads[fp->pad_count];
        memset(p, 0, sizeof(*p));

        /* (pad "number" shape ...) */
        const char* q = pad + strlen("(pad ");
        const char* bend = pad + pad_len;
        /* number */
        char num[32] = {0};
        q = pcb_extract_token(q, bend, num, sizeof(num));
        if (*num == '"') {
            /* quoted */
            size_t i = 0;
            while (q < bend && *q != '"' && i < 31) p->number[i++] = *q++;
            p->number[i] = '\0';
            if (q < bend) q++;
        } else {
            strncpy(p->number, num, 31);
        }
        /* shape */
        while (q < bend && isspace((unsigned char)*q)) q++;
        char shape[32] = {0};
        q = pcb_extract_token(q, bend, shape, sizeof(shape));
        strncpy(p->shape, shape, 31);

        /* at */
        double ax = 0, ay = 0;
        pcb_extract_at(pad, pad_len, &ax, &ay, NULL);
        p->x = ax; p->y = ay;

        /* size */
        const char size_needle[] = "(size ";
        const char* sp = (const char*)memmem(pad, pad_len, size_needle, strlen(size_needle));
        if (sp) {
            const char* sv = sp + strlen(size_needle);
            char* ep = NULL;
            p->w = strtod(sv, &ep);
            if (ep != sv) {
                const char* sv2 = ep;
                while (sv2 < bend && isspace((unsigned char)*sv2)) sv2++;
                p->h = strtod(sv2, NULL);
            }
        }

        /* layer */
        char layer_name[PCB_MAX_PROP_LEN] = {0};
        if (pcb_extract_quoted(pad, pad_len, "(layer \"", layer_name, PCB_MAX_PROP_LEN))
            p->layer_id = layer_name_to_id(layer_name);
        else
            p->layer_id = 0; /* default F.Cu */

        /* net name */
        pcb_extract_quoted(pad, pad_len, "(net ", p->net, PCB_MAX_PROP_LEN);

        fp->pad_count++;
        offset = (size_t)(pad_end - block);
    }
}

static void parse_footprints(KicadPcb* pcb)
{
    const char* content = pcb->raw_content;
    size_t len = pcb->raw_len;
    const char prefix[] = "(footprint ";
    size_t offset = 0;

    while (pcb->footprint_count < PCB_MAX_FOOTPRINTS) {
        const char* block_end = NULL;
        const char* block = pcb_find_sexp_block(content, len, offset, prefix, &block_end);
        if (!block) break;
        size_t block_len = (size_t)(block_end - block);

        PcbFootprint* fp = &pcb->footprints[pcb->footprint_count];
        memset(fp, 0, sizeof(*fp));

        /* reference */
        pcb_extract_quoted(block, block_len,
                           "(property \"Reference\" \"", fp->reference, PCB_MAX_PROP_LEN);
        if (fp->reference[0] == '\0')
            pcb_extract_quoted(block, block_len, "(reference \"", fp->reference, PCB_MAX_PROP_LEN);

        /* value */
        pcb_extract_quoted(block, block_len,
                           "(property \"Value\" \"", fp->value, PCB_MAX_PROP_LEN);
        if (fp->value[0] == '\0')
            pcb_extract_quoted(block, block_len, "(value \"", fp->value, PCB_MAX_PROP_LEN);

        /* position */
        pcb_extract_at(block, block_len, &fp->x, &fp->y, &fp->angle);

        /* layer */
        char layer_name[PCB_MAX_PROP_LEN] = {0};
        if (pcb_extract_quoted(block, block_len, "(layer \"", layer_name, PCB_MAX_PROP_LEN))
            fp->layer_id = layer_name_in_pcb(pcb, layer_name);
        else
            fp->layer_id = 0;

        /* pads */
        parse_pads_in_footprint(fp, block, block_len);

        pcb->footprint_count++;
        offset = (size_t)(block_end - content);
    }
}

static void parse_segments(KicadPcb* pcb)
{
    const char* content = pcb->raw_content;
    size_t len = pcb->raw_len;
    const char prefix[] = "(segment ";
    size_t offset = 0;

    while (pcb->segment_count < PCB_MAX_SEGMENTS) {
        const char* block_end = NULL;
        const char* block = pcb_find_sexp_block(content, len, offset, prefix, &block_end);
        if (!block) break;
        size_t block_len = (size_t)(block_end - block);

        PcbSegment* seg = &pcb->segments[pcb->segment_count];
        memset(seg, 0, sizeof(*seg));

        /* (start x y) */
        const char st_needle[] = "(start ";
        const char* sp = (const char*)memmem(block, block_len, st_needle, strlen(st_needle));
        if (sp) {
            const char* sv = sp + strlen(st_needle);
            char* ep = NULL;
            seg->x1 = strtod(sv, &ep);
            if (ep != sv) {
                const char* sv2 = ep;
                while (*sv2 && isspace((unsigned char)*sv2)) sv2++;
                seg->y1 = strtod(sv2, NULL);
            }
        }

        /* (end x y) */
        const char en_needle[] = "(end ";
        const char* ep2 = (const char*)memmem(block, block_len, en_needle, strlen(en_needle));
        if (ep2) {
            const char* sv = ep2 + strlen(en_needle);
            char* ep = NULL;
            seg->x2 = strtod(sv, &ep);
            if (ep != sv) {
                const char* sv2 = ep;
                while (*sv2 && isspace((unsigned char)*sv2)) sv2++;
                seg->y2 = strtod(sv2, NULL);
            }
        }

        /* (width w) */
        const char w_needle[] = "(width ";
        const char* wp = (const char*)memmem(block, block_len, w_needle, strlen(w_needle));
        if (wp) {
            const char* sv = wp + strlen(w_needle);
            seg->width = strtod(sv, NULL);
        }
        if (seg->width <= 0.0) seg->width = 0.2;

        /* (layer "name") */
        char layer_name[PCB_MAX_PROP_LEN] = {0};
        if (pcb_extract_quoted(block, block_len, "(layer \"", layer_name, PCB_MAX_PROP_LEN))
            seg->layer_id = layer_name_in_pcb(pcb, layer_name);

        /* (net "name") or (net N "name") */
        pcb_extract_quoted(block, block_len, "(net \"", seg->net, PCB_MAX_PROP_LEN);

        pcb->segment_count++;
        offset = (size_t)(block_end - content);
    }
}

static void parse_vias(KicadPcb* pcb)
{
    const char* content = pcb->raw_content;
    size_t len = pcb->raw_len;
    const char prefix[] = "(via ";
    size_t offset = 0;

    while (pcb->via_count < PCB_MAX_VIAS) {
        const char* block_end = NULL;
        const char* block = pcb_find_sexp_block(content, len, offset, prefix, &block_end);
        if (!block) break;
        size_t block_len = (size_t)(block_end - block);

        PcbVia* via = &pcb->vias[pcb->via_count];
        memset(via, 0, sizeof(*via));

        /* (at x y) */
        pcb_extract_at(block, block_len, &via->x, &via->y, NULL);

        /* (size d) */
        const char sz_needle[] = "(size ";
        const char* sp = (const char*)memmem(block, block_len, sz_needle, strlen(sz_needle));
        if (sp) via->size = strtod(sp + strlen(sz_needle), NULL);
        if (via->size <= 0.0) via->size = 0.8;

        /* (layers "from" "to") */
        const char layers_needle[] = "(layers ";
        const char* lp = (const char*)memmem(block, block_len, layers_needle, strlen(layers_needle));
        if (lp) {
            const char* lv = lp + strlen(layers_needle);
            const char* lend = block + block_len;
            char from_name[PCB_MAX_PROP_LEN] = {0}, to_name[PCB_MAX_PROP_LEN] = {0};
            /* first quoted */
            while (lv < lend && *lv != '"') lv++;
            if (lv < lend) {
                lv++;
                size_t i = 0;
                while (lv < lend && *lv != '"' && i < PCB_MAX_PROP_LEN - 1)
                    from_name[i++] = *lv++;
                from_name[i] = '\0';
                if (lv < lend) lv++;
            }
            while (lv < lend && *lv != '"') lv++;
            if (lv < lend) {
                lv++;
                size_t i = 0;
                while (lv < lend && *lv != '"' && i < PCB_MAX_PROP_LEN - 1)
                    to_name[i++] = *lv++;
                to_name[i] = '\0';
            }
            via->layer_from = layer_name_in_pcb(pcb, from_name);
            via->layer_to   = layer_name_in_pcb(pcb, to_name);
        } else {
            via->layer_from = 0;   /* F.Cu */
            via->layer_to   = 31;  /* B.Cu */
        }

        pcb_extract_quoted(block, block_len, "(net \"", via->net, PCB_MAX_PROP_LEN);

        pcb->via_count++;
        offset = (size_t)(block_end - content);
    }
}

static void parse_zones(KicadPcb* pcb)
{
    const char* content = pcb->raw_content;
    size_t len = pcb->raw_len;
    const char prefix[] = "(zone ";
    size_t offset = 0;

    while (pcb->zone_count < PCB_MAX_ZONES) {
        const char* block_end = NULL;
        const char* block = pcb_find_sexp_block(content, len, offset, prefix, &block_end);
        if (!block) break;
        size_t block_len = (size_t)(block_end - block);

        PcbZone* zone = &pcb->zones[pcb->zone_count];
        memset(zone, 0, sizeof(*zone));

        /* layer */
        char layer_name[PCB_MAX_PROP_LEN] = {0};
        if (pcb_extract_quoted(block, block_len, "(layer \"", layer_name, PCB_MAX_PROP_LEN))
            zone->layer_id = layer_name_in_pcb(pcb, layer_name);

        /* net name */
        pcb_extract_quoted(block, block_len, "(net_name \"", zone->net, PCB_MAX_PROP_LEN);
        if (zone->net[0] == '\0')
            pcb_extract_quoted(block, block_len, "(net \"", zone->net, PCB_MAX_PROP_LEN);

        /* filled polygon: (filled_polygon (pts (xy ...) ...)) */
        const char fp_needle[] = "(filled_polygon";
        const char* fp_blk_end = NULL;
        const char* fp_blk = pcb_find_sexp_block(block, block_len, 0, fp_needle, &fp_blk_end);
        if (!fp_blk) {
            /* try polygon outline */
            const char pg_needle[] = "(polygon";
            fp_blk = pcb_find_sexp_block(block, block_len, 0, pg_needle, &fp_blk_end);
        }
        if (fp_blk) {
            size_t fp_len = (size_t)(fp_blk_end - fp_blk);
            const char xy_needle[] = "(xy ";
            size_t xy_offset = 0;
            while (zone->pt_count < PCB_MAX_POLY_PTS) {
                const char* xy_end = NULL;
                const char* xy = pcb_find_sexp_block(fp_blk, fp_len, xy_offset,
                                                      xy_needle, &xy_end);
                if (!xy) break;
                const char* sv = xy + strlen(xy_needle);
                const char* xy_bend = fp_blk + fp_len;
                char* ep = NULL;
                double px = strtod(sv, &ep);
                if (ep == sv) { xy_offset = (size_t)(xy_end - fp_blk); continue; }
                sv = ep;
                while (sv < xy_bend && isspace((unsigned char)*sv)) sv++;
                double py = strtod(sv, NULL);
                zone->pts_x[zone->pt_count] = px;
                zone->pts_y[zone->pt_count] = py;
                zone->pt_count++;
                xy_offset = (size_t)(xy_end - fp_blk);
            }
        }

        pcb->zone_count++;
        offset = (size_t)(block_end - content);
    }
}

/* ------------------------------------------------------------------ */
/* JSON builders                                                        */
/* ------------------------------------------------------------------ */

static void pcb_json_escape(const char* src, char* dst, size_t dst_size)
{
    size_t di = 0;
    for (size_t i = 0; src[i] && di < dst_size - 2; i++) {
        unsigned char c = (unsigned char)src[i];
        if      (c == '"')  { dst[di++] = '\\'; dst[di++] = '"'; }
        else if (c == '\\') { dst[di++] = '\\'; dst[di++] = '\\'; }
        else if (c == '\n') { dst[di++] = '\\'; dst[di++] = 'n'; }
        else if (c == '\r') { dst[di++] = '\\'; dst[di++] = 'r'; }
        else if (c == '\t') { dst[di++] = '\\'; dst[di++] = 't'; }
        else dst[di++] = (char)c;
    }
    dst[di] = '\0';
}

static char* build_layers_json(const KicadPcb* pcb)
{
    char* buf = (char*)malloc(PCB_JSON_BUF_SIZE);
    if (!buf) return NULL;
    size_t pos = 0;
    char tmp[PCB_MAX_PROP_LEN * 2];

#define JA(fmt, ...) do { \
    int w = snprintf(buf + pos, PCB_JSON_BUF_SIZE - pos, fmt, ##__VA_ARGS__); \
    if (w < 0 || (size_t)w >= PCB_JSON_BUF_SIZE - pos) { free(buf); return NULL; } \
    pos += (size_t)w; \
} while(0)

    JA("[\n");
    for (int i = 0; i < pcb->layer_count; i++) {
        const PcbLayer* l = &pcb->layers[i];
        if (i > 0) JA(",\n");
        pcb_json_escape(l->name, tmp, sizeof(tmp));
        JA("  {\"id\":%d,\"name\":\"%s\",\"color\":\"%s\",\"visible\":%s}",
           l->id, tmp, l->color, l->visible ? "true" : "false");
    }
    JA("\n]\n");
#undef JA
    return buf;
}

static char* build_footprints_json(const KicadPcb* pcb)
{
    char* buf = (char*)malloc(PCB_JSON_BUF_SIZE);
    if (!buf) return NULL;
    size_t pos = 0;
    char tmp[PCB_MAX_PROP_LEN * 2];

#define JB(fmt, ...) do { \
    int w = snprintf(buf + pos, PCB_JSON_BUF_SIZE - pos, fmt, ##__VA_ARGS__); \
    if (w < 0 || (size_t)w >= PCB_JSON_BUF_SIZE - pos) { free(buf); return NULL; } \
    pos += (size_t)w; \
} while(0)

    JB("[\n");
    for (int i = 0; i < pcb->footprint_count; i++) {
        const PcbFootprint* fp = &pcb->footprints[i];
        if (i > 0) JB(",\n");
        char ref[PCB_MAX_PROP_LEN * 2], val[PCB_MAX_PROP_LEN * 2];
        pcb_json_escape(fp->reference, ref, sizeof(ref));
        pcb_json_escape(fp->value,     val, sizeof(val));
        /* Find layer name */
        const char* lname = "F.Cu";
        for (int li = 0; li < pcb->layer_count; li++) {
            if (pcb->layers[li].id == fp->layer_id) { lname = pcb->layers[li].name; break; }
        }
        pcb_json_escape(lname, tmp, sizeof(tmp));
        JB("  {\"reference\":\"%s\",\"value\":\"%s\","
           "\"x\":%g,\"y\":%g,\"angle\":%g,\"layer\":\"%s\"}",
           ref, val, fp->x, fp->y, fp->angle, tmp);
    }
    JB("\n]\n");
#undef JB
    return buf;
}

/* ------------------------------------------------------------------ */
/* SVG renderer                                                         */
/* ------------------------------------------------------------------ */

/*
 * Compute bounding box of all geometry on the given layer (or all layers
 * if layer_id < 0).
 */
static void compute_bbox(const KicadPcb* pcb, int layer_id,
                         double* out_x, double* out_y,
                         double* out_w, double* out_h)
{
    double min_x = 1e18, min_y = 1e18, max_x = -1e18, max_y = -1e18;
    int any = 0;

#define EXPAND(px, py) do { \
    if ((px) < min_x) min_x = (px); if ((px) > max_x) max_x = (px); \
    if ((py) < min_y) min_y = (py); if ((py) > max_y) max_y = (py); \
    any = 1; \
} while(0)

    for (int i = 0; i < pcb->segment_count; i++) {
        const PcbSegment* s = &pcb->segments[i];
        if (layer_id >= 0 && s->layer_id != layer_id) continue;
        EXPAND(s->x1, s->y1); EXPAND(s->x2, s->y2);
    }
    for (int i = 0; i < pcb->via_count; i++) {
        const PcbVia* v = &pcb->vias[i];
        if (layer_id >= 0 && v->layer_from != layer_id && v->layer_to != layer_id) continue;
        EXPAND(v->x, v->y);
    }
    for (int i = 0; i < pcb->footprint_count; i++) {
        const PcbFootprint* fp = &pcb->footprints[i];
        if (layer_id >= 0 && fp->layer_id != layer_id) continue;
        EXPAND(fp->x, fp->y);
        for (int p = 0; p < fp->pad_count; p++) {
            EXPAND(fp->x + fp->pads[p].x, fp->y + fp->pads[p].y);
        }
    }
    for (int i = 0; i < pcb->zone_count; i++) {
        const PcbZone* z = &pcb->zones[i];
        if (layer_id >= 0 && z->layer_id != layer_id) continue;
        for (int p = 0; p < z->pt_count; p++)
            EXPAND(z->pts_x[p], z->pts_y[p]);
    }
#undef EXPAND

    if (!any) { min_x = 0; min_y = 0; max_x = 150; max_y = 100; }

    double margin = 5.0;
    *out_x = min_x - margin;
    *out_y = min_y - margin;
    *out_w = (max_x - min_x) + 2 * margin;
    *out_h = (max_y - min_y) + 2 * margin;
    if (*out_w < 1) *out_w = 150;
    if (*out_h < 1) *out_h = 100;
}

static char* build_layer_svg(const KicadPcb* pcb, int layer_id)
{
    char* buf = (char*)malloc(PCB_SVG_BUF_SIZE);
    if (!buf) return NULL;
    size_t pos = 0;

#define SA(fmt, ...) do { \
    int w = snprintf(buf + pos, PCB_SVG_BUF_SIZE - pos, fmt, ##__VA_ARGS__); \
    if (w < 0 || (size_t)w >= PCB_SVG_BUF_SIZE - pos) { free(buf); return NULL; } \
    pos += (size_t)w; \
} while(0)

    double vx, vy, vw, vh;
    compute_bbox(pcb, layer_id, &vx, &vy, &vw, &vh);

    /* Layer color */
    const char* layer_color = layer_id_to_color(layer_id);

    SA("<svg xmlns=\"http://www.w3.org/2000/svg\"\n");
    SA("     viewBox=\"%g %g %g %g\"\n", vx, vy, vw, vh);
    SA("     style=\"background:#1e1e2e\">\n");

    /* Zones (filled polygons — render first, behind tracks) */
    for (int i = 0; i < pcb->zone_count; i++) {
        const PcbZone* z = &pcb->zones[i];
        if (z->layer_id != layer_id || z->pt_count < 3) continue;
        SA("  <polygon points=\"");
        for (int p = 0; p < z->pt_count; p++) {
            SA("%g,%g ", z->pts_x[p], z->pts_y[p]);
        }
        SA("\" fill=\"%s\" fill-opacity=\"0.25\" stroke=\"%s\" stroke-width=\"0.1\"/>\n",
           layer_color, layer_color);
    }

    /* Segments (tracks) */
    for (int i = 0; i < pcb->segment_count; i++) {
        const PcbSegment* s = &pcb->segments[i];
        if (s->layer_id != layer_id) continue;
        SA("  <line x1=\"%g\" y1=\"%g\" x2=\"%g\" y2=\"%g\""
           " stroke=\"%s\" stroke-width=\"%g\""
           " stroke-linecap=\"round\"/>\n",
           s->x1, s->y1, s->x2, s->y2,
           layer_color, s->width > 0 ? s->width : 0.2);
    }

    /* Vias — shown on both copper layers */
    for (int i = 0; i < pcb->via_count; i++) {
        const PcbVia* v = &pcb->vias[i];
        if (v->layer_from != layer_id && v->layer_to != layer_id) continue;
        double r = v->size / 2.0;
        SA("  <circle cx=\"%g\" cy=\"%g\" r=\"%g\""
           " fill=\"#888888\" stroke=\"#cccccc\" stroke-width=\"0.1\"/>\n",
           v->x, v->y, r);
        /* drill hole */
        SA("  <circle cx=\"%g\" cy=\"%g\" r=\"%g\" fill=\"#1e1e2e\"/>\n",
           v->x, v->y, r * 0.4);
    }

    /* Footprint pads */
    for (int fi = 0; fi < pcb->footprint_count; fi++) {
        const PcbFootprint* fp = &pcb->footprints[fi];
        if (fp->layer_id != layer_id) continue;

        SA("  <g id=\"fp_%d\" class=\"footprint\">\n", fi);
        /* Reference label */
        if (fp->reference[0]) {
            SA("    <text x=\"%g\" y=\"%g\" font-size=\"0.8\""
               " fill=\"#cdd6f4\" text-anchor=\"middle\">%s</text>\n",
               fp->x, fp->y - 1.5, fp->reference);
        }

        for (int pi = 0; pi < fp->pad_count; pi++) {
            const PcbPad* pad = &fp->pads[pi];
            if (pad->layer_id != layer_id) continue;
            double px = fp->x + pad->x;
            double py = fp->y + pad->y;
            double pw = pad->w > 0 ? pad->w : 1.0;
            double ph = pad->h > 0 ? pad->h : 1.0;

            if (strcmp(pad->shape, "circle") == 0 || strcmp(pad->shape, "oval") == 0) {
                SA("    <ellipse cx=\"%g\" cy=\"%g\" rx=\"%g\" ry=\"%g\""
                   " fill=\"%s\" fill-opacity=\"0.85\""
                   " stroke=\"#ffffff\" stroke-width=\"0.05\"/>\n",
                   px, py, pw / 2.0, ph / 2.0, layer_color);
            } else {
                /* rect / roundrect / default */
                SA("    <rect x=\"%g\" y=\"%g\" width=\"%g\" height=\"%g\""
                   " fill=\"%s\" fill-opacity=\"0.85\""
                   " stroke=\"#ffffff\" stroke-width=\"0.05\"/>\n",
                   px - pw / 2.0, py - ph / 2.0, pw, ph, layer_color);
            }
        }
        SA("  </g>\n");
    }

    SA("</svg>\n");
#undef SA
    return buf;
}

/* ------------------------------------------------------------------ */
/* Public API                                                           */
/* ------------------------------------------------------------------ */

kicad_pcb_handle kicad_pcb_open(const char* path)
{
    if (!path) return NULL;

    FILE* f = fopen(path, "rb");
    if (!f) return NULL;

    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    rewind(f);

    if (file_size <= 0) { fclose(f); return NULL; }

    char* content = (char*)malloc((size_t)file_size + 1);
    if (!content) { fclose(f); return NULL; }

    size_t read_bytes = fread(content, 1, (size_t)file_size, f);
    fclose(f);

    if (read_bytes != (size_t)file_size) { free(content); return NULL; }
    content[file_size] = '\0';

    KicadPcb* pcb = (KicadPcb*)calloc(1, sizeof(KicadPcb));
    if (!pcb) { free(content); return NULL; }

    pcb->raw_content = content;
    pcb->raw_len = (size_t)file_size;

    parse_pcb_layers(pcb);
    parse_footprints(pcb);
    parse_segments(pcb);
    parse_vias(pcb);
    parse_zones(pcb);

    return (kicad_pcb_handle)pcb;
}

const char* kicad_pcb_get_layers_json(kicad_pcb_handle h)
{
    if (!h) return NULL;
    KicadPcb* pcb = (KicadPcb*)h;
    if (!pcb->layers_json)
        pcb->layers_json = build_layers_json(pcb);
    return pcb->layers_json;
}

const char* kicad_pcb_get_footprints_json(kicad_pcb_handle h)
{
    if (!h) return NULL;
    KicadPcb* pcb = (KicadPcb*)h;
    if (!pcb->footprints_json)
        pcb->footprints_json = build_footprints_json(pcb);
    return pcb->footprints_json;
}

const char* kicad_pcb_render_layer_svg(kicad_pcb_handle h, int layer_id,
                                       double x, double y,
                                       double w, double h_rect)
{
    (void)x; (void)y; (void)w; (void)h_rect;  /* viewport hint — unused */
    if (!h) return NULL;
    if (layer_id < 0 || layer_id >= PCB_MAX_LAYERS) return NULL;
    KicadPcb* pcb = (KicadPcb*)h;
    if (!pcb->layer_svg[layer_id])
        pcb->layer_svg[layer_id] = build_layer_svg(pcb, layer_id);
    return pcb->layer_svg[layer_id];
}

int kicad_pcb_close(kicad_pcb_handle h)
{
    if (!h) return 0;
    KicadPcb* pcb = (KicadPcb*)h;
    free(pcb->raw_content);
    free(pcb->layers_json);
    free(pcb->footprints_json);
    for (int i = 0; i < PCB_MAX_LAYERS; i++)
        free(pcb->layer_svg[i]);
    free(pcb->drc_cache);
    free(pcb);
    return 0;
}
