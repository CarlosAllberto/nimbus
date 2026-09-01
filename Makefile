.PHONY: build lint ci

build:
	swift build

lint:
	@if command -v swiftlint >/dev/null 2>&1; then swiftlint lint; else echo "swiftlint not installed; no native Swift linter configured."; fi

ci: lint build
