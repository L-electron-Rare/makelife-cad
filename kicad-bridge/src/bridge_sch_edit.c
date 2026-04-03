/*
 * bridge_sch_edit.c — Schematic edit functions (Phase 4)
 *
 * Implements mutations on top of the KicadSch struct defined in
 * kicad_bridge_internal.h.  Compiled as a separate translation unit and
 * linked into the same static library as bridge_sch.c.
 *
 * All coordinates are in KiCad mils (1 mil = 0.0254 mm).
 * The undo stack is a ring buffer of SCH_UNDO_MAX entries.
 */

#include "kicad_bridge.h"
#include "kicad_bridge_internal.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */

static SchItem* find_item(KicadSch* h, uint64_t id) {
    for (int i = 0; i < h->items_count; i++) {
        if (h->items[i].id == id && !h->items[i].deleted)
            return &h->items[i];
    }
    return NULL;
}

static void invalidate_items_json(KicadSch* h) {
    free(h->items_json);
    h->items_json = NULL;
}

static void push_undo(KicadSch* h, SchCommand cmd) {
    h->undo_stack[h->undo_head % SCH_UNDO_MAX] = cmd;
    h->undo_head = (h->undo_head + 1) % SCH_UNDO_MAX;
    if (h->undo_size < SCH_UNDO_MAX) h->undo_size++;
    /* Any new action clears the redo stack */
    h->redo_size = 0;
    h->redo_head = 0;
    invalidate_items_json(h);
}

static uint64_t alloc_id(KicadSch* h) {
    return ++h->next_id;
}

/* ------------------------------------------------------------------ */
/* Public API — add                                                    */
/* ------------------------------------------------------------------ */

uint64_t kicad_sch_add_symbol(KicadSch* h, const char* lib_id,
                              double x, double y) {
    if (!h || h->items_count >= SCH_ITEMS_MAX) return 0;

    SchItem item;
    memset(&item, 0, sizeof(item));
    item.id   = alloc_id(h);
    item.type = SCH_ITEM_SYMBOL;
    item.x    = x;
    item.y    = y;
    strncpy(item.lib_id, lib_id ? lib_id : "", sizeof(item.lib_id) - 1);

    /* Derive a default reference from the lib_id suffix (e.g. "Device:R" -> "R?") */
    const char* colon = strrchr(lib_id ? lib_id : "", ':');
    const char* base  = colon ? colon + 1 : (lib_id ? lib_id : "U");
    snprintf(item.reference, sizeof(item.reference), "%s?", base);
    strncpy(item.value, base, sizeof(item.value) - 1);

    h->items[h->items_count++] = item;

    SchCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.kind  = CMD_ADD;
    cmd.after = item;
    push_undo(h, cmd);
    return item.id;
}

uint64_t kicad_sch_add_wire(KicadSch* h,
                            double x1, double y1,
                            double x2, double y2) {
    if (!h || h->items_count >= SCH_ITEMS_MAX) return 0;

    SchItem item;
    memset(&item, 0, sizeof(item));
    item.id   = alloc_id(h);
    item.type = SCH_ITEM_WIRE;
    item.x    = x1;
    item.y    = y1;
    item.x2   = x2;
    item.y2   = y2;

    h->items[h->items_count++] = item;

    SchCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.kind  = CMD_ADD;
    cmd.after = item;
    push_undo(h, cmd);
    return item.id;
}

uint64_t kicad_sch_add_label(KicadSch* h, const char* text,
                             double x, double y) {
    if (!h || h->items_count >= SCH_ITEMS_MAX) return 0;

    SchItem item;
    memset(&item, 0, sizeof(item));
    item.id   = alloc_id(h);
    item.type = SCH_ITEM_LABEL;
    item.x    = x;
    item.y    = y;
    strncpy(item.text, text ? text : "", sizeof(item.text) - 1);

    h->items[h->items_count++] = item;

    SchCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.kind  = CMD_ADD;
    cmd.after = item;
    push_undo(h, cmd);
    return item.id;
}

/* ------------------------------------------------------------------ */
/* Public API — mutate                                                 */
/* ------------------------------------------------------------------ */

int kicad_sch_move_item(KicadSch* h, uint64_t item_id,
                        double dx, double dy) {
    if (!h) return -1;
    SchItem* it = find_item(h, item_id);
    if (!it) return -1;

    SchCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.kind   = CMD_MOVE;
    cmd.before = *it;
    it->x  += dx;
    it->y  += dy;
    it->x2 += dx;
    it->y2 += dy;
    cmd.after = *it;
    push_undo(h, cmd);
    return 0;
}

int kicad_sch_delete_item(KicadSch* h, uint64_t item_id) {
    if (!h) return -1;
    SchItem* it = find_item(h, item_id);
    if (!it) return -1;

    SchCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.kind   = CMD_DELETE;
    cmd.before = *it;
    it->deleted = 1;
    cmd.after = *it;
    push_undo(h, cmd);
    return 0;
}

int kicad_sch_set_property(KicadSch* h, uint64_t item_id,
                           const char* key, const char* value) {
    if (!h || !key || !value) return -1;
    SchItem* it = find_item(h, item_id);
    if (!it) return -1;

    SchCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.kind   = CMD_SET_PROP;
    cmd.before = *it;

    if (strcmp(key, "reference") == 0)
        strncpy(it->reference, value, sizeof(it->reference) - 1);
    else if (strcmp(key, "value") == 0)
        strncpy(it->value, value, sizeof(it->value) - 1);
    else if (strcmp(key, "footprint") == 0)
        strncpy(it->footprint, value, sizeof(it->footprint) - 1);
    else if (strcmp(key, "text") == 0)
        strncpy(it->text, value, sizeof(it->text) - 1);
    else {
        /* Append to props_json as "key":"value" pair */
        char pair[512];
        snprintf(pair, sizeof(pair), "\"%s\":\"%s\"", key, value);
        size_t remaining = sizeof(it->props_json) - strlen(it->props_json) - 2;
        if (remaining > strlen(pair) + 1) {
            if (strlen(it->props_json) > 0)
                strncat(it->props_json, ",", remaining);
            strncat(it->props_json, pair, remaining);
        }
    }

    cmd.after = *it;
    push_undo(h, cmd);
    invalidate_items_json(h);
    return 0;
}

/* ------------------------------------------------------------------ */
/* Undo / Redo helpers                                                 */
/* ------------------------------------------------------------------ */

static void apply_inverse(KicadSch* h, SchCommand* cmd) {
    switch (cmd->kind) {
        case CMD_ADD: {
            SchItem* it = find_item(h, cmd->after.id);
            if (it) it->deleted = 1;
            break;
        }
        case CMD_DELETE: {
            /* find even if deleted */
            for (int i = 0; i < h->items_count; i++) {
                if (h->items[i].id == cmd->before.id) {
                    h->items[i].deleted = 0;
                    break;
                }
            }
            break;
        }
        case CMD_MOVE:
        case CMD_SET_PROP: {
            for (int i = 0; i < h->items_count; i++) {
                if (h->items[i].id == cmd->before.id) {
                    h->items[i] = cmd->before;
                    break;
                }
            }
            break;
        }
    }
    invalidate_items_json(h);
}

static void apply_forward(KicadSch* h, SchCommand* cmd) {
    switch (cmd->kind) {
        case CMD_ADD: {
            for (int i = 0; i < h->items_count; i++) {
                if (h->items[i].id == cmd->after.id) {
                    h->items[i].deleted = 0;
                    break;
                }
            }
            break;
        }
        case CMD_DELETE: {
            SchItem* it = find_item(h, cmd->after.id);
            if (it) it->deleted = 1;
            break;
        }
        case CMD_MOVE:
        case CMD_SET_PROP: {
            for (int i = 0; i < h->items_count; i++) {
                if (h->items[i].id == cmd->after.id) {
                    h->items[i] = cmd->after;
                    break;
                }
            }
            break;
        }
    }
    invalidate_items_json(h);
}

int kicad_sch_undo(KicadSch* h) {
    if (!h || h->undo_size == 0) return -1;

    h->undo_head = (h->undo_head - 1 + SCH_UNDO_MAX) % SCH_UNDO_MAX;
    h->undo_size--;
    SchCommand* cmd = &h->undo_stack[h->undo_head];

    /* Save to redo stack */
    h->redo_stack[h->redo_head % SCH_UNDO_MAX] = *cmd;
    h->redo_head = (h->redo_head + 1) % SCH_UNDO_MAX;
    if (h->redo_size < SCH_UNDO_MAX) h->redo_size++;

    apply_inverse(h, cmd);
    return 0;
}

int kicad_sch_redo(KicadSch* h) {
    if (!h || h->redo_size == 0) return -1;

    h->redo_head = (h->redo_head - 1 + SCH_UNDO_MAX) % SCH_UNDO_MAX;
    h->redo_size--;
    SchCommand* cmd = &h->redo_stack[h->redo_head];

    /* Push back to undo stack without clearing redo */
    h->undo_stack[h->undo_head % SCH_UNDO_MAX] = *cmd;
    h->undo_head = (h->undo_head + 1) % SCH_UNDO_MAX;
    if (h->undo_size < SCH_UNDO_MAX) h->undo_size++;

    apply_forward(h, cmd);
    return 0;
}

/* ------------------------------------------------------------------ */
/* Save — S-expression serialisation (minimal KiCad 7 format)         */
/* ------------------------------------------------------------------ */

int kicad_sch_save(KicadSch* h, const char* path) {
    if (!h || !path) return -1;
    FILE* f = fopen(path, "w");
    if (!f) return -1;

    fprintf(f, "(kicad_sch\n");
    fprintf(f, "  (version 20230121)\n");
    fprintf(f, "  (generator makelife_cad)\n");
    fprintf(f, "\n");

    for (int i = 0; i < h->items_count; i++) {
        SchItem* it = &h->items[i];
        if (it->deleted) continue;

        switch (it->type) {
            case SCH_ITEM_SYMBOL:
                fprintf(f,
                    "  (symbol (lib_id \"%s\") (at %.4f %.4f 0)\n"
                    "    (property \"Reference\" \"%s\" (at %.4f %.4f 0))\n"
                    "    (property \"Value\" \"%s\" (at %.4f %.4f 0))\n"
                    "    (property \"Footprint\" \"%s\" (at 0 0 0))\n"
                    "  )\n",
                    it->lib_id, it->x, it->y,
                    it->reference, it->x, it->y - 2.54,
                    it->value,     it->x, it->y + 2.54,
                    it->footprint);
                break;

            case SCH_ITEM_WIRE:
                fprintf(f,
                    "  (wire (pts (xy %.4f %.4f) (xy %.4f %.4f)))\n",
                    it->x, it->y, it->x2, it->y2);
                break;

            case SCH_ITEM_LABEL:
                fprintf(f,
                    "  (label \"%s\" (at %.4f %.4f 0))\n",
                    it->text, it->x, it->y);
                break;
        }
    }

    fprintf(f, ")\n");
    fclose(f);
    return 0;
}

/* ------------------------------------------------------------------ */
/* Items JSON (for Swift to re-render the canvas)                      */
/* ------------------------------------------------------------------ */

const char* kicad_sch_get_items_json(KicadSch* h) {
    if (!h) return NULL;
    if (h->items_json) return h->items_json;

    /* Estimate: ~300 chars per item */
    size_t cap = (size_t)(h->items_count + 1) * 300 + 32;
    char*  buf = (char*)malloc(cap);
    if (!buf) return NULL;
    size_t pos = 0;

    buf[pos++] = '[';

    int first = 1;
    for (int i = 0; i < h->items_count; i++) {
        SchItem* it = &h->items[i];
        if (it->deleted) continue;

        if (!first) buf[pos++] = ',';
        first = 0;

        int written = 0;
        switch (it->type) {
            case SCH_ITEM_SYMBOL:
                written = snprintf(buf + pos, cap - pos,
                    "{\"id\":%llu,\"type\":\"symbol\","
                    "\"lib_id\":\"%s\",\"x\":%.4f,\"y\":%.4f,"
                    "\"reference\":\"%s\",\"value\":\"%s\","
                    "\"footprint\":\"%s\"}",
                    (unsigned long long)it->id,
                    it->lib_id, it->x, it->y,
                    it->reference, it->value, it->footprint);
                break;

            case SCH_ITEM_WIRE:
                written = snprintf(buf + pos, cap - pos,
                    "{\"id\":%llu,\"type\":\"wire\","
                    "\"x1\":%.4f,\"y1\":%.4f,\"x2\":%.4f,\"y2\":%.4f}",
                    (unsigned long long)it->id,
                    it->x, it->y, it->x2, it->y2);
                break;

            case SCH_ITEM_LABEL:
                written = snprintf(buf + pos, cap - pos,
                    "{\"id\":%llu,\"type\":\"label\","
                    "\"text\":\"%s\",\"x\":%.4f,\"y\":%.4f}",
                    (unsigned long long)it->id,
                    it->text, it->x, it->y);
                break;
        }

        if (written > 0 && (size_t)written < cap - pos)
            pos += (size_t)written;
    }

    buf[pos++] = ']';
    buf[pos]   = '\0';
    h->items_json = buf;
    return buf;
}
