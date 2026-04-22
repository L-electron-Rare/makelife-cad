/*
 * bridge_sch.c — standalone KiCad .kicad_sch S-expression parser
 * Pure C11, no external dependencies.
 * Logic ported from gateway/kicad_parser.py.
 */

#include "kicad_bridge.h"
#include "kicad_bridge_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

/* ------------------------------------------------------------------ */
/* Low-level helpers                                                    */
/* ------------------------------------------------------------------ */

/*
 * find_sexp_block — locate a balanced S-expression block starting with prefix.
 * Searches content[start_offset..len) for the first occurrence of prefix,
 * then walks forward tracking parenthesis depth until balanced.
 * Sets *end_out to the character after the closing ')'.
 * Returns pointer to the opening '(' of the block, or NULL.
 */
static const char* find_sexp_block(const char* content, size_t len,
                                   size_t start_offset,
                                   const char* prefix,
                                   const char** end_out)
{
    size_t prefix_len = strlen(prefix);
    if (start_offset >= len) return NULL;

    const char* p = content + start_offset;
    const char* end = content + len;

    while (p < end) {
        /* Find next occurrence of prefix */
        const char* found = (const char*)memmem(p, (size_t)(end - p),
                                                 prefix, prefix_len);
        if (!found) return NULL;

        /* Walk forward balancing parens */
        int depth = 0;
        const char* q = found;
        while (q < end) {
            if (*q == '(') depth++;
            else if (*q == ')') {
                depth--;
                if (depth == 0) {
                    if (end_out) *end_out = q + 1;
                    return found;
                }
            }
            q++;
        }
        /* Unbalanced — skip past prefix and keep looking */
        p = found + prefix_len;
    }
    return NULL;
}

/*
 * extract_quoted — copy the value in (key "value") from block into buf.
 * Finds the first occurrence of 'key' followed by a quoted string.
 * Returns 1 on success, 0 if not found.
 */
static int extract_quoted(const char* block, size_t block_len,
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
        /* Skip whitespace */
        while (after < end && isspace((unsigned char)*after)) after++;
        if (after >= end || *after != '"') {
            p = found + key_len;
            continue;
        }
        /* Copy quoted string */
        after++; /* skip opening " */
        size_t i = 0;
        while (after < end && *after != '"' && i < buf_size - 1) {
            buf[i++] = *after++;
        }
        buf[i] = '\0';
        return 1;
    }
    return 0;
}

/*
 * extract_at — parse "(at x y ...)" from block into *x_out, *y_out.
 * Returns 1 on success, 0 if not found.
 */
static int extract_at(const char* block, size_t block_len,
                      double* x_out, double* y_out)
{
    const char needle[] = "(at ";
    size_t nlen = sizeof(needle) - 1;
    const char* end = block + block_len;
    const char* p = (const char*)memmem(block, block_len, needle, nlen);
    if (!p) return 0;

    p += nlen;
    if (p >= end) return 0;

    char* endptr = NULL;
    double x = strtod(p, &endptr);
    if (endptr == p) return 0;
    p = endptr;
    while (p < end && isspace((unsigned char)*p)) p++;
    double y = strtod(p, &endptr);
    if (endptr == p) return 0;

    *x_out = x;
    *y_out = y;
    return 1;
}

/*
 * strip_lib_symbols — remove the (lib_symbols ...) block from content.
 * Returns heap-allocated cleaned string (caller frees), sets *out_len.
 * Also sets *lib_start and *lib_len to the lib_symbols block location in original.
 */
static char* strip_lib_symbols(const char* content, size_t len, size_t* out_len,
                               const char** lib_start, size_t* lib_len)
{
    const char needle[] = "(lib_symbols";
    size_t nlen = sizeof(needle) - 1;
    const char* found = (const char*)memmem(content, len, needle, nlen);
    if (!found) {
        if (lib_start) *lib_start = NULL;
        if (lib_len)   *lib_len = 0;
        char* copy = (char*)malloc(len + 1);
        if (!copy) return NULL;
        memcpy(copy, content, len);
        copy[len] = '\0';
        *out_len = len;
        return copy;
    }

    /* Walk forward to find balanced close */
    int depth = 0;
    const char* q = found;
    const char* content_end = content + len;
    while (q < content_end) {
        if (*q == '(') depth++;
        else if (*q == ')') {
            depth--;
            if (depth == 0) { q++; break; }
        }
        q++;
    }

    /* Save lib_symbols location for later parsing */
    if (lib_start) *lib_start = found;
    if (lib_len)   *lib_len = (size_t)(q - found);

    /* Build cleaned: before_block + after_block */
    size_t before = (size_t)(found - content);
    size_t after  = (size_t)(content_end - q);
    size_t total  = before + after;
    char* result = (char*)malloc(total + 1);
    if (!result) return NULL;
    memcpy(result, content, before);
    memcpy(result + before, q, after);
    result[total] = '\0';
    *out_len = total;
    return result;
}

/* ------------------------------------------------------------------ */
/* extract_at_full — parse "(at x y [angle])" with optional angle     */
/* ------------------------------------------------------------------ */

static int extract_at_full(const char* block, size_t block_len,
                           double* x_out, double* y_out, double* angle_out)
{
    const char needle[] = "(at ";
    size_t nlen = sizeof(needle) - 1;
    const char* end = block + block_len;
    const char* p = (const char*)memmem(block, block_len, needle, nlen);
    if (!p) return 0;

    p += nlen;
    if (p >= end) return 0;

    char* endptr = NULL;
    double x = strtod(p, &endptr);
    if (endptr == p) return 0;
    p = endptr;
    while (p < end && isspace((unsigned char)*p)) p++;
    double y = strtod(p, &endptr);
    if (endptr == p) return 0;

    *x_out = x;
    *y_out = y;

    /* Try to parse optional angle */
    if (angle_out) {
        p = endptr;
        while (p < end && isspace((unsigned char)*p)) p++;
        if (p < end && *p != ')') {
            double a = strtod(p, &endptr);
            if (endptr != p) *angle_out = a;
            else *angle_out = 0;
        } else {
            *angle_out = 0;
        }
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/* extract_xy — parse "(xy x y)" from block                           */
/* ------------------------------------------------------------------ */

static int extract_xy(const char* block, size_t block_len,
                      const char* prefix, double* x_out, double* y_out)
{
    size_t plen = strlen(prefix);
    const char* end = block + block_len;
    const char* p = (const char*)memmem(block, block_len, prefix, plen);
    if (!p) return 0;

    p += plen;
    while (p < end && isspace((unsigned char)*p)) p++;
    char* ep = NULL;
    *x_out = strtod(p, &ep);
    if (ep == p) return 0;
    p = ep;
    while (p < end && isspace((unsigned char)*p)) p++;
    *y_out = strtod(p, &ep);
    if (ep == p) return 0;
    return 1;
}

/* ------------------------------------------------------------------ */
/* parse_lib_symbols — parse library symbol definitions for geometry   */
/* ------------------------------------------------------------------ */

static void parse_lib_draw_rect(const char* block, size_t block_len,
                                LibSymbol* sym)
{
    if (sym->draw_count >= LIB_MAX_DRAW_ITEMS) return;
    DrawPrimitive* d = &sym->draws[sym->draw_count];
    memset(d, 0, sizeof(*d));
    d->type = DRAW_RECT;
    d->stroke_width = 0.254;
    extract_xy(block, block_len, "(start ", &d->x1, &d->y1);
    extract_xy(block, block_len, "(end ", &d->x2, &d->y2);

    /* Check fill type */
    const char* fill = (const char*)memmem(block, block_len, "(fill ", 6);
    if (fill) {
        if (memmem(fill, (size_t)(block + block_len - fill), "background", 10))
            d->filled = 2;
        else if (memmem(fill, (size_t)(block + block_len - fill), "outline", 7))
            d->filled = 1;
    }

    /* Parse stroke width if specified */
    const char* sw = (const char*)memmem(block, block_len, "(width ", 7);
    if (sw) {
        double w = strtod(sw + 7, NULL);
        if (w > 0) d->stroke_width = w;
    }

    sym->draw_count++;
}

static void parse_lib_draw_circle(const char* block, size_t block_len,
                                  LibSymbol* sym)
{
    if (sym->draw_count >= LIB_MAX_DRAW_ITEMS) return;
    DrawPrimitive* d = &sym->draws[sym->draw_count];
    memset(d, 0, sizeof(*d));
    d->type = DRAW_CIRCLE;
    d->stroke_width = 0.254;

    extract_xy(block, block_len, "(center ", &d->cx, &d->cy);

    const char* rp = (const char*)memmem(block, block_len, "(radius ", 8);
    if (rp) d->r = strtod(rp + 8, NULL);

    const char* fill = (const char*)memmem(block, block_len, "(fill ", 6);
    if (fill) {
        if (memmem(fill, (size_t)(block + block_len - fill), "background", 10))
            d->filled = 2;
        else if (memmem(fill, (size_t)(block + block_len - fill), "outline", 7))
            d->filled = 1;
    }

    const char* sw = (const char*)memmem(block, block_len, "(width ", 7);
    if (sw) {
        double w = strtod(sw + 7, NULL);
        if (w > 0) d->stroke_width = w;
    }

    sym->draw_count++;
}

static void parse_lib_draw_polyline(const char* block, size_t block_len,
                                    LibSymbol* sym)
{
    if (sym->draw_count >= LIB_MAX_DRAW_ITEMS) return;
    DrawPrimitive* d = &sym->draws[sym->draw_count];
    memset(d, 0, sizeof(*d));
    d->type = DRAW_POLYLINE;
    d->stroke_width = 0.254;

    /* Parse all (xy x y) within (pts ...) */
    const char* pts = (const char*)memmem(block, block_len, "(pts ", 5);
    if (pts) {
        const char* end = block + block_len;
        const char* p = pts + 5;
        while (p < end && d->pt_count < LIB_MAX_POLY_POINTS) {
            const char* xy = (const char*)memmem(p, (size_t)(end - p), "(xy ", 4);
            if (!xy) break;
            const char* after_xy = xy + 4;
            char* ep = NULL;
            double x = strtod(after_xy, &ep);
            if (ep == after_xy) break;
            double y = strtod(ep, &ep);
            d->pts_x[d->pt_count] = x;
            d->pts_y[d->pt_count] = y;
            d->pt_count++;
            p = ep;
        }
    }

    const char* fill = (const char*)memmem(block, block_len, "(fill ", 6);
    if (fill) {
        if (memmem(fill, (size_t)(block + block_len - fill), "background", 10))
            d->filled = 2;
        else if (memmem(fill, (size_t)(block + block_len - fill), "outline", 7))
            d->filled = 1;
    }

    const char* sw = (const char*)memmem(block, block_len, "(width ", 7);
    if (sw) {
        double w = strtod(sw + 7, NULL);
        if (w > 0) d->stroke_width = w;
    }

    sym->draw_count++;
}

static void parse_lib_draw_arc(const char* block, size_t block_len,
                               LibSymbol* sym)
{
    if (sym->draw_count >= LIB_MAX_DRAW_ITEMS) return;
    DrawPrimitive* d = &sym->draws[sym->draw_count];
    memset(d, 0, sizeof(*d));
    d->type = DRAW_ARC;
    d->stroke_width = 0.254;

    /* KiCad arcs: (start x y) (mid x y) (end x y) */
    double sx = 0, sy = 0, mx = 0, my = 0, ex = 0, ey = 0;
    extract_xy(block, block_len, "(start ", &sx, &sy);
    extract_xy(block, block_len, "(mid ", &mx, &my);
    extract_xy(block, block_len, "(end ", &ex, &ey);

    /* Compute arc center from 3 points using perpendicular bisectors */
    double ax = sx, ay = sy, bx = mx, by = my, cx2 = ex, cy2 = ey;
    double D = 2 * (ax * (by - cy2) + bx * (cy2 - ay) + cx2 * (ay - by));
    if (fabs(D) < 1e-10) {
        /* Degenerate — just store as polyline-like */
        d->pts_x[0] = sx; d->pts_y[0] = sy;
        d->pts_x[1] = mx; d->pts_y[1] = my;
        d->pts_x[2] = ex; d->pts_y[2] = ey;
        d->pt_count = 3;
        d->type = DRAW_POLYLINE;
        sym->draw_count++;
        return;
    }
    double ux = ((ax*ax + ay*ay) * (by - cy2) + (bx*bx + by*by) * (cy2 - ay) +
                 (cx2*cx2 + cy2*cy2) * (ay - by)) / D;
    double uy = ((ax*ax + ay*ay) * (cx2 - bx) + (bx*bx + by*by) * (ax - cx2) +
                 (cx2*cx2 + cy2*cy2) * (bx - ax)) / D;
    d->cx = ux;
    d->cy = uy;
    d->r = sqrt((sx - ux) * (sx - ux) + (sy - uy) * (sy - uy));

    /* Compute angles */
    d->start_angle = atan2(sy - uy, sx - ux) * 180.0 / M_PI;
    d->end_angle   = atan2(ey - uy, ex - ux) * 180.0 / M_PI;

    /* Store start/end points for fallback rendering */
    d->x1 = sx; d->y1 = sy;
    d->x2 = ex; d->y2 = ey;

    const char* sw = (const char*)memmem(block, block_len, "(width ", 7);
    if (sw) {
        double w = strtod(sw + 7, NULL);
        if (w > 0) d->stroke_width = w;
    }

    sym->draw_count++;
}

static void parse_lib_pin(const char* block, size_t block_len,
                          LibSymbol* sym)
{
    if (sym->pin_count >= LIB_MAX_LIB_PINS) return;
    LibPin* pin = &sym->pins[sym->pin_count];
    memset(pin, 0, sizeof(*pin));

    /* (pin type style (at x y angle) (length len)
     *   (name "name" ...) (number "number" ...)) */
    double angle = 0;
    extract_at_full(block, block_len, &pin->x, &pin->y, &angle);
    pin->angle = angle;

    const char* lp = (const char*)memmem(block, block_len, "(length ", 8);
    if (lp) pin->length = strtod(lp + 8, NULL);

    extract_quoted(block, block_len, "(name \"", pin->name, sizeof(pin->name));
    extract_quoted(block, block_len, "(number \"", pin->number, sizeof(pin->number));

    sym->pin_count++;
}

static void parse_single_lib_symbol(const char* block, size_t block_len,
                                    LibSymbol* sym)
{
    /* Parse sub-symbol drawing primitives */
    const char* end = block + block_len;

    /* Rectangles */
    {
        size_t off = 0;
        while (1) {
            const char* be = NULL;
            const char* b = find_sexp_block(block, block_len, off, "(rectangle ", &be);
            if (!b) break;
            parse_lib_draw_rect(b, (size_t)(be - b), sym);
            off = (size_t)(be - block);
        }
    }

    /* Circles */
    {
        size_t off = 0;
        while (1) {
            const char* be = NULL;
            const char* b = find_sexp_block(block, block_len, off, "(circle ", &be);
            if (!b) break;
            parse_lib_draw_circle(b, (size_t)(be - b), sym);
            off = (size_t)(be - block);
        }
    }

    /* Polylines */
    {
        size_t off = 0;
        while (1) {
            const char* be = NULL;
            const char* b = find_sexp_block(block, block_len, off, "(polyline", &be);
            if (!b) break;
            parse_lib_draw_polyline(b, (size_t)(be - b), sym);
            off = (size_t)(be - block);
        }
    }

    /* Arcs */
    {
        size_t off = 0;
        while (1) {
            const char* be = NULL;
            const char* b = find_sexp_block(block, block_len, off, "(arc ", &be);
            if (!b) break;
            parse_lib_draw_arc(b, (size_t)(be - b), sym);
            off = (size_t)(be - block);
        }
    }

    /* Pins */
    {
        size_t off = 0;
        while (1) {
            const char* be = NULL;
            const char* b = find_sexp_block(block, block_len, off, "(pin ", &be);
            if (!b) break;
            /* Make sure it's a pin definition, not "(pin_names" or "(pin_numbers" */
            const char* after = b + 4;
            if (after < end && (*after == '_' || *after == 's')) {
                off = (size_t)(be - block);
                continue;
            }
            parse_lib_pin(b, (size_t)(be - b), sym);
            off = (size_t)(be - block);
        }
    }

    /* Pin name offset */
    const char* pno = (const char*)memmem(block, block_len, "(pin_names ", 11);
    if (pno) {
        const char* off_p = (const char*)memmem(pno, (size_t)(end - pno), "(offset ", 8);
        if (off_p) sym->pin_name_offset = strtod(off_p + 8, NULL);
    }

    /* Hide pin names/numbers */
    if (memmem(block, block_len, "(pin_names hide)", 16))
        sym->hide_pin_names = 1;
    if (memmem(block, block_len, "(pin_numbers hide)", 18))
        sym->hide_pin_numbers = 1;
}

static void parse_lib_symbols(KicadSch* sch, const char* lib_block, size_t lib_len)
{
    if (!lib_block || lib_len == 0) return;

    /* Allocate on heap to avoid stack overflow */
    sch->lib_symbols = (LibSymbol*)calloc(LIB_MAX_SYMBOLS, sizeof(LibSymbol));
    if (!sch->lib_symbols) return;

    /* Find top-level (symbol "Name" ...) blocks inside lib_symbols */
    size_t offset = 0;
    while (sch->lib_symbol_count < LIB_MAX_SYMBOLS) {
        const char* be = NULL;
        const char* b = find_sexp_block(lib_block, lib_len, offset, "(symbol \"", &be);
        if (!b) break;
        size_t blen = (size_t)(be - b);

        LibSymbol* sym = &sch->lib_symbols[sch->lib_symbol_count];
        memset(sym, 0, sizeof(*sym));

        /* Extract symbol name */
        const char* p = b + 9; /* after (symbol " */
        size_t i = 0;
        while (p < be && *p != '"' && i < KICAD_MAX_PROP_LEN - 1)
            sym->name[i++] = *p++;
        sym->name[i] = '\0';

        /* Parse all sub-symbols (e.g. "R_0_1", "R_1_1") which contain the geometry */
        /* The top-level symbol block also contains primitives directly in some cases */
        parse_single_lib_symbol(b, blen, sym);

        sch->lib_symbol_count++;
        offset = (size_t)(be - lib_block);
    }
}

/* Find a library symbol by lib_id. Returns NULL if not found. */
static const LibSymbol* find_lib_symbol(const KicadSch* sch, const char* lib_id)
{
    for (int i = 0; i < sch->lib_symbol_count; i++) {
        if (strcmp(sch->lib_symbols[i].name, lib_id) == 0)
            return &sch->lib_symbols[i];
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Parse junctions and no-connect markers                              */
/* ------------------------------------------------------------------ */

static void parse_junctions(KicadSch* sch)
{
    const char* content = sch->cleaned_content;
    size_t len = sch->cleaned_len;
    size_t offset = 0;

    while (sch->junction_count < KICAD_MAX_JUNCTIONS) {
        const char* be = NULL;
        const char* b = find_sexp_block(content, len, offset, "(junction ", &be);
        if (!b) break;
        size_t blen = (size_t)(be - b);
        KicadJunction* j = &sch->junctions[sch->junction_count];
        if (extract_at(b, blen, &j->x, &j->y))
            sch->junction_count++;
        offset = (size_t)(be - content);
    }
}

static void parse_noconnects(KicadSch* sch)
{
    const char* content = sch->cleaned_content;
    size_t len = sch->cleaned_len;
    size_t offset = 0;

    while (sch->noconnect_count < KICAD_MAX_NOCONNECTS) {
        const char* be = NULL;
        const char* b = find_sexp_block(content, len, offset, "(no_connect ", &be);
        if (!b) break;
        size_t blen = (size_t)(be - b);
        KicadNoConnect* nc = &sch->noconnects[sch->noconnect_count];
        if (extract_at(b, blen, &nc->x, &nc->y))
            sch->noconnect_count++;
        offset = (size_t)(be - content);
    }
}

/* ------------------------------------------------------------------ */
/* Parse buses                                                          */
/* ------------------------------------------------------------------ */

static void parse_buses(KicadSch* sch)
{
    const char* content = sch->cleaned_content;
    size_t len = sch->cleaned_len;
    size_t offset = 0;

    while (sch->bus_count < KICAD_MAX_BUSES) {
        const char* be = NULL;
        const char* b = find_sexp_block(content, len, offset, "(bus ", &be);
        if (!b) break;
        size_t blen = (size_t)(be - b);

        /* Skip "(bus_alias" and "(bus_entry" */
        if (b[4] == '_') {
            offset = (size_t)(be - content);
            continue;
        }

        KicadBus* bus = &sch->buses[sch->bus_count];
        /* Extract (pts (xy x1 y1) (xy x2 y2)) — same as wire */
        const char* pts = (const char*)memmem(b, blen, "(pts ", 5);
        if (pts) {
            size_t pts_len = (size_t)(be - pts);
            const char* xy1 = (const char*)memmem(pts, pts_len, "(xy ", 4);
            if (xy1) {
                const char* p = xy1 + 4;
                char* ep = NULL;
                bus->x1 = strtod(p, &ep);
                if (ep != p) { p = ep; while (*p == ' ') p++; bus->y1 = strtod(p, NULL); }
                size_t rem = (size_t)(be - (xy1 + 4));
                const char* xy2 = (const char*)memmem(xy1 + 4, rem, "(xy ", 4);
                if (xy2) {
                    p = xy2 + 4;
                    bus->x2 = strtod(p, &ep);
                    if (ep != p) { p = ep; while (*p == ' ') p++; bus->y2 = strtod(p, NULL); }
                    sch->bus_count++;
                }
            }
        }
        offset = (size_t)(be - content);
    }
}

/* ------------------------------------------------------------------ */
/* Parse hierarchical sheets                                            */
/* ------------------------------------------------------------------ */

static void parse_sheets(KicadSch* sch)
{
    const char* content = sch->cleaned_content;
    size_t len = sch->cleaned_len;
    size_t offset = 0;

    while (sch->sheet_count < KICAD_MAX_SHEETS) {
        const char* be = NULL;
        const char* b = find_sexp_block(content, len, offset, "(sheet ", &be);
        if (!b) break;
        size_t blen = (size_t)(be - b);
        KicadSheet* sheet = &sch->sheets[sch->sheet_count];
        memset(sheet, 0, sizeof(*sheet));

        extract_at(b, blen, &sheet->x, &sheet->y);

        /* (size w h) */
        const char* sz = (const char*)memmem(b, blen, "(size ", 6);
        if (sz) {
            char* ep = NULL;
            sheet->w = strtod(sz + 6, &ep);
            if (ep) sheet->h = strtod(ep, NULL);
        }

        /* Sheet name: (property "Sheetname" "value" ...) */
        extract_quoted(b, blen, "(property \"Sheetname\" \"", sheet->name, KICAD_MAX_PROP_LEN);
        if (!sheet->name[0])
            extract_quoted(b, blen, "(property \"Sheet name\" \"", sheet->name, KICAD_MAX_PROP_LEN);

        /* Sheet file: (property "Sheetfile" "value" ...) */
        extract_quoted(b, blen, "(property \"Sheetfile\" \"", sheet->filename, KICAD_MAX_PROP_LEN);
        if (!sheet->filename[0])
            extract_quoted(b, blen, "(property \"Sheet file\" \"", sheet->filename, KICAD_MAX_PROP_LEN);

        sch->sheet_count++;
        offset = (size_t)(be - content);
    }
}

/* ------------------------------------------------------------------ */
/* Parse title block and paper size                                     */
/* ------------------------------------------------------------------ */

static void parse_title_block(KicadSch* sch)
{
    const char* content = sch->raw_content;
    size_t len = sch->raw_len;

    /* Paper size: (paper "A4") */
    {
        const char* p = (const char*)memmem(content, len, "(paper \"", 8);
        if (p) {
            p += 8;
            size_t i = 0;
            while (p[i] && p[i] != '"' && i < 15)
                sch->paper.name[i] = p[i], i++;
            sch->paper.name[i] = '\0';
            /* Common paper sizes in mils */
            if (strcmp(sch->paper.name, "A4") == 0)      { sch->paper.w = 297; sch->paper.h = 210; }
            else if (strcmp(sch->paper.name, "A3") == 0)  { sch->paper.w = 420; sch->paper.h = 297; }
            else if (strcmp(sch->paper.name, "A2") == 0)  { sch->paper.w = 594; sch->paper.h = 420; }
            else if (strcmp(sch->paper.name, "A1") == 0)  { sch->paper.w = 841; sch->paper.h = 594; }
            else if (strcmp(sch->paper.name, "Letter") == 0) { sch->paper.w = 279.4; sch->paper.h = 215.9; }
            else { sch->paper.w = 297; sch->paper.h = 210; } /* default A4 */
        }
    }

    /* Title block */
    const char* be = NULL;
    const char* tb = find_sexp_block(content, len, 0, "(title_block", &be);
    if (!tb) return;
    size_t tblen = (size_t)(be - tb);

    sch->has_title_block = 1;
    extract_quoted(tb, tblen, "(title \"", sch->title_block.title, KICAD_MAX_PROP_LEN);
    extract_quoted(tb, tblen, "(date \"", sch->title_block.date, 64);
    extract_quoted(tb, tblen, "(rev \"", sch->title_block.rev, 64);
    extract_quoted(tb, tblen, "(company \"", sch->title_block.company, KICAD_MAX_PROP_LEN);
}

/* ------------------------------------------------------------------ */
/* Parse standalone text annotations                                    */
/* ------------------------------------------------------------------ */

static void parse_texts(KicadSch* sch)
{
    const char* content = sch->cleaned_content;
    size_t len = sch->cleaned_len;
    size_t offset = 0;

    while (sch->text_count < KICAD_MAX_TEXTS) {
        const char* be = NULL;
        const char* b = find_sexp_block(content, len, offset, "(text \"", &be);
        if (!b) break;
        size_t blen = (size_t)(be - b);
        KicadText* txt = &sch->texts[sch->text_count];
        memset(txt, 0, sizeof(*txt));

        /* Extract text content */
        const char* p = b + 6;  /* after (text " */
        if (*p == '"') p++; /* skip opening quote */
        size_t i = 0;
        while (p < be && *p != '"' && i < KICAD_MAX_PROP_LEN - 1)
            txt->text[i++] = *p++;
        txt->text[i] = '\0';

        extract_at_full(b, blen, &txt->x, &txt->y, &txt->angle);

        /* Font size: (effects (font (size h w))) */
        txt->font_size = 1.27; /* default KiCad text size */
        const char* fs = (const char*)memmem(b, blen, "(size ", 6);
        if (fs) {
            double sz = strtod(fs + 6, NULL);
            if (sz > 0) txt->font_size = sz;
        }

        sch->text_count++;
        offset = (size_t)(be - content);
    }
}

/* ------------------------------------------------------------------ */
/* Parse top-level graphics (rectangle, polyline, circle, arc)          */
/* ------------------------------------------------------------------ */

static void parse_top_graphics(KicadSch* sch)
{
    const char* content = sch->cleaned_content;
    size_t len = sch->cleaned_len;

    /* Top-level rectangles */
    {
        size_t offset = 0;
        while (sch->graphic_count < KICAD_MAX_GFX) {
            const char* be = NULL;
            const char* b = find_sexp_block(content, len, offset, "(rectangle ", &be);
            if (!b) break;
            size_t blen = (size_t)(be - b);
            KicadGraphic* g = &sch->graphics[sch->graphic_count];
            memset(g, 0, sizeof(*g));
            g->type = DRAW_RECT;
            g->stroke_width = 0.254;
            extract_xy(b, blen, "(start ", &g->x1, &g->y1);
            extract_xy(b, blen, "(end ", &g->x2, &g->y2);
            const char* sw = (const char*)memmem(b, blen, "(width ", 7);
            if (sw) { double w = strtod(sw + 7, NULL); if (w > 0) g->stroke_width = w; }
            const char* fill = (const char*)memmem(b, blen, "(fill ", 6);
            if (fill && memmem(fill, (size_t)(be - fill), "background", 10)) g->filled = 2;
            sch->graphic_count++;
            offset = (size_t)(be - content);
        }
    }

    /* Top-level polylines */
    {
        size_t offset = 0;
        while (sch->graphic_count < KICAD_MAX_GFX) {
            const char* be = NULL;
            const char* b = find_sexp_block(content, len, offset, "(polyline", &be);
            if (!b) break;
            size_t blen = (size_t)(be - b);
            KicadGraphic* g = &sch->graphics[sch->graphic_count];
            memset(g, 0, sizeof(*g));
            g->type = DRAW_POLYLINE;
            g->stroke_width = 0.254;

            const char* pts = (const char*)memmem(b, blen, "(pts ", 5);
            if (pts) {
                const char* pe = b + blen;
                const char* p = pts + 5;
                while (p < pe && g->pt_count < LIB_MAX_POLY_POINTS) {
                    const char* xy = (const char*)memmem(p, (size_t)(pe - p), "(xy ", 4);
                    if (!xy) break;
                    char* ep = NULL;
                    double x = strtod(xy + 4, &ep);
                    if (ep == xy + 4) break;
                    double y = strtod(ep, &ep);
                    g->pts_x[g->pt_count] = x;
                    g->pts_y[g->pt_count] = y;
                    g->pt_count++;
                    p = ep;
                }
            }

            const char* sw = (const char*)memmem(b, blen, "(width ", 7);
            if (sw) { double w = strtod(sw + 7, NULL); if (w > 0) g->stroke_width = w; }
            sch->graphic_count++;
            offset = (size_t)(be - content);
        }
    }

    /* Top-level circles */
    {
        size_t offset = 0;
        while (sch->graphic_count < KICAD_MAX_GFX) {
            const char* be = NULL;
            const char* b = find_sexp_block(content, len, offset, "(circle ", &be);
            if (!b) break;
            size_t blen = (size_t)(be - b);
            KicadGraphic* g = &sch->graphics[sch->graphic_count];
            memset(g, 0, sizeof(*g));
            g->type = DRAW_CIRCLE;
            g->stroke_width = 0.254;
            extract_xy(b, blen, "(center ", &g->cx, &g->cy);
            const char* rp = (const char*)memmem(b, blen, "(radius ", 8);
            if (rp) g->r = strtod(rp + 8, NULL);
            const char* sw = (const char*)memmem(b, blen, "(width ", 7);
            if (sw) { double w = strtod(sw + 7, NULL); if (w > 0) g->stroke_width = w; }
            sch->graphic_count++;
            offset = (size_t)(be - content);
        }
    }
}

/* ------------------------------------------------------------------ */
/* Parsing passes                                                       */
/* ------------------------------------------------------------------ */

static void parse_symbols(KicadSch* sch)
{
    const char* content = sch->cleaned_content;
    size_t len = sch->cleaned_len;
    const char prefix[] = "(symbol ";
    size_t offset = 0;

    while (sch->component_count < KICAD_MAX_COMPONENTS) {
        const char* block_end = NULL;
        const char* block = find_sexp_block(content, len, offset, prefix, &block_end);
        if (!block) break;

        size_t block_len = (size_t)(block_end - block);

        /* Must have a lib_id to be an instance (not a lib definition) */
        char lib_id[KICAD_MAX_PROP_LEN] = {0};
        if (!extract_quoted(block, block_len, "(lib_id \"", lib_id, sizeof(lib_id))) {
            offset = (size_t)(block_end - content);
            continue;
        }
        if (lib_id[0] == '\0') {
            offset = (size_t)(block_end - content);
            continue;
        }

        KicadComponent* comp = &sch->components[sch->component_count];
        memset(comp, 0, sizeof(*comp));
        strncpy(comp->lib_id, lib_id, KICAD_MAX_PROP_LEN - 1);

        extract_quoted(block, block_len, "(property \"Reference\" \"", comp->reference, KICAD_MAX_PROP_LEN);
        extract_quoted(block, block_len, "(property \"Value\" \"",     comp->value,     KICAD_MAX_PROP_LEN);
        extract_quoted(block, block_len, "(property \"Footprint\" \"", comp->footprint, KICAD_MAX_PROP_LEN);
        extract_at_full(block, block_len, &comp->x, &comp->y, &comp->angle);

        /* Check for mirror: (mirror x) or (mirror y) or (mirror xy) */
        const char* mir = (const char*)memmem(block, block_len, "(mirror ", 8);
        if (mir) {
            const char* mir_end = block + block_len;
            const char* mp = mir + 8;
            while (mp < mir_end && *mp != ')') {
                if (*mp == 'x') comp->mirror_x = 1;
                if (*mp == 'y') comp->mirror_y = 1;
                mp++;
            }
        }

        /* Extract pins: (pin "number" ...) */
        const char pin_prefix[] = "(pin \"";
        size_t pin_offset = 0;
        comp->pin_count = 0;
        while (comp->pin_count < KICAD_MAX_PINS) {
            const char* pin_end = NULL;
            const char* pin = find_sexp_block(block, block_len, pin_offset, pin_prefix, &pin_end);
            if (!pin) break;
            /* Extract pin number (first quoted string) */
            const char* q = pin + strlen(pin_prefix);
            const char* block_finish = block + block_len;
            size_t i = 0;
            while (q < block_finish && *q != '"' && i < 15) {
                comp->pins[comp->pin_count][i++] = *q++;
            }
            comp->pins[comp->pin_count][i] = '\0';
            if (i > 0) comp->pin_count++;
            pin_offset = (size_t)(pin_end - block);
        }

        sch->component_count++;
        offset = (size_t)(block_end - content);
    }
}

static void parse_wires(KicadSch* sch)
{
    const char* content = sch->cleaned_content;
    size_t len = sch->cleaned_len;
    const char prefix[] = "(wire ";
    size_t offset = 0;

    while (sch->wire_count < KICAD_MAX_WIRES) {
        const char* block_end = NULL;
        const char* block = find_sexp_block(content, len, offset, prefix, &block_end);
        if (!block) break;

        size_t block_len = (size_t)(block_end - block);
        KicadWire* wire = &sch->wires[sch->wire_count];

        /* Extract (pts (xy x1 y1) (xy x2 y2)) */
        const char pts_needle[] = "(pts ";
        const char* pts = (const char*)memmem(block, block_len, pts_needle, strlen(pts_needle));
        if (pts) {
            const char xy_needle[] = "(xy ";
            size_t pts_len = (size_t)(block_end - pts);
            /* First xy */
            const char* xy1 = (const char*)memmem(pts, pts_len, xy_needle, strlen(xy_needle));
            if (xy1) {
                const char* p = xy1 + strlen(xy_needle);
                char* ep = NULL;
                wire->x1 = strtod(p, &ep);
                if (ep != p) { p = ep; while (isspace((unsigned char)*p)) p++; wire->y1 = strtod(p, NULL); }
                /* Second xy */
                size_t remaining = (size_t)(block_end - (xy1 + strlen(xy_needle)));
                const char* xy2 = (const char*)memmem(xy1 + strlen(xy_needle), remaining,
                                                        xy_needle, strlen(xy_needle));
                if (xy2) {
                    p = xy2 + strlen(xy_needle);
                    ep = NULL;
                    wire->x2 = strtod(p, &ep);
                    if (ep != p) { p = ep; while (isspace((unsigned char)*p)) p++; wire->y2 = strtod(p, NULL); }
                    sch->wire_count++;
                }
            }
        }
        offset = (size_t)(block_end - content);
    }
}

static void parse_labels(KicadSch* sch)
{
    const char* content = sch->cleaned_content;
    size_t len = sch->cleaned_len;

    /* Regular labels: (label "text" (at x y ...)) */
    {
        const char prefix[] = "(label \"";
        size_t offset = 0;
        while (sch->label_count < KICAD_MAX_LABELS) {
            const char* block_end = NULL;
            const char* block = find_sexp_block(content, len, offset, prefix, &block_end);
            if (!block) break;
            size_t block_len = (size_t)(block_end - block);
            KicadLabel* lbl = &sch->labels[sch->label_count];
            memset(lbl, 0, sizeof(*lbl));
            /* Extract label text (first quoted string after "(label ") */
            const char* p = block + strlen("(label \"");
            const char* bend = block + block_len;
            size_t i = 0;
            while (p < bend && *p != '"' && i < KICAD_MAX_PROP_LEN - 1) lbl->text[i++] = *p++;
            lbl->text[i] = '\0';
            lbl->is_global = 0;
            extract_at(block, block_len, &lbl->x, &lbl->y);
            sch->label_count++;
            offset = (size_t)(block_end - content);
        }
    }

    /* Global labels: (global_label "text" ...) */
    {
        const char prefix[] = "(global_label \"";
        size_t offset = 0;
        while (sch->label_count < KICAD_MAX_LABELS) {
            const char* block_end = NULL;
            const char* block = find_sexp_block(content, len, offset, prefix, &block_end);
            if (!block) break;
            size_t block_len = (size_t)(block_end - block);
            KicadLabel* lbl = &sch->labels[sch->label_count];
            memset(lbl, 0, sizeof(*lbl));
            const char* p = block + strlen("(global_label \"");
            const char* bend = block + block_len;
            size_t i = 0;
            while (p < bend && *p != '"' && i < KICAD_MAX_PROP_LEN - 1) lbl->text[i++] = *p++;
            lbl->text[i] = '\0';
            lbl->is_global = 1;
            extract_at(block, block_len, &lbl->x, &lbl->y);
            sch->label_count++;
            offset = (size_t)(block_end - content);
        }
    }
}

/* ------------------------------------------------------------------ */
/* JSON builder                                                         */
/* ------------------------------------------------------------------ */

static void json_escape(const char* src, char* dst, size_t dst_size)
{
    size_t di = 0;
    for (size_t i = 0; src[i] && di < dst_size - 2; i++) {
        unsigned char c = (unsigned char)src[i];
        if (c == '"')  { dst[di++] = '\\'; dst[di++] = '"'; }
        else if (c == '\\') { dst[di++] = '\\'; dst[di++] = '\\'; }
        else if (c == '\n') { dst[di++] = '\\'; dst[di++] = 'n'; }
        else if (c == '\r') { dst[di++] = '\\'; dst[di++] = 'r'; }
        else if (c == '\t') { dst[di++] = '\\'; dst[di++] = 't'; }
        else dst[di++] = (char)c;
    }
    dst[di] = '\0';
}

static char* build_components_json(const KicadSch* sch)
{
    char* buf = (char*)malloc(KICAD_JSON_BUF_SIZE);
    if (!buf) return NULL;

    size_t pos = 0;
    char tmp[KICAD_MAX_PROP_LEN * 2];

#define JAPPEND(fmt, ...) do { \
    int written = snprintf(buf + pos, KICAD_JSON_BUF_SIZE - pos, fmt, ##__VA_ARGS__); \
    if (written < 0 || (size_t)written >= KICAD_JSON_BUF_SIZE - pos) { free(buf); return NULL; } \
    pos += (size_t)written; \
} while (0)

    JAPPEND("[\n");

    for (int i = 0; i < sch->component_count; i++) {
        const KicadComponent* c = &sch->components[i];
        if (i > 0) JAPPEND(",\n");

        JAPPEND("  {\n");
        json_escape(c->reference, tmp, sizeof(tmp));
        JAPPEND("    \"reference\": \"%s\",\n", tmp);
        json_escape(c->value, tmp, sizeof(tmp));
        JAPPEND("    \"value\": \"%s\",\n", tmp);
        json_escape(c->footprint, tmp, sizeof(tmp));
        JAPPEND("    \"footprint\": \"%s\",\n", tmp);
        json_escape(c->lib_id, tmp, sizeof(tmp));
        JAPPEND("    \"lib_id\": \"%s\",\n", tmp);
        JAPPEND("    \"pins\": [");
        for (int p = 0; p < c->pin_count; p++) {
            if (p > 0) JAPPEND(", ");
            json_escape(c->pins[p], tmp, sizeof(tmp));
            JAPPEND("\"%s\"", tmp);
        }
        JAPPEND("],\n");
        JAPPEND("    \"x\": %g,\n", c->x);
        JAPPEND("    \"y\": %g\n", c->y);
        JAPPEND("  }");
    }

    JAPPEND("\n]\n");
#undef JAPPEND

    return buf;
}

/* ------------------------------------------------------------------ */
/* SVG renderer                                                         */
/* ------------------------------------------------------------------ */

/* ------------------------------------------------------------------ */
/* SVG helper: transform a point by component placement                */
/* ------------------------------------------------------------------ */

static void transform_point(double lx, double ly,
                            double cx, double cy,
                            double angle, int mirror_x, int mirror_y,
                            double* ox, double* oy)
{
    double px = lx, py = ly;

    /* Mirror first (before rotation) */
    if (mirror_x) px = -px;
    if (mirror_y) py = -py;

    /* Rotate (KiCad uses clockwise degrees in screen coords) */
    if (angle != 0) {
        double rad = -angle * M_PI / 180.0;
        double c = cos(rad), s = sin(rad);
        double rx = px * c - py * s;
        double ry = px * s + py * c;
        px = rx;
        py = ry;
    }

    *ox = cx + px;
    *oy = cy + py;
}

/* ------------------------------------------------------------------ */
/* SVG renderer — full symbol geometry                                 */
/* ------------------------------------------------------------------ */

static char* build_svg(const KicadSch* sch)
{
    char* buf = (char*)malloc(KICAD_SVG_BUF_SIZE);
    if (!buf) return NULL;
    size_t pos = 0;

#define SAPPEND(fmt, ...) do { \
    int written = snprintf(buf + pos, KICAD_SVG_BUF_SIZE - pos, fmt, ##__VA_ARGS__); \
    if (written < 0 || (size_t)written >= KICAD_SVG_BUF_SIZE - pos) { free(buf); return NULL; } \
    pos += (size_t)written; \
} while (0)

    /* ---- Compute bounding box ---- */
    double min_x = 1e9, min_y = 1e9, max_x = -1e9, max_y = -1e9;
    int has_pts = 0;

#define BBOX_UPDATE(px, py) do { \
    double _x = (px), _y = (py); \
    if (!has_pts) { min_x = max_x = _x; min_y = max_y = _y; has_pts = 1; } \
    else { if (_x < min_x) min_x = _x; if (_x > max_x) max_x = _x; \
           if (_y < min_y) min_y = _y; if (_y > max_y) max_y = _y; } \
} while(0)

    for (int i = 0; i < sch->component_count; i++) {
        const KicadComponent* c = &sch->components[i];
        BBOX_UPDATE(c->x, c->y);
        /* Extend bbox by symbol geometry */
        const LibSymbol* sym = find_lib_symbol(sch, c->lib_id);
        if (sym) {
            for (int d = 0; d < sym->draw_count; d++) {
                const DrawPrimitive* dp = &sym->draws[d];
                switch (dp->type) {
                case DRAW_RECT: {
                    double ox, oy;
                    transform_point(dp->x1, dp->y1, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox, &oy);
                    BBOX_UPDATE(ox, oy);
                    transform_point(dp->x2, dp->y2, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox, &oy);
                    BBOX_UPDATE(ox, oy);
                    break;
                }
                case DRAW_CIRCLE:
                    BBOX_UPDATE(c->x + dp->cx - dp->r, c->y + dp->cy - dp->r);
                    BBOX_UPDATE(c->x + dp->cx + dp->r, c->y + dp->cy + dp->r);
                    break;
                case DRAW_POLYLINE:
                    for (int p = 0; p < dp->pt_count; p++) {
                        double ox, oy;
                        transform_point(dp->pts_x[p], dp->pts_y[p], c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox, &oy);
                        BBOX_UPDATE(ox, oy);
                    }
                    break;
                case DRAW_ARC:
                    BBOX_UPDATE(c->x + dp->cx - dp->r, c->y + dp->cy - dp->r);
                    BBOX_UPDATE(c->x + dp->cx + dp->r, c->y + dp->cy + dp->r);
                    break;
                }
            }
            for (int p = 0; p < sym->pin_count; p++) {
                double ox, oy, ox2, oy2;
                const LibPin* pin = &sym->pins[p];
                transform_point(pin->x, pin->y, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox, &oy);
                /* Pin endpoint */
                double pex = pin->x, pey = pin->y;
                double pin_rad = pin->angle * M_PI / 180.0;
                pex += pin->length * cos(pin_rad);
                pey -= pin->length * sin(pin_rad);
                transform_point(pex, pey, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox2, &oy2);
                BBOX_UPDATE(ox, oy);
                BBOX_UPDATE(ox2, oy2);
            }
        }
    }
    for (int i = 0; i < sch->wire_count; i++) {
        BBOX_UPDATE(sch->wires[i].x1, sch->wires[i].y1);
        BBOX_UPDATE(sch->wires[i].x2, sch->wires[i].y2);
    }
    for (int i = 0; i < sch->label_count; i++) {
        BBOX_UPDATE(sch->labels[i].x, sch->labels[i].y);
    }
    for (int i = 0; i < sch->junction_count; i++) {
        BBOX_UPDATE(sch->junctions[i].x, sch->junctions[i].y);
    }
    for (int i = 0; i < sch->bus_count; i++) {
        BBOX_UPDATE(sch->buses[i].x1, sch->buses[i].y1);
        BBOX_UPDATE(sch->buses[i].x2, sch->buses[i].y2);
    }
    for (int i = 0; i < sch->sheet_count; i++) {
        BBOX_UPDATE(sch->sheets[i].x, sch->sheets[i].y);
        BBOX_UPDATE(sch->sheets[i].x + sch->sheets[i].w, sch->sheets[i].y + sch->sheets[i].h);
    }
    for (int i = 0; i < sch->text_count; i++) {
        BBOX_UPDATE(sch->texts[i].x, sch->texts[i].y);
    }
    for (int i = 0; i < sch->graphic_count; i++) {
        const KicadGraphic* g = &sch->graphics[i];
        if (g->type == DRAW_RECT) {
            BBOX_UPDATE(g->x1, g->y1);
            BBOX_UPDATE(g->x2, g->y2);
        } else if (g->type == DRAW_CIRCLE) {
            BBOX_UPDATE(g->cx - g->r, g->cy - g->r);
            BBOX_UPDATE(g->cx + g->r, g->cy + g->r);
        } else if (g->type == DRAW_POLYLINE) {
            for (int p = 0; p < g->pt_count; p++)
                BBOX_UPDATE(g->pts_x[p], g->pts_y[p]);
        }
    }
    /* If paper/title block present, include full page */
    if (sch->paper.w > 0 && sch->paper.h > 0) {
        BBOX_UPDATE(0, 0);
        BBOX_UPDATE(sch->paper.w, sch->paper.h);
    }
#undef BBOX_UPDATE

    if (!has_pts) { min_x = 0; min_y = 0; max_x = 200; max_y = 150; }

    double margin = 15.0;
    double vx = min_x - margin;
    double vy = min_y - margin;
    double vw = (max_x - min_x) + 2 * margin;
    double vh = (max_y - min_y) + 2 * margin;
    if (vw < 1) vw = 200;
    if (vh < 1) vh = 150;

    SAPPEND("<svg xmlns=\"http://www.w3.org/2000/svg\"\n");
    SAPPEND("     viewBox=\"%g %g %g %g\"\n", vx, vy, vw, vh);
    SAPPEND("     style=\"background:#1e1e2e\">\n");

    /* Defs for common styles */
    SAPPEND("  <defs>\n");
    SAPPEND("    <style>\n");
    SAPPEND("      .wire { stroke: #89b4fa; stroke-width: 0.254; fill: none; stroke-linecap: round; }\n");
    SAPPEND("      .sym-body { stroke: #cba6f7; fill: none; stroke-linecap: round; stroke-linejoin: round; }\n");
    SAPPEND("      .sym-fill { stroke: #cba6f7; fill: #313244; stroke-linecap: round; }\n");
    SAPPEND("      .pin-line { stroke: #cba6f7; stroke-width: 0.15; fill: none; }\n");
    SAPPEND("      .pin-dot { fill: #cba6f7; }\n");
    SAPPEND("      .ref-text { font-family: monospace; font-size: 2.5px; fill: #cdd6f4; }\n");
    SAPPEND("      .val-text { font-family: monospace; font-size: 2px; fill: #a6e3a1; }\n");
    SAPPEND("      .pin-num { font-family: monospace; font-size: 1.5px; fill: #94e2d5; }\n");
    SAPPEND("      .pin-name { font-family: monospace; font-size: 1.8px; fill: #cdd6f4; }\n");
    SAPPEND("      .label { font-family: monospace; font-size: 2.5px; fill: #f38ba8; }\n");
    SAPPEND("      .glabel { font-family: monospace; font-size: 2.5px; fill: #fab387; }\n");
    SAPPEND("      .junction { fill: #89b4fa; }\n");
    SAPPEND("      .noconn { stroke: #f38ba8; stroke-width: 0.35; }\n");
    SAPPEND("      .component:hover .sym-body, .component:hover .sym-fill { stroke: #fab387; }\n");
    SAPPEND("    </style>\n");
    SAPPEND("  </defs>\n");

    /* ---- Wires ---- */
    for (int i = 0; i < sch->wire_count; i++) {
        const KicadWire* w = &sch->wires[i];
        SAPPEND("  <line x1=\"%g\" y1=\"%g\" x2=\"%g\" y2=\"%g\" class=\"wire\"/>\n",
                w->x1, w->y1, w->x2, w->y2);
    }

    /* ---- Junctions ---- */
    for (int i = 0; i < sch->junction_count; i++) {
        const KicadJunction* j = &sch->junctions[i];
        SAPPEND("  <circle cx=\"%g\" cy=\"%g\" r=\"0.5\" class=\"junction\"/>\n", j->x, j->y);
    }

    /* ---- No-connects ---- */
    for (int i = 0; i < sch->noconnect_count; i++) {
        const KicadNoConnect* nc = &sch->noconnects[i];
        double s = 1.0; /* half-size of X */
        SAPPEND("  <line x1=\"%g\" y1=\"%g\" x2=\"%g\" y2=\"%g\" class=\"noconn\"/>\n",
                nc->x - s, nc->y - s, nc->x + s, nc->y + s);
        SAPPEND("  <line x1=\"%g\" y1=\"%g\" x2=\"%g\" y2=\"%g\" class=\"noconn\"/>\n",
                nc->x - s, nc->y + s, nc->x + s, nc->y - s);
    }

    /* ---- Components with full geometry ---- */
    for (int i = 0; i < sch->component_count; i++) {
        const KicadComponent* c = &sch->components[i];
        const LibSymbol* sym = find_lib_symbol(sch, c->lib_id);
        char esc_ref[512];
        json_escape(c->reference[0] ? c->reference : "?", esc_ref, sizeof(esc_ref));

        SAPPEND("  <g id=\"%s\" class=\"component\">\n", esc_ref);

        if (sym && sym->draw_count > 0) {
            /* Render symbol drawing primitives */
            for (int d = 0; d < sym->draw_count; d++) {
                const DrawPrimitive* dp = &sym->draws[d];
                const char* cls = dp->filled == 2 ? "sym-fill" : "sym-body";
                double sw = dp->stroke_width > 0 ? dp->stroke_width : 0.254;

                switch (dp->type) {
                case DRAW_RECT: {
                    double ox1, oy1, ox2, oy2, ox3, oy3, ox4, oy4;
                    transform_point(dp->x1, dp->y1, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox1, &oy1);
                    transform_point(dp->x2, dp->y1, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox2, &oy2);
                    transform_point(dp->x2, dp->y2, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox3, &oy3);
                    transform_point(dp->x1, dp->y2, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox4, &oy4);
                    SAPPEND("    <polygon points=\"%g,%g %g,%g %g,%g %g,%g\""
                            " class=\"%s\" stroke-width=\"%g\"/>\n",
                            ox1, oy1, ox2, oy2, ox3, oy3, ox4, oy4, cls, sw);
                    break;
                }
                case DRAW_CIRCLE: {
                    double ocx, ocy;
                    transform_point(dp->cx, dp->cy, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ocx, &ocy);
                    SAPPEND("    <circle cx=\"%g\" cy=\"%g\" r=\"%g\""
                            " class=\"%s\" stroke-width=\"%g\"/>\n",
                            ocx, ocy, dp->r, cls, sw);
                    break;
                }
                case DRAW_POLYLINE: {
                    if (dp->pt_count < 2) break;
                    SAPPEND("    <polyline points=\"");
                    for (int p = 0; p < dp->pt_count; p++) {
                        double ox, oy;
                        transform_point(dp->pts_x[p], dp->pts_y[p], c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox, &oy);
                        if (p > 0) SAPPEND(" ");
                        SAPPEND("%g,%g", ox, oy);
                    }
                    SAPPEND("\" class=\"%s\" stroke-width=\"%g\"/>\n", cls, sw);
                    break;
                }
                case DRAW_ARC: {
                    /* Render arc using SVG path with arc command */
                    double ox1, oy1, ox2, oy2;
                    transform_point(dp->x1, dp->y1, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox1, &oy1);
                    transform_point(dp->x2, dp->y2, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ox2, &oy2);
                    /* Use large-arc-flag = 0, sweep = 1 as default */
                    double r = dp->r;
                    SAPPEND("    <path d=\"M%g,%g A%g,%g 0 0 1 %g,%g\""
                            " class=\"%s\" stroke-width=\"%g\"/>\n",
                            ox1, oy1, r, r, ox2, oy2, cls, sw);
                    break;
                }
                }
            }

            /* Render pins */
            for (int p = 0; p < sym->pin_count; p++) {
                const LibPin* pin = &sym->pins[p];
                if (pin->length <= 0) continue;

                /* Pin base point */
                double bx, by;
                transform_point(pin->x, pin->y, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &bx, &by);

                /* Pin end point (where it connects to the symbol body) */
                double pex = pin->x, pey = pin->y;
                double pin_rad = pin->angle * M_PI / 180.0;
                pex += pin->length * cos(pin_rad);
                pey -= pin->length * sin(pin_rad);
                double ex2, ey2;
                transform_point(pex, pey, c->x, c->y, c->angle, c->mirror_x, c->mirror_y, &ex2, &ey2);

                /* Pin line */
                SAPPEND("    <line x1=\"%g\" y1=\"%g\" x2=\"%g\" y2=\"%g\" class=\"pin-line\"/>\n",
                        bx, by, ex2, ey2);

                /* Pin dot at connection point */
                SAPPEND("    <circle cx=\"%g\" cy=\"%g\" r=\"0.25\" class=\"pin-dot\"/>\n", bx, by);

                /* Pin number (near middle of pin) */
                if (!sym->hide_pin_numbers && pin->number[0]) {
                    double mx = (bx + ex2) / 2.0;
                    double my = (by + ey2) / 2.0 - 0.5;
                    SAPPEND("    <text x=\"%g\" y=\"%g\" text-anchor=\"middle\" class=\"pin-num\">%s</text>\n",
                            mx, my, pin->number);
                }

                /* Pin name (near body end) */
                if (!sym->hide_pin_names && pin->name[0] && strcmp(pin->name, "~") != 0) {
                    double offset = sym->pin_name_offset > 0 ? sym->pin_name_offset : 0.5;
                    /* Place name slightly inside the body from the body-end of the pin */
                    double nx = ex2, ny = ey2;
                    /* Offset along the pin direction toward the body */
                    double dx = ex2 - bx, dy = ey2 - by;
                    double dlen = sqrt(dx*dx + dy*dy);
                    if (dlen > 0) {
                        nx += offset * dx / dlen;
                        ny += offset * dy / dlen;
                    }
                    SAPPEND("    <text x=\"%g\" y=\"%g\" text-anchor=\"start\" class=\"pin-name\">%s</text>\n",
                            nx, ny + 0.6, pin->name);
                }
            }
        } else {
            /* Fallback: no library definition found — draw circle marker */
            SAPPEND("    <circle cx=\"%g\" cy=\"%g\" r=\"2\" fill=\"none\" stroke=\"#cba6f7\" stroke-width=\"0.3\"/>\n",
                    c->x, c->y);
        }

        /* Reference text */
        if (c->reference[0]) {
            SAPPEND("    <text x=\"%g\" y=\"%g\" class=\"ref-text\">%s</text>\n",
                    c->x + 4, c->y - 1, c->reference);
        }

        /* Value text */
        if (c->value[0]) {
            SAPPEND("    <text x=\"%g\" y=\"%g\" class=\"val-text\">%s</text>\n",
                    c->x + 4, c->y + 2.5, c->value);
        }

        SAPPEND("  </g>\n");
    }

    /* ---- Labels ---- */
    for (int i = 0; i < sch->label_count; i++) {
        const KicadLabel* lbl = &sch->labels[i];
        if (lbl->is_global) {
            /* Global label with flag shape */
            double tx = lbl->x, ty = lbl->y;
            double tw = strlen(lbl->text) * 1.5 + 2;
            SAPPEND("  <polygon points=\"%g,%g %g,%g %g,%g %g,%g %g,%g\""
                    " fill=\"none\" stroke=\"#fab387\" stroke-width=\"0.2\"/>\n",
                    tx, ty,
                    tx + tw, ty - 1.8,
                    tx + tw + 1.5, ty,
                    tx + tw, ty + 1.8,
                    tx, ty);
            SAPPEND("  <text x=\"%g\" y=\"%g\" class=\"glabel\">%s</text>\n",
                    tx + 1, ty + 0.8, lbl->text);
        } else {
            SAPPEND("  <text x=\"%g\" y=\"%g\" class=\"label\">%s</text>\n",
                    lbl->x, lbl->y + 0.8, lbl->text);
        }
    }

    /* ---- Buses ---- */
    for (int i = 0; i < sch->bus_count; i++) {
        const KicadBus* bus = &sch->buses[i];
        SAPPEND("  <line x1=\"%g\" y1=\"%g\" x2=\"%g\" y2=\"%g\""
                " stroke=\"#89dceb\" stroke-width=\"0.5\" stroke-linecap=\"round\"/>\n",
                bus->x1, bus->y1, bus->x2, bus->y2);
    }

    /* ---- Hierarchical sheets ---- */
    for (int i = 0; i < sch->sheet_count; i++) {
        const KicadSheet* sh = &sch->sheets[i];
        SAPPEND("  <rect x=\"%g\" y=\"%g\" width=\"%g\" height=\"%g\""
                " fill=\"#313244\" fill-opacity=\"0.4\" stroke=\"#74c7ec\" stroke-width=\"0.3\"/>\n",
                sh->x, sh->y, sh->w, sh->h);
        if (sh->name[0]) {
            SAPPEND("  <text x=\"%g\" y=\"%g\" font-family=\"monospace\" font-size=\"2.5px\""
                    " fill=\"#74c7ec\">%s</text>\n",
                    sh->x + 1, sh->y - 1, sh->name);
        }
        if (sh->filename[0]) {
            SAPPEND("  <text x=\"%g\" y=\"%g\" font-family=\"monospace\" font-size=\"1.8px\""
                    " fill=\"#6c7086\">%s</text>\n",
                    sh->x + 1, sh->y + sh->h + 2.5, sh->filename);
        }
    }

    /* ---- Standalone text annotations ---- */
    for (int i = 0; i < sch->text_count; i++) {
        const KicadText* txt = &sch->texts[i];
        double fsz = txt->font_size > 0 ? txt->font_size : 1.27;
        char esc_text[512];
        json_escape(txt->text, esc_text, sizeof(esc_text));
        if (txt->angle != 0) {
            SAPPEND("  <text x=\"%g\" y=\"%g\" font-family=\"monospace\" font-size=\"%gpx\""
                    " fill=\"#cdd6f4\" transform=\"rotate(%g %g %g)\">%s</text>\n",
                    txt->x, txt->y, fsz, txt->angle, txt->x, txt->y, esc_text);
        } else {
            SAPPEND("  <text x=\"%g\" y=\"%g\" font-family=\"monospace\" font-size=\"%gpx\""
                    " fill=\"#cdd6f4\">%s</text>\n",
                    txt->x, txt->y, fsz, esc_text);
        }
    }

    /* ---- Top-level graphics ---- */
    for (int i = 0; i < sch->graphic_count; i++) {
        const KicadGraphic* g = &sch->graphics[i];
        double sw = g->stroke_width > 0 ? g->stroke_width : 0.254;
        const char* clr = "#585b70";  /* muted overlay color */

        switch (g->type) {
        case DRAW_RECT:
            SAPPEND("  <rect x=\"%g\" y=\"%g\" width=\"%g\" height=\"%g\""
                    " fill=\"%s\" stroke=\"%s\" stroke-width=\"%g\"/>\n",
                    fmin(g->x1, g->x2), fmin(g->y1, g->y2),
                    fabs(g->x2 - g->x1), fabs(g->y2 - g->y1),
                    g->filled == 2 ? "#313244" : "none", clr, sw);
            break;
        case DRAW_POLYLINE:
            if (g->pt_count >= 2) {
                SAPPEND("  <polyline points=\"");
                for (int p = 0; p < g->pt_count; p++) {
                    if (p > 0) SAPPEND(" ");
                    SAPPEND("%g,%g", g->pts_x[p], g->pts_y[p]);
                }
                SAPPEND("\" fill=\"none\" stroke=\"%s\" stroke-width=\"%g\"/>\n", clr, sw);
            }
            break;
        case DRAW_CIRCLE:
            SAPPEND("  <circle cx=\"%g\" cy=\"%g\" r=\"%g\""
                    " fill=\"none\" stroke=\"%s\" stroke-width=\"%g\"/>\n",
                    g->cx, g->cy, g->r, clr, sw);
            break;
        default:
            break;
        }
    }

    /* ---- Title block (bottom-right corner) ---- */
    if (sch->has_title_block && sch->paper.w > 0) {
        double pw = sch->paper.w, ph = sch->paper.h;
        /* Title block is typically at bottom-right, ~170mm wide, ~30mm tall */
        double tbw = 170, tbh = 30;
        double tbx = pw - tbw - 5;
        double tby = ph - tbh - 5;

        SAPPEND("  <rect x=\"%g\" y=\"%g\" width=\"%g\" height=\"%g\""
                " fill=\"none\" stroke=\"#45475a\" stroke-width=\"0.3\"/>\n",
                tbx, tby, tbw, tbh);

        /* Title */
        if (sch->title_block.title[0]) {
            char esc[512];
            json_escape(sch->title_block.title, esc, sizeof(esc));
            SAPPEND("  <text x=\"%g\" y=\"%g\" font-family=\"monospace\" font-size=\"4px\""
                    " fill=\"#cdd6f4\" font-weight=\"bold\">%s</text>\n",
                    tbx + 3, tby + 10, esc);
        }
        /* Date */
        if (sch->title_block.date[0]) {
            SAPPEND("  <text x=\"%g\" y=\"%g\" font-family=\"monospace\" font-size=\"2.5px\""
                    " fill=\"#a6adc8\">Date: %s</text>\n",
                    tbx + 3, tby + 17, sch->title_block.date);
        }
        /* Rev */
        if (sch->title_block.rev[0]) {
            SAPPEND("  <text x=\"%g\" y=\"%g\" font-family=\"monospace\" font-size=\"2.5px\""
                    " fill=\"#a6adc8\">Rev: %s</text>\n",
                    tbx + 80, tby + 17, sch->title_block.rev);
        }
        /* Company */
        if (sch->title_block.company[0]) {
            char esc[512];
            json_escape(sch->title_block.company, esc, sizeof(esc));
            SAPPEND("  <text x=\"%g\" y=\"%g\" font-family=\"monospace\" font-size=\"2px\""
                    " fill=\"#6c7086\">%s</text>\n",
                    tbx + 3, tby + 24, esc);
        }

        /* Page border */
        SAPPEND("  <rect x=\"0\" y=\"0\" width=\"%g\" height=\"%g\""
                " fill=\"none\" stroke=\"#313244\" stroke-width=\"0.3\"/>\n",
                pw, ph);
    }

    SAPPEND("</svg>\n");
#undef SAPPEND

    return buf;
}

/* ------------------------------------------------------------------ */
/* Public API                                                           */
/* ------------------------------------------------------------------ */

KicadSch* kicad_sch_open(const char* path)
{
    if (!path) return NULL;

    FILE* f = fopen(path, "rb");
    if (!f) return NULL;

    /* Read entire file */
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

    KicadSch* sch = (KicadSch*)calloc(1, sizeof(KicadSch));
    if (!sch) { free(content); return NULL; }

    sch->raw_content = content;
    sch->raw_len = (size_t)file_size;

    /* Parse lib_symbols FIRST (from raw content), then strip for component parsing */
    const char* lib_start = NULL;
    size_t lib_len = 0;
    sch->cleaned_content = strip_lib_symbols(content, sch->raw_len, &sch->cleaned_len,
                                              &lib_start, &lib_len);
    if (!sch->cleaned_content) {
        sch->cleaned_content = content;
        sch->cleaned_len = sch->raw_len;
    }

    /* Parse library symbol definitions for geometry */
    if (lib_start && lib_len > 0) {
        parse_lib_symbols(sch, lib_start, lib_len);
    }

    parse_symbols(sch);
    parse_wires(sch);
    parse_labels(sch);
    parse_junctions(sch);
    parse_noconnects(sch);
    parse_buses(sch);
    parse_sheets(sch);
    parse_title_block(sch);
    parse_texts(sch);
    parse_top_graphics(sch);

    return sch;
}

const char* kicad_sch_get_components_json(KicadSch* h)
{
    if (!h) return NULL;
    if (!h->json_cache) {
        h->json_cache = build_components_json(h);
    }
    return h->json_cache;
}

const char* kicad_sch_render_svg(KicadSch* h)
{
    if (!h) return NULL;
    if (!h->svg_cache) {
        h->svg_cache = build_svg(h);
    }
    return h->svg_cache;
}

int kicad_sch_close(KicadSch* h)
{
    if (!h) return 0;
    free(h->raw_content);
    if (h->cleaned_content && h->cleaned_content != h->raw_content) {
        free(h->cleaned_content);
    }
    free(h->json_cache);
    free(h->svg_cache);
    free(h->erc_cache);
    free(h->lib_symbols);
    free(h);
    return 0;
}
