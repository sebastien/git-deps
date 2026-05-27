SOURCES_BASH=$(wildcard bin/* src/sh/*sh tests/*.sh)
USER?=$(shell whoami)
HOME?=/home/$(USER)
PREFIX?=$(HOME)/.local

MISE ?= mise
MISE_EXEC := $(shell command -v $(MISE) >/dev/null 2>&1 && echo "$(MISE) exec --" || echo "")

.PHONY: test
test:
	@$(MISE_EXEC) bash tests/harness.sh

.PHONY: check lint
check lint:
	@if $(MISE_EXEC) shellcheck -x --severity=error $(SOURCES_BASH); then \
		echo "✓ shellcheck passed - no errors found"; \
	else \
		echo "✗ shellcheck failed - errors detected above"; \
		exit 1; \
	fi

.PHONY: fmt
fmt:
	@$(MISE_EXEC) shfmt -w $(SOURCES_BASH)

.PHONY: ci
ci: test lint

.PHONY: shell
shell:
	@env PATH=$(realpath bin):$(PATH) bash

.PHONY: install
install: install-link
	@

.PHONY: install-web
install-web:
	@mkdir -p "$(PREFIX)/bin"
	TARGET="$(PREFIX)/bin/git-deps"
	if [ -e "$$TARGET" ]; then
		curl -o "$$TARGET" 'https://raw.githubusercontent.com/sebastien/git-deps/master/bin/git-deps'
		chmod +x "$$TARGET"
	else
		echo "Already installed"
	fi

.PHONY: install-link
install-link:
	@mkdir -p "$(PREFIX)/bin"
	for TOOL in $(foreach T,$(wildcard bin/*),$(notdir $T)); do
		TARGET="$(PREFIX)/bin/$$TOOL"
		if [ -e "$$TARGET" ]; then
			unlink "$$TARGET"
		fi
		echo -n "Installing $${TARGET}…"
		ln -sfr "bin/$$TOOL" "$$TARGET"
		echo "OK"
	done

.PHONY: uninstall
uninstall:
	for TOOL in $(foreach T,$(wildcard bin/*),$(notdir $T)); do
		if [ -e "$$TARGET" ]; then
			unlink "$$TARGET"
		fi
	done

print-%:
	@$(info $*=$($*))

.ONESHELL:
# EOF
