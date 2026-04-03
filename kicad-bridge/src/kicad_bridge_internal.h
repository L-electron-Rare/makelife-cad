/*
 * kicad_bridge_internal.h — shared internal struct definitions
 * Included by bridge_sch.c, bridge_pcb.c, and bridge_drc.c.
 * Not part of the public API — do not include from outside the library.
 */

#pragma once

#include <stddef.h>
#include <stdint.h>

/* ------------------------------------------------------------------ */
/* Schematic internal constants                                         */
/* ------------------------------------------------------------------ */

#define KICAD_MAX_COMPONENTS 4096
#define KICAD_MAX_PROP_LEN   256
#define KICAD_MAX_PINS       64
#define KICAD_MAX_WIRES      8192
#define KICAD_MAX_LABELS     1024
#define KICAD_JSON_BUF_SIZE  (1 << 20)  /* 1 MB */
#define KICAD_SVG_BUF_SIZE   (4 << 20)  /* 4 MB */

/* ------------------------------------------------------------------ */
/* Schematic internal types                                             */
/* ------------------------------------------------------------------ */

typedef struct {
    char reference[KICAD_MAX_PROP_LEN];
    char value[KICAD_MAX_PROP_LEN];
    char footprint[KICAD_MAX_PROP_LEN];
    char lib_id[KICAD_MAX_PROP_LEN];
    char pins[KICAD_MAX_PINS][16];
    int  pin_count;
    double x, y;
} KicadComponent;

typedef struct {
    double x1, y1, x2, y2;
} KicadWire;

typedef struct {
    char text[KICAD_MAX_PROP_LEN];
    double x, y;
    int is_global;
} KicadLabel;

/* ------------------------------------------------------------------ */
/* Schematic edit types (Phase 4)                                      */
/* ------------------------------------------------------------------ */

#define SCH_ITEMS_MAX  4096
#define SCH_UNDO_MAX   128

typedef enum {
    SCH_ITEM_SYMBOL = 1,
    SCH_ITEM_WIRE   = 2,
    SCH_ITEM_LABEL  = 3,
} SchItemType;

typedef struct {
    uint64_t    id;
    SchItemType type;
    int         deleted;
    char        lib_id[256];
    char        reference[64];
    char        value[128];
    char        footprint[256];
    double      x, y;
    double      x2, y2;
    char        text[256];
    char        props_json[1024];
} SchItem;

typedef enum {
    CMD_ADD      = 1,
    CMD_DELETE   = 2,
    CMD_MOVE     = 3,
    CMD_SET_PROP = 4,
} SchCmdKind;

typedef struct {
    SchCmdKind kind;
    SchItem    before;
    SchItem    after;
} SchCommand;

/* ------------------------------------------------------------------ */
/* KicadSch internal layout                                            */
/* ------------------------------------------------------------------ */

struct KicadSch {
    /* --- Phase 1 fields (read-only viewer) --- */
    char*          raw_content;
    size_t         raw_len;
    char*          cleaned_content;
    size_t         cleaned_len;

    KicadComponent components[KICAD_MAX_COMPONENTS];
    int            component_count;

    KicadWire      wires[KICAD_MAX_WIRES];
    int            wire_count;

    KicadLabel     labels[KICAD_MAX_LABELS];
    int            label_count;

    char*          json_cache;
    char*          svg_cache;
    char*          erc_cache;

    /* --- Phase 4 fields (edit) --- */
    SchItem    items[SCH_ITEMS_MAX];
    int        items_count;
    uint64_t   next_id;

    SchCommand undo_stack[SCH_UNDO_MAX];
    int        undo_head;
    int        undo_size;

    SchCommand redo_stack[SCH_UNDO_MAX];
    int        redo_head;
    int        redo_size;

    char*      items_json;
};

/* ------------------------------------------------------------------ */
/* PCB internal constants                                               */
/* ------------------------------------------------------------------ */

#define PCB_MAX_FOOTPRINTS  2048
#define PCB_MAX_SEGMENTS    16384
#define PCB_MAX_VIAS        2048
#define PCB_MAX_ZONES       512
#define PCB_MAX_PADS        64
#define PCB_MAX_POLY_PTS    256
#define PCB_MAX_LAYERS      64
#define PCB_MAX_PROP_LEN    KICAD_MAX_PROP_LEN   /* same value (256) */
#define PCB_JSON_BUF_SIZE   (1 << 20)
#define PCB_SVG_BUF_SIZE    (8 << 20)

/* ------------------------------------------------------------------ */
/* PCB internal types                                                   */
/* ------------------------------------------------------------------ */

typedef struct {
    int    id;
    char   name[PCB_MAX_PROP_LEN];
    char   color[16];
    int    visible;
} PcbLayer;

typedef struct {
    char   shape[32];
    double x, y;
    double w, h;
    int    layer_id;
    char   net[PCB_MAX_PROP_LEN];
    char   number[32];
} PcbPad;

typedef struct {
    char   reference[PCB_MAX_PROP_LEN];
    char   value[PCB_MAX_PROP_LEN];
    double x, y;
    double angle;
    int    layer_id;
    PcbPad pads[PCB_MAX_PADS];
    int    pad_count;
} PcbFootprint;

typedef struct {
    double x1, y1, x2, y2;
    double width;
    int    layer_id;
    char   net[PCB_MAX_PROP_LEN];
} PcbSegment;

typedef struct {
    double x, y;
    double size;
    int    layer_from;
    int    layer_to;
    char   net[PCB_MAX_PROP_LEN];
} PcbVia;

typedef struct {
    int    layer_id;
    char   net[PCB_MAX_PROP_LEN];
    double pts_x[PCB_MAX_POLY_PTS];
    double pts_y[PCB_MAX_POLY_PTS];
    int    pt_count;
} PcbZone;

typedef struct KicadPcb KicadPcb;
struct KicadPcb {
    char*        raw_content;
    size_t       raw_len;

    PcbLayer     layers[PCB_MAX_LAYERS];
    int          layer_count;

    PcbFootprint footprints[PCB_MAX_FOOTPRINTS];
    int          footprint_count;

    PcbSegment   segments[PCB_MAX_SEGMENTS];
    int          segment_count;

    PcbVia       vias[PCB_MAX_VIAS];
    int          via_count;

    PcbZone      zones[PCB_MAX_ZONES];
    int          zone_count;

    char*        layers_json;
    char*        footprints_json;
    char*        layer_svg[PCB_MAX_LAYERS];
    char*        drc_cache;
};
