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
#define KICAD_MAX_JUNCTIONS  2048
#define KICAD_MAX_NOCONNECTS 512
#define KICAD_MAX_BUSES      1024
#define KICAD_MAX_SHEETS     64
#define KICAD_MAX_TEXTS      256
#define KICAD_MAX_GFX        512
#define KICAD_JSON_BUF_SIZE  (1 << 20)  /* 1 MB */
#define KICAD_SVG_BUF_SIZE   (16 << 20) /* 16 MB — full symbol geometry */

/* Library symbol geometry limits */
#define LIB_MAX_SYMBOLS      512
#define LIB_MAX_DRAW_ITEMS   128
#define LIB_MAX_POLY_POINTS  64
#define LIB_MAX_LIB_PINS     64

/* ------------------------------------------------------------------ */
/* Schematic internal types                                             */
/* ------------------------------------------------------------------ */

/* ------------------------------------------------------------------ */
/* Library symbol drawing primitives                                    */
/* ------------------------------------------------------------------ */

typedef enum {
    DRAW_RECT     = 0,
    DRAW_CIRCLE   = 1,
    DRAW_ARC      = 2,
    DRAW_POLYLINE = 3,
} DrawPrimType;

typedef struct {
    DrawPrimType type;
    /* Rect: (x1,y1)=(start), (x2,y2)=(end) */
    /* Circle: (cx,cy)=center, r=radius */
    /* Arc: (cx,cy)=center, r=radius, start_angle..end_angle */
    /* Polyline: pts array */
    double x1, y1, x2, y2;
    double cx, cy, r;
    double start_angle, end_angle;
    double pts_x[LIB_MAX_POLY_POINTS];
    double pts_y[LIB_MAX_POLY_POINTS];
    int    pt_count;
    double stroke_width;
    int    filled;          /* 0=none, 1=outline, 2=background */
} DrawPrimitive;

typedef struct {
    double x, y;            /* relative to symbol origin */
    double length;
    double angle;           /* 0, 90, 180, 270 */
    char   name[64];
    char   number[16];
} LibPin;

typedef struct {
    char           name[KICAD_MAX_PROP_LEN];  /* e.g. "Device:R" */
    DrawPrimitive  draws[LIB_MAX_DRAW_ITEMS];
    int            draw_count;
    LibPin         pins[LIB_MAX_LIB_PINS];
    int            pin_count;
    double         pin_name_offset;
    int            hide_pin_names;
    int            hide_pin_numbers;
} LibSymbol;

/* ------------------------------------------------------------------ */
/* Schematic element types                                              */
/* ------------------------------------------------------------------ */

typedef struct {
    char reference[KICAD_MAX_PROP_LEN];
    char value[KICAD_MAX_PROP_LEN];
    char footprint[KICAD_MAX_PROP_LEN];
    char lib_id[KICAD_MAX_PROP_LEN];
    char pins[KICAD_MAX_PINS][16];
    int  pin_count;
    double x, y;
    double angle;           /* rotation in degrees (0, 90, 180, 270) */
    int    mirror_x;        /* 1 if mirrored on X axis */
    int    mirror_y;        /* 1 if mirrored on Y axis */
} KicadComponent;

typedef struct {
    double x1, y1, x2, y2;
} KicadWire;

typedef struct {
    char text[KICAD_MAX_PROP_LEN];
    double x, y;
    int is_global;
} KicadLabel;

typedef struct {
    double x, y;
} KicadJunction;

typedef struct {
    double x, y;
} KicadNoConnect;

/* Bus segments: (bus (pts (xy x1 y1) (xy x2 y2))) */
typedef struct {
    double x1, y1, x2, y2;
} KicadBus;

/* Hierarchical sheet: (sheet (at x y) (size w h) (fields...) (pin...)) */
typedef struct {
    double x, y, w, h;
    char   name[KICAD_MAX_PROP_LEN];       /* "Sheet name" property */
    char   filename[KICAD_MAX_PROP_LEN];   /* "Sheet file" property */
} KicadSheet;

/* Title block: (title_block (title "...") (date "...") (rev "...") (company "...")) */
typedef struct {
    char title[KICAD_MAX_PROP_LEN];
    char date[64];
    char rev[64];
    char company[KICAD_MAX_PROP_LEN];
} KicadTitleBlock;

/* Standalone text annotation: (text "content" (at x y angle) (effects ...)) */
typedef struct {
    char   text[KICAD_MAX_PROP_LEN];
    double x, y;
    double angle;
    double font_size;        /* from (effects (font (size h w))) */
} KicadText;

/* Standalone graphics: (rectangle ...), (polyline ...), (circle ...) at top level */
typedef struct {
    DrawPrimType type;
    double x1, y1, x2, y2;          /* rect start/end or line endpoints */
    double cx, cy, r;                /* circle */
    double pts_x[LIB_MAX_POLY_POINTS];
    double pts_y[LIB_MAX_POLY_POINTS];
    int    pt_count;
    double stroke_width;
    char   stroke_color[16];         /* optional color override */
    int    filled;
} KicadGraphic;

/* Paper size */
typedef struct {
    char   name[16];    /* "A4", "A3", "Letter", etc. */
    double w, h;        /* dimensions in mils */
} KicadPaper;

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

    KicadJunction  junctions[KICAD_MAX_JUNCTIONS];
    int            junction_count;

    KicadNoConnect noconnects[KICAD_MAX_NOCONNECTS];
    int            noconnect_count;

    KicadBus       buses[KICAD_MAX_BUSES];
    int            bus_count;

    KicadSheet     sheets[KICAD_MAX_SHEETS];
    int            sheet_count;

    KicadText      texts[KICAD_MAX_TEXTS];
    int            text_count;

    KicadGraphic   graphics[KICAD_MAX_GFX];
    int            graphic_count;

    KicadTitleBlock title_block;
    int             has_title_block;

    KicadPaper     paper;

    /* Library symbol definitions (parsed from lib_symbols block) */
    LibSymbol*     lib_symbols;      /* heap-allocated array */
    int            lib_symbol_count;

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
#ifndef PCB_MAX_PROP_LEN
#define PCB_MAX_PROP_LEN    KICAD_MAX_PROP_LEN   /* same value (256) */
#endif
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
    char*        json_3d;      /* 3D export JSON (Phase 6) */
};
