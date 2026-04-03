/* makelife-cad/kicad-bridge/src/bridge_pcb_edit.c
 * PCB interactive editing API — Phase 5
 * Maintains per-handle edit state (items, undo/redo stack) in a global linked list.
 */
#include "kicad_bridge.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ------------------------------------------------------------------ */
/* Internal data model                                                  */
/* ------------------------------------------------------------------ */

#define PCB_ITEM_FOOTPRINT  1
#define PCB_ITEM_TRACK      2
#define PCB_ITEM_VIA        3
#define PCB_ITEM_ZONE       4

typedef struct {
    int   type;
    int   item_id;

    /* footprint */
    char  lib_id[256];
    /* track / via / zone */
    double x, y, x2, y2;
    double width;   /* track width or via outer size */
    double drill;   /* via drill diameter */
    char   layer[64];
    int    net_id;
    char*  points_json; /* zone polygon — heap-allocated, may be NULL */
    int    deleted;
} PCBItem;

#define CMD_ADD    1
#define CMD_MOVE   2
#define CMD_DELETE 3

typedef struct {
    int    type;
    int    item_id;
    double prev_x, prev_y;  /* for MOVE */
    PCBItem snapshot;        /* full copy for ADD/DELETE inverse */
} PCBCommand;

#define MAX_ITEMS    4096
#define MAX_UNDO     256

typedef struct PCBEditState {
    PCBItem     items[MAX_ITEMS];
    int         item_count;
    int         next_id;

    PCBCommand  undo_stack[MAX_UNDO];
    int         undo_top;   /* index of next free slot */

    PCBCommand  redo_stack[MAX_UNDO];
    int         redo_top;

    kicad_pcb_handle handle; /* back-pointer for identification */
    struct PCBEditState* next; /* linked list */
} PCBEditState;

/* Global linked list of edit states, one per open PCB handle */
static PCBEditState* g_states = NULL;

static PCBEditState* get_or_create_state(kicad_pcb_handle h) {
    PCBEditState* s = g_states;
    while (s) {
        if (s->handle == h) return s;
        s = s->next;
    }
    s = (PCBEditState*)calloc(1, sizeof(PCBEditState));
    if (!s) return NULL;
    s->handle  = h;
    s->next_id = 1;
    s->next    = g_states;
    g_states   = s;
    return s;
}

static PCBItem* find_item(PCBEditState* s, int item_id) {
    for (int i = 0; i < s->item_count; i++) {
        if (s->items[i].item_id == item_id && !s->items[i].deleted)
            return &s->items[i];
    }
    return NULL;
}

/* Push command to undo stack, clear redo stack */
static void push_undo(PCBEditState* s, PCBCommand cmd) {
    if (s->undo_top < MAX_UNDO) {
        s->undo_stack[s->undo_top++] = cmd;
    }
    s->redo_top = 0; /* any new action clears redo */
}

/* ------------------------------------------------------------------ */
/* Public edit API                                                      */
/* ------------------------------------------------------------------ */

/**
 * kicad_pcb_add_footprint — place a footprint on the board.
 * lib_id : e.g. "Resistor_SMD:R_0402"
 * layer  : "F.Cu" or "B.Cu"
 * Returns the new item_id (> 0) or -1 on error.
 */
int kicad_pcb_add_footprint(kicad_pcb_handle h,
                             const char* lib_id,
                             double x, double y,
                             const char* layer) {
    if (!h) return -1;
    PCBEditState* s = get_or_create_state(h);
    if (!s || s->item_count >= MAX_ITEMS) return -1;

    PCBItem* it = &s->items[s->item_count++];
    memset(it, 0, sizeof(PCBItem));
    it->type    = PCB_ITEM_FOOTPRINT;
    it->item_id = s->next_id++;
    strncpy(it->lib_id, lib_id ? lib_id : "", sizeof(it->lib_id) - 1);
    it->x       = x;
    it->y       = y;
    strncpy(it->layer, layer ? layer : "F.Cu", sizeof(it->layer) - 1);

    PCBCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type    = CMD_ADD;
    cmd.item_id = it->item_id;
    cmd.snapshot = *it;
    push_undo(s, cmd);
    return it->item_id;
}

/**
 * kicad_pcb_add_track — add a point-to-point track segment.
 * width   : in mm
 * layer   : "F.Cu", "B.Cu", etc.
 * net_id  : net identifier (0 = no net)
 * Returns new item_id or -1 on error.
 */
int kicad_pcb_add_track(kicad_pcb_handle h,
                         double x1, double y1,
                         double x2, double y2,
                         double width,
                         const char* layer,
                         int net_id) {
    if (!h) return -1;
    PCBEditState* s = get_or_create_state(h);
    if (!s || s->item_count >= MAX_ITEMS) return -1;

    PCBItem* it = &s->items[s->item_count++];
    memset(it, 0, sizeof(PCBItem));
    it->type    = PCB_ITEM_TRACK;
    it->item_id = s->next_id++;
    it->x       = x1; it->y  = y1;
    it->x2      = x2; it->y2 = y2;
    it->width   = width;
    strncpy(it->layer, layer ? layer : "F.Cu", sizeof(it->layer) - 1);
    it->net_id  = net_id;

    PCBCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type    = CMD_ADD;
    cmd.item_id = it->item_id;
    cmd.snapshot = *it;
    push_undo(s, cmd);
    return it->item_id;
}

/**
 * kicad_pcb_add_via — add a via.
 * size  : outer diameter in mm
 * drill : drill diameter in mm
 * Returns new item_id or -1 on error.
 */
int kicad_pcb_add_via(kicad_pcb_handle h,
                       double x, double y,
                       double size, double drill,
                       int net_id) {
    if (!h) return -1;
    PCBEditState* s = get_or_create_state(h);
    if (!s || s->item_count >= MAX_ITEMS) return -1;

    PCBItem* it = &s->items[s->item_count++];
    memset(it, 0, sizeof(PCBItem));
    it->type    = PCB_ITEM_VIA;
    it->item_id = s->next_id++;
    it->x       = x;
    it->y       = y;
    it->width   = size;
    it->drill   = drill;
    it->net_id  = net_id;

    PCBCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type    = CMD_ADD;
    cmd.item_id = it->item_id;
    cmd.snapshot = *it;
    push_undo(s, cmd);
    return it->item_id;
}

/**
 * kicad_pcb_add_zone — add a copper pour zone.
 * points_json : JSON array of {x,y} objects defining the polygon,
 *               e.g. [{"x":0,"y":0},{"x":10,"y":0},{"x":10,"y":10}]
 * Returns new item_id or -1 on error.
 */
int kicad_pcb_add_zone(kicad_pcb_handle h,
                        int net_id,
                        const char* layer,
                        const char* points_json) {
    if (!h) return -1;
    PCBEditState* s = get_or_create_state(h);
    if (!s || s->item_count >= MAX_ITEMS) return -1;

    PCBItem* it = &s->items[s->item_count++];
    memset(it, 0, sizeof(PCBItem));
    it->type    = PCB_ITEM_ZONE;
    it->item_id = s->next_id++;
    it->net_id  = net_id;
    strncpy(it->layer, layer ? layer : "F.Cu", sizeof(it->layer) - 1);
    if (points_json) {
        it->points_json = strdup(points_json);
    }

    PCBCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type    = CMD_ADD;
    cmd.item_id = it->item_id;
    /* snapshot does not own points_json — shallow copy is fine for undo */
    cmd.snapshot = *it;
    push_undo(s, cmd);
    return it->item_id;
}

/**
 * kicad_pcb_move_item — translate an item by (dx, dy) in mm.
 */
void kicad_pcb_move_item(kicad_pcb_handle h, int item_id,
                          double dx, double dy) {
    if (!h) return;
    PCBEditState* s = get_or_create_state(h);
    if (!s) return;
    PCBItem* it = find_item(s, item_id);
    if (!it) return;

    PCBCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type    = CMD_MOVE;
    cmd.item_id = item_id;
    cmd.prev_x  = it->x;
    cmd.prev_y  = it->y;
    push_undo(s, cmd);

    it->x  += dx; it->y  += dy;
    it->x2 += dx; it->y2 += dy;
}

/**
 * kicad_pcb_delete_item — mark an item as deleted.
 */
void kicad_pcb_delete_item(kicad_pcb_handle h, int item_id) {
    if (!h) return;
    PCBEditState* s = get_or_create_state(h);
    if (!s) return;
    PCBItem* it = find_item(s, item_id);
    if (!it) return;

    PCBCommand cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type     = CMD_DELETE;
    cmd.item_id  = item_id;
    cmd.snapshot = *it;
    push_undo(s, cmd);
    it->deleted = 1;
}

/**
 * kicad_pcb_undo — undo the last edit operation.
 */
void kicad_pcb_undo(kicad_pcb_handle h) {
    if (!h) return;
    PCBEditState* s = get_or_create_state(h);
    if (!s || s->undo_top == 0) return;

    PCBCommand cmd = s->undo_stack[--s->undo_top];

    /* Save to redo stack */
    if (s->redo_top < MAX_UNDO) {
        PCBItem* it_cur = find_item(s, cmd.item_id);
        PCBCommand redo_cmd = cmd;
        if (it_cur) redo_cmd.snapshot = *it_cur;
        s->redo_stack[s->redo_top++] = redo_cmd;
    }

    /* Reverse the command */
    switch (cmd.type) {
        case CMD_ADD: {
            PCBItem* it = find_item(s, cmd.item_id);
            if (it) it->deleted = 1;
            break;
        }
        case CMD_MOVE: {
            PCBItem* it = find_item(s, cmd.item_id);
            if (it) {
                double ddx = cmd.prev_x - it->x;
                double ddy = cmd.prev_y - it->y;
                it->x  += ddx; it->y  += ddy;
                it->x2 += ddx; it->y2 += ddy;
            }
            break;
        }
        case CMD_DELETE: {
            PCBItem* it = find_item(s, cmd.item_id);
            if (!it) {
                /* Restore from snapshot */
                if (s->item_count < MAX_ITEMS) {
                    s->items[s->item_count++] = cmd.snapshot;
                    s->items[s->item_count - 1].deleted = 0;
                }
            } else {
                it->deleted = 0;
            }
            break;
        }
        default: break;
    }
}

/**
 * kicad_pcb_redo — redo the last undone operation.
 */
void kicad_pcb_redo(kicad_pcb_handle h) {
    if (!h) return;
    PCBEditState* s = get_or_create_state(h);
    if (!s || s->redo_top == 0) return;

    PCBCommand cmd = s->redo_stack[--s->redo_top];

    if (s->undo_top < MAX_UNDO)
        s->undo_stack[s->undo_top++] = cmd;

    switch (cmd.type) {
        case CMD_ADD: {
            PCBItem* it = find_item(s, cmd.item_id);
            if (!it && s->item_count < MAX_ITEMS) {
                s->items[s->item_count++] = cmd.snapshot;
                s->items[s->item_count - 1].deleted = 0;
            } else if (it) {
                it->deleted = 0;
            }
            break;
        }
        case CMD_MOVE: {
            PCBItem* it = find_item(s, cmd.item_id);
            if (it) {
                double ddx = cmd.snapshot.x - it->x;
                double ddy = cmd.snapshot.y - it->y;
                it->x  += ddx; it->y  += ddy;
                it->x2 += ddx; it->y2 += ddy;
            }
            break;
        }
        case CMD_DELETE: {
            PCBItem* it = find_item(s, cmd.item_id);
            if (it) it->deleted = 1;
            break;
        }
        default: break;
    }
}

/**
 * kicad_pcb_save — serialize edit state to a minimal .kicad_pcb S-expression.
 *
 * The output is a standalone .kicad_pcb file containing only the items
 * added via the edit API (no merge with the original file in this phase).
 * Full merge with the existing file contents is Phase 6 scope.
 *
 * Returns 0 on success, -1 on error.
 */
int kicad_pcb_save(kicad_pcb_handle h, const char* path) {
    if (!h || !path) return -1;
    PCBEditState* s = get_or_create_state(h);
    if (!s) return -1;

    FILE* f = fopen(path, "w");
    if (!f) return -1;

    fprintf(f, "(kicad_pcb (version 20221018) (generator yiacad)\n");
    fprintf(f, "  (general (thickness 1.6))\n");
    fprintf(f, "  (layers\n");
    fprintf(f, "    (0 \"F.Cu\" signal)\n");
    fprintf(f, "    (31 \"B.Cu\" signal)\n");
    fprintf(f, "    (44 \"Edge.Cuts\" user \"Edge Cuts\")\n");
    fprintf(f, "  )\n");

    for (int i = 0; i < s->item_count; i++) {
        PCBItem* it = &s->items[i];
        if (it->deleted) continue;

        switch (it->type) {
            case PCB_ITEM_FOOTPRINT:
                fprintf(f,
                    "  (footprint \"%s\" (layer \"%s\")\n"
                    "    (at %g %g)\n"
                    "  )\n",
                    it->lib_id, it->layer, it->x, it->y);
                break;
            case PCB_ITEM_TRACK:
                fprintf(f,
                    "  (segment (start %g %g) (end %g %g)"
                    " (width %g) (layer \"%s\") (net %d))\n",
                    it->x, it->y, it->x2, it->y2,
                    it->width, it->layer, it->net_id);
                break;
            case PCB_ITEM_VIA:
                fprintf(f,
                    "  (via (at %g %g) (size %g) (drill %g) (net %d))\n",
                    it->x, it->y, it->width, it->drill, it->net_id);
                break;
            case PCB_ITEM_ZONE:
                fprintf(f,
                    "  (zone (net %d) (layer \"%s\")\n"
                    "    (polygon (pts %s))\n"
                    "  )\n",
                    it->net_id, it->layer,
                    it->points_json ? it->points_json : "");
                break;
            default: break;
        }
    }

    fprintf(f, ")\n");
    fclose(f);
    return 0;
}

/**
 * kicad_pcb_import_netlist — import net assignments from a JSON netlist
 * (produced by kicad_sch_get_components_json or an export of the schematic).
 *
 * netlist_json format:
 * [{"net_id":1,"name":"GND","pins":[{"reference":"R1","pin":"1"}]}, ...]
 *
 * Side effect: assigns net_id to footprints whose reference matches.
 * Returns 0 on success, -1 on parse error.
 */
int kicad_pcb_import_netlist(kicad_pcb_handle h, const char* netlist_json) {
    /* Minimal implementation: net_id is already passed directly in
     * add_track / add_via. Full JSON parse deferred to Phase 7. */
    (void)h;
    (void)netlist_json;
    return 0;
}
