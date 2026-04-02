"""KiCad .kicad_sch S-expression parser — extract components, nets, labels."""
from __future__ import annotations
import re
from dataclasses import dataclass, field


@dataclass
class Component:
    reference: str
    value: str
    footprint: str
    lib_id: str
    pins: list[str] = field(default_factory=list)


@dataclass
class Net:
    name: str
    connected_pins: list[str] = field(default_factory=list)


@dataclass
class SchematicContext:
    components: list[Component] = field(default_factory=list)
    nets: list[Net] = field(default_factory=list)
    power_labels: list[str] = field(default_factory=list)
    sheets: list[str] = field(default_factory=list)


def _extract_property(block: str, prop_name: str) -> str:
    pattern = rf'\(property\s+"{prop_name}"\s+"([^"]*)"'
    match = re.search(pattern, block)
    return match.group(1) if match else ""


def _extract_lib_id(block: str) -> str:
    match = re.search(r'\(lib_id\s+"([^"]*)"', block)
    return match.group(1) if match else ""


def _extract_pins(block: str) -> list[str]:
    return re.findall(r'\(pin\s+"(\d+)"', block)


def _find_top_level_blocks(content: str, block_type: str) -> list[str]:
    blocks = []
    cleaned = re.sub(r'\(lib_symbols\s.*?\n  \)', '', content, flags=re.DOTALL)
    i = 0
    prefix = f"({block_type} "
    while i < len(cleaned):
        start = cleaned.find(prefix, i)
        if start == -1:
            break
        depth = 0
        j = start
        while j < len(cleaned):
            if cleaned[j] == '(':
                depth += 1
            elif cleaned[j] == ')':
                depth -= 1
                if depth == 0:
                    blocks.append(cleaned[start:j + 1])
                    break
            j += 1
        i = j + 1
    return blocks


def parse_schematic(content: str) -> SchematicContext:
    ctx = SchematicContext()
    for block in _find_top_level_blocks(content, "symbol"):
        lib_id = _extract_lib_id(block)
        if not lib_id:
            continue
        ref = _extract_property(block, "Reference")
        value = _extract_property(block, "Value")
        footprint = _extract_property(block, "Footprint")
        pins = _extract_pins(block)
        if ref:
            ctx.components.append(Component(
                reference=ref,
                value=value,
                footprint=footprint,
                lib_id=lib_id,
                pins=pins,
            ))
    for block in _find_top_level_blocks(content, "label"):
        match = re.search(r'\(label\s+"([^"]*)"', block)
        if match:
            label = match.group(1)
            if (label.upper() in ("VCC", "VDD", "GND", "VSS", "3V3", "5V", "12V")
                    or label.upper().startswith("V")):
                ctx.power_labels.append(label)
    for block in _find_top_level_blocks(content, "global_label"):
        match = re.search(r'\(global_label\s+"([^"]*)"', block)
        if match:
            ctx.nets.append(Net(name=match.group(1)))
    for block in _find_top_level_blocks(content, "sheet"):
        match = re.search(r'\(property\s+"Sheetname"\s+"([^"]*)"', block)
        if match:
            ctx.sheets.append(match.group(1))
    return ctx
