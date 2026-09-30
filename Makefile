# Development commands of the workbench template: make [check|test|lint|format|format-check].
# Needs bats, shellcheck and shfmt; formatting rules live in .editorconfig.
.POSIX:

SH_FILES = install.sh bin/* scripts/*.sh adapters/claude/hooks/*.sh .githooks/*
TEST_FILES = tests/*.bats tests/helpers.bash

check: lint format-check test

test:
	bats tests

lint:
	shellcheck --shell=sh $(SH_FILES)
	shellcheck $(TEST_FILES)

format:
	shfmt -w $(SH_FILES) $(TEST_FILES)

format-check:
	shfmt -d $(SH_FILES) $(TEST_FILES)

.PHONY: check test lint format format-check
