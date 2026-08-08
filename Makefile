EASYBAR_ROOT ?= ../easybar
LUA ?= lua
PYTHON ?= scripts/python.sh
STYLUA ?= stylua

.PHONY: check validate check-lua fmt-lua lint-lua

check: validate check-lua

validate:
	@$(PYTHON) scripts/validate.py

check-lua:
	@LUA="$(LUA)" EASYBAR_ROOT="$(EASYBAR_ROOT)" scripts/check.sh

fmt-lua:
	@$(STYLUA) packages tests

lint-lua:
	@$(STYLUA) --check packages tests
