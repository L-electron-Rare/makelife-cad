SHELL := /bin/bash

# Local paths (override at invocation, ex: make YIACAD_DIR=../yiacad yiacad-link)
PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
VENDOR_DIR := $(PROJECT_ROOT)/vendor
YIACAD_DIR ?= ../YiACAD
YIACAD_LINK := $(VENDOR_DIR)/yiacad

# Fork URLs (override with your own forks)
KICAD_FORK_URL ?= https://github.com/electron-rare/kicad-source-mirror.git
FREECAD_FORK_URL ?= https://github.com/electron-rare/FreeCAD.git
YIACAD_KICAD_PLUGIN_URL ?= https://github.com/electron-rare/yiacad-kicad-plugin.git

# Optional branches for fork tracking
KICAD_BRANCH ?= master
FREECAD_BRANCH ?= main
YIACAD_KICAD_PLUGIN_BRANCH ?= main

# Python / Node
PYTHON ?= python3
PIP ?= pip3
NPM ?= npm
VENV_DIR ?= .venv
PYTHON_VENV := $(PROJECT_ROOT)/$(VENV_DIR)/bin/python
PIP_VENV := $(PROJECT_ROOT)/$(VENV_DIR)/bin/pip

.PHONY: help doctor bootstrap-macos setup-python setup-web setup all \
	dev dev-gateway dev-web test build-web clean \
	yiacad-link yiacad-check \
	yiacad-plugin-clone yiacad-plugin-check yiacad-plugin-pull \
	kicad-clone-fork freecad-clone-fork forks-clone forks-pull \
	xcode-open xcode-project-skeleton

help:
	@echo "Targets disponibles:"
	@echo "  setup                 - Installe dependances Python et web"
	@echo "  bootstrap-macos       - Verifie outils macOS de base"
	@echo "  yiacad-link           - Lie ton repo Yiacad dans vendor/yiacad"
	@echo "  yiacad-check          - Verifie le lien Yiacad"
	@echo "  yiacad-plugin-clone   - Clone le plugin yiacad-kicad dans vendor/"
	@echo "  yiacad-plugin-check   - Verifie le plugin yiacad-kicad local"
	@echo "  forks-clone           - Clone KiCad et FreeCAD dans vendor/"
	@echo "  forks-pull            - Met a jour les forks locaux"
	@echo "  dev                   - Lance backend + frontend (2 terminaux requis)"
	@echo "  dev-gateway           - Lance FastAPI (port 8001)"
	@echo "  dev-web               - Lance Next.js web"
	@echo "  test                  - Lance tests Python"
	@echo "  build-web             - Build frontend"
	@echo "  xcode-project-skeleton- Cree un squelette Swift macOS"
	@echo "  xcode-open            - Ouvre le dossier app/macos dans Xcode"
	@echo ""
	@echo "Variables utiles:"
	@echo "  YIACAD_DIR=$(YIACAD_DIR)"
	@echo "  KICAD_FORK_URL=$(KICAD_FORK_URL)"
	@echo "  FREECAD_FORK_URL=$(FREECAD_FORK_URL)"
	@echo "  YIACAD_KICAD_PLUGIN_URL=$(YIACAD_KICAD_PLUGIN_URL)"

doctor:
	@echo "[doctor] make: $$(command -v make || echo absent)"
	@echo "[doctor] python: $$(command -v $(PYTHON) || echo absent)"
	@echo "[doctor] npm: $$(command -v $(NPM) || echo absent)"
	@echo "[doctor] git: $$(command -v git || echo absent)"
	@echo "[doctor] xcodebuild: $$(command -v xcodebuild || echo absent)"
	@echo "[doctor] xcode-select: $$(xcode-select -p 2>/dev/null || echo non configure)"
	@echo "[doctor] venv python: $$( [ -x '$(PYTHON_VENV)' ] && echo '$(PYTHON_VENV)' || echo absent )"

bootstrap-macos:
	@command -v xcodebuild >/dev/null || (echo "Xcode CLI Tools manquants" && exit 1)
	@command -v git >/dev/null || (echo "git manquant" && exit 1)
	@command -v $(PYTHON) >/dev/null || (echo "python3 manquant" && exit 1)
	@command -v $(NPM) >/dev/null || (echo "npm manquant" && exit 1)
	@echo "Environnement macOS OK"

setup-python:
	@if [ ! -x "$(PYTHON_VENV)" ]; then \
		cd "$(PROJECT_ROOT)" && $(PYTHON) -m venv "$(VENV_DIR)"; \
	fi
	cd "$(PROJECT_ROOT)" && "$(PIP_VENV)" install -e ".[dev]"

setup-web:
	cd "$(PROJECT_ROOT)" && $(NPM) install --prefix web

setup: setup-python setup-web

all: setup yiacad-check

yiacad-link:
	@mkdir -p "$(VENDOR_DIR)"
	@if [ ! -d "$(YIACAD_DIR)" ]; then \
		echo "YIACAD_DIR introuvable: $(YIACAD_DIR)"; \
		echo "Exemple: make YIACAD_DIR=../yiacad yiacad-link"; \
		exit 1; \
	fi
	@rm -rf "$(YIACAD_LINK)"
	@ln -s "$(abspath $(YIACAD_DIR))" "$(YIACAD_LINK)"
	@echo "Lien cree: $(YIACAD_LINK) -> $(abspath $(YIACAD_DIR))"

yiacad-check:
	@if [ -L "$(YIACAD_LINK)" ] || [ -d "$(YIACAD_LINK)" ]; then \
		echo "Yiacad present: $(YIACAD_LINK)"; \
	else \
		echo "Yiacad absent. Lance: make YIACAD_DIR=../yiacad yiacad-link"; \
		exit 1; \
	fi

yiacad-plugin-clone:
	@mkdir -p "$(VENDOR_DIR)"
	@if [ -d "$(VENDOR_DIR)/yiacad-kicad-plugin/.git" ]; then \
		echo "Plugin YiACAD KiCad deja clone: $(VENDOR_DIR)/yiacad-kicad-plugin"; \
	else \
		git clone --branch "$(YIACAD_KICAD_PLUGIN_BRANCH)" --single-branch "$(YIACAD_KICAD_PLUGIN_URL)" "$(VENDOR_DIR)/yiacad-kicad-plugin"; \
	fi

yiacad-plugin-check:
	@if [ -d "$(VENDOR_DIR)/yiacad-kicad-plugin/.git" ]; then \
		echo "Plugin YiACAD KiCad present: $(VENDOR_DIR)/yiacad-kicad-plugin"; \
	else \
		echo "Plugin absent. Lance: make yiacad-plugin-clone"; \
		exit 1; \
	fi

yiacad-plugin-pull:
	@if [ -d "$(VENDOR_DIR)/yiacad-kicad-plugin/.git" ]; then \
		git -C "$(VENDOR_DIR)/yiacad-kicad-plugin" pull --ff-only; \
	else \
		echo "Plugin absent. Lance: make yiacad-plugin-clone"; \
		exit 1; \
	fi

kicad-clone-fork:
	@mkdir -p "$(VENDOR_DIR)"
	@if [ -d "$(VENDOR_DIR)/kicad/.git" ]; then \
		echo "KiCad deja clone: $(VENDOR_DIR)/kicad"; \
	else \
		git clone --branch "$(KICAD_BRANCH)" --single-branch "$(KICAD_FORK_URL)" "$(VENDOR_DIR)/kicad"; \
	fi

freecad-clone-fork:
	@mkdir -p "$(VENDOR_DIR)"
	@if [ -d "$(VENDOR_DIR)/freecad/.git" ]; then \
		echo "FreeCAD deja clone: $(VENDOR_DIR)/freecad"; \
	else \
		git clone --branch "$(FREECAD_BRANCH)" --single-branch "$(FREECAD_FORK_URL)" "$(VENDOR_DIR)/freecad"; \
	fi

forks-clone: kicad-clone-fork freecad-clone-fork

forks-pull:
	@if [ -d "$(VENDOR_DIR)/kicad/.git" ]; then git -C "$(VENDOR_DIR)/kicad" pull --ff-only; else echo "KiCad non clone"; fi
	@if [ -d "$(VENDOR_DIR)/freecad/.git" ]; then git -C "$(VENDOR_DIR)/freecad" pull --ff-only; else echo "FreeCAD non clone"; fi

dev:
	@echo "Lancer dans 2 terminaux: make dev-gateway et make dev-web"

dev-gateway:
	cd "$(PROJECT_ROOT)" && if [ -x "$(PYTHON_VENV)" ]; then "$(PYTHON_VENV)" -m uvicorn gateway.app:app --reload --port 8001; else uvicorn gateway.app:app --reload --port 8001; fi

dev-web:
	cd "$(PROJECT_ROOT)" && $(NPM) run web:dev

test:
	cd "$(PROJECT_ROOT)" && if [ -x "$(PYTHON_VENV)" ]; then "$(PYTHON_VENV)" -m pytest tests/ -v; else $(PYTHON) -m pytest tests/ -v; fi

build-web:
	cd "$(PROJECT_ROOT)" && $(NPM) run web:build

xcode-project-skeleton:
	@mkdir -p "$(PROJECT_ROOT)/app/macos/MakelifeCAD"
	@mkdir -p "$(PROJECT_ROOT)/app/macos/MakelifeCAD.xcodeproj"
	@echo "// Placeholder xcodeproj - initialise ton vrai projet via Xcode" > "$(PROJECT_ROOT)/app/macos/MakelifeCAD.xcodeproj/project.pbxproj"
	@printf '%s\n' \
		'import SwiftUI' \
		'' \
		'@main' \
		'struct MakelifeCADApp: App {' \
		'    var body: some Scene {' \
		'        WindowGroup {' \
		'            Text("Makelife CAD - Yiacad bridge")' \
		'                .padding()' \
		'        }' \
		'    }' \
		'}' \
		> "$(PROJECT_ROOT)/app/macos/MakelifeCAD/main.swift"
	@echo "Squelette cree dans app/macos"

xcode-open:
	open -a Xcode "$(PROJECT_ROOT)/app/macos"

clean:
	@echo "Aucun artefact build central a nettoyer"
