#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Shared constants */
#define PCB_MAX_PROP_LEN 256

/* ------------------------------------------------------------------ */
/* Schematic API                                                        */
/* ------------------------------------------------------------------ */

/* Opaque handle to a parsed schematic */
typedef struct KicadSch KicadSch;

/* Open and parse a .kicad_sch file.
 * Returns NULL on failure (path not found, parse error).
 * Caller must call kicad_sch_close() when done. */
KicadSch* kicad_sch_open(const char* path);

/* Return JSON array of components:
 * [{"reference":"R1","value":"10k","footprint":"...","lib_id":"...","pins":["1","2"],"x":0.0,"y":0.0}, ...]
 * Returned pointer is owned by the handle — valid until kicad_sch_close().
 * Returns NULL on error. */
const char* kicad_sch_get_components_json(KicadSch* h);

/* Return SVG string for the full schematic.
 * Returned pointer is owned by the handle — valid until kicad_sch_close().
 * Returns NULL on error. */
const char* kicad_sch_render_svg(KicadSch* h);

/* Free resources. Always call this after use. Returns 0 on success. */
int kicad_sch_close(KicadSch* h);

/* ------------------------------------------------------------------ */
/* Schematic Edit API (Phase 4)                                        */
/* ------------------------------------------------------------------ */

/* Add a symbol from a library.
 * lib_id: "Device:R", "Device:C", etc.
 * x, y:   position in KiCad mils (1 mil = 0.0254 mm).
 * Returns the new item id (>0), or 0 on failure. */
uint64_t kicad_sch_add_symbol(KicadSch* h, const char* lib_id,
                              double x, double y);

/* Add a wire segment between two points.
 * Returns the new item id (>0), or 0 on failure. */
uint64_t kicad_sch_add_wire(KicadSch* h,
                            double x1, double y1,
                            double x2, double y2);

/* Add a net label at position (x, y).
 * Returns the new item id (>0), or 0 on failure. */
uint64_t kicad_sch_add_label(KicadSch* h, const char* text,
                             double x, double y);

/* Translate item by (dx, dy). Returns 0 on success, -1 if not found. */
int kicad_sch_move_item(KicadSch* h, uint64_t item_id,
                        double dx, double dy);

/* Soft-delete item. Returns 0 on success, -1 if not found. */
int kicad_sch_delete_item(KicadSch* h, uint64_t item_id);

/* Set a named property on an item (reference, value, footprint, or custom).
 * Returns 0 on success, -1 if item not found. */
int kicad_sch_set_property(KicadSch* h, uint64_t item_id,
                           const char* key, const char* value);

/* Undo last edit. Returns 0 if undone, -1 if stack empty. */
int kicad_sch_undo(KicadSch* h);

/* Redo last undone edit. Returns 0 if redone, -1 if stack empty. */
int kicad_sch_redo(KicadSch* h);

/* Save the schematic to path in KiCad S-expression format.
 * Returns 0 on success, -1 on I/O error. */
int kicad_sch_save(KicadSch* h, const char* path);

/* Return JSON array of all non-deleted items (symbols + wires + labels).
 * Pointer owned by handle — valid until next call to any edit function.
 * Returns NULL on error. */
const char* kicad_sch_get_items_json(KicadSch* h);

/* ------------------------------------------------------------------ */
/* PCB API                                                             */
/* ------------------------------------------------------------------ */

/* Opaque handle to a parsed PCB */
typedef void* kicad_pcb_handle;

/* Open and parse a .kicad_pcb file.
 * Returns NULL on failure (path not found, parse error).
 * Caller must call kicad_pcb_close() when done. */
kicad_pcb_handle kicad_pcb_open(const char* path);

/* Return JSON array of layers:
 * [{"id":0,"name":"F.Cu","color":"#ff5555","visible":true}, ...]
 * Returned pointer is owned by the handle. Returns NULL on error. */
const char* kicad_pcb_get_layers_json(kicad_pcb_handle h);

/* Return JSON array of footprints:
 * [{"reference":"R1","value":"10k","x":100.0,"y":50.0,"layer":"F.Cu"}, ...]
 * Returned pointer is owned by the handle. Returns NULL on error. */
const char* kicad_pcb_get_footprints_json(kicad_pcb_handle h);

/* Return SVG for the given copper/silkscreen layer.
 * layer_id: 0=F.Cu, 31=B.Cu, 35=F.SilkS, 36=B.SilkS, 44=Edge.Cuts, etc.
 * x, y, w, h_rect: viewport hint (unused in simple renderer — pass 0,0,0,0).
 * Returned pointer is owned by the handle. Returns NULL on error. */
const char* kicad_pcb_render_layer_svg(kicad_pcb_handle h, int layer_id,
                                       double x, double y,
                                       double w, double h_rect);

/* Free resources. Always call this after use. Returns 0 on success. */
int kicad_pcb_close(kicad_pcb_handle h);

/* ------------------------------------------------------------------ */
/* PCB Edit API (Phase 5)                                              */
/* ------------------------------------------------------------------ */

/* Place a footprint.  lib_id: "Resistor_SMD:R_0402". layer: "F.Cu"/"B.Cu".
 * Returns item_id > 0 on success, -1 on error. */
int kicad_pcb_add_footprint(kicad_pcb_handle h,
                             const char* lib_id,
                             double x, double y,
                             const char* layer);

/* Add a point-to-point track segment. width and coords in mm.
 * Returns item_id > 0 on success, -1 on error. */
int kicad_pcb_add_track(kicad_pcb_handle h,
                         double x1, double y1,
                         double x2, double y2,
                         double width,
                         const char* layer,
                         int net_id);

/* Add a via. size = outer diameter, drill = drill diameter, both in mm.
 * Returns item_id > 0 on success, -1 on error. */
int kicad_pcb_add_via(kicad_pcb_handle h,
                       double x, double y,
                       double size, double drill,
                       int net_id);

/* Add a copper pour zone. points_json: JSON array of {x,y} objects.
 * Returns item_id > 0 on success, -1 on error. */
int kicad_pcb_add_zone(kicad_pcb_handle h,
                        int net_id,
                        const char* layer,
                        const char* points_json);

/* Translate item by (dx, dy) in mm. No-op if item_id not found. */
void kicad_pcb_move_item(kicad_pcb_handle h, int item_id,
                          double dx, double dy);

/* Delete item. No-op if item_id not found. */
void kicad_pcb_delete_item(kicad_pcb_handle h, int item_id);

/* Undo / redo last edit operation. No-op if stack empty. */
void kicad_pcb_undo(kicad_pcb_handle h);
void kicad_pcb_redo(kicad_pcb_handle h);

/* Serialize board to a .kicad_pcb file.
 * Returns 0 on success, -1 on error (path invalid, write failed). */
int kicad_pcb_save(kicad_pcb_handle h, const char* path);

/* Import net assignments from a JSON netlist.
 * Returns 0 on success, -1 on error. */
int kicad_pcb_import_netlist(kicad_pcb_handle h, const char* netlist_json);

/* Return JSON describing the PCB in 3D-ready form.
 * Schema: { "board": { "width_mm", "height_mm", "thickness_mm", "outline" },
 *           "layers": [...], "components": [...] }
 * Returned pointer is owned by the handle — valid until kicad_pcb_close().
 * Returns NULL on error. */
const char* kicad_pcb_export_3d_json(kicad_pcb_handle h);

/* ------------------------------------------------------------------ */
/* DRC / ERC API                                                        */
/* ------------------------------------------------------------------ */

/* Run basic Design Rule Checks on a PCB.
 * Returns a JSON array of violation objects:
 * [{"severity":"error","rule":"min_track_width","location":{"x":..,"y":..},
 *   "message":"...","layer":"F.Cu"}, ...]
 * Returned pointer is owned by the handle — valid until kicad_pcb_close().
 * Returns NULL on error. */
const char* kicad_run_drc_json(kicad_pcb_handle h);

/* Run basic Electrical Rule Checks on a schematic.
 * Returns a JSON array of violation objects:
 * [{"severity":"warning","rule":"unconnected_pin","component":"U1","pin":"3",
 *   "message":"Pin 3 of U1 is not connected"}, ...]
 * Returned pointer is owned by the handle — valid until kicad_sch_close().
 * Returns NULL on error. */
const char* kicad_run_erc_json(KicadSch* h);

#ifdef __cplusplus
}
#endif
