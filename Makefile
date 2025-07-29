SOURCES_BASH=$(wildcard *.sh bin/*sh src/sh/*sh tests/*.sh research/*.sh)
USER?=$(shell whoami)
HOME?=/home/$(USER)
PREFIX?=$(HOME)/.local

.PHONY: test
test:
	@bash tests/harness.sh

.PHONY: lint
lint:
	@shellcheck $(SOURCES_BASH)

.PHONY: fmt
fmt:
	@shfmt -w $(SOURCES_BASH)

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
