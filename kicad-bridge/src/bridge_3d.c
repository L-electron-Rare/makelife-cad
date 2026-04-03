/*
 * bridge_3d.c — 3D JSON export for the PCB 3D viewer (Phase 6)
 * Pure C11, no external dependencies.
 * Reuses KicadPcb internal type from kicad_bridge_internal.h.
 */

#include "kicad_bridge.h"
#include "kicad_bridge_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <float.h>
#include <math.h>

#define PCB_3D_JSON_BUF_SIZE (2 << 20)  /* 2 MB */

/* Classify component type from reference prefix */
static const char* classify_ref(const char* ref) {
    if (!ref || !ref[0]) return "other";
    char c = ref[0];
    if (c == 'U')                         return "ic";
    if (c == 'R' || c == 'C' || c == 'L') return "passive";
    if (c == 'J' || c == 'P')             return "connector";
    if (strncmp(ref, "IC",  2) == 0)      return "ic";
    if (strncmp(ref, "CN",  2) == 0)      return "connector";
    return "other";
}

/* Component height by type */
static double height_for_type(const char* type) {
    if (strcmp(type, "ic")        == 0) return 1.5;
    if (strcmp(type, "passive")   == 0) return 0.8;
    if (strcmp(type, "connector") == 0) return 3.0;
    return 1.0;
}

const char* kicad_pcb_export_3d_json(kicad_pcb_handle h) {
    KicadPcb* b = (KicadPcb*)h;
    if (!b) return NULL;

    /* Allocate or reuse buffer */
    if (!b->json_3d) {
        b->json_3d = (char*)malloc(PCB_3D_JSON_BUF_SIZE);
        if (!b->json_3d) return NULL;
    }

    /* --- Board bounding box from Edge.Cuts segments (layer_id==44) --- */
    double bx_min = DBL_MAX, bx_max = -DBL_MAX;
    double by_min = DBL_MAX, by_max = -DBL_MAX;

    for (int i = 0; i < b->segment_count; i++) {
        if (b->segments[i].layer_id != 44) continue;
        double x1 = b->segments[i].x1, y1 = b->segments[i].y1;
        double x2 = b->segments[i].x2, y2 = b->segments[i].y2;
        if (x1 < bx_min) bx_min = x1; if (x1 > bx_max) bx_max = x1;
        if (x2 < bx_min) bx_min = x2; if (x2 > bx_max) bx_max = x2;
        if (y1 < by_min) by_min = y1; if (y1 > by_max) by_max = y1;
        if (y2 < by_min) by_min = y2; if (y2 > by_max) by_max = y2;
    }

    /* Fallback: bounding box from footprints */
    if (bx_min == DBL_MAX) {
        for (int i = 0; i < b->footprint_count; i++) {
            double x = b->footprints[i].x, y = b->footprints[i].y;
            if (x < bx_min) bx_min = x; if (x > bx_max) bx_max = x;
            if (y < by_min) by_min = y; if (y > by_max) by_max = y;
        }
        if (bx_min == DBL_MAX) { bx_min = 0; bx_max = 100; by_min = 0; by_max = 80; }
    }

    double board_w = bx_max - bx_min;
    double board_h = by_max - by_min;

    /* --- Build JSON --- */
    char* p   = b->json_3d;
    int   rem = PCB_3D_JSON_BUF_SIZE;
    int   n;

    n = snprintf(p, rem,
        "{\n"
        "  \"board\": {\n"
        "    \"width_mm\": %.3f,\n"
        "    \"height_mm\": %.3f,\n"
        "    \"thickness_mm\": 1.6,\n"
        "    \"outline\": ["
        "[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f]"
        "]\n"
        "  },\n",
        board_w, board_h,
        bx_min, by_min,  bx_max, by_min,
        bx_max, by_max,  bx_min, by_max);
    p += n; rem -= n;

    /* Layer stack (hardcoded for Phase 6) */
    n = snprintf(p, rem,
        "  \"layers\": [\n"
        "    {\"id\":0,  \"name\":\"F.Cu\",    \"z_mm\":1.6,   \"color\":\"#ff5555\"},\n"
        "    {\"id\":35, \"name\":\"F.SilkS\", \"z_mm\":1.65,  \"color\":\"#ffffff\"},\n"
        "    {\"id\":33, \"name\":\"F.Mask\",  \"z_mm\":1.62,  \"color\":\"#224422\"},\n"
        "    {\"id\":34, \"name\":\"B.Mask\",  \"z_mm\":-0.02, \"color\":\"#224422\"},\n"
        "    {\"id\":36, \"name\":\"B.SilkS\", \"z_mm\":-0.05, \"color\":\"#cccccc\"},\n"
        "    {\"id\":31, \"name\":\"B.Cu\",    \"z_mm\":0.0,   \"color\":\"#5599ff\"}\n"
        "  ],\n"
        "  \"components\": [\n");
    p += n; rem -= n;

    /* Components */
    for (int i = 0; i < b->footprint_count; i++) {
        PcbFootprint* fp = &b->footprints[i];

        /* Bounding box from pads */
        double px_min = DBL_MAX, px_max = -DBL_MAX;
        double py_min = DBL_MAX, py_max = -DBL_MAX;
        for (int j = 0; j < fp->pad_count; j++) {
            double lx = fp->pads[j].x, ly = fp->pads[j].y;
            double hw = fp->pads[j].w / 2.0, hh = fp->pads[j].h / 2.0;
            if (lx - hw < px_min) px_min = lx - hw;
            if (lx + hw > px_max) px_max = lx + hw;
            if (ly - hh < py_min) py_min = ly - hh;
            if (ly + hh > py_max) py_max = ly + hh;
        }
        double bbox_w = (px_min == DBL_MAX) ? 2.54 : (px_max - px_min) * 1.2;
        double bbox_h = (py_min == DBL_MAX) ? 2.54 : (py_max - py_min) * 1.2;

        const char* type   = classify_ref(fp->reference);
        double      height = height_for_type(type);
        const char* sep    = (i < b->footprint_count - 1) ? "," : "";

        n = snprintf(p, rem,
            "    {\"reference\":\"%s\",\"value\":\"%s\","
            "\"x_mm\":%.3f,\"y_mm\":%.3f,\"angle_deg\":%.1f,"
            "\"layer\":\"%s\","
            "\"bbox_w\":%.3f,\"bbox_h\":%.3f,\"height_mm\":%.2f,"
            "\"type\":\"%s\"}%s\n",
            fp->reference, fp->value,
            fp->x, fp->y, fp->angle,
            fp->layer_id == 31 ? "B.Cu" : "F.Cu",
            bbox_w, bbox_h, height,
            type, sep);
        p += n; rem -= n;
        if (rem < 512) break;  /* safety — buffer nearly full */
    }

    snprintf(p, rem, "  ]\n}\n");
    return b->json_3d;
}
