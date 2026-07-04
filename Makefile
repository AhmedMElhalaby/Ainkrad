# Ainkrad — common developer tasks.
#
# The Xcode project is generated from project.yml by XcodeGen and is NOT
# committed. After cloning, run `make` (or `make open`) to generate it.
# project.yml is the source of truth — re-run `make generate` after editing it.

# The project currently needs the macOS 27 beta SDK; default to Xcode-beta when
# it's installed. Override on the command line: `make build DEVELOPER_DIR=…`.
ifneq ($(wildcard /Applications/Xcode-beta.app),)
DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
export DEVELOPER_DIR
endif

SCHEME := Ainkrad
PROJECT := Ainkrad.xcodeproj

.DEFAULT_GOAL := generate
.PHONY: generate open build test release clean help

generate: ## Generate the Xcode project from project.yml
	xcodegen generate

open: generate ## Generate the project and open it in Xcode
	open $(PROJECT)

build: generate ## Build the app (Debug)
	xcodebuild -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS' build

test: generate ## Run the test suite
	xcodebuild -scheme $(SCHEME) -destination 'platform=macOS' test

release: ## Build a distributable .dmg (see scripts/release.sh)
	./scripts/release.sh

clean: ## Remove the generated project and build output
	rm -rf $(PROJECT) dist

help: ## List the available targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-10s %s\n", $$1, $$2}'
