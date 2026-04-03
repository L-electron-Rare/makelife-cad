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
 * Mirrors the Python: re.sub(r'\(lib_symbols\s.*?\n  \)', '', content, re.DOTALL)
 * Returns heap-allocated cleaned string (caller frees), sets *out_len.
 */
static char* strip_lib_symbols(const char* content, size_t len, size_t* out_len)
{
    const char needle[] = "(lib_symbols";
    size_t nlen = sizeof(needle) - 1;
    const char* found = (const char*)memmem(content, len, needle, nlen);
    if (!found) {
        /* No lib_symbols block — copy as-is */
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
        extract_at(block, block_len, &comp->x, &comp->y);

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

    /* Compute bounding box */
    double min_x = 0, min_y = 0, max_x = 100, max_y = 100;
    int first = 1;

    for (int i = 0; i < sch->component_count; i++) {
        double x = sch->components[i].x, y = sch->components[i].y;
        if (first) { min_x = max_x = x; min_y = max_y = y; first = 0; }
        else {
            if (x < min_x) min_x = x;
            if (x > max_x) max_x = x;
            if (y < min_y) min_y = y;
            if (y > max_y) max_y = y;
        }
    }
    for (int i = 0; i < sch->wire_count; i++) {
        double coords[4] = {sch->wires[i].x1, sch->wires[i].y1,
                            sch->wires[i].x2, sch->wires[i].y2};
        for (int j = 0; j < 4; j += 2) {
            double x = coords[j], y = coords[j+1];
            if (first) { min_x = max_x = x; min_y = max_y = y; first = 0; }
            else {
                if (x < min_x) min_x = x;
                if (x > max_x) max_x = x;
                if (y < min_y) min_y = y;
                if (y > max_y) max_y = y;
            }
        }
    }
    for (int i = 0; i < sch->label_count; i++) {
        double x = sch->labels[i].x, y = sch->labels[i].y;
        if (first) { min_x = max_x = x; min_y = max_y = y; first = 0; }
        else {
            if (x < min_x) min_x = x;
            if (x > max_x) max_x = x;
            if (y < min_y) min_y = y;
            if (y > max_y) max_y = y;
        }
    }

    double margin = 10.0;
    double vx = min_x - margin;
    double vy = min_y - margin;
    double vw = (max_x - min_x) + 2 * margin;
    double vh = (max_y - min_y) + 2 * margin;
    if (vw < 1) vw = 200;
    if (vh < 1) vh = 150;

    SAPPEND("<svg xmlns=\"http://www.w3.org/2000/svg\"\n");
    SAPPEND("     viewBox=\"%g %g %g %g\"\n", vx, vy, vw, vh);
    SAPPEND("     style=\"background:#1e1e2e\">\n");

    /* Wires */
    for (int i = 0; i < sch->wire_count; i++) {
        const KicadWire* w = &sch->wires[i];
        SAPPEND("  <line x1=\"%g\" y1=\"%g\" x2=\"%g\" y2=\"%g\""
                " stroke=\"#6c7086\" stroke-width=\"0.5\"/>\n",
                w->x1, w->y1, w->x2, w->y2);
    }

    /* Components */
    for (int i = 0; i < sch->component_count; i++) {
        const KicadComponent* c = &sch->components[i];
        SAPPEND("  <g id=\"%s\" class=\"component\">\n", c->reference[0] ? c->reference : "?");
        SAPPEND("    <circle cx=\"%g\" cy=\"%g\" r=\"3\" fill=\"#cba6f7\"/>\n", c->x, c->y);
        SAPPEND("    <text x=\"%g\" y=\"%g\" font-size=\"4\" fill=\"#cdd6f4\">%s</text>\n",
                c->x + 4, c->y, c->reference);
        SAPPEND("    <text x=\"%g\" y=\"%g\" font-size=\"3\" fill=\"#a6e3a1\">%s</text>\n",
                c->x + 4, c->y + 4, c->value);
        SAPPEND("  </g>\n");
    }

    /* Labels */
    for (int i = 0; i < sch->label_count; i++) {
        const KicadLabel* lbl = &sch->labels[i];
        SAPPEND("  <text x=\"%g\" y=\"%g\" font-size=\"3.5\" fill=\"#f38ba8\">%s</text>\n",
                lbl->x, lbl->y, lbl->text);
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

    /* Strip lib_symbols for parsing passes */
    sch->cleaned_content = strip_lib_symbols(content, sch->raw_len, &sch->cleaned_len);
    if (!sch->cleaned_content) {
        /* Fall back to raw content */
        sch->cleaned_content = content;
        sch->cleaned_len = sch->raw_len;
    }

    parse_symbols(sch);
    parse_wires(sch);
    parse_labels(sch);

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
    /* cleaned_content may alias raw_content — only free if distinct */
    if (h->cleaned_content && h->cleaned_content != h->raw_content) {
        free(h->cleaned_content);
    }
    free(h->json_cache);
    free(h->svg_cache);
    free(h->erc_cache);
    free(h);
    return 0;
}
