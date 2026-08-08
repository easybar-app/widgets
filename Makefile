EASYBAR_ROOT ?= ../easybar
LUA ?= lua
PYTHON ?= scripts/python.sh
STYLUA ?= stylua
OUTPUT_DIR ?= dist

.PHONY: check validate check-lua package bump release fmt-lua lint-lua

check: validate check-lua

validate:
	@$(PYTHON) scripts/validate.py

check-lua:
	@LUA="$(LUA)" EASYBAR_ROOT="$(EASYBAR_ROOT)" scripts/check.sh

package:
	@test -n "$(PACKAGE)" || (echo "PACKAGE is required" >&2; exit 2)
	@$(PYTHON) scripts/package.py --package "$(PACKAGE)" --output-dir "$(OUTPUT_DIR)"

bump:
	@test -n "$(PACKAGE)" || (echo "PACKAGE is required" >&2; exit 2)
	@test -n "$(LEVEL)" || (echo "LEVEL is required (patch, minor, or major)" >&2; exit 2)
	@$(PYTHON) scripts/bump.py --package "$(PACKAGE)" --level "$(LEVEL)"
	@$(MAKE) check

release:
	@test -n "$(PACKAGE)" || (echo "PACKAGE is required" >&2; exit 2)
	@$(PYTHON) scripts/release.py --package "$(PACKAGE)"
	@$(MAKE) check
	@$(PYTHON) scripts/release.py --package "$(PACKAGE)" --publish

fmt-lua:
	@$(STYLUA) packages tests

lint-lua:
	@$(STYLUA) --check packages tests
