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
FREE_CODE_URL ?= https://github.com/paoloanzn/free-code.git

# Optional branches for fork tracking
KICAD_BRANCH ?= master
FREECAD_BRANCH ?= yiacad/freecad-1.1.0
FREECAD_TARGET_TAG ?= 1.1.0
YIACAD_KICAD_PLUGIN_BRANCH ?= main
FREE_CODE_BRANCH ?= main

# Python / Node
PYTHON ?= python3
PIP ?= pip3
NPM ?= npm
VENV_DIR ?= .venv
PYTHON_VENV := $(PROJECT_ROOT)/$(VENV_DIR)/bin/python
PIP_VENV := $(PROJECT_ROOT)/$(VENV_DIR)/bin/pip
FREECAD_CMD ?= freecadcmd
FREECAD_TIMEOUT ?= 120
MACOS_DEPLOYMENT_TARGET ?= 14.0

.PHONY: help doctor bootstrap-macos setup-python setup-web setup all \
	dev dev-gateway dev-web test build-web clean build-kicad-bridge \
	yiacad-link yiacad-check freecad-check freecad-pin-1.1.0 freecad-push-branch \
	yiacad-plugin-clone yiacad-plugin-check yiacad-plugin-pull \
	free-code-clone free-code-check free-code-pull \
	kicad-clone-fork freecad-clone-fork forks-clone forks-pull kicad-smoke kicad-drc \
	xcode-open xcode-project-skeleton

help:
	@echo "Targets disponibles:"
	@echo "  setup                 - Installe dependances Python et web"
	@echo "  bootstrap-macos       - Verifie outils macOS de base"
	@echo "  freecad-check         - Verifie presence de freecadcmd"
	@echo "  freecad-pin-1.1.0     - Pointe vendor/freecad sur le tag $(FREECAD_TARGET_TAG)"
	@echo "  freecad-push-branch   - Push la branche $(FREECAD_BRANCH) sur le fork"
	@echo "  yiacad-link           - Lie ton repo Yiacad dans vendor/yiacad"
	@echo "  yiacad-check          - Verifie le lien Yiacad"
	@echo "  yiacad-plugin-clone   - Clone le plugin yiacad-kicad dans vendor/"
	@echo "  yiacad-plugin-check   - Verifie le plugin yiacad-kicad local"
	@echo "  free-code-clone       - Clone paoloanzn/free-code dans vendor/free-code"
	@echo "  free-code-check       - Verifie le clone local de free-code"
	@echo "  free-code-pull        - Met a jour free-code local"
	@echo "  forks-clone           - Clone KiCad et FreeCAD dans vendor/"
	@echo "  forks-pull            - Met a jour les forks locaux"
	@echo "  dev                   - Lance backend + frontend (2 terminaux requis)"
	@echo "  dev-gateway           - Lance FastAPI (port 8001)"
	@echo "  dev-web               - Lance Next.js web"
	@echo "  test                  - Lance tests Python"
	@echo "  build-web             - Build frontend"
	@echo "  build-kicad-bridge    - Rebuild libkicad_bridge.a avec cible macOS $(MACOS_DEPLOYMENT_TARGET)"
	@echo "  kicad-smoke           - Smoke test kicad-cli export SVG"
	@echo "  kicad-drc             - DRC check kicad-cli sur fixture PCB"
	@echo "  xcode-project-skeleton- Cree un squelette Swift macOS"
	@echo "  xcode-open            - Ouvre le dossier app/macos dans Xcode"
	@echo ""
	@echo "Variables utiles:"
	@echo "  YIACAD_DIR=$(YIACAD_DIR)"
	@echo "  KICAD_FORK_URL=$(KICAD_FORK_URL)"
	@echo "  FREECAD_FORK_URL=$(FREECAD_FORK_URL)"
	@echo "  FREECAD_BRANCH=$(FREECAD_BRANCH)"
	@echo "  FREECAD_TARGET_TAG=$(FREECAD_TARGET_TAG)"
	@echo "  YIACAD_KICAD_PLUGIN_URL=$(YIACAD_KICAD_PLUGIN_URL)"
	@echo "  FREE_CODE_URL=$(FREE_CODE_URL)"
	@echo "  FREECAD_CMD=$(FREECAD_CMD)"
	@echo "  FREECAD_TIMEOUT=$(FREECAD_TIMEOUT)"
	@echo "  MACOS_DEPLOYMENT_TARGET=$(MACOS_DEPLOYMENT_TARGET)"

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

freecad-check:
	@command -v $(FREECAD_CMD) >/dev/null && echo "FreeCAD CLI OK: $(FREECAD_CMD)" || (echo "freecadcmd introuvable. Installe FreeCAD ou definis FREECAD_CMD"; exit 1)

freecad-pin-1.1.0:
	@if [ ! -d "$(VENDOR_DIR)/freecad/.git" ]; then \
		echo "vendor/freecad absent. Lance: make freecad-clone-fork"; \
		exit 1; \
	fi
	@if [ -n "$$(git -C "$(VENDOR_DIR)/freecad" status --porcelain)" ]; then \
		echo "vendor/freecad contient des changements locaux; nettoyage requis avant pin."; \
		exit 1; \
	fi
	@git -C "$(VENDOR_DIR)/freecad" fetch origin --tags
	@git -C "$(VENDOR_DIR)/freecad" checkout -B "$(FREECAD_BRANCH)" "$(FREECAD_TARGET_TAG)"
	@echo "vendor/freecad pointe maintenant sur $(FREECAD_BRANCH) depuis $(FREECAD_TARGET_TAG)"

freecad-push-branch:
	@if [ ! -d "$(VENDOR_DIR)/freecad/.git" ]; then \
		echo "vendor/freecad absent. Lance: make freecad-clone-fork"; \
		exit 1; \
	fi
	@git -C "$(VENDOR_DIR)/freecad" push -u origin "$(FREECAD_BRANCH)"
	@echo "Branche poussee sur le fork: $(FREECAD_BRANCH)"

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

free-code-clone:
	@mkdir -p "$(VENDOR_DIR)"
	@if [ -d "$(VENDOR_DIR)/free-code/.git" ]; then \
		echo "free-code deja clone: $(VENDOR_DIR)/free-code"; \
	else \
		git clone --branch "$(FREE_CODE_BRANCH)" --single-branch "$(FREE_CODE_URL)" "$(VENDOR_DIR)/free-code" || \
		( echo "Echec clone free-code. Si le depot upstream est indisponible, override FREE_CODE_URL:" && \
		  echo "  make FREE_CODE_URL=https://github.com/<owner>/<fork>.git free-code-clone" && false ); \
	fi

free-code-check:
	@if [ -d "$(VENDOR_DIR)/free-code/.git" ]; then \
		echo "free-code present: $(VENDOR_DIR)/free-code"; \
	else \
		echo "free-code absent. Lance: make free-code-clone"; \
		exit 1; \
	fi

free-code-pull:
	@if [ -d "$(VENDOR_DIR)/free-code/.git" ]; then \
		git -C "$(VENDOR_DIR)/free-code" pull --ff-only; \
	else \
		echo "free-code absent. Lance: make free-code-clone"; \
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

forks-clone: kicad-clone-fork freecad-clone-fork free-code-clone

forks-pull:
	@if [ -d "$(VENDOR_DIR)/kicad/.git" ]; then git -C "$(VENDOR_DIR)/kicad" pull --ff-only; else echo "KiCad non clone"; fi
	@if [ -d "$(VENDOR_DIR)/freecad/.git" ]; then git -C "$(VENDOR_DIR)/freecad" pull --ff-only; else echo "FreeCAD non clone"; fi
	@if [ -d "$(VENDOR_DIR)/free-code/.git" ]; then git -C "$(VENDOR_DIR)/free-code" pull --ff-only; else echo "free-code non clone"; fi

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

build-kicad-bridge:
	cd "$(PROJECT_ROOT)" && cmake -B kicad-bridge/build -S kicad-bridge -DCMAKE_OSX_DEPLOYMENT_TARGET="$(MACOS_DEPLOYMENT_TARGET)"
	cd "$(PROJECT_ROOT)" && cmake --build kicad-bridge/build

kicad-smoke:
	cd "$(PROJECT_ROOT)" && bash scripts/kicad_smoke_check.sh

kicad-drc:
	cd "$(PROJECT_ROOT)" && bash scripts/kicad_drc_check.sh

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
