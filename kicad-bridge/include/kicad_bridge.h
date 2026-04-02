#pragma once

#ifdef __cplusplus
extern "C" {
#endif

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

#ifdef __cplusplus
}
#endif
