/* kicad_bridge_swift.h — void* wrappers for Swift interop.
 * Swift cannot form UnsafeMutablePointer<KicadSch> because the struct is opaque.
 * These wrappers take/return void* (OpaquePointer in Swift). */
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Schematic */
void* kbs_sch_open(const char* path);
const char* kbs_sch_get_components_json(void* h);
const char* kbs_sch_render_svg(void* h);
int kbs_sch_close(void* h);
uint64_t kbs_sch_add_symbol(void* h, const char* lib_id, double x, double y);
uint64_t kbs_sch_add_wire(void* h, double x1, double y1, double x2, double y2);
uint64_t kbs_sch_add_label(void* h, const char* text, double x, double y);
int kbs_sch_move_item(void* h, uint64_t item_id, double dx, double dy);
int kbs_sch_delete_item(void* h, uint64_t item_id);
int kbs_sch_set_property(void* h, uint64_t item_id, const char* key, const char* value);
int kbs_sch_undo(void* h);
int kbs_sch_redo(void* h);
int kbs_sch_save(void* h, const char* path);
const char* kbs_sch_get_items_json(void* h);
const char* kbs_run_erc_json(void* h);

#ifdef __cplusplus
}
#endif
