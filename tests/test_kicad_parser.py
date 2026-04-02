"""Tests for KiCad S-expression parser."""
from pathlib import Path
import pytest
from gateway.kicad_parser import parse_schematic, SchematicContext, Component, Net

FIXTURE = Path(__file__).parent / "fixtures" / "simple.kicad_sch"

def test_parse_returns_schematic_context():
    result = parse_schematic(FIXTURE.read_text())
    assert isinstance(result, SchematicContext)

def test_parse_extracts_components():
    result = parse_schematic(FIXTURE.read_text())
    assert len(result.components) == 2
    refs = [c.reference for c in result.components]
    assert "R1" in refs
    assert "C1" in refs

def test_parse_component_details():
    result = parse_schematic(FIXTURE.read_text())
    r1 = next(c for c in result.components if c.reference == "R1")
    assert r1.value == "10k"
    assert "0402" in r1.footprint
    assert r1.lib_id == "Device:R"

def test_parse_extracts_power_labels():
    result = parse_schematic(FIXTURE.read_text())
    assert "VCC" in result.power_labels
    assert "GND" in result.power_labels

def test_parse_extracts_nets():
    result = parse_schematic(FIXTURE.read_text())
    net_names = [n.name for n in result.nets]
    assert "NET1" in net_names

def test_parse_extracts_sheets():
    result = parse_schematic(FIXTURE.read_text())
    assert "PowerSupply" in result.sheets

def test_parse_empty_schematic():
    content = '(kicad_sch (version 20231120) (generator "eeschema"))'
    result = parse_schematic(content)
    assert result.components == []
    assert result.nets == []
    assert result.power_labels == []
    assert result.sheets == []
