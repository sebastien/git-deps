SOURCES_BASH=$(wildcard *.sh bin/*sh src/sh/*sh tests/*.sh research/*.sh)
USER?=$(shell whoami)
HOME?=/home/$(USER)
PREFIX?=$(HOME)/.local

# Detect if mise is available and use it for tools
MISE_EXEC := $(shell which mise 2>/dev/null && echo "mise exec --" || echo "")

.PHONY: check lint
check lint:
	@if $(MISE_EXEC) shellcheck --severity=error $(SOURCES_BASH); then \
		echo "✓ shellcheck passed - no errors found"; \
	else \
		echo "✗ shellcheck failed - errors detected above"; \
		exit 1; \
	fi

.PHONY: fmt
fmt:
	@$(MISE_EXEC) shfmt -w $(SOURCES_BASH)

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
