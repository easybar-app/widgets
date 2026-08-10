EASYBAR_ROOT ?= ../easybar
LUA ?= lua
PYTHON ?= scripts/support/python.sh
STYLUA ?= stylua
PRETTIER ?= npx --yes prettier@3.9.6
TAPLO ?= npx --yes @taplo/cli@0.7.0
OUTPUT_DIR ?= dist
PRETTIER_MD_SOURCES := README.md "packages/**/*.md"
PRETTIER_YAML_SOURCES := ".github/**/*.{yml,yaml}"
PRETTIER_JSON_SOURCES := ".github/**/*.json" .luarc.json
TAPLO_SOURCES := .stylua.toml "packages/**/*.toml"

.DEFAULT_GOAL := help

.PHONY: help fmt fmt-lua fmt-md fmt-yaml fmt-json fmt-toml lint-lua check validate test-validator check-lua package bump release

help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z\_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Formatting

fmt: fmt-lua fmt-md fmt-yaml fmt-json fmt-toml ## Format all supported source and configuration files.

fmt-lua: ## Format package and test Lua files with StyLua.
	@$(STYLUA) packages tests

fmt-md: ## Format Markdown files with Prettier.
	@$(PRETTIER) --write $(PRETTIER_MD_SOURCES)

fmt-yaml: ## Format YAML files with Prettier.
	@$(PRETTIER) --write $(PRETTIER_YAML_SOURCES)

fmt-json: ## Format JSON configuration files with Prettier.
	@$(PRETTIER) --write $(PRETTIER_JSON_SOURCES)

fmt-toml: ## Format TOML files with Taplo.
	@$(TAPLO) fmt $(TAPLO_SOURCES)

lint-lua: ## Check Lua formatting with StyLua.
	@$(STYLUA) --check packages tests

##@ Validation

check: validate test-validator check-lua ## Validate packages and run Lua checks.

validate: ## Validate package manifests and dependency compatibility.
	@$(PYTHON) scripts/ci/validate.py

test-validator: ## Run package validator regression tests.
	@$(PYTHON) -m unittest discover -s tests/ci -p 'test_*.py'

check-lua: ## Check Lua syntax and run package tests.
	@LUA="$(LUA)" EASYBAR_ROOT="$(EASYBAR_ROOT)" scripts/ci/check.sh

##@ Packaging

package: ## Build one package archive with PACKAGE=name.
	@test -n "$(PACKAGE)" || (echo "PACKAGE is required" >&2; exit 2)
	@$(PYTHON) scripts/release/package.py --package "$(PACKAGE)" --output-dir "$(OUTPUT_DIR)"

bump: ## Bump one package version with PACKAGE=name LEVEL=patch|minor|major.
	@test -n "$(PACKAGE)" || (echo "PACKAGE is required" >&2; exit 2)
	@test -n "$(LEVEL)" || (echo "LEVEL is required (patch, minor, or major)" >&2; exit 2)
	@$(PYTHON) scripts/release/bump.py --package "$(PACKAGE)" --level "$(LEVEL)"
	@$(MAKE) check

release: ## Validate and publish one package with PACKAGE=name.
	@test -n "$(PACKAGE)" || (echo "PACKAGE is required" >&2; exit 2)
	@$(PYTHON) scripts/release/release.py --package "$(PACKAGE)"
	@$(MAKE) check
	@$(PYTHON) scripts/release/release.py --package "$(PACKAGE)" --publish


