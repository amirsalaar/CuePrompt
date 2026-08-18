.PHONY: help build build-notarize install test lint lint-fix clean dmg setup-local-signing

SCRIPTS := scripts

help:
	@echo "CuePrompt Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  build               - Build the release app bundle (universal binary)"
	@echo "  test                - Run tests"
	@echo "  lint                - Run SwiftLint"
	@echo "  lint-fix            - Autocorrect the mechanical SwiftLint violations"
	@echo "  install             - Build and install to /Applications/"
	@echo "  clean               - Clean build artifacts"
	@echo "  dmg                 - Create a DMG for distribution"
	@echo "  setup-local-signing - Create a persistent local signing identity (preserves permissions across reinstalls)"

build:
	$(SCRIPTS)/build.sh

build-notarize:
	$(SCRIPTS)/build.sh --notarize

install:
	$(SCRIPTS)/install.sh

test:
	$(SCRIPTS)/run-tests.sh

lint:
	swiftlint lint

lint-fix:
	swiftlint --fix

clean:
	rm -rf .build
	rm -rf CuePrompt.app
	rm -f CuePrompt.zip
	rm -f *.dmg

dmg:
	$(SCRIPTS)/create-dmg.sh

setup-local-signing:
	$(SCRIPTS)/setup-local-signing.sh
