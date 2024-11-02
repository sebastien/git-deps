SOURCES_BASH=$(wildcard *.sh bin/*sh src/sh/*sh tests/*.sh research/*.sh)
USER?=$(shell whoami)
HOME?=/home/$(USER)
PREFIX?=$(HOME)/.local

test:
	@bash tests/harness.sh

lint:
	@shellcheck $(SOURCES_BASH)

fmt:
	@shfmt -w $(SOURCES_BASH)

shell:
	@env PATH=$(realpath bin):$(PATH) bash

install:
	@mkdir -p "$(PREFIX)/bin"
	TARGET="$(PREFIX)/bin/git-deps"
	if [ -e "$$TARGET" ]; then
		curl -o "$$TARGET" 'https://raw.githubusercontent.com/sebastien/git-deps/master/bin/git-deps'
		chmod +x "$$TARGET"
	fi

install-link:
	@mkdir -p "$(PREFIX)/bin"
	for TOOL in $(foreach T,$(wildcard bin/*),$(notdir $T)); do
		TARGET="$(PREFIX)/bin/$$TOOL"
		if [ -e "$$TARGET" ]; then
			unlink "$$TARGET"
		fi
		echo -n "Installing $$TARGET"
		ln -sfr "bin/$$TOOL" "$$TARGET"
	done

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
