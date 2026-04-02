"""Prompt templates for AI-assisted CAD endpoints."""
from __future__ import annotations
import json
from gateway.kicad_parser import SchematicContext

def build_component_prompt(
    description: str,
    constraints: dict | None = None,
    project_context: SchematicContext | None = None,
) -> list[dict]:
    system = (
        "You are an expert electronic component engineer. "
        "Given a component description and constraints, suggest 2-5 suitable components. "
        "Return ONLY a JSON array where each element has: "
        '"name", "manufacturer", "package", "key_specs" (dict), "reason" (string). '
        "No markdown, no explanation outside the JSON."
    )
    user_parts = [f"I need: {description}"]
    if constraints:
        specs = ", ".join(f"{k}: {v}" for k, v in constraints.items())
        user_parts.append(f"Constraints: {specs}")
    if project_context and project_context.components:
        existing = [f"{c.reference} ({c.value}, {c.footprint})" for c in project_context.components[:20]]
        user_parts.append(f"Existing components in project (for consistency): {', '.join(existing)}")
        footprints = list({c.footprint.split(':')[-1] for c in project_context.components if c.footprint})
        if footprints:
            user_parts.append(f"Preferred footprint families: {', '.join(footprints[:10])}")
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": "\n".join(user_parts)},
    ]

def build_review_prompt(
    schematic: SchematicContext,
    focus: list[str] | None = None,
) -> list[dict]:
    system = (
        "You are an expert schematic reviewer for electronic design. "
        "Analyze the following KiCad schematic data and identify design issues. "
        "Return ONLY a JSON array where each element has: "
        '"severity" ("high", "medium", "low"), "category", "component", "message", "suggestion". '
        "Categories: power, decoupling, esd, connectivity, values, thermal. "
        "No markdown, no explanation outside the JSON."
    )
    components_text = "\n".join(
        f"  {c.reference}: {c.value} ({c.footprint}) [lib: {c.lib_id}]"
        for c in schematic.components
    )
    nets_text = "\n".join(f"  {n.name}" for n in schematic.nets) if schematic.nets else "  (none extracted)"
    power_text = ", ".join(schematic.power_labels) if schematic.power_labels else "(none)"
    sheets_text = ", ".join(schematic.sheets) if schematic.sheets else "(single sheet)"
    user_parts = [
        "Schematic data:",
        f"Components ({len(schematic.components)}):",
        components_text,
        f"Nets: {nets_text}",
        f"Power rails: {power_text}",
        f"Sheets: {sheets_text}",
    ]
    if focus:
        user_parts.append(f"Focus analysis on: {', '.join(focus)}")
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": "\n".join(user_parts)},
    ]
