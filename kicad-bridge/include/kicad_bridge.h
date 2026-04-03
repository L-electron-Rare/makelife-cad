#pragma once

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
