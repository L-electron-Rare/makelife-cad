/* bridge_swift.c — thin void* wrappers for Swift interop. */
#include "kicad_bridge.h"
#include "kicad_bridge_swift.h"

void* kbs_sch_open(const char* path) { return kicad_sch_open(path); }
const char* kbs_sch_get_components_json(void* h) { return kicad_sch_get_components_json(h); }
const char* kbs_sch_render_svg(void* h) { return kicad_sch_render_svg(h); }
int kbs_sch_close(void* h) { return kicad_sch_close(h); }
uint64_t kbs_sch_add_symbol(void* h, const char* lib_id, double x, double y) { return kicad_sch_add_symbol(h, lib_id, x, y); }
uint64_t kbs_sch_add_wire(void* h, double x1, double y1, double x2, double y2) { return kicad_sch_add_wire(h, x1, y1, x2, y2); }
uint64_t kbs_sch_add_label(void* h, const char* text, double x, double y) { return kicad_sch_add_label(h, text, x, y); }
int kbs_sch_move_item(void* h, uint64_t item_id, double dx, double dy) { return kicad_sch_move_item(h, item_id, dx, dy); }
int kbs_sch_delete_item(void* h, uint64_t item_id) { return kicad_sch_delete_item(h, item_id); }
int kbs_sch_set_property(void* h, uint64_t item_id, const char* key, const char* value) { return kicad_sch_set_property(h, item_id, key, value); }
int kbs_sch_undo(void* h) { return kicad_sch_undo(h); }
int kbs_sch_redo(void* h) { return kicad_sch_redo(h); }
int kbs_sch_save(void* h, const char* path) { return kicad_sch_save(h, path); }
const char* kbs_sch_get_items_json(void* h) { return kicad_sch_get_items_json(h); }
const char* kbs_run_erc_json(void* h) { return kicad_run_erc_json(h); }
