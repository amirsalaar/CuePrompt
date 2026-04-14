.PHONY: help build build-notarize install test clean dmg

SCRIPTS := scripts

help:
	@echo "CuePrompt Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  build    - Build the release app bundle (universal binary)"
	@echo "  test     - Run tests"
	@echo "  install  - Build and install to /Applications/"
	@echo "  clean    - Clean build artifacts"
	@echo "  dmg      - Create a DMG for distribution"

build:
	$(SCRIPTS)/build.sh

build-notarize:
	$(SCRIPTS)/build.sh --notarize

install:
	$(SCRIPTS)/install.sh

test:
	$(SCRIPTS)/run-tests.sh

clean:
	rm -rf .build
	rm -rf CuePrompt.app
	rm -f CuePrompt.zip
	rm -f *.dmg

dmg:
	$(SCRIPTS)/create-dmg.sh
