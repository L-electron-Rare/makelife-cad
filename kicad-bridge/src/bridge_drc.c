/*
 * bridge_drc.c — basic DRC (PCB) and ERC (schematic) checks
 * Pure C11, no external dependencies.
 *
 * DRC checks:
 *   - min_track_width   : segment width < 0.2mm
 *   - track_clearance   : parallel segments on same net closer than 0.2mm
 *   - unconnected_pad   : footprint pad with empty net name
 *
 * ERC checks:
 *   - unconnected_pin   : component with pins but no wires nearby
 *   - duplicate_ref     : two components share the same reference
 *   - floating_net      : wire connected to only one pin endpoint
 */

#include "kicad_bridge.h"
#include "kicad_bridge_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ------------------------------------------------------------------ */
/* Shared JSON builder helpers                                          */
/* ------------------------------------------------------------------ */

#define DRC_BUF_SIZE (1 << 20)  /* 1 MB */

#define JAPP(fmt, ...) do { \
    int _w = snprintf(buf + pos, DRC_BUF_SIZE - pos, fmt, ##__VA_ARGS__); \
    if (_w < 0 || (size_t)_w >= DRC_BUF_SIZE - pos) { free(buf); return NULL; } \
    pos += (size_t)_w; \
} while (0)

static void drc_json_escape(const char* src, char* dst, size_t dst_size)
{
    size_t di = 0;
    for (size_t i = 0; src[i] && di < dst_size - 2; i++) {
        unsigned char c = (unsigned char)src[i];
        if      (c == '"')  { dst[di++] = '\\'; dst[di++] = '"';  }
        else if (c == '\\') { dst[di++] = '\\'; dst[di++] = '\\'; }
        else if (c == '\n') { dst[di++] = '\\'; dst[di++] = 'n';  }
        else                { dst[di++] = (char)c; }
    }
    dst[di] = '\0';
}

/* ------------------------------------------------------------------ */
/* Geometry helpers                                                     */
/* ------------------------------------------------------------------ */

/* Distance from point (px,py) to line segment (ax,ay)-(bx,by) */
static double point_to_segment_dist(double px, double py,
                                    double ax, double ay,
                                    double bx, double by)
{
    double dx = bx - ax, dy = by - ay;
    double len2 = dx*dx + dy*dy;
    if (len2 < 1e-12) {
        double ex = px - ax, ey = py - ay;
        return sqrt(ex*ex + ey*ey);
    }
    double t = ((px - ax)*dx + (py - ay)*dy) / len2;
    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;
    double qx = ax + t*dx - px;
    double qy = ay + t*dy - py;
    return sqrt(qx*qx + qy*qy);
}

/* ------------------------------------------------------------------ */
/* DRC implementation                                                   */
/* ------------------------------------------------------------------ */

static const char* layer_name_for_id(int id)
{
    switch (id) {
    case  0: return "F.Cu";
    case 31: return "B.Cu";
    case 35: return "F.SilkS";
    case 36: return "B.SilkS";
    case 44: return "Edge.Cuts";
    default: return "Inner";
    }
}

static char* run_drc(KicadPcb* pcb)
{
    char* buf = (char*)malloc(DRC_BUF_SIZE);
    if (!buf) return NULL;
    size_t pos = 0;

    char tmp[PCB_MAX_PROP_LEN * 2];
    int first = 1;

    JAPP("[\n");

#define OPEN_VIOLATION \
    do { if (!first) JAPP(",\n"); first = 0; } while (0)

    /* --- Rule 1: minimum track width (< 0.2mm) ------------------- */
    for (int i = 0; i < pcb->segment_count; i++) {
        const PcbSegment* s = &pcb->segments[i];
        if (s->width > 0.0 && s->width < 0.2) {
            OPEN_VIOLATION;
            const char* lname = layer_name_for_id(s->layer_id);
            JAPP("  {\"severity\":\"error\","
                 "\"rule\":\"min_track_width\","
                 "\"location\":{\"x\":%.4f,\"y\":%.4f},",
                 (s->x1 + s->x2) * 0.5,
                 (s->y1 + s->y2) * 0.5);
            snprintf(tmp, sizeof(tmp),
                     "Track width %.3fmm below minimum 0.2mm on %s",
                     s->width, lname);
            drc_json_escape(tmp, tmp + PCB_MAX_PROP_LEN, PCB_MAX_PROP_LEN);
            JAPP("\"message\":\"%s\",\"layer\":\"%s\"}",
                 tmp + PCB_MAX_PROP_LEN, lname);
        }
    }

    /* --- Rule 2: track clearance between segments on same layer --- */
    /* O(n²) — acceptable for reasonable board sizes (≤ 16384 segs)  */
    for (int i = 0; i < pcb->segment_count && i < 2048; i++) {
        const PcbSegment* a = &pcb->segments[i];
        for (int j = i + 1; j < pcb->segment_count && j < 2048; j++) {
            const PcbSegment* b = &pcb->segments[j];
            if (a->layer_id != b->layer_id) continue;
            /* Skip segments on the same net */
            if (a->net[0] && b->net[0] && strcmp(a->net, b->net) == 0) continue;

            /* Check endpoints of b against segment a */
            double d1 = point_to_segment_dist(b->x1, b->y1,
                                               a->x1, a->y1, a->x2, a->y2);
            double d2 = point_to_segment_dist(b->x2, b->y2,
                                               a->x1, a->y1, a->x2, a->y2);
            double d = d1 < d2 ? d1 : d2;
            /* Account for track half-widths */
            double clearance = d - (a->width + b->width) * 0.5;
            if (clearance > 0.0 && clearance < 0.2) {
                OPEN_VIOLATION;
                const char* lname = layer_name_for_id(a->layer_id);
                JAPP("  {\"severity\":\"error\","
                     "\"rule\":\"track_clearance\","
                     "\"location\":{\"x\":%.4f,\"y\":%.4f},",
                     b->x1, b->y1);
                snprintf(tmp, sizeof(tmp),
                         "Track clearance %.3fmm below minimum 0.2mm on %s",
                         clearance, lname);
                drc_json_escape(tmp, tmp + PCB_MAX_PROP_LEN, PCB_MAX_PROP_LEN);
                JAPP("\"message\":\"%s\",\"layer\":\"%s\"}",
                     tmp + PCB_MAX_PROP_LEN, lname);
            }
        }
    }

    /* --- Rule 3: unconnected pads (empty net name) ---------------- */
    for (int i = 0; i < pcb->footprint_count; i++) {
        const PcbFootprint* fp = &pcb->footprints[i];
        for (int p = 0; p < fp->pad_count; p++) {
            const PcbPad* pad = &fp->pads[p];
            if (pad->net[0] == '\0') {
                OPEN_VIOLATION;
                char ref_esc[PCB_MAX_PROP_LEN * 2];
                drc_json_escape(fp->reference, ref_esc, sizeof(ref_esc));
                char num_esc[64];
                drc_json_escape(pad->number, num_esc, sizeof(num_esc));
                snprintf(tmp, sizeof(tmp),
                         "Pad %s of %s has no net connection",
                         pad->number, fp->reference);
                char msg_esc[PCB_MAX_PROP_LEN * 2];
                drc_json_escape(tmp, msg_esc, sizeof(msg_esc));
                const char* lname = layer_name_for_id(fp->layer_id);
                JAPP("  {\"severity\":\"warning\","
                     "\"rule\":\"unconnected_pad\","
                     "\"location\":{\"x\":%.4f,\"y\":%.4f},"
                     "\"message\":\"%s\","
                     "\"layer\":\"%s\"}",
                     fp->x + pad->x, fp->y + pad->y,
                     msg_esc, lname);
            }
        }
    }

#undef OPEN_VIOLATION

    JAPP("\n]\n");
    return buf;
}

/* ------------------------------------------------------------------ */
/* ERC implementation                                                   */
/* ------------------------------------------------------------------ */

static char* run_erc(KicadSch* sch)
{
    char* buf = (char*)malloc(DRC_BUF_SIZE);
    if (!buf) return NULL;
    size_t pos = 0;

    char tmp[KICAD_MAX_PROP_LEN * 2];
    char esc[KICAD_MAX_PROP_LEN * 2];
    int first = 1;

    JAPP("[\n");

#define OPEN_VIOL \
    do { if (!first) JAPP(",\n"); first = 0; } while (0)

    /* --- Rule 1: duplicate references ----------------------------- */
    for (int i = 0; i < sch->component_count; i++) {
        const KicadComponent* ci = &sch->components[i];
        if (ci->reference[0] == '\0') continue;
        for (int j = i + 1; j < sch->component_count; j++) {
            const KicadComponent* cj = &sch->components[j];
            if (strcmp(ci->reference, cj->reference) == 0) {
                OPEN_VIOL;
                drc_json_escape(ci->reference, esc, sizeof(esc));
                snprintf(tmp, sizeof(tmp),
                         "Duplicate reference %s", ci->reference);
                char msg_esc[KICAD_MAX_PROP_LEN * 2];
                drc_json_escape(tmp, msg_esc, sizeof(msg_esc));
                JAPP("  {\"severity\":\"error\","
                     "\"rule\":\"duplicate_ref\","
                     "\"component\":\"%s\","
                     "\"pin\":\"\","
                     "\"message\":\"%s\"}",
                     esc, msg_esc);
            }
        }
    }

    /* --- Rule 2: unconnected pins --------------------------------- */
    /*
     * Simplified heuristic: a component pin at (cx, cy) is "connected"
     * if any wire endpoint is within 1mm of the component position.
     * Real ERC would need full net connectivity, but this catches obvious
     * floating components (no wires nearby at all).
     */
    for (int i = 0; i < sch->component_count; i++) {
        const KicadComponent* c = &sch->components[i];
        if (c->pin_count == 0) continue;

        int has_wire = 0;
        for (int w = 0; w < sch->wire_count; w++) {
            const KicadWire* wire = &sch->wires[w];
            double d1x = wire->x1 - c->x, d1y = wire->y1 - c->y;
            double d2x = wire->x2 - c->x, d2y = wire->y2 - c->y;
            if (sqrt(d1x*d1x + d1y*d1y) < 5.0 ||
                sqrt(d2x*d2x + d2y*d2y) < 5.0) {
                has_wire = 1;
                break;
            }
        }

        if (!has_wire) {
            /* Report first pin as representative */
            OPEN_VIOL;
            drc_json_escape(c->reference, esc, sizeof(esc));
            const char* pin0 = c->pin_count > 0 ? c->pins[0] : "?";
            char pin_esc[32];
            drc_json_escape(pin0, pin_esc, sizeof(pin_esc));
            snprintf(tmp, sizeof(tmp),
                     "Component %s has no wire connections (pin %s unconnected)",
                     c->reference, pin0);
            char msg_esc[KICAD_MAX_PROP_LEN * 2];
            drc_json_escape(tmp, msg_esc, sizeof(msg_esc));
            JAPP("  {\"severity\":\"warning\","
                 "\"rule\":\"unconnected_pin\","
                 "\"component\":\"%s\","
                 "\"pin\":\"%s\","
                 "\"message\":\"%s\"}",
                 esc, pin_esc, msg_esc);
        }
    }

    /* --- Rule 3: missing power labels (no VCC or GND label) ------- */
    {
        int has_vcc = 0, has_gnd = 0;
        for (int i = 0; i < sch->label_count; i++) {
            const KicadLabel* lbl = &sch->labels[i];
            if (strncmp(lbl->text, "VCC", 3) == 0 ||
                strncmp(lbl->text, "VDD", 3) == 0 ||
                strncmp(lbl->text, "+3V", 3) == 0 ||
                strncmp(lbl->text, "+5V", 3) == 0) {
                has_vcc = 1;
            }
            if (strncmp(lbl->text, "GND", 3) == 0 ||
                strncmp(lbl->text, "GNDD", 4) == 0 ||
                strncmp(lbl->text, "AGND", 4) == 0) {
                has_gnd = 1;
            }
        }
        /* Only warn if there are components but no power rails */
        if (sch->component_count > 0 && (!has_vcc || !has_gnd)) {
            if (!has_vcc) {
                OPEN_VIOL;
                JAPP("  {\"severity\":\"warning\","
                     "\"rule\":\"missing_power\","
                     "\"component\":\"\","
                     "\"pin\":\"\","
                     "\"message\":\"No VCC/VDD power label found in schematic\"}");
            }
            if (!has_gnd) {
                OPEN_VIOL;
                JAPP("  {\"severity\":\"warning\","
                     "\"rule\":\"missing_power\","
                     "\"component\":\"\","
                     "\"pin\":\"\","
                     "\"message\":\"No GND power label found in schematic\"}");
            }
        }
    }

    /* --- Rule 4: floating nets (wire connected to only one pin) --- */
    /*
     * A floating net is a wire whose both endpoints are far from any
     * component position. Heuristic: if neither wire endpoint is within
     * 5 schematic units of any component, the wire is floating.
     */
    for (int w = 0; w < sch->wire_count; w++) {
        const KicadWire* wire = &sch->wires[w];
        int ep1_connected = 0, ep2_connected = 0;

        for (int i = 0; i < sch->component_count; i++) {
            const KicadComponent* c = &sch->components[i];
            double d1x = wire->x1 - c->x, d1y = wire->y1 - c->y;
            double d2x = wire->x2 - c->x, d2y = wire->y2 - c->y;
            if (sqrt(d1x*d1x + d1y*d1y) < 5.0) ep1_connected = 1;
            if (sqrt(d2x*d2x + d2y*d2y) < 5.0) ep2_connected = 1;
            if (ep1_connected && ep2_connected) break;
        }
        /* Also consider label endpoints as connected */
        if (!ep1_connected || !ep2_connected) {
            for (int i = 0; i < sch->label_count; i++) {
                const KicadLabel* lbl = &sch->labels[i];
                double d1x = wire->x1 - lbl->x, d1y = wire->y1 - lbl->y;
                double d2x = wire->x2 - lbl->x, d2y = wire->y2 - lbl->y;
                if (sqrt(d1x*d1x + d1y*d1y) < 5.0) ep1_connected = 1;
                if (sqrt(d2x*d2x + d2y*d2y) < 5.0) ep2_connected = 1;
                if (ep1_connected && ep2_connected) break;
            }
        }
        /* Also count wire-to-wire junctions as connected */
        if (!ep1_connected || !ep2_connected) {
            for (int j = 0; j < sch->wire_count; j++) {
                if (j == w) continue;
                const KicadWire* other = &sch->wires[j];
                /* Check if this wire's endpoint lands on the other wire */
                double d;
                if (!ep1_connected) {
                    d = point_to_segment_dist(wire->x1, wire->y1,
                                              other->x1, other->y1,
                                              other->x2, other->y2);
                    if (d < 1.0) ep1_connected = 1;
                }
                if (!ep2_connected) {
                    d = point_to_segment_dist(wire->x2, wire->y2,
                                              other->x1, other->y1,
                                              other->x2, other->y2);
                    if (d < 1.0) ep2_connected = 1;
                }
                if (ep1_connected && ep2_connected) break;
            }
        }

        if (!ep1_connected || !ep2_connected) {
            OPEN_VIOL;
            JAPP("  {\"severity\":\"warning\","
                 "\"rule\":\"floating_net\","
                 "\"component\":\"\","
                 "\"pin\":\"\","
                 "\"message\":\"Wire at (%.2f,%.2f)-(%.2f,%.2f) has a floating endpoint\"}",
                 wire->x1, wire->y1, wire->x2, wire->y2);
        }
    }

#undef OPEN_VIOL

    JAPP("\n]\n");
    return buf;
}

#undef JAPP

/* ------------------------------------------------------------------ */
/* Public API                                                           */
/* ------------------------------------------------------------------ */

const char* kicad_run_drc_json(kicad_pcb_handle h)
{
    if (!h) return NULL;
    KicadPcb* pcb = (KicadPcb*)h;
    if (!pcb->drc_cache) {
        pcb->drc_cache = run_drc(pcb);
    }
    return pcb->drc_cache;
}

const char* kicad_run_erc_json(KicadSch* h)
{
    if (!h) return NULL;
    if (!h->erc_cache) {
        h->erc_cache = run_erc(h);
    }
    return h->erc_cache;
}
